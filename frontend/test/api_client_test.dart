import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';

void main() {
  test('refreshes once for concurrent 401s and retries both requests', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'expired-access'
      ..refreshToken = 'old-refresh';
    final adapter = _RefreshAdapter();
    final client = _createClient(storage, adapter);

    final responses = await Future.wait([
      client.dio.get<Map<String, dynamic>>('/todos/'),
      client.dio.get<Map<String, dynamic>>('/todos/'),
    ]);

    expect(responses, hasLength(2));
    expect(adapter.refreshCalls, 1);
    expect(adapter.todoCalls, 4);
    expect(storage.accessToken, 'new-access');
    expect(storage.refreshToken, 'new-refresh');
    expect(adapter.retriedAuthorizationHeaders, [
      'Bearer new-access',
      'Bearer new-access',
    ]);
  });

  test('invalid refresh clears tokens and notifies the auth layer once', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'expired-access'
      ..refreshToken = 'revoked-refresh';
    final adapter = _RefreshAdapter(invalidRefresh: true);
    final client = _createClient(storage, adapter);
    var sessionExpiredCalls = 0;
    client.onSessionExpired = () => sessionExpiredCalls++;

    await expectLater(client.dio.get<void>('/todos/'), throwsA(isA<DioException>()));

    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
    expect(sessionExpiredCalls, 1);
  });

  test('network failure during refresh preserves local tokens', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'expired-access'
      ..refreshToken = 'valid-refresh';
    final adapter = _RefreshAdapter(refreshUnavailable: true);
    final client = _createClient(storage, adapter);

    await expectLater(client.dio.get<void>('/todos/'), throwsA(isA<DioException>()));

    expect(storage.accessToken, 'expired-access');
    expect(storage.refreshToken, 'valid-refresh');
  });

  test('does not attach tokens or refresh auth endpoints', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'some-access'
      ..refreshToken = 'some-refresh';
    final adapter = _RefreshAdapter(authEndpointUnauthorized: true);
    final client = _createClient(storage, adapter);

    await expectLater(
      client.dio.post<void>('/auth/login'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.refreshCalls, 0);
    expect(adapter.authRequestAuthorization, isNull);
  });
}

ApiClient _createClient(
  TokenStorage storage,
  _RefreshAdapter adapter,
) {
  Dio dio() {
    final client = Dio(BaseOptions(baseUrl: 'https://todo.test'));
    client.httpClientAdapter = adapter;
    return client;
  }

  return ApiClient(
    tokenStorage: storage,
    baseUrl: 'https://todo.test',
    dio: dio(),
    unauthenticatedDio: dio(),
    refreshDio: dio(),
  );
}

class _MemoryTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> hasTokens() async =>
      accessToken != null && refreshToken != null;
}

class _RefreshAdapter implements HttpClientAdapter {
  _RefreshAdapter({
    this.invalidRefresh = false,
    this.refreshUnavailable = false,
    this.authEndpointUnauthorized = false,
  });

  final bool invalidRefresh;
  final bool refreshUnavailable;
  final bool authEndpointUnauthorized;
  int refreshCalls = 0;
  int todoCalls = 0;
  String? authRequestAuthorization;
  final List<String?> retriedAuthorizationHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/auth/login')) {
      authRequestAuthorization =
          options.headers['Authorization'] as String?;
      return _jsonResponse(
        {'detail': 'Invalid credentials'},
        401,
        authenticate: true,
      );
    }

    if (path.endsWith('/auth/refresh')) {
      refreshCalls++;
      if (refreshUnavailable) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (invalidRefresh) {
        return _jsonResponse(
          {'detail': 'Invalid or expired refresh token'},
          401,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _jsonResponse({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
        'token_type': 'bearer',
        'expires_in': 900,
        'refresh_expires_in': 604800,
      }, 200);
    }

    if (path.endsWith('/todos/')) {
      todoCalls++;
      final authorization =
          options.headers['Authorization'] as String?;
      if (authorization == 'Bearer new-access') {
        retriedAuthorizationHeaders.add(authorization);
        return _jsonResponse({'ok': true}, 200);
      }
      return _jsonResponse(
        {'detail': 'Could not validate credentials'},
        401,
        authenticate: true,
      );
    }
    return _jsonResponse({'detail': 'Not found'}, 404);
  }

  ResponseBody _jsonResponse(
    Object body,
    int statusCode, {
    bool authenticate = false,
  }) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (authenticate) 'www-authenticate': ['Bearer'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
