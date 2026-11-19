import 'package:flutter/foundation.dart';

const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

final String apiBaseUrl = _apiBaseUrlOverride.isNotEmpty
    ? _apiBaseUrlOverride
    : kIsWeb
    ? 'http://127.0.0.1:8000'
    : defaultTargetPlatform == TargetPlatform.android
    ? 'http://10.0.2.2:8000'
    : 'http://localhost:8000';
