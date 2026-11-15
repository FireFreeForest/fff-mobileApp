import '../core/utils/json_utils.dart';

enum EventSeverity {
  error,
  warning,
  critical;

  static EventSeverity fromApi(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'error':
        return EventSeverity.error;
      case 'critical':
        return EventSeverity.critical;
      default:
        return EventSeverity.warning;
    }
  }

  String get label {
    switch (this) {
      case EventSeverity.error:
        return 'Error';
      case EventSeverity.warning:
        return 'Waspada';
      case EventSeverity.critical:
        return 'Bahaya';
    }
  }
}

enum EventStatus {
  active,
  acknowledged,
  resolved;

  static EventStatus fromApi(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'acknowledged':
        return EventStatus.acknowledged;
      case 'resolved':
        return EventStatus.resolved;
      default:
        return EventStatus.active;
    }
  }

  String get label {
    switch (this) {
      case EventStatus.active:
        return 'Menunggu';
      case EventStatus.acknowledged:
        return 'Dikonfirmasi';
      case EventStatus.resolved:
        return 'Selesai';
    }
  }
}

class Event {
  const Event({
    required this.id,
    required this.deviceId,
    required this.eventType,
    required this.severity,
    required this.source,
    required this.message,
    required this.status,
    this.metadata,
    this.triggeredAt,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.resolvedAt,
    this.createdAt,
  });

  final String id;
  final String deviceId;
  final String eventType;
  final EventSeverity severity;
  final String source;
  final String message;
  final EventStatus status;
  final Map<String, dynamic>? metadata;
  final DateTime? triggeredAt;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  String get typeLabel {
    switch (eventType) {
      case 'FIRE_DETECTED':
        return 'Api terdeteksi';
      case 'SMOKE_DETECTED':
        return 'Asap melewati ambang';
      case 'SOIL_DRY':
        return 'Tanah kering';
      case 'TEMPERATURE_HIGH':
        return 'Suhu tinggi';
      case 'SENSOR_ERROR':
        return 'Sensor bermasalah';
      case 'DEVICE_OFFLINE':
        return 'Perangkat offline';
      default:
        return eventType;
    }
  }

  String get timeLabel {
    final value = triggeredAt ?? createdAt;
    if (value == null) return '—';
    return value.toLocal().toString();
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    return Event(
      id: json['id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      severity: EventSeverity.fromApi(json['severity']),
      source: json['source']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      status: EventStatus.fromApi(json['status']),
      metadata: rawMetadata is Map ? parseMap(rawMetadata) : null,
      triggeredAt: parseDateTime(json['triggered_at']),
      acknowledgedBy: json['acknowledged_by']?.toString(),
      acknowledgedAt: parseDateTime(json['acknowledged_at']),
      resolvedAt: parseDateTime(json['resolved_at']),
      createdAt: parseDateTime(json['created_at']),
    );
  }
}
