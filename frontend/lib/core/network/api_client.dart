import 'package:dio/dio.dart';
import 'package:frontend/auth/data/auth_tokens.dart';
import 'package:frontend/core/consts.dart';
import 'package:frontend/core/storage/token_storage.dart';

class ApiClient {
  ApiClient({
    required this.tokenStorage,
    String? baseUrl,
    Dio? dio,
    Dio? unauthenticatedDio,
    Dio? refreshDio,
  }) : dio = dio ?? Dio(_baseOptions(baseUrl)),
       unauthenticatedDio = unauthenticatedDio ?? Dio(_baseOptions(baseUrl)),
       _refreshDio = refreshDio ?? Dio(_baseOptions(baseUrl)) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _attachAccessToken,
        onError: _retryAfterRefresh,
      ),
    );
  }

  static BaseOptions _baseOptions(String? baseUrl) => BaseOptions(
    baseUrl: baseUrl ?? apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      Headers.contentTypeHeader: Headers.jsonContentType,
      Headers.acceptHeader: Headers.jsonContentType,
    },
  );

  static const _retryAfterRefreshKey = 'authRefreshRetried';

  final TokenStorage tokenStorage;
  final Dio _refreshDio;
  final Dio unauthenticatedDio;
  final Dio dio;

  Future<Map<String, dynamic>>? _refreshInProgress;
  bool _sessionExpiryNotified = false;
  void Function()? onSessionExpired;

  Future<void> _attachAccessToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isExcludedPath(options.uri.path)) {
      handler.next(options);
      return;
    }

    final accessToken = await tokenStorage.getAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  Future<void> _retryAfterRefresh(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    if (request.extra[_retryAfterRefreshKey] == true &&
        error.response?.statusCode == 401) {
      await _expireSession();
      handler.next(error);
      return;
    }

    if (error.response?.statusCode != 401 ||
        !_hasBearerHeader(request) ||
        _isExcludedPath(request.uri.path) ||
        request.extra[_retryAfterRefreshKey] == true ||
        !_isAuthenticationChallenge(error.response)) {
      handler.next(error);
      return;
    }

    try {
      final tokens = await refreshTokens();
      request
        ..extra[_retryAfterRefreshKey] = true
        ..headers['Authorization'] =
            'Bearer ${tokens['access_token']}';
      final response = await dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException {
      handler.next(error);
    } on FormatException {
      handler.next(error);
    }
  }

  bool _hasBearerHeader(RequestOptions request) {
    final authorization =
        request.headers['Authorization'] ??
        request.headers['authorization'];
    return authorization is String &&
        authorization.toLowerCase().startsWith('bearer ');
  }

  bool _isExcludedPath(String path) {
    final normalizedPath = path.toLowerCase();
    return normalizedPath.endsWith('/auth/login') ||
        normalizedPath.endsWith('/auth/register') ||
        normalizedPath.endsWith('/auth/refresh') ||
        normalizedPath.endsWith('/auth/logout');
  }

  bool _isAuthenticationChallenge(Response<dynamic>? response) {
    final challenge = response?.headers.value('www-authenticate');
    if (challenge != null && challenge.toLowerCase().contains('bearer')) {
      return true;
    }
    final data = response?.data;
    return data is Map && data['detail'] == 'Could not validate credentials';
  }

  Future<Map<String, dynamic>> refreshTokens({String? refreshToken}) {
    final existingRefresh = _refreshInProgress;
    if (existingRefresh != null) return existingRefresh;

    final refreshFuture = _performRefresh(refreshToken: refreshToken);
    _refreshInProgress = refreshFuture;
    return refreshFuture.whenComplete(() {
      if (identical(_refreshInProgress, refreshFuture)) {
        _refreshInProgress = null;
      }
    });
  }

  Future<Map<String, dynamic>> _performRefresh({
    String? refreshToken,
  }) async {
    final token = refreshToken ?? await tokenStorage.getRefreshToken();
    if (token == null || token.isEmpty) {
      await _expireSession();
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        type: DioExceptionType.badResponse,
      );
    }

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': token},
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Invalid token refresh response.');
      }
      final tokens = AuthTokens.fromJson(data);

      await tokenStorage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      _sessionExpiryNotified = false;
      return data;
    } on DioException catch (error) {
      if (_isPermanentRefreshFailure(error)) {
        await _expireSession();
      }
      rethrow;
    }
  }

  bool _isPermanentRefreshFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    return statusCode == 400 || statusCode == 401 || statusCode == 403;
  }

  Future<void> _expireSession() async {
    await tokenStorage.clearTokens();
    if (_sessionExpiryNotified) return;
    _sessionExpiryNotified = true;
    onSessionExpired?.call();
  }

  void markSessionActive() {
    _sessionExpiryNotified = false;
  }
}
