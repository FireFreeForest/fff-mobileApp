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

class EnvironmentAggregatePoint {
  const EnvironmentAggregatePoint({
    this.bucketStart,
    this.temperature,
    this.humidity,
    this.soilMoisture,
    this.sampleCount = 0,
  });

  final DateTime? bucketStart;
  final double? temperature;
  final double? humidity;
  final double? soilMoisture;
  final int sampleCount;

  factory EnvironmentAggregatePoint.fromJson(Map<String, dynamic> json) {
    return EnvironmentAggregatePoint(
      bucketStart: parseDateTime(json['bucket_start']),
      temperature: parseDouble(json['temperature']),
      humidity: parseDouble(json['humidity']),
      soilMoisture: parseDouble(json['soil_moisture']),
      sampleCount: parseInt(json['sample_count']) ?? 0,
    );
  }
}

class FireAggregatePoint {
  const FireAggregatePoint({
    this.bucketStart,
    this.flameLevel,
    this.smokeLevel,
    this.flameDetectedRatio,
    this.pumpOnRatio,
    this.buzzerOnRatio,
    this.sampleCount = 0,
  });

  final DateTime? bucketStart;
  final double? flameLevel;
  final double? smokeLevel;
  final double? flameDetectedRatio;
  final double? pumpOnRatio;
  final double? buzzerOnRatio;
  final int sampleCount;

  factory FireAggregatePoint.fromJson(Map<String, dynamic> json) {
    return FireAggregatePoint(
      bucketStart: parseDateTime(json['bucket_start']),
      flameLevel: parseDouble(json['flame_level']),
      smokeLevel: parseDouble(json['smoke_level']),
      flameDetectedRatio: parseDouble(json['flame_detected_ratio']),
      pumpOnRatio: parseDouble(json['pump_on_ratio']),
      buzzerOnRatio: parseDouble(json['buzzer_on_ratio']),
      sampleCount: parseInt(json['sample_count']) ?? 0,
    );
  }
}
