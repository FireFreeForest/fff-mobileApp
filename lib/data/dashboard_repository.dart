import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<DashboardSummary> getSummary() async {
    final response = await _apiClient.getJson('/api/v1/dashboard/summary');
    return DashboardSummary.fromJson(parseMap(response['data']));
  }
}
