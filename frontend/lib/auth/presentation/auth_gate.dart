import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_state.dart';
import 'package:frontend/auth/presentation/login_screen.dart';
import 'package:frontend/auth/presentation/signed_in_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthInitial || state is AuthLoading) {
          return const _SplashScreen();
        }
        if (state is AuthAuthenticated) {
          return SignedInScreen(
            name: state.user.name,
            email: state.user.email,
          );
        }
        return const LoginScreen();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
