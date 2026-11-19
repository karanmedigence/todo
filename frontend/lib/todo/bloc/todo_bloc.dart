import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/todo/bloc/todo_event.dart';
import 'package:frontend/todo/bloc/todo_states.dart';
import 'package:frontend/todo/data/todo_model.dart';
import 'package:frontend/todo/domain/todo_repository.dart';

class TodoBloc extends Bloc<TodoEvent, TodoState> {
  TodoBloc({required this.todoRepository}) : super(const TodoInitial()) {
    on<TodoLoadRequested>(_onLoadRequested);
    on<TodoCreateRequested>(_onCreateRequested);
    on<TodoUpdateRequested>(_onUpdateRequested);
    on<TodoDeleteRequested>(_onDeleteRequested);
  }

  
  final TodoRepository todoRepository;

  Future<void> _onLoadRequested(
    TodoLoadRequested event,
    Emitter<TodoState> emit,
  ) async {
    emit(const TodoLoading());
    try {
      emit(TodoLoaded(await todoRepository.getTodos()));
    } on TodoException catch (error) {
      emit(TodoError(error.message));
    }
  }

  Future<void> _onCreateRequested(
    TodoCreateRequested event,
    Emitter<TodoState> emit,
  ) async {
    final todos = state is TodoLoaded
        ? (state as TodoLoaded).todos
        : const <TodoModel>[];
    emit(const TodoLoading());
    try {
      final todo = await todoRepository.createTodo(
        title: event.title,
        description: event.description,
      );
      emit(TodoLoaded([todo, ...todos]));
    } on TodoException catch (error) {
      emit(TodoError(error.message));
    }
  }

  Future<void> _onUpdateRequested(
    TodoUpdateRequested event,
    Emitter<TodoState> emit,
  ) async {
    try {
      final updatedTodo = await todoRepository.updateTodo(
        id: event.id,
        isCompleted: event.isCompleted,
      );
      final todos = state is TodoLoaded
          ? (state as TodoLoaded).todos
          : const <TodoModel>[];
      final index = todos.indexWhere((todo) => todo.id == updatedTodo.id);
      if (index == -1) {
        emit(TodoLoaded([updatedTodo, ...todos]));
      } else {
        final updatedTodos = [...todos];
        updatedTodos[index] = updatedTodo;
        emit(TodoLoaded(updatedTodos));
      }
    } on TodoException catch (error) {
      emit(TodoError(error.message));
    }
  }

  Future<void> _onDeleteRequested(
    TodoDeleteRequested event,
    Emitter<TodoState> emit,
  ) async {
    try {
      await todoRepository.deleteTodo(event.id);
      final todos = state is TodoLoaded
          ? (state as TodoLoaded).todos
          : const <TodoModel>[];
      emit(TodoLoaded(todos.where((todo) => todo.id != event.id).toList()));
    } on TodoException catch (error) {
      emit(TodoError(error.message));
    }
  }
}
