import '../core/utils/json_utils.dart';
import '../models/device.dart';
import '../models/device_status.dart';
import '../models/realtime_event.dart';
import '../models/telemetry.dart';

DeviceStatus applyRealtimeToStatus(DeviceStatus current, RealtimeEvent event) {
  switch (event.type) {
    case RealtimeTypes.telemetryEnvironment:
      final payload = event.telemetry;
      if (payload.isEmpty) return current;
      final environment = TelemetryEnvironment.fromJson(payload);
      return current.copyWith(
        connection: DeviceConnection.online,
        environment: environment,
        lastSeenAt: _latest(
          current.lastSeenAt,
          environment.receivedAt ?? environment.recordedAt ?? event.timestamp,
        ),
      );

    case RealtimeTypes.telemetryFire:
      final payload = event.telemetry;
      if (payload.isEmpty) return current;
      final fire = TelemetryFire.fromJson(payload);
      return current.copyWith(
        connection: DeviceConnection.online,
        fire: fire,
        lastSeenAt: _latest(
          current.lastSeenAt,
          fire.receivedAt ?? fire.recordedAt ?? event.timestamp,
        ),
      );

    case RealtimeTypes.riskUpdated:
      final rawLevel = event.data['level'];
      if (rawLevel == null) return current;
      return current.copyWith(riskLevel: RiskLevel.fromApi(rawLevel));

    case RealtimeTypes.deviceStatus:
      final rawStatus = event.data['status'];
      final rawOnline = event.data['online'];
      if (rawStatus == null && rawOnline == null) return current;

      final online =
          rawOnline == true || rawStatus?.toString().toLowerCase() == 'online';
      return current.copyWith(
        connection: online ? DeviceConnection.online : DeviceConnection.offline,
        lastSeenAt: _latest(
          current.lastSeenAt,
          parseDateTime(event.data['last_seen_at']) ??
              (online ? event.timestamp : null),
        ),
      );

    default:
      return current;
  }
}

DateTime? _latest(DateTime? first, DateTime? second) {
  if (first == null) return second;
  if (second == null) return first;
  return second.isAfter(first) ? second : first;
}
