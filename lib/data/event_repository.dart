import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/event.dart';
import '../models/paginated.dart';

class EventRepository {
  EventRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<Paginated<Event>> listEvents({
    String? severity,
    String? status,
    String? eventType,
    String? deviceId,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/events',
      query: {
        if (severity != null && severity.isNotEmpty) 'severity': severity,
        if (status != null && status.isNotEmpty) 'status': status,
        if (eventType != null && eventType.isNotEmpty) 'event_type': eventType,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return Paginated.fromJson(response, Event.fromJson);
  }

  Future<Event> getEvent(String eventId) async {
    final response = await _apiClient.getJson('/api/v1/events/$eventId');
    return Event.fromJson(parseMap(response['data']));
  }

  Future<Event> acknowledge(String eventId) async {
    final response = await _apiClient.postJson(
      '/api/v1/events/$eventId/acknowledge',
    );
    return Event.fromJson(parseMap(response['data']));
  }

  Future<Event> resolve(String eventId) async {
    final response = await _apiClient.postJson(
      '/api/v1/events/$eventId/resolve',
    );
    return Event.fromJson(parseMap(response['data']));
  }

  Future<Paginated<EventTimeline>> listTimeline(
    String eventId, {
    String include = 'all',
    int page = 1,
    int perPage = 50,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/events/$eventId/timeline',
      query: {
        'include': include,
        'page': '$page',
        'per_page': '$perPage',
      },
    );
    return Paginated.fromJson(response, EventTimeline.fromJson);
  }
}
