import '../core/utils/json_utils.dart';

enum DeviceConnection {
  online,
  offline;

  static DeviceConnection fromApi(dynamic value) {
    return value?.toString().toLowerCase() == 'online'
        ? DeviceConnection.online
        : DeviceConnection.offline;
  }

  String get label => this == DeviceConnection.online ? 'Online' : 'Offline';
}

class Device {
  const Device({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.locationName,
    required this.status,
    required this.firmwareVersion,
    this.latitude,
    this.longitude,
    this.lastSeenAt,
    this.onlineSince,
    this.uptimeSeconds = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String deviceId;
  final String name;
  final String locationName;
  final DeviceConnection status;
  final String firmwareVersion;
  final double? latitude;
  final double? longitude;
  final DateTime? lastSeenAt;
  final DateTime? onlineSince;
  final int uptimeSeconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => name.trim().isEmpty ? deviceId : name;

  String get locationLabel =>
      locationName.trim().isEmpty ? 'Lokasi belum diisi' : locationName;

  bool get hasLocation => latitude != null && longitude != null;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      locationName: json['location_name']?.toString() ?? '',
      status: DeviceConnection.fromApi(json['status']),
      firmwareVersion: json['firmware_version']?.toString() ?? '',
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      lastSeenAt: parseDateTime(json['last_seen_at']),
      onlineSince: parseDateTime(json['online_since']),
      uptimeSeconds: parseInt(json['uptime_seconds']) ?? 0,
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }
}
