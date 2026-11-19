import 'package:frontend/auth/data/user_model.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.refreshExpiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final int refreshExpiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final accessToken = json['access_token'];
    final refreshToken = json['refresh_token'];
    final tokenType = json['token_type'];
    final expiresIn = json['expires_in'];
    final refreshExpiresIn = json['refresh_expires_in'];

    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        tokenType != 'bearer' ||
        expiresIn is! int ||
        refreshExpiresIn is! int) {
      throw const FormatException('Invalid token response from server.');
    }

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      refreshExpiresIn: refreshExpiresIn,
    );
  }
}

class AuthLoginResult {
  const AuthLoginResult({required this.user, required this.tokens});

  final UserModel user;
  final AuthTokens tokens;
}
