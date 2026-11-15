import '../core/utils/json_utils.dart';
import 'event.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalDevices,
    required this.onlineDevices,
    required this.offlineDevices,
    required this.riskCounts,
    required this.activeEvents,
    required this.activeEventsBySeverity,
    required this.recentEvents,
  });

  final int totalDevices;
  final int onlineDevices;
  final int offlineDevices;
  final Map<String, int> riskCounts;
  final int activeEvents;
  final Map<String, int> activeEventsBySeverity;
  final List<Event> recentEvents;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final devices = parseMap(json['devices']);
    final risk = parseMap(json['risk']);
    final active = parseMap(json['active_events']);

    Map<String, int> intMap(dynamic value) {
      final map = parseMap(value);
      return map.map((key, item) => MapEntry(key, parseInt(item) ?? 0));
    }

    return DashboardSummary(
      totalDevices: parseInt(devices['total']) ?? 0,
      onlineDevices: parseInt(devices['online']) ?? 0,
      offlineDevices: parseInt(devices['offline']) ?? 0,
      riskCounts: intMap(risk['counts']),
      activeEvents: parseInt(active['total']) ?? 0,
      activeEventsBySeverity: intMap(active['by_severity']),
      recentEvents: parseMapList(json['recent_events'])
          .map(Event.fromJson)
          .toList(),
    );
  }
}
