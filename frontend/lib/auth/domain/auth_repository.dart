import 'package:frontend/auth/data/user_model.dart';

abstract interface class AuthRepository {
  Future<UserModel> login({
    required String email,
    required String password,
  });

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  });

  Future<UserModel?> restoreSession();

  Future<UserModel> getCurrentUser();

  Future<void> refreshToken();

  Future<void> logout();

  Future<void> logoutAll();

  Future<void> clearTokens();
}

class AuthException implements Exception {
  const AuthException(this.message, {this.isTemporary = false});

  final String message;
  final bool isTemporary;

  @override
  String toString() => message;
}
