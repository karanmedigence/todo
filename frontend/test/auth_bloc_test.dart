import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/core/network/api_client.dart';

import 'test_support/fakes.dart';

void main() {
  test('restores a saved session to the authenticated state', () async {
    final repository = FakeAuthRepository()
      ..restoredUser = FakeAuthRepository().user;
    final bloc = AuthBloc(
      authRepository: repository,
      apiClient: ApiClient(tokenStorage: MemoryTokenStorage()),
    );
    addTearDown(bloc.close);
    final authenticated = bloc.stream.firstWhere(
      (state) => state is AuthAuthenticated,
    );

    bloc.add(const AuthCheckRequested());

    expect(await authenticated, isA<AuthAuthenticated>());
  });

  test('keeps temporary restoration failures retryable', () async {
    final repository = FakeAuthRepository()
      ..restorationError = const AuthException(
        'The server is unavailable.',
        isTemporary: true,
      );
    final bloc = AuthBloc(
      authRepository: repository,
      apiClient: ApiClient(tokenStorage: MemoryTokenStorage()),
    );
    addTearDown(bloc.close);
    final error = bloc.stream.firstWhere((state) => state is AuthError);

    bloc.add(const AuthCheckRequested());

    final state = await error as AuthError;
    expect(state.message, 'The server is unavailable.');
    expect(state.isRestorationError, isTrue);
    expect(repository.clearTokenCalls, 0);
  });

  test('logout emits unauthenticated even when server logout fails', () async {
    final repository = FakeAuthRepository()
      ..logoutError = const AuthException(
        'Could not connect to the server.',
        isTemporary: true,
      );
    final bloc = AuthBloc(
      authRepository: repository,
      apiClient: ApiClient(tokenStorage: MemoryTokenStorage()),
    );
    addTearDown(bloc.close);
    final unauthenticated = bloc.stream.firstWhere(
      (state) => state is AuthUnauthenticated,
    );

    bloc.add(const AuthLogoutRequested());

    final state = await unauthenticated as AuthUnauthenticated;
    expect(state.notice, contains('Signed out on this device'));
    expect(repository.clearTokenCalls, 1);
  });

  test('login errors are surfaced without authenticating', () async {
    final repository = FakeAuthRepository()
      ..loginError = const AuthException('Invalid credentials');
    final bloc = AuthBloc(
      authRepository: repository,
      apiClient: ApiClient(tokenStorage: MemoryTokenStorage()),
    );
    addTearDown(bloc.close);
    final error = bloc.stream.firstWhere((state) => state is AuthError);

    bloc.add(const AuthLoginRequested(email: 'a@example.com', password: 'bad'));

    expect((await error as AuthError).message, 'Invalid credentials');
  });
}
