import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';

class GeocodingRepository {
  GeocodingRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<String?> reverseLabel({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/geocode/reverse',
      query: {
        'lat': latitude.toStringAsFixed(6),
        'lon': longitude.toStringAsFixed(6),
      },
    );
    final data = parseMap(response['data']);
    final label = data['label']?.toString().trim() ?? '';
    return label.isEmpty ? null : label;
  }
}
