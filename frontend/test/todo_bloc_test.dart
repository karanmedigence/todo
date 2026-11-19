import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/bloc/todo_event.dart';
import 'package:frontend/todo/bloc/todo_states.dart';
import 'package:frontend/todo/data/todo_model.dart';
import 'package:frontend/todo/domain/todo_repository.dart';

import 'test_support/fakes.dart';

void main() {
  test('loads and applies create, update, and delete requests', () async {
    final repository = FakeTodoRepository()
      ..todos = [todo(id: 'todo-1', title: 'First todo')];
    final bloc = TodoBloc(todoRepository: repository);
    addTearDown(bloc.close);

    final loaded = bloc.stream.firstWhere((state) => state is TodoLoaded);
    bloc.add(const TodoLoadRequested());
    expect((await loaded as TodoLoaded).todos, hasLength(1));

    final created = bloc.stream.firstWhere(
      (state) => state is TodoLoaded && state.todos.length == 2,
    );
    bloc.add(const TodoCreateRequested(title: 'Second todo'));
    expect((await created as TodoLoaded).todos.first.title, 'Second todo');

    final updated = bloc.stream.firstWhere(
      (state) =>
          state is TodoLoaded &&
          state.todos.any((item) => item.id == 'todo-1' && item.isCompleted),
    );
    bloc.add(
      const TodoUpdateRequested(
        id: 'todo-1',
        title: 'Updated first todo',
        description: 'Updated description',
        isCompleted: true,
      ),
    );
    expect(
      (await updated as TodoLoaded).todos
          .singleWhere((item) => item.id == 'todo-1')
          .isCompleted,
      isTrue,
    );

    final deleted = bloc.stream.firstWhere(
      (state) => state is TodoLoaded && state.todos.length == 1,
    );
    bloc.add(const TodoDeleteRequested('todo-1'));
    expect((await deleted as TodoLoaded).todos.single.title, 'Second todo');
  });

  test('emits a todo error when loading fails', () async {
    final bloc = TodoBloc(
      todoRepository: FakeTodoRepository()
        ..error = const TodoException('Could not load todos.'),
    );
    addTearDown(bloc.close);
    final error = bloc.stream.firstWhere((state) => state is TodoError);

    bloc.add(const TodoLoadRequested());

    expect((await error as TodoError).message, 'Could not load todos.');
  });
}

TodoModel todo({required String id, required String title}) =>
    TodoModel(id: id, title: title, description: null, isCompleted: false);

class FakeTodoRepository extends TodoRepository {
  FakeTodoRepository() : super(ApiClient(tokenStorage: MemoryTokenStorage()));

  List<TodoModel> todos = [];
  TodoException? error;

  void _throwIfNeeded() {
    final error = this.error;
    if (error != null) throw error;
  }

  @override
  Future<List<TodoModel>> getTodos() async {
    _throwIfNeeded();
    return todos;
  }

  @override
  Future<TodoModel> createTodo({
    required String title,
    String? description,
  }) async {
    _throwIfNeeded();
    final created = TodoModel(
      id: 'todo-${todos.length + 1}',
      title: title,
      description: description,
      isCompleted: false,
    );
    todos = [created, ...todos];
    return created;
  }

  @override
  Future<TodoModel> updateTodo({
    required String id,
    String? title,
    String? description,
    bool? isCompleted,
    bool clearDescription = false,
  }) async {
    _throwIfNeeded();
    final index = todos.indexWhere((item) => item.id == id);
    final updated = TodoModel(
      id: id,
      title: title ?? todos[index].title,
      description: clearDescription
          ? null
          : (description ?? todos[index].description),
      isCompleted: isCompleted ?? todos[index].isCompleted,
    );
    todos[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodo(String id) async {
    _throwIfNeeded();
    todos = todos.where((item) => item.id != id).toList();
  }
}
