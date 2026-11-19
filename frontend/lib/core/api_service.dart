import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';

@Deprecated('Use ApiClient and provide the shared TokenStorage.')
class ApiService extends ApiClient {
  ApiService({TokenStorage? tokenStorage})
    : super(tokenStorage: tokenStorage ?? SecureTokenStorage());
}
