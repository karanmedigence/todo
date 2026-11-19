import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/core/network/api_client.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required this.authRepository,
    required this.apiClient,
  }) : super(const AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthLogoutAllRequested>(_onLogoutAllRequested);
    on<AuthSessionExpired>(_onSessionExpired);
    apiClient.onSessionExpired = _notifySessionExpired;
  }

  final AuthRepository authRepository;
  final ApiClient apiClient;
  bool _isBusy = false;
  int _operationVersion = 0;

  void _notifySessionExpired() {
    if (!isClosed) add(const AuthSessionExpired());
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isBusy) return;
    _isBusy = true;
    final operationVersion = ++_operationVersion;
    emit(const AuthLoading());
    try {
      final user = await authRepository.restoreSession();
      if (operationVersion != _operationVersion) return;
      emit(
        user == null
            ? const AuthUnauthenticated()
            : AuthAuthenticated(user),
      );
    } on AuthException catch (error) {
      if (operationVersion == _operationVersion) {
        emit(AuthError(error.message, isRestorationError: true));
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isBusy) return;
    _isBusy = true;
    final operationVersion = ++_operationVersion;
    emit(const AuthLoading());
    try {
      final user = await authRepository.login(
        email: event.email,
        password: event.password,
      );
      if (operationVersion == _operationVersion) {
        emit(AuthAuthenticated(user));
      }
    } on AuthException catch (error) {
      if (operationVersion == _operationVersion) {
        emit(AuthError(error.message));
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_isBusy) return;
    _isBusy = true;
    final operationVersion = ++_operationVersion;
    emit(const AuthLoading());
    try {
      final user = await authRepository.register(
        name: event.name,
        email: event.email,
        password: event.password,
      );
      if (operationVersion == _operationVersion) {
        emit(AuthRegistrationSuccess(user.email));
      }
    } on AuthException catch (error) {
      if (operationVersion == _operationVersion) {
        emit(AuthError(error.message));
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _logout(emit, allDevices: false);
  }

  Future<void> _onLogoutAllRequested(
    AuthLogoutAllRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _logout(emit, allDevices: true);
  }

  Future<void> _logout(
    Emitter<AuthState> emit, {
    required bool allDevices,
  }) async {
    if (_isBusy) return;
    _isBusy = true;
    ++_operationVersion;
    emit(const AuthLoading());
    String? notice;
    try {
      if (allDevices) {
        await authRepository.logoutAll();
      } else {
        await authRepository.logout();
      }
    } on AuthException catch (error) {
      notice = 'Signed out on this device. ${error.message}';
    } finally {
      await authRepository.clearTokens();
      apiClient.markSessionActive();
      _isBusy = false;
      emit(AuthUnauthenticated(notice: notice));
    }
  }

  Future<void> _onSessionExpired(
    AuthSessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    ++_operationVersion;
    await authRepository.clearTokens();
    emit(
      const AuthUnauthenticated(
        notice: 'Your session expired. Please sign in again.',
      ),
    );
  }

  @override
  Future<void> close() {
    apiClient.onSessionExpired = null;
    return super.close();
  }
}
