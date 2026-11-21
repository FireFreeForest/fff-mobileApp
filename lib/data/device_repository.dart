import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/device.dart';
import '../models/device_status.dart';
import '../models/paginated.dart';
import '../models/telemetry.dart';

class DeviceRepository {
  DeviceRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<Paginated<Device>> listDevices({
    int page = 1,
    int perPage = 100,
    String? query,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices',
      query: {
        'page': '$page',
        'per_page': '$perPage',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return Paginated.fromJson(response, Device.fromJson);
  }

  Future<List<Device>> listAllDevices({String? query}) async {
    final devices = <Device>[];
    var page = 1;

    while (true) {
      final result = await listDevices(page: page, query: query);
      devices.addAll(result.items);
      if (result.items.isEmpty || devices.length >= result.total) {
        break;
      }
      page++;
    }

    return devices;
  }

  Future<Device> createDevice({
    String? deviceId,
    required String name,
    required String locationName,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _apiClient.postJson(
      '/api/v1/devices',
      body: {
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'device_id': deviceId.trim(),
        'name': name,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return Device.fromJson(parseMap(response['data']));
  }

  Future<Device> updateDevice({
    required String deviceId,
    required String name,
    required String locationName,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _apiClient.patchJson(
      '/api/v1/devices/${Uri.encodeComponent(deviceId)}',
      body: {
        'name': name,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return Device.fromJson(parseMap(response['data']));
  }

  Future<Device> getDevice(String deviceId) async {
    final response = await _apiClient.getJson('/api/v1/devices/$deviceId');
    return Device.fromJson(parseMap(response['data']));
  }

  Future<void> deleteDevice(String deviceId) async {
    await _apiClient.delete('/api/v1/devices/${Uri.encodeComponent(deviceId)}');
  }

  Future<DeviceStatus> getLatest(String deviceId) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/telemetry/latest',
    );
    final data = parseMap(response['data']);
    return DeviceStatus(
      device: Device.fromJson(parseMap(data['device'])),
      connection: DeviceConnection.fromApi(parseMap(data['device'])['status']),
      riskLevel: RiskLevel.fromApi(data['risk_level']),
      environment: data['environment'] is Map
          ? TelemetryEnvironment.fromJson(parseMap(data['environment']))
          : null,
      fire: data['fire'] is Map
          ? TelemetryFire.fromJson(parseMap(data['fire']))
          : null,
    );
  }

  Future<DeviceStatus> getStatus(String deviceId) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/status',
    );
    return DeviceStatus.fromJson(parseMap(response['data']));
  }

  Future<List<DeviceStatus>> listStatuses({String? query}) async {
    final devices = await listAllDevices(query: query);
    return Future.wait(
      devices.map((device) async {
        try {
          return await getStatus(device.deviceId);
        } catch (_) {
          return DeviceStatus(
            device: device,
            connection: device.status,
            riskLevel: RiskLevel.unknown,
          );
        }
      }),
    );
  }

  Future<Paginated<TelemetryFire>> listFireHistory(
    String deviceId, {
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 30,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/telemetry/fire',
      query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return Paginated.fromJson(response, TelemetryFire.fromJson);
  }

  Future<Paginated<TelemetryEnvironment>> listEnvironmentHistory(
    String deviceId, {
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 30,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/telemetry/environment',
      query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return Paginated.fromJson(response, TelemetryEnvironment.fromJson);
  }

  Future<Map<String, dynamic>> aggregateEnvironment(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int interval = 5,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/telemetry/environment/aggregate',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'interval': '$interval',
      },
    );
    return parseMap(response['data']);
  }

  Future<Map<String, dynamic>> aggregateFire(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int interval = 5,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/telemetry/fire/aggregate',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'interval': '$interval',
      },
    );
    return parseMap(response['data']);
  }
}
