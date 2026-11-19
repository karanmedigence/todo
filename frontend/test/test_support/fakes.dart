import 'package:frontend/auth/data/user_model.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/core/storage/token_storage.dart';

class MemoryTokenStorage implements TokenStorage {
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
      accessToken?.isNotEmpty == true && refreshToken?.isNotEmpty == true;
}

class FakeAuthRepository implements AuthRepository {
  UserModel user = const UserModel(
    id: 'user-1',
    name: 'Avery User',
    email: 'avery@example.com',
  );
  UserModel? restoredUser;
  AuthException? loginError;
  AuthException? registrationError;
  AuthException? restorationError;
  AuthException? logoutError;
  AuthException? logoutAllError;
  int loginCalls = 0;
  int registerCalls = 0;
  int clearTokenCalls = 0;

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    if (loginError != null) throw loginError!;
    return user;
  }

  @override
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    if (registrationError != null) throw registrationError!;
    return user;
  }

  @override
  Future<UserModel?> restoreSession() async {
    if (restorationError != null) throw restorationError!;
    return restoredUser;
  }

  @override
  Future<UserModel> getCurrentUser() async => user;

  @override
  Future<void> refreshToken() async {}

  @override
  Future<void> logout() async {
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<void> logoutAll() async {
    if (logoutAllError != null) throw logoutAllError!;
  }

  @override
  Future<void> clearTokens() async {
    clearTokenCalls++;
  }
}
