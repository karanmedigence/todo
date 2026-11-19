import 'package:frontend/auth/data/user_model.dart';
import 'package:frontend/auth/domain/auth_repository.dart';

@Deprecated('Use AuthRepository.')
class UserRepository {
  const UserRepository(this._authRepository);

  final AuthRepository _authRepository;

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) {
    return _authRepository.login(email: email, password: password);
  }

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _authRepository.register(
      name: name,
      email: email,
      password: password,
    );
  }

  Future<void> signOut() => _authRepository.logout();
}
