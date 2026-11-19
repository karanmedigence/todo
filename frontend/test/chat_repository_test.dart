import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/chat/data/chat_repository.dart';
import 'package:frontend/core/network/api_client.dart';

import 'test_support/fakes.dart';

void main() {
  test('searches contacts and loads persistent chat history', () async {
    final storage = MemoryTokenStorage()..accessToken = 'access-1';
    final adapter = _ChatApiAdapter();
    Dio createDio() {
      final dio = Dio(BaseOptions(baseUrl: 'https://todo.test'));
      dio.httpClientAdapter = adapter;
      return dio;
    }

    final repository = ChatRepository(
      apiClient: ApiClient(
        tokenStorage: storage,
        baseUrl: 'https://todo.test',
        dio: createDio(),
      ),
      tokenStorage: storage,
      baseUrl: 'https://todo.test',
    );

    final contacts = await repository.findUsers('bob@example.com');
    final history = await repository.getHistory('peer-1');

    expect(contacts.single.email, 'bob@example.com');
    expect(history.single.content, 'Hello');
    expect(history.single.senderId, 'user-1');
    expect(adapter.authorizationHeaders, everyElement('Bearer access-1'));
    expect(adapter.search, 'bob@example.com');
  });
}

class _ChatApiAdapter implements HttpClientAdapter {
  final List<String?> authorizationHeaders = [];
  String? search;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization'] as String?);
    if (options.uri.path == '/chat/users') {
      search = options.queryParameters['search'] as String?;
      return _response([
        {'id': 'peer-1', 'name': 'Bob Example', 'email': 'bob@example.com'},
      ], 200);
    }
    return _response([
      {
        'id': 'message-1',
        'sender_id': 'user-1',
        'recipient_id': 'peer-1',
        'content': 'Hello',
        'created_at': '2026-11-19T10:00:00Z',
      },
    ], 200);
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
