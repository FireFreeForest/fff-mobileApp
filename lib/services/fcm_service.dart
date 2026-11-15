import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/storage/secure_token_store.dart';
import '../data/push_repository.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('BACKGROUND MESSAGE: ${message.messageId}');
}

class FcmService {
  FcmService({
    required this._apiClient,
    required this._pushRepository,
    required this._tokenStore,
    LocalNotificationService? localNotifications,
  }) : _localNotifications = localNotifications ?? LocalNotificationService();

  final ApiClient _apiClient;
  final PushRepository _pushRepository;
  final SecureTokenStore _tokenStore;
  final LocalNotificationService _localNotifications;

  final StreamController<String> _deviceTapController =
      StreamController<String>.broadcast();

  String? _pendingDeviceId;
  String? _token;

  Stream<String> get deviceTaps => _deviceTapController.stream;

  String? takePendingDeviceId() {
    final deviceId = _pendingDeviceId;
    _pendingDeviceId = null;
    return deviceId;
  }

  Future<void> initialize() async {
    await _localNotifications.initialize(
      onNotificationTap: _handleNotificationPayload,
    );

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('Notification permission: ${settings.authorizationStatus}');

    await _localNotifications.requestPermission();

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }

    // The backend stores legacy FCM registration tokens.
    // ignore: deprecated_member_use
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _token = newToken;
      unawaited(syncToken());
    });

    await _loadToken();
  }

  Future<void> syncToken() async {
    final token = await _loadToken();
    if (token == null || token.isEmpty) return;

    final accessToken = await _tokenStore.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;

    try {
      await _pushRepository.registerToken(token);
      debugPrint('FCM token registered.');
    } catch (error) {
      debugPrint('FCM token registration failed: $error');
    }
  }

  Future<void> unregisterToken() async {
    final token = _token ?? await _loadToken();
    if (token == null || token.isEmpty) return;

    try {
      await _pushRepository.deleteToken(token);
      debugPrint('FCM token removed.');
    } catch (error) {
      debugPrint('FCM token removal failed: $error');
    }
  }

  Future<String?> _loadToken() async {
    if (_token != null && _token!.isNotEmpty) {
      return _token;
    }

    try {
      // The backend stores legacy FCM registration tokens.
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('FCM token unavailable: $error');
    }
    return _token;
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final title = message.notification?.title ?? 'Peringatan Fire Free Forest';
    final body = message.notification?.body ?? _bodyFromData(data);

    await _localNotifications.show(
      title: title,
      body: body,
      eventType: data['event_type']?.toString(),
      payload: jsonEncode({'device_id': data['device_id']}),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final deviceId = message.data['device_id']?.toString();
    if (deviceId != null && deviceId.isNotEmpty) {
      _emitDevice(deviceId);
    }
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final deviceId = decoded['device_id']?.toString();
        if (deviceId != null && deviceId.isNotEmpty) {
          _emitDevice(deviceId);
        }
      }
    } catch (error) {
      debugPrint('Invalid notification payload: $error');
    }
  }

  void _emitDevice(String deviceId) {
    _pendingDeviceId = deviceId;
    if (!_deviceTapController.isClosed) {
      _deviceTapController.add(deviceId);
    }
  }

  String _bodyFromData(Map<String, dynamic> data) {
    final deviceName = data['device_name']?.toString();
    final eventType = data['event_type']?.toString();

    if (deviceName != null && deviceName.isNotEmpty) {
      return 'Peringatan dari $deviceName';
    }
    if (eventType != null && eventType.isNotEmpty) {
      return 'Peringatan baru: $eventType';
    }
    return 'Peringatan baru diterima.';
  }

  void dispose() {
    _deviceTapController.close();
    _apiClient.close();
  }
}
