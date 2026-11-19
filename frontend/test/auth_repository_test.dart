import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/auth/data/auth_api.dart';
import 'package:frontend/auth/data/auth_repository_impl.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';

void main() {
  test('login stores both tokens and current-user uses the bearer token', () async {
    final storage = _MemoryTokenStorage();
    final adapter = _AuthAdapter();
    final repository = _createRepository(storage, adapter);

    final user = await repository.login(
      email: 'avery@example.com',
      password: 'password123',
    );
    final currentUser = await repository.getCurrentUser();

    expect(user.email, 'avery@example.com');
    expect(currentUser.id, 'user-1');
    expect(storage.accessToken, 'access-1');
    expect(storage.refreshToken, 'refresh-1');
    expect(adapter.loginBody, {
      'email': 'avery@example.com',
      'password': 'password123',
      'device_name': 'Flutter app',
    });
    expect(adapter.currentUserAuthorization, 'Bearer access-1');
  });

  test('invalid credentials are exposed as a meaningful auth exception', () async {
    final storage = _MemoryTokenStorage();
    final adapter = _AuthAdapter(invalidLogin: true);
    final repository = _createRepository(storage, adapter);

    await expectLater(
      repository.login(
        email: 'avery@example.com',
        password: 'wrong-password',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'Invalid credentials',
        ),
      ),
    );
    expect(storage.accessToken, isNull);
  });

  test('session restoration rotates tokens then loads current user', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'old-access'
      ..refreshToken = 'old-refresh';
    final adapter = _AuthAdapter();
    final repository = _createRepository(storage, adapter);

    final user = await repository.restoreSession();

    expect(user?.email, 'avery@example.com');
    expect(storage.accessToken, 'new-access');
    expect(storage.refreshToken, 'new-refresh');
    expect(adapter.refreshBody, {'refresh_token': 'old-refresh'});
    expect(adapter.currentUserAuthorization, 'Bearer new-access');
  });

  test('revoked refresh token clears the local session', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'old-access'
      ..refreshToken = 'revoked-refresh';
    final repository = _createRepository(
      storage,
      _AuthAdapter(invalidRefresh: true),
    );

    expect(await repository.restoreSession(), isNull);
    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
  });

  test('temporary refresh failure preserves tokens for retry', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'old-access'
      ..refreshToken = 'valid-refresh';
    final repository = _createRepository(
      storage,
      _AuthAdapter(refreshUnavailable: true),
    );

    await expectLater(
      repository.restoreSession(),
      throwsA(isA<AuthException>().having(
        (error) => error.isTemporary,
        'isTemporary',
        isTrue,
      )),
    );
    expect(storage.accessToken, 'old-access');
    expect(storage.refreshToken, 'valid-refresh');
  });

  test('logout clears local tokens when backend is unavailable', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';
    final repository = _createRepository(
      storage,
      _AuthAdapter(logoutUnavailable: true),
    );

    await expectLater(repository.logout(), throwsA(isA<AuthException>()));
    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
  });

  test('logout-all clears local tokens when the API fails', () async {
    final storage = _MemoryTokenStorage()
      ..accessToken = 'access-1'
      ..refreshToken = 'refresh-1';
    final repository = _createRepository(
      storage,
      _AuthAdapter(logoutUnavailable: true),
    );

    await expectLater(repository.logoutAll(), throwsA(isA<AuthException>()));
    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
  });
}

AuthRepositoryImpl _createRepository(
  _MemoryTokenStorage storage,
  _AuthAdapter adapter,
) {
  Dio createDio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://todo.test'));
    dio.httpClientAdapter = adapter;
    return dio;
  }

  final client = ApiClient(
    tokenStorage: storage,
    baseUrl: 'https://todo.test',
    dio: createDio(),
    unauthenticatedDio: createDio(),
    refreshDio: createDio(),
  );
  return AuthRepositoryImpl(
    authApi: AuthApi(client),
    apiClient: client,
    tokenStorage: storage,
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

class _AuthAdapter implements HttpClientAdapter {
  _AuthAdapter({
    this.invalidLogin = false,
    this.invalidRefresh = false,
    this.refreshUnavailable = false,
    this.logoutUnavailable = false,
  });

  final bool invalidLogin;
  final bool invalidRefresh;
  final bool refreshUnavailable;
  final bool logoutUnavailable;
  Map<String, dynamic>? loginBody;
  Map<String, dynamic>? refreshBody;
  String? currentUserAuthorization;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/auth/login')) {
      loginBody = options.data as Map<String, dynamic>;
      if (invalidLogin) {
        return _jsonResponse({'detail': 'Invalid credentials'}, 401);
      }
      return _jsonResponse({
        ..._user,
        ..._tokens('access-1', 'refresh-1'),
        'message': 'User logged in successfully',
      }, 200);
    }

    if (path.endsWith('/auth/refresh')) {
      refreshBody = options.data as Map<String, dynamic>;
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
      return _jsonResponse(_tokens('new-access', 'new-refresh'), 200);
    }

    if (path.endsWith('/auth/me')) {
      currentUserAuthorization =
          options.headers['Authorization'] as String?;
      return _jsonResponse(_user, 200);
    }

    if (path.endsWith('/auth/logout')) {
      if (logoutUnavailable) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return _jsonResponse({'message': 'Logged out'}, 200);
    }

    if (path.endsWith('/auth/logout-all')) {
      if (logoutUnavailable) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return _jsonResponse(
        {'message': 'Logged out from all devices', 'revoked_sessions': 1},
        200,
      );
    }

    return _jsonResponse({
      ..._user,
      'message': 'User registered successfully',
    }, 201);
  }

  static const _user = {
    'id': 'user-1',
    'name': 'Avery User',
    'email': 'avery@example.com',
  };

  Map<String, dynamic> _tokens(String accessToken, String refreshToken) => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': 'bearer',
    'expires_in': 900,
    'refresh_expires_in': 604800,
  };

  ResponseBody _jsonResponse(Object body, int statusCode) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
