import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/admin/data/admin_users_repository.dart';
import 'package:frontend/core/network/api_client.dart';

import 'test_support/fakes.dart';

void main() {
  test(
    'admin repository lists, creates, and deletes users with auth',
    () async {
      final storage = MemoryTokenStorage()..accessToken = 'admin-access';
      final adapter = _AdminUsersAdapter();
      Dio createDio() {
        final dio = Dio(BaseOptions(baseUrl: 'https://todo.test'));
        dio.httpClientAdapter = adapter;
        return dio;
      }

      final repository = AdminUsersRepository(
        ApiClient(
          tokenStorage: storage,
          baseUrl: 'https://todo.test',
          dio: createDio(),
        ),
      );

      final users = await repository.getUsers(skip: 10, limit: 25);
      expect(users, hasLength(1));
      expect(users.single.role, 'admin');
      expect(adapter.listQuery, {'skip': 10, 'limit': 25});
      expect(adapter.authorizationHeaders, everyElement('Bearer admin-access'));

      final created = await repository.createUser(
        name: 'New User',
        email: 'new@example.com',
        password: 'password123',
        role: 'user',
      );
      expect(created.email, 'new@example.com');
      expect(created.role, 'user');
      expect(adapter.createBody?['role'], 'user');

      await repository.deleteUser('user-1');
      expect(adapter.deletedPath, '/admin/users/user-1');
    },
  );
}

class _AdminUsersAdapter implements HttpClientAdapter {
  final List<String?> authorizationHeaders = [];
  Map<String, dynamic>? listQuery;
  Map<String, dynamic>? createBody;
  String? deletedPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization'] as String?);
    if (options.method == 'GET') {
      listQuery = options.queryParameters.cast<String, dynamic>();
      return _response([
        {
          'id': 'user-1',
          'name': 'Admin User',
          'email': 'admin@example.com',
          'role': 'admin',
        },
      ], 200);
    }
    if (options.method == 'POST') {
      createBody = options.data as Map<String, dynamic>;
      return _response({
        'id': 'user-2',
        'name': 'New User',
        'email': 'new@example.com',
        'role': 'user',
      }, 201);
    }

    deletedPath = options.path;
    return _response({}, 204);
  }

  ResponseBody _response(Object data, int statusCode) {
    return ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
