import '../core/utils/json_utils.dart';

class TelemetryEnvironment {
  const TelemetryEnvironment({
    required this.id,
    required this.deviceId,
    this.temperature,
    this.humidity,
    required this.soilMoisture,
    this.recordedAt,
    this.receivedAt,
  });

  final int id;
  final String deviceId;
  final double? temperature;
  final double? humidity;
  final double soilMoisture;
  final DateTime? recordedAt;
  final DateTime? receivedAt;

  factory TelemetryEnvironment.fromJson(Map<String, dynamic> json) {
    return TelemetryEnvironment(
      id: parseInt(json['id']) ?? 0,
      deviceId: json['device_id']?.toString() ?? '',
      temperature: parseDouble(json['temperature']),
      humidity: parseDouble(json['humidity']),
      soilMoisture: parseDouble(json['soil_moisture']) ?? 0,
      recordedAt: parseDateTime(json['recorded_at']),
      receivedAt: parseDateTime(json['received_at']),
    );
  }
}

class TelemetryFire {
  const TelemetryFire({
    required this.id,
    required this.deviceId,
    required this.flameDetected,
    this.flameLevel,
    required this.smokeLevel,
    required this.pump,
    required this.buzzer,
    this.recordedAt,
    this.receivedAt,
  });

  final int id;
  final String deviceId;
  final bool flameDetected;
  final int? flameLevel;
  final int smokeLevel;
  final bool pump;
  final bool buzzer;
  final DateTime? recordedAt;
  final DateTime? receivedAt;

  factory TelemetryFire.fromJson(Map<String, dynamic> json) {
    return TelemetryFire(
      id: parseInt(json['id']) ?? 0,
      deviceId: json['device_id']?.toString() ?? '',
      flameDetected: json['flame_detected'] == true,
      flameLevel: parseInt(json['flame_level']),
      smokeLevel: parseInt(json['smoke_level']) ?? 0,
      pump: json['pump'] == true,
      buzzer: json['buzzer'] == true,
      recordedAt: parseDateTime(json['recorded_at']),
      receivedAt: parseDateTime(json['received_at']),
    );
  }
}
