import '../core/utils/json_utils.dart';
import 'device.dart';
import 'telemetry.dart';

enum RiskLevel {
  normal,
  waspada,
  bahaya,
  darurat,
  unknown;

  static RiskLevel fromApi(dynamic value) {
    switch (value?.toString().toUpperCase()) {
      case 'NORMAL':
        return RiskLevel.normal;
      case 'WASPADA':
        return RiskLevel.waspada;
      case 'BAHAYA':
        return RiskLevel.bahaya;
      case 'DARURAT':
        return RiskLevel.darurat;
      default:
        return RiskLevel.unknown;
    }
  }

  String get label {
    switch (this) {
      case RiskLevel.normal:
        return 'Normal';
      case RiskLevel.waspada:
        return 'Waspada';
      case RiskLevel.bahaya:
        return 'Bahaya';
      case RiskLevel.darurat:
        return 'Darurat';
      case RiskLevel.unknown:
        return 'Tidak diketahui';
    }
  }

  int get urgency {
    switch (this) {
      case RiskLevel.darurat:
        return 4;
      case RiskLevel.bahaya:
        return 3;
      case RiskLevel.waspada:
        return 2;
      case RiskLevel.normal:
        return 1;
      case RiskLevel.unknown:
        return 0;
    }
  }

  bool get isCritical => this == RiskLevel.bahaya || this == RiskLevel.darurat;
}

class DeviceStatus {
  const DeviceStatus({
    required this.device,
    required this.connection,
    required this.riskLevel,
    this.lastSeenAt,
    this.onlineSince,
    this.uptimeSeconds = 0,
    this.environment,
    this.fire,
    this.serverTime,
  });

  final Device device;
  final DeviceConnection connection;
  final RiskLevel riskLevel;
  final DateTime? lastSeenAt;
  final DateTime? onlineSince;
  final int uptimeSeconds;
  final TelemetryEnvironment? environment;
  final TelemetryFire? fire;
  final DateTime? serverTime;

  bool get hasTelemetry => environment != null || fire != null;

  DateTime? get lastTelemetryAt {
    final fireAt = fire?.recordedAt ?? fire?.receivedAt;
    final environmentAt = environment?.recordedAt ?? environment?.receivedAt;
    if (fireAt == null) return environmentAt;
    if (environmentAt == null) return fireAt;
    return fireAt.isAfter(environmentAt) ? fireAt : environmentAt;
  }

  DeviceStatus copyWith({
    Device? device,
    DeviceConnection? connection,
    RiskLevel? riskLevel,
    DateTime? lastSeenAt,
    DateTime? onlineSince,
    int? uptimeSeconds,
    TelemetryEnvironment? environment,
    TelemetryFire? fire,
    DateTime? serverTime,
  }) {
    return DeviceStatus(
      device: device ?? this.device,
      connection: connection ?? this.connection,
      riskLevel: riskLevel ?? this.riskLevel,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      onlineSince: onlineSince ?? this.onlineSince,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
      environment: environment ?? this.environment,
      fire: fire ?? this.fire,
      serverTime: serverTime ?? this.serverTime,
    );
  }

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final environmentJson = json['environment'];
    final fireJson = json['fire'];
    final deviceJson = parseMap(json['device']);

    return DeviceStatus(
      device: Device.fromJson(deviceJson),
      connection: DeviceConnection.fromApi(
        json['status'] ?? deviceJson['status'],
      ),
      riskLevel: RiskLevel.fromApi(json['risk_level']),
      lastSeenAt: parseDateTime(json['last_seen_at']),
      onlineSince: parseDateTime(json['online_since']),
      uptimeSeconds: parseInt(json['uptime_seconds']) ?? 0,
      environment: environmentJson is Map
          ? TelemetryEnvironment.fromJson(parseMap(environmentJson))
          : null,
      fire: fireJson is Map ? TelemetryFire.fromJson(parseMap(fireJson)) : null,
      serverTime: parseDateTime(json['server_time']),
    );
  }
}
