import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum FireAlertChannel {
  fire(
    id: 'fire_alerts_fire',
    name: 'Kebakaran',
    description: 'Notifikasi darurat kebakaran Fire Free Forest',
    sound: 'notif_fire',
  ),
  warning(
    id: 'fire_alerts_warning',
    name: 'Peringatan',
    description: 'Notifikasi peringatan Fire Free Forest',
    sound: 'notif_smoke',
  ),
  sensorError(
    id: 'fire_alerts_error',
    name: 'Error sensor',
    description: 'Notifikasi error sensor Fire Free Forest',
    sound: 'notif_sensor_error',
  );

  const FireAlertChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.sound,
  });

  final String id;
  final String name;
  final String description;
  final String sound;

  AndroidNotificationChannel get androidChannel => AndroidNotificationChannel(
    id,
    name,
    description: description,
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound(sound),
  );

  static FireAlertChannel fromEventType(String? eventType) {
    switch (eventType?.trim().toUpperCase()) {
      case 'FIRE_DETECTED':
        return FireAlertChannel.fire;
      case 'SENSOR_ERROR':
      case 'DEVICE_OFFLINE':
        return FireAlertChannel.sensorError;
      default:
        return FireAlertChannel.warning;
    }
  }
}

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize({
    required void Function(String? payload) onNotificationTap,
  }) async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_notification',
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap(response.payload);
      },
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    for (final channel in FireAlertChannel.values) {
      await androidPlugin?.createNotificationChannel(channel.androidChannel);
    }
  }

  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> show({
    required String title,
    required String body,
    String? eventType,
    String? payload,
  }) async {
    final channel = FireAlertChannel.fromEventType(eventType);
    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(channel.sound),
      icon: '@drawable/ic_stat_notification',
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }
}
