import 'package:equatable/equatable.dart';
import 'package:frontend/todo/data/todo_model.dart';

sealed class TodoState extends Equatable {
  const TodoState();

  @override
  List<Object?> get props => [];
}

final class TodoInitial extends TodoState {
  const TodoInitial();
}

final class TodoLoading extends TodoState {
  const TodoLoading();
}

final class TodoLoaded extends TodoState {
  TodoLoaded(List<TodoModel> todos) : todos = List.unmodifiable(todos);

  final List<TodoModel> todos;

  @override
  List<Object?> get props => [
    todos
        .map(
          (todo) => [todo.id, todo.title, todo.description, todo.isCompleted],
        )
        .toList(growable: false),
  ];
}

final class TodoError extends TodoState {
  const TodoError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
