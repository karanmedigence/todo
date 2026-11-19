import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/todo/domain/todo_repository.dart';

import 'test_support/fakes.dart';

void main() {
  test('sends authenticated list, update, and delete requests', () async {
    final tokenStorage = MemoryTokenStorage()
      ..accessToken = 'test-token'
      ..refreshToken = 'test-refresh-token';
    final apiClient = ApiClient(tokenStorage: tokenStorage);
    final adapter = _TodoApiAdapter();
    apiClient.dio.httpClientAdapter = adapter;
    final repository = TodoRepository(apiClient);

    final todos = await repository.getTodos();
    final updatedTodo = await repository.updateTodo(
      id: 'todo-1',
      title: 'Buy groceries',
      description: 'Milk and eggs',
      isCompleted: true,
    );
    await repository.deleteTodo('todo-1');

    expect(todos, hasLength(1));
    expect(todos.single.title, 'Buy milk');
    expect(updatedTodo.isCompleted, isTrue);
    expect(adapter.requests.map((request) => request.method), [
      'GET',
      'PUT',
      'DELETE',
    ]);
    expect(adapter.requests.map((request) => request.path), [
      '/todos/',
      '/todos/todo-1',
      '/todos/todo-1',
    ]);
    expect(
      adapter.requests.every(
        (request) => request.headers['Authorization'] == 'Bearer test-token',
      ),
      isTrue,
    );
    expect(adapter.requests[1].data, {
      'title': 'Buy groceries',
      'description': 'Milk and eggs',
      'is_completed': true,
    });
  });
}

class _TodoApiAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'DELETE') {
      return ResponseBody.fromString('', 204);
    }

    final isUpdate = options.method == 'PUT';
    final todo = {
      'id': 'todo-1',
      'title': 'Buy milk',
      'description': null,
      'is_completed': isUpdate,
    };
    final response = isUpdate ? todo : [todo];
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
