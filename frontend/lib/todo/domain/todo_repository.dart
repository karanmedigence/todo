import 'package:dio/dio.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/todo/data/todo_model.dart';

class TodoException implements Exception {
  const TodoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TodoRepository {
  TodoRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<TodoModel> createTodo({
    required String title,
    String? description,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/todos/',
        data: {'title': title, 'description': description},
      );
      final data = response.data;
      if (data == null) {
        throw const TodoException(
          'The server returned an empty todo response.',
        );
      }

      try {
        return TodoModel.fromJson(data);
      } on FormatException catch (error) {
        throw TodoException(error.message);
      }
    } on DioException catch (error) {
      throw _toTodoException(error, fallbackMessage: 'Could not create todo.');
    }
  }

  Future<List<TodoModel>> getTodos() async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/todos/',
      );
      final data = response.data;
      if (data == null) {
        throw const TodoException(
          'The server returned an empty todo list response.',
        );
      }

      try {
        return data.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException(
              'Invalid todo list response from server.',
            );
          }
          return TodoModel.fromJson(item);
        }).toList(growable: false);
      } on FormatException catch (error) {
        throw TodoException(error.message);
      }
    } on DioException catch (error) {
      throw _toTodoException(error, fallbackMessage: 'Could not load todos.');
    }
  }

  Future<TodoModel> updateTodo({
    required String id,
    required bool isCompleted,
  }) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        '/todos/${Uri.encodeComponent(id)}',
        data: {'is_completed': isCompleted},
      );
      final data = response.data;
      if (data == null) {
        throw const TodoException(
          'The server returned an empty todo response.',
        );
      }

      try {
        return TodoModel.fromJson(data);
      } on FormatException catch (error) {
        throw TodoException(error.message);
      }
    } on DioException catch (error) {
      throw _toTodoException(error, fallbackMessage: 'Could not update todo.');
    }
  }

  Future<void> deleteTodo(String id) async {
    try {
      await _apiClient.dio.delete<void>('/todos/${Uri.encodeComponent(id)}');
    } on DioException catch (error) {
      throw _toTodoException(error, fallbackMessage: 'Could not delete todo.');
    }
  }

  TodoException _toTodoException(
    DioException error, {
    required String fallbackMessage,
  }) {
    final responseData = error.response?.data;
    if (responseData is Map) {
      final detail = responseData['detail'];
      if (detail is String && detail.isNotEmpty) {
        return TodoException(detail);
      }
      if (detail is List && detail.isNotEmpty) {
        final firstError = detail.first;
        if (firstError is Map && firstError['msg'] is String) {
          return TodoException(firstError['msg'] as String);
        }
      }
    }

    if (error.response == null) {
      return const TodoException(
        'Could not connect to the server. Check your connection and try again.',
      );
    }
    return TodoException('$fallbackMessage Please try again.');
  }
}
