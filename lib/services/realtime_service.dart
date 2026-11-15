import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config/server_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/realtime_event.dart';

class RealtimeService {
  RealtimeService({required ApiClient apiClient, required String apiBaseUrl})
    : _apiBaseUrl = ServerConfig.normalize(apiBaseUrl) {
    _apiClient = apiClient;
  }

  late final ApiClient _apiClient;
  String _apiBaseUrl;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  bool _started = false;
  bool _connecting = false;
  bool _hasConnected = false;
  int _attempt = 0;
  int _generation = 0;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> updateApiBaseUrl(String apiBaseUrl) async {
    final normalized = ServerConfig.normalize(apiBaseUrl);
    if (normalized == _apiBaseUrl) return;
    _apiBaseUrl = normalized;
    if (_started) {
      await stop();
      await start();
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _attempt = 0;
    await _connect(++_generation);
  }

  Future<void> stop() async {
    _started = false;
    _connecting = false;
    _attempt = 0;
    _hasConnected = false;
    _generation += 1;
    _retryTimer?.cancel();
    _retryTimer = null;

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  Future<void> _connect(int generation) async {
    if (!_started || _connecting || generation != _generation) return;
    _connecting = true;

    WebSocketChannel? channel;
    try {
      final ticket = await _fetchTicket();
      if (!_started || generation != _generation) {
        _connecting = false;
        return;
      }

      channel = WebSocketChannel.connect(_webSocketUri(ticket));
      await channel.ready.timeout(const Duration(seconds: 12));
      if (!_started || generation != _generation) {
        _connecting = false;
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _attempt = 0;
      _connecting = false;

      if (_hasConnected) {
        _events.add(const RealtimeEvent(type: RealtimeTypes.reconnected));
      }
      _hasConnected = true;

      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on ApiException catch (error) {
      if (generation != _generation) return;
      _connecting = false;
      if (error.isUnauthorized) {
        await stop();
        return;
      }
      await channel?.sink.close();
      _scheduleReconnect();
    } catch (_) {
      if (generation != _generation) return;
      _connecting = false;
      await channel?.sink.close();
      _scheduleReconnect();
    }
  }

  Future<String> _fetchTicket() async {
    final response = await _apiClient.postJson('/api/v1/realtime/ticket');
    final data = response['data'];
    if (data is! Map) {
      throw const ApiException(
        'Tiket realtime tidak tersedia.',
        code: 'invalid_response',
      );
    }
    final ticket = data['ticket']?.toString().trim();
    if (ticket == null || ticket.isEmpty) {
      throw const ApiException(
        'Tiket realtime tidak tersedia.',
        code: 'invalid_response',
      );
    }
    return ticket;
  }

  Uri _webSocketUri(String ticket) {
    final base = Uri.parse(_apiBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    return base.replace(
      scheme: scheme,
      path: '$path/api/v1/ws',
      queryParameters: {'ticket': ticket},
    );
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;

    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      final event = RealtimeEvent.tryParse(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (event != null) {
        _events.add(event);
      }
    } catch (_) {
      // Ignore malformed frames so one bad message does not break the stream.
    }
  }

  void _scheduleReconnect() {
    if (!_started || _retryTimer != null) return;

    _connecting = false;
    _attempt += 1;
    final generation = _generation;
    final seconds = min(30, 1 << min(_attempt, 5));

    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());

    final channel = _channel;
    _channel = null;
    unawaited(channel?.sink.close());

    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (generation == _generation) {
        unawaited(_connect(generation));
      }
    });
  }

  void dispose() {
    unawaited(stop());
    unawaited(_events.close());
  }
}
