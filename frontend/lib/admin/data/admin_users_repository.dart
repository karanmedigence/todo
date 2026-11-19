import 'package:dio/dio.dart';
import 'package:frontend/auth/data/user_model.dart';
import 'package:frontend/core/network/api_client.dart';

class AdminUsersRepository {
  const AdminUsersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<UserModel>> getUsers({int skip = 0, int limit = 50}) {
    return _withApiErrors(() async {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/admin/users',
        queryParameters: {'skip': skip, 'limit': limit},
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('The server returned an empty user list.');
      }
      return data.map((item) {
        if (item is! Map) {
          throw const FormatException('Invalid user response from server.');
        }
        return UserModel.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false);
    });
  }

  Future<UserModel> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) {
    return _withApiErrors(() async {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/admin/users',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('The server returned an empty response.');
      }
      return UserModel.fromJson(data);
    });
  }

  Future<void> deleteUser(String userId) {
    return _withApiErrors(
      () => _apiClient.dio.delete<void>('/admin/users/$userId'),
    );
  }

  Future<T> _withApiErrors<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw AdminUsersException(_messageFor(error));
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

class AdminUsersException implements Exception {
  const AdminUsersException(this.message);

  final String message;

  @override
  String toString() => message;
}
