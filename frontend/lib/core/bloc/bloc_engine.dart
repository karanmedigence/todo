import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_event.dart';
import 'package:frontend/di/injection.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';

class BlocEngine extends StatelessWidget {
  const BlocEngine({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(const AuthCheckRequested()),
        ),
        BlocProvider<TodoBloc>(create: (_) => getIt<TodoBloc>()),
      ],
      child: child,
    );
  }
}
