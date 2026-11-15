import '../core/utils/json_utils.dart';

class RealtimeTypes {
  const RealtimeTypes._();

  static const connected = 'connected';
  static const reconnected = 'realtime.reconnected';
  static const telemetryEnvironment = 'telemetry.environment';
  static const telemetryFire = 'telemetry.fire';
  static const riskUpdated = 'risk.updated';
  static const eventCreated = 'event.created';
  static const eventResolved = 'event.resolved';
  static const deviceStatus = 'device.status';
  static const commandIssued = 'command.issued';
  static const commandAck = 'command.ack';
  static const commandTimeout = 'command.timeout';
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    this.deviceId,
    this.data = const {},
    this.timestamp,
  });

  final String type;
  final String? deviceId;
  final Map<String, dynamic> data;
  final DateTime? timestamp;

  bool get isTelemetry => type.startsWith('telemetry.');
  bool get isEvent => type.startsWith('event.');
  bool get isCommand => type.startsWith('command.');

  Map<String, dynamic> get telemetry => parseMap(data['telemetry']);

  String? get commandId {
    final value = data['command_id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static RealtimeEvent? tryParse(Map<String, dynamic> json) {
    final type = json['type']?.toString().trim() ?? '';
    if (type.isEmpty) return null;

    return RealtimeEvent(
      type: type,
      deviceId: json['device_id']?.toString(),
      data: parseMap(json['data']),
      timestamp: parseDateTime(json['ts'] ?? json['timestamp']),
    );
  }
}
