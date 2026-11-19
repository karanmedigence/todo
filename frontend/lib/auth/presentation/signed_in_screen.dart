import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/todo/presentation/add_todo_screen.dart';
import 'package:frontend/todo/presentation/all_todo_screen.dart';

class SignedInScreen extends StatelessWidget {
  const SignedInScreen({super.key, required this.name, required this.email});

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                'You’re signed in',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(name),
              Text(email),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AllTodoScreen(),
                  ),
                ),
                icon: const Icon(Icons.checklist),
                label: const Text('My todos'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddTodoScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add todo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    context.read<AuthBloc>().add(const AuthLogoutRequested()),
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.read<AuthBloc>().add(
                  const AuthLogoutAllRequested(),
                ),
                child: const Text('Sign out all devices'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
