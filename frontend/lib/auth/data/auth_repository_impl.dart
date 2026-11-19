import 'package:dio/dio.dart';
import 'package:frontend/auth/data/auth_api.dart';
import 'package:frontend/auth/data/auth_tokens.dart';
import 'package:frontend/auth/data/user_model.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required this.authApi,
    required this.apiClient,
    required this.tokenStorage,
  });

  final AuthApi authApi;
  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final session = await authApi.login(
        email: email,
        password: password,
        deviceName: 'Flutter app',
      );
      await _saveTokens(session.tokens);
      return session.user;
    } on DioException catch (error) {
      throw _toAuthException(error);
    } on FormatException catch (error) {
      throw AuthException(error.message);
    }
  }

  @override
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      return await authApi.register(
        name: name,
        email: email,
        password: password,
      );
    } on DioException catch (error) {
      throw _toAuthException(error);
    } on FormatException catch (error) {
      throw AuthException(error.message);
    }
  }

  @override
  Future<UserModel?> restoreSession() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      await authApi.refreshToken(refreshToken);
      return await authApi.getCurrentUser();
    } on DioException catch (error) {
      if (_isPermanentAuthenticationFailure(error)) {
        await clearTokens();
        return null;
      }
      throw _toAuthException(error, isTemporary: true);
    } on FormatException catch (error) {
      throw AuthException(error.message, isTemporary: true);
    }
  }

  @override
  Future<UserModel> getCurrentUser() async {
    try {
      return await authApi.getCurrentUser();
    } on DioException catch (error) {
      throw _toAuthException(error);
    } on FormatException catch (error) {
      throw AuthException(error.message);
    }
  }

  @override
  Future<void> refreshToken() async {
    final refreshToken = await tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearTokens();
      throw const AuthException('Your session has expired. Please sign in.');
    }
    try {
      final tokens = await authApi.refreshToken(refreshToken);
      await _saveTokens(tokens);
    } on DioException catch (error) {
      if (_isPermanentAuthenticationFailure(error)) await clearTokens();
      throw _toAuthException(error, isTemporary: !_isPermanentAuthenticationFailure(error));
    } on FormatException catch (error) {
      throw AuthException(error.message, isTemporary: true);
    }
  }

  @override
  Future<void> logout() async {
    AuthException? logoutFailure;
    try {
      final refreshToken = await tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await authApi.logout(refreshToken);
      }
    } on DioException catch (error) {
      logoutFailure = _toAuthException(error, isTemporary: true);
    } finally {
      await clearTokens();
    }

    if (logoutFailure != null) throw logoutFailure;
  }

  @override
  Future<void> logoutAll() async {
    AuthException? logoutFailure;
    try {
      await authApi.logoutAll();
    } on DioException catch (error) {
      logoutFailure = _toAuthException(error, isTemporary: true);
    } finally {
      await clearTokens();
    }

    if (logoutFailure != null) throw logoutFailure;
  }

  @override
  Future<void> clearTokens() async {
    await tokenStorage.clearTokens();
    apiClient.markSessionActive();
  }

  Future<void> _saveTokens(AuthTokens tokens) async {
    await tokenStorage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    apiClient.markSessionActive();
  }

  bool _isPermanentAuthenticationFailure(DioException error) {
    final statusCode = error.response?.statusCode;
    return statusCode == 400 || statusCode == 401 || statusCode == 403;
  }

  AuthException _toAuthException(
    DioException error, {
    bool isTemporary = false,
  }) {
    final responseData = error.response?.data;
    if (responseData is Map) {
      final detail = responseData['detail'];
      if (detail is String && detail.isNotEmpty) {
        return AuthException(detail, isTemporary: isTemporary);
      }
      if (detail is List && detail.isNotEmpty) {
        final firstError = detail.first;
        if (firstError is Map && firstError['msg'] is String) {
          return AuthException(
            firstError['msg'] as String,
            isTemporary: isTemporary,
          );
        }
      }
    }

    if (error.response == null) {
      return const AuthException(
        'Could not connect to the server. Check your connection and try again.',
        isTemporary: true,
      );
    }
    return AuthException(
      'Request failed. Please try again.',
      isTemporary: isTemporary,
    );
  }
}
