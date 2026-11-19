import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:frontend/chat/data/chat_models.dart';
import 'package:frontend/core/consts.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChatRepository {
  ChatRepository({
    required this._apiClient,
    required this._tokenStorage,
    String? baseUrl,
  }) : _baseUrl = baseUrl ?? apiBaseUrl;

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final String _baseUrl;

  Future<List<ChatContact>> findUsers(String search) {
    return _withApiErrors(() async {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/chat/users',
        queryParameters: {'search': search},
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('The server returned an empty user list.');
      }
      return data
          .map((item) {
            if (item is! Map) {
              throw const FormatException(
                'Invalid chat user response from server.',
              );
            }
            return ChatContact.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false);
    });
  }

  Future<List<ChatMessage>> getHistory(String peerId) {
    return _withApiErrors(() async {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/chat/$peerId/messages',
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException(
          'The server returned an empty chat history.',
        );
      }
      return data
          .map((item) {
            if (item is! Map) {
              throw const FormatException('Invalid chat message from server.');
            }
            return ChatMessage.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false);
    });
  }

  Future<WebSocketChannel> connect(String peerId) async {
    final accessToken = await _tokenStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const ChatException('Sign in again to start a chat.');
    }

    final baseUri = Uri.parse(_baseUrl);
    final socketUri = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/chat/ws/${Uri.encodeComponent(peerId)}',
      query: null,
      fragment: null,
    );
    final channel = WebSocketChannel.connect(socketUri);
    await channel.ready;
    channel.sink.add(
      jsonEncode({'type': 'authenticate', 'token': accessToken}),
    );
    return channel;
  }

  Future<T> _withApiErrors<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ChatException(_messageFor(error));
    }
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final firstError = detail.first;
        if (firstError is Map && firstError['msg'] is String) {
          return firstError['msg'] as String;
        }
      }
    }
    if (error.response == null) {
      return 'Could not connect to the server. Check your connection and try again.';
    }
    return 'Request failed. Please try again.';
  }
}

class ChatException implements Exception {
  const ChatException(this.message);

  final String message;

  @override
  String toString() => message;
}
