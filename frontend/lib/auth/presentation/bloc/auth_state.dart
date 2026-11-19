import 'package:equatable/equatable.dart';
import 'package:frontend/auth/data/user_model.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final UserModel user;

  @override
  List<Object?> get props => [user.id, user.name, user.email, user.role];
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.notice});

  final String? notice;

  @override
  List<Object?> get props => [notice];
}

final class AuthError extends AuthState {
  const AuthError(this.message, {this.isRestorationError = false});

  final String message;
  final bool isRestorationError;

  @override
  List<Object?> get props => [message, isRestorationError];
}

final class AuthRegistrationSuccess extends AuthState {
  const AuthRegistrationSuccess(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}
