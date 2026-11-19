import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/auth/presentation/login_screen.dart';
import 'package:frontend/auth/presentation/signed_in_screen.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/presentation/all_todo_screen.dart';
import 'package:frontend/todo/data/todo_model.dart';
import 'package:frontend/todo/domain/todo_repository.dart';
import 'package:material_ui/material_ui.dart';

import 'test_support/fakes.dart';

void main() {
  testWidgets('login validates email and password', (tester) async {
    final bloc = _createAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(_withAuthBloc(bloc, const LoginScreen()));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('registration validates name, email, and password', (
    tester,
  ) async {
    final bloc = _createAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(_withAuthBloc(bloc, const LoginScreen()));

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a name with at least 2 characters.'),
      findsOneWidget,
    );
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('signed-in screen displays the user name and email', (
    tester,
  ) async {
    final bloc = _createAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _withAuthBloc(
        bloc,
        const SignedInScreen(
          userId: 'user-1',
          name: 'Avery User',
          email: 'avery@example.com',
          role: 'user',
        ),
      ),
    );

    expect(find.text('Avery User'), findsOneWidget);
    expect(find.text('avery@example.com'), findsOneWidget);
    expect(find.text('Manage users'), findsNothing);
  });

  testWidgets('admin sees the user management entry', (tester) async {
    final bloc = _createAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _withAuthBloc(
        bloc,
        const SignedInScreen(
          userId: 'admin-1',
          name: 'Admin User',
          email: 'admin@example.com',
          role: 'admin',
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Manage users'), findsOneWidget);
  });

  testWidgets('todo screen displays todos loaded through the bloc', (
    tester,
  ) async {
    final bloc = TodoBloc(todoRepository: _TodoRepository());
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(home: AllTodoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Widget todo'), findsOneWidget);
  });
}

AuthBloc _createAuthBloc() => AuthBloc(
  authRepository: FakeAuthRepository(),
  apiClient: ApiClient(tokenStorage: MemoryTokenStorage()),
);

Widget _withAuthBloc(AuthBloc bloc, Widget child) => BlocProvider.value(
  value: bloc,
  child: MaterialApp(home: child),
);

class _TodoRepository extends TodoRepository {
  _TodoRepository() : super(ApiClient(tokenStorage: MemoryTokenStorage()));

  @override
  Future<List<TodoModel>> getTodos() async => const [
    TodoModel(
      id: 'todo-1',
      title: 'Widget todo',
      description: null,
      isCompleted: false,
    ),
  ];
}
