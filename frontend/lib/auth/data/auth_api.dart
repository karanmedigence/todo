import 'package:frontend/auth/data/auth_tokens.dart';
import 'package:frontend/auth/data/user_model.dart';
import 'package:frontend/core/network/api_client.dart';

class AuthApi {
  const AuthApi(this._apiClient);

  final ApiClient _apiClient;

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.unauthenticatedDio
        .post<Map<String, dynamic>>(
          '/auth/register',
          data: {'name': name, 'email': email, 'password': password},
        );
    final data = response.data;
    if (data == null) {
      throw const FormatException('The server returned an empty response.');
    }
    return _parseUser(data);
  }

  Future<AuthLoginResult> login({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    final response = await _apiClient.unauthenticatedDio
        .post<Map<String, dynamic>>(
          '/auth/login',
          data: {
            'email': email,
            'password': password,
            if (deviceName != null && deviceName.isNotEmpty)
              'device_name': deviceName,
          },
        );
    final data = response.data;
    if (data == null) {
      throw const FormatException('The server returned an empty response.');
    }

    return AuthLoginResult(
      user: _parseUser(data),
      tokens: AuthTokens.fromJson(data),
    );
  }

  Future<AuthTokens> refreshToken(String refreshToken) async {
    final response = await _apiClient.refreshTokens(
      refreshToken: refreshToken,
    );
    return AuthTokens.fromJson(response);
  }

  Future<void> logout(String refreshToken) async {
    await _apiClient.unauthenticatedDio.post<void>(
      '/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  }

  Future<void> logoutAll() async {
    await _apiClient.dio.post<void>('/auth/logout-all');
  }

  Future<UserModel> getCurrentUser() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/auth/me',
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('The server returned an empty response.');
    }
    return _parseUser(data);
  }

  UserModel _parseUser(Map<String, dynamic> json) {
    return UserModel.fromJson(json);
  }
}
