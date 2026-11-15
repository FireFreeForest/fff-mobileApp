import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSettingsStore {
  AppSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _apiBaseUrlKey = 'api_base_url';

  Future<String?> readApiBaseUrl() async {
    final value = await _storage.read(key: _apiBaseUrlKey);
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> saveApiBaseUrl(String value) {
    return _storage.write(key: _apiBaseUrlKey, value: value.trim());
  }
}
