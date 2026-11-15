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
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices',
      query: {'page': '$page', 'per_page': '$perPage'},
    );
    return Paginated.fromJson(response, Device.fromJson);
  }

  Future<List<Device>> listAllDevices() async {
    final devices = <Device>[];
    var page = 1;

    while (true) {
      final result = await listDevices(page: page);
      devices.addAll(result.items);
      if (result.items.isEmpty || devices.length >= result.total) {
        break;
      }
      page++;
    }

    return devices;
  }

  Future<Device> createDevice({
    required String deviceId,
    required String name,
    required String locationName,
    required double latitude,
    required double longitude,
    String firmwareVersion = '',
  }) async {
    final response = await _apiClient.postJson(
      '/api/v1/devices',
      body: {
        'device_id': deviceId,
        'name': name,
        'location_name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'firmware_version': firmwareVersion,
      },
    );
    return Device.fromJson(parseMap(response['data']));
  }

  Future<Device> getDevice(String deviceId) async {
    final response = await _apiClient.getJson('/api/v1/devices/$deviceId');
    return Device.fromJson(parseMap(response['data']));
  }

  Future<DeviceStatus> getStatus(String deviceId) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/status',
    );
    return DeviceStatus.fromJson(parseMap(response['data']));
  }

  Future<List<DeviceStatus>> listStatuses() async {
    final devices = await listAllDevices();
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
}
