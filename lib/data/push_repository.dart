import '../core/network/api_client.dart';

class PushRepository {
  PushRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<void> registerToken(String token) async {
    await _apiClient.postJson(
      '/api/v1/push/tokens',
      body: {'token': token, 'platform': 'android'},
    );
  }

  Future<void> deleteToken(String token) async {
    final encodedToken = Uri.encodeComponent(token);
    await _apiClient.delete('/api/v1/push/tokens/$encodedToken');
  }
}
