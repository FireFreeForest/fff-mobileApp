import '../core/utils/json_utils.dart';
import 'device.dart';

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
    this.device,
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
    this.resolvedBy,
    this.timelinePreview = const [],
    this.timelineTotal = 0,
    this.timelineHasMore = false,
    this.createdAt,
  });

  final String id;
  final String deviceId;
  final Device? device;
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
  final String? resolvedBy;
  final List<EventTimeline> timelinePreview;
  final int timelineTotal;
  final bool timelineHasMore;
  final DateTime? createdAt;

  String get deviceCode => device?.deviceId ?? deviceId;
  String get deviceName => device?.displayName ?? deviceCode;
  String get deviceLocation => device?.locationLabel ?? '';

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
    final rawDevice = json['device'];
    return Event(
      id: json['id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      device: rawDevice is Map ? Device.fromJson(parseMap(rawDevice)) : null,
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
      resolvedBy: json['resolved_by']?.toString(),
      timelinePreview: json['timeline_preview'] is List
          ? (json['timeline_preview'] as List)
                .whereType<Map>()
                .map((item) => EventTimeline.fromJson(parseMap(item)))
                .toList()
          : const [],
      timelineTotal: parseInt(json['timeline_total']) ?? 0,
      timelineHasMore: json['timeline_has_more'] == true,
      createdAt: parseDateTime(json['created_at']),
    );
  }
}

class EventTimeline {
  const EventTimeline({
    required this.id,
    required this.eventId,
    required this.kind,
    required this.title,
    required this.description,
    this.outcome,
    required this.level,
    this.actor,
    this.metadata,
    this.occurredAt,
  });

  final int id;
  final String eventId;
  final String kind;
  final String title;
  final String description;
  final String? outcome;
  final String level;
  final Map<String, dynamic>? actor;
  final Map<String, dynamic>? metadata;
  final DateTime? occurredAt;

  factory EventTimeline.fromJson(Map<String, dynamic> json) {
    final rawActor = json['actor'];
    final rawMetadata = json['metadata'];
    return EventTimeline(
      id: parseInt(json['id']) ?? 0,
      eventId: json['event_id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      outcome: json['outcome']?.toString(),
      level: json['level']?.toString() ?? 'info',
      actor: rawActor is Map ? parseMap(rawActor) : null,
      metadata: rawMetadata is Map ? parseMap(rawMetadata) : null,
      occurredAt: parseDateTime(json['occurred_at']),
    );
  }
}
