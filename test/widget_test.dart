import 'dart:async';
import 'dart:convert';

import 'package:firefreeforest/core/network/api_client.dart';
import 'package:firefreeforest/core/storage/app_settings_store.dart';
import 'package:firefreeforest/core/storage/secure_token_store.dart';
import 'package:firefreeforest/data/command_repository.dart';
import 'package:firefreeforest/data/dashboard_repository.dart';
import 'package:firefreeforest/data/device_repository.dart';
import 'package:firefreeforest/data/event_repository.dart';
import 'package:firefreeforest/data/geocoding_repository.dart';
import 'package:firefreeforest/data/provisioning_service.dart';
import 'package:firefreeforest/features/analytics/analytics_screen.dart';
import 'package:firefreeforest/features/auth/login_screen.dart';
import 'package:firefreeforest/features/nodes/add_node_screen.dart';
import 'package:firefreeforest/features/history/history_screen.dart';
import 'package:firefreeforest/features/nodes/node_detail_screen.dart';
import 'package:firefreeforest/features/nodes/nodes_screen.dart';
import 'package:firefreeforest/features/status/status_screen.dart';
import 'package:firefreeforest/models/api_error.dart';
import 'package:firefreeforest/models/command.dart';
import 'package:firefreeforest/models/dashboard_summary.dart';
import 'package:firefreeforest/models/device.dart';
import 'package:firefreeforest/models/device_status.dart';
import 'package:firefreeforest/models/event.dart';
import 'package:firefreeforest/models/paginated.dart';
import 'package:firefreeforest/models/realtime_event.dart';
import 'package:firefreeforest/models/telemetry.dart';
import 'package:firefreeforest/models/token_pair.dart';
import 'package:firefreeforest/models/user.dart';
import 'package:firefreeforest/services/realtime_service.dart';
import 'package:firefreeforest/services/realtime_updater.dart';
import 'package:firefreeforest/state/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class FakeAuthController extends ChangeNotifier implements AuthController {
  FakeAuthController({
    this.canOperateValue = false,
    this.canManageDevicesValue = false,
  });

  final bool canOperateValue;
  final bool canManageDevicesValue;
  String? _errorMessage;

  @override
  AuthStatus get status => AuthStatus.unauthenticated;

  @override
  User? get user => null;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get isAuthenticated => false;

  @override
  bool get canOperate => canOperateValue;

  @override
  bool get canResolve => false;

  @override
  bool get canManageDevices => canManageDevicesValue;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<bool> login({required String email, required String password}) async {
    _errorMessage = 'Email atau kata sandi salah.';
    notifyListeners();
    return false;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> resetSessionForServerChange() async {}

  @override
  void handleSessionExpired() {}

  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockGeocodingRepository extends Mock implements GeocodingRepository {}

class MockProvisioningService extends Mock implements ProvisioningService {}

class MockSecureTokenStore extends Mock implements SecureTokenStore {}

class MockCommandRepository extends Mock implements CommandRepository {}

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockEventRepository extends Mock implements EventRepository {}

class FakeRealtimeService implements RealtimeService {
  final _events = StreamController<RealtimeEvent>.broadcast();

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateApiBaseUrl(String baseUrl) async {}

  void emit(RealtimeEvent event) => _events.add(event);

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

DeviceStatus _status({
  required String deviceId,
  required String name,
  required String location,
  required RiskLevel risk,
  required DeviceConnection connection,
  required int smoke,
  bool flame = false,
  double? latitude = -2.2,
  double? longitude = 113.9,
}) {
  final now = DateTime.now().toUtc();
  return DeviceStatus(
    device: Device(
      id: 'uuid-$deviceId',
      deviceId: deviceId,
      name: name,
      locationName: location,
      status: connection,
      firmwareVersion: '1.0.0',
      latitude: latitude,
      longitude: longitude,
      lastSeenAt: now,
    ),
    connection: connection,
    riskLevel: risk,
    lastSeenAt: now,
    environment: TelemetryEnvironment(
      id: 1,
      deviceId: 'uuid-$deviceId',
      temperature: 31.5,
      humidity: 60,
      soilMoisture: 45,
      recordedAt: now,
    ),
    fire: TelemetryFire(
      id: 1,
      deviceId: 'uuid-$deviceId',
      flameDetected: flame,
      smokeLevel: smoke,
      pump: flame,
      buzzer: false,
      recordedAt: now,
    ),
    serverTime: now,
  );
}

void main() {
  group('Event model', () {
    test('parses nested device and exposes display identifiers', () {
      final event = Event.fromJson({
        'id': 'event-1',
        'device_id': 'device-uuid',
        'device': {
          'id': 'device-uuid',
          'device_id': 'FFF-ABCDEFGH',
          'name': 'Blok A',
          'location_name': 'Sektor 1',
          'status': 'online',
          'firmware_version': '1.2.0',
        },
        'event_type': 'FIRE_DETECTED',
        'severity': 'critical',
        'status': 'active',
      });

      expect(event.deviceCode, 'FFF-ABCDEFGH');
      expect(event.deviceName, 'Blok A');
      expect(event.deviceLocation, 'Sektor 1');
      expect(event.device?.id, 'device-uuid');
    });

    test('falls back safely when nested device is absent', () {
      final event = Event.fromJson({
        'id': 'event-2',
        'device_id': 'device-uuid',
      });

      expect(event.device, isNull);
      expect(event.deviceCode, 'device-uuid');
      expect(event.deviceName, 'device-uuid');
    });
  });

  group('Telemetry model', () {
    test('accepts environment payload without DHT readings', () {
      final environment = TelemetryEnvironment.fromJson({
        'id': 1,
        'device_id': 'device-uuid',
        'soil_moisture': 640,
      });

      expect(environment.temperature, isNull);
      expect(environment.humidity, isNull);
      expect(environment.soilMoisture, 640);
    });

    test('parses optional flame level', () {
      final fire = TelemetryFire.fromJson({
        'id': 1,
        'device_id': 'device-uuid',
        'flame_detected': false,
        'flame_level': 900,
        'smoke_level': 180,
        'pump': false,
        'buzzer': false,
      });

      expect(fire.flameLevel, 900);
      expect(fire.smokeLevel, 180);
    });
  });

  group('Realtime updates', () {
    test('parses nested event device payload', () {
      final realtime = RealtimeEvent.tryParse({
        'type': RealtimeTypes.eventUpdated,
        'device_id': 'FFF-ABCDEFGH',
        'data': {
          'event': {
            'id': 'event-1',
            'device_id': 'device-uuid',
            'device': {
              'id': 'device-uuid',
              'device_id': 'FFF-ABCDEFGH',
              'name': 'Blok A',
              'location_name': 'Sektor 1',
              'status': 'online',
            },
            'event_type': 'FIRE_DETECTED',
            'severity': 'critical',
            'status': 'acknowledged',
          },
        },
      });

      expect(realtime?.eventPayload?.deviceCode, 'FFF-ABCDEFGH');
      expect(realtime?.eventPayload?.deviceLocation, 'Sektor 1');
    });

    test('applies telemetry, risk, and device status events', () {
      final status = _status(
        deviceId: 'FFF-01',
        name: 'Kereng Bangkirai',
        location: 'Kereng Bangkirai',
        risk: RiskLevel.normal,
        connection: DeviceConnection.online,
        smoke: 120,
      );

      final fireUpdated = applyRealtimeToStatus(
        status,
        RealtimeEvent(
          type: RealtimeTypes.telemetryFire,
          deviceId: 'FFF-01',
          data: {
            'telemetry': {
              'id': 9,
              'device_id': 'uuid-FFF-01',
              'flame_detected': false,
              'flame_level': 900,
              'smoke_level': 620,
              'pump': true,
              'buzzer': false,
            },
          },
        ),
      );

      expect(fireUpdated.fire?.smokeLevel, 620);
      expect(fireUpdated.fire?.pump, isTrue);

      final riskUpdated = applyRealtimeToStatus(
        fireUpdated,
        const RealtimeEvent(
          type: RealtimeTypes.riskUpdated,
          deviceId: 'FFF-01',
          data: {'level': 'BAHAYA'},
        ),
      );

      expect(riskUpdated.riskLevel, RiskLevel.bahaya);

      final offline = applyRealtimeToStatus(
        riskUpdated,
        const RealtimeEvent(
          type: RealtimeTypes.deviceStatus,
          deviceId: 'FFF-01',
          data: {'status': 'offline', 'online': false},
        ),
      );

      expect(offline.connection, DeviceConnection.offline);
      expect(offline.lastSeenAt, riskUpdated.lastSeenAt);
    });
  });

  group('UserRole', () {
    test('maps API values safely', () {
      expect(UserRole.fromApi('admin'), UserRole.admin);
      expect(UserRole.fromApi('petugas'), UserRole.petugas);
      expect(UserRole.fromApi('viewer'), UserRole.viewer);
      expect(UserRole.fromApi('unknown'), UserRole.viewer);
    });

    test('follows backend permission rules', () {
      expect(UserRole.admin.canOperate, isTrue);
      expect(UserRole.admin.canManageDevices, isTrue);
      expect(UserRole.admin.canResolve, isFalse);

      expect(UserRole.petugas.canOperate, isTrue);
      expect(UserRole.petugas.canResolve, isTrue);
      expect(UserRole.petugas.canManageDevices, isFalse);

      expect(UserRole.viewer.canOperate, isFalse);
      expect(UserRole.viewer.canResolve, isFalse);
      expect(UserRole.viewer.canManageDevices, isFalse);
    });
  });

  test('User parses login payload', () {
    final user = User.fromJson({
      'id': 'user-1',
      'name': 'Operator',
      'email': 'operator@example.com',
      'role': 'petugas',
      'is_active': true,
    });

    expect(user.displayName, 'Operator');
    expect(user.role, UserRole.petugas);
    expect(user.isActive, isTrue);
  });

  test('TokenPair parses token response', () {
    final tokens = TokenPair.fromJson({
      'access_token': 'access',
      'refresh_token': 'refresh',
      'token_type': 'Bearer',
    });

    expect(tokens.accessToken, 'access');
    expect(tokens.refreshToken, 'refresh');
    expect(tokens.tokenType, 'Bearer');
  });

  test('ApiError parses backend error envelope', () {
    final error = ApiError.fromJson({
      'error': {
        'code': 'invalid_credentials',
        'message': 'Email atau kata sandi salah.',
      },
    });

    expect(error.code, 'invalid_credentials');
    expect(error.message, 'Email atau kata sandi salah.');
  });

  testWidgets('login screen validates and shows login errors', (tester) async {
    final auth = FakeAuthController();
    final apiClient = ApiClient(
      baseUrl: 'http://localhost:8080',
      tokenStore: SecureTokenStore(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<ApiClient>.value(value: apiClient),
          Provider<RealtimeService>(
            create: (_) => RealtimeService(
              apiClient: apiClient,
              apiBaseUrl: apiClient.baseUrl,
            ),
            dispose: (_, service) => service.dispose(),
          ),
          Provider<AppSettingsStore>(create: (_) => AppSettingsStore()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Masuk ke pusat pemantauan'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata sandi'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('localhost:8080'), findsOneWidget);

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Email wajib diisi.'), findsOneWidget);
    expect(find.text('Kata sandi wajib diisi.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'operator@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Email atau kata sandi salah.'), findsWidgets);
  });

  testWidgets('node list shows urgency, raw smoke ADC, and filters', (
    tester,
  ) async {
    final repo = MockDeviceRepository();
    final auth = FakeAuthController();
    final realtime = FakeRealtimeService();
    final danger = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.bahaya,
      connection: DeviceConnection.online,
      smoke: 342,
      flame: true,
    );
    final normal = _status(
      deviceId: 'FFF-01',
      name: 'Kereng Bangkirai',
      location: 'Kereng Bangkirai',
      risk: RiskLevel.normal,
      connection: DeviceConnection.online,
      smoke: 120,
    );

    when(() => repo.listStatuses()).thenAnswer((_) async => [normal, danger]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<DeviceRepository>.value(value: repo),
          Provider<RealtimeService>.value(value: realtime),
        ],
        child: const MaterialApp(home: NodesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FFF-03 · Sei Sebangau'), findsOneWidget);
    expect(find.text('FFF-01 · Kereng Bangkirai'), findsOneWidget);
    expect(find.text('342'), findsOneWidget);

    realtime.emit(
      RealtimeEvent(
        type: RealtimeTypes.telemetryFire,
        deviceId: 'FFF-01',
        data: {
          'telemetry': {
            'id': 99,
            'device_id': 'uuid-FFF-01',
            'flame_detected': false,
            'flame_level': 900,
            'smoke_level': 620,
            'pump': false,
            'buzzer': false,
          },
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('620'), findsOneWidget);

    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Node tidak ditemukan'), findsOneWidget);
  });

  testWidgets('status map shows filters, online count, and node selection', (
    tester,
  ) async {
    final repo = MockDeviceRepository();
    final realtime = FakeRealtimeService();
    final danger = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.bahaya,
      connection: DeviceConnection.online,
      smoke: 342,
      flame: true,
      latitude: -2.2,
      longitude: 113.9,
    );
    final normal = _status(
      deviceId: 'FFF-01',
      name: 'Kereng Bangkirai',
      location: 'Kereng Bangkirai',
      risk: RiskLevel.normal,
      connection: DeviceConnection.online,
      smoke: 120,
      latitude: -2.35,
      longitude: 113.75,
    );
    final offline = _status(
      deviceId: 'FFF-02',
      name: 'Tanjung Puting',
      location: 'Tanjung Puting',
      risk: RiskLevel.unknown,
      connection: DeviceConnection.offline,
      smoke: 0,
      latitude: -2.5,
      longitude: 114.05,
    );

    when(() => repo.listStatuses())
        .thenAnswer((_) async => [normal, danger, offline]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(
            value: FakeAuthController(),
          ),
          Provider<DeviceRepository>.value(value: repo),
          Provider<RealtimeService>.value(value: realtime),
        ],
        child: const MaterialApp(home: StatusScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('Bahaya'), findsWidgets);
    expect(find.text('Waspada'), findsWidgets);
    expect(find.text('Offline'), findsWidgets);
    expect(find.textContaining('Wilayah pemantauan'), findsOneWidget);
    expect(find.text('3 node · 2 online'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await tester.tap(find.text('FFF-03').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('NODE TERPILIH'), findsOneWidget);
    expect(find.text('Buka detail node'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);

    await tester.tap(find.bySemanticsLabel(RegExp('Filter Bahaya')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('STATUS WILAYAH'), findsOneWidget);
    expect(find.text('1 node · 1 online'), findsOneWidget);
  });

  testWidgets('node detail displays readings and smoke history', (
    tester,
  ) async {
    final repo = MockDeviceRepository();
    final status = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.bahaya,
      connection: DeviceConnection.online,
      smoke: 342,
      flame: true,
    );
    final now = DateTime.now().toUtc();
    final history = Paginated<TelemetryFire>(
      items: [
        TelemetryFire(
          id: 1,
          deviceId: 'uuid-FFF-03',
          flameDetected: false,
          smokeLevel: 180,
          pump: false,
          buzzer: false,
          recordedAt: now.subtract(const Duration(minutes: 10)),
        ),
        TelemetryFire(
          id: 2,
          deviceId: 'uuid-FFF-03',
          flameDetected: true,
          smokeLevel: 342,
          pump: true,
          buzzer: false,
          recordedAt: now,
        ),
      ],
      page: 1,
      perPage: 30,
      total: 2,
    );

    when(() => repo.getStatus('FFF-03')).thenAnswer((_) async => status);
    when(() => repo.listFireHistory('FFF-03', perPage: 30))
        .thenAnswer((_) async => history);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(
            value: FakeAuthController(),
          ),
          Provider<DeviceRepository>.value(value: repo),
          Provider<RealtimeService>.value(value: FakeRealtimeService()),
        ],
        child: const MaterialApp(home: NodeDetailScreen(deviceId: 'FFF-03')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FFF-03 · Sei Sebangau'), findsOneWidget);
    expect(find.text('Ambang bahaya ≥ 500 ADC'), findsOneWidget);
    expect(find.text('342'), findsWidgets);
    expect(find.text('Menyala'), findsOneWidget);
  });

  testWidgets('pump control issues a manual command', (tester) async {
    final deviceRepo = MockDeviceRepository();
    final commandRepo = MockCommandRepository();
    final status = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.normal,
      connection: DeviceConnection.online,
      smoke: 120,
    );
    final history = Paginated.empty<TelemetryFire>();
    final command = Command(
      id: 'command-uuid',
      commandId: 'CMD-001',
      deviceId: 'uuid-FFF-03',
      action: 'SET_PUMP',
      payload: const {'state': true, 'duration': 30},
      status: CommandStatus.success,
      origin: 'manual',
      ackMessage: 'Pompa menyala',
    );

    when(() => deviceRepo.getStatus('FFF-03')).thenAnswer((_) async => status);
    when(() => deviceRepo.listFireHistory('FFF-03', perPage: 30))
        .thenAnswer((_) async => history);
    when(
      () => commandRepo.issuePump(
        deviceId: 'FFF-03',
        state: true,
        duration: any(named: 'duration'),
      ),
    ).thenAnswer((_) async => command);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(
            value: FakeAuthController(canOperateValue: true),
          ),
          Provider<DeviceRepository>.value(value: deviceRepo),
          Provider<CommandRepository>.value(value: commandRepo),
          Provider<RealtimeService>.value(value: FakeRealtimeService()),
        ],
        child: const MaterialApp(home: NodeDetailScreen(deviceId: 'FFF-03')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nyalakan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Perintah Berhasil'), findsOneWidget);
    verify(
      () => commandRepo.issuePump(
        deviceId: 'FFF-03',
        state: true,
        duration: any(named: 'duration'),
      ),
    ).called(1);
  });

  testWidgets('analytics shows summary, threshold, ranking, and events', (
    tester,
  ) async {
    final deviceRepo = MockDeviceRepository();
    final dashboardRepo = MockDashboardRepository();
    final danger = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.bahaya,
      connection: DeviceConnection.online,
      smoke: 620,
      flame: true,
    );
    final normal = _status(
      deviceId: 'FFF-01',
      name: 'Kereng Bangkirai',
      location: 'Kereng Bangkirai',
      risk: RiskLevel.normal,
      connection: DeviceConnection.online,
      smoke: 120,
    );
    final summary = DashboardSummary.fromJson({
      'devices': {'total': 2, 'online': 2, 'offline': 0},
      'risk': {
        'counts': {
          'NORMAL': 1,
          'WASPADA': 0,
          'BAHAYA': 1,
          'DARURAT': 0,
          'UNKNOWN': 0,
        },
      },
      'active_events': {
        'total': 1,
        'by_severity': {'critical': 1, 'error': 0, 'warning': 0},
      },
      'recent_events': [
        {
          'id': 'event-1',
          'device_id': 'uuid-FFF-03',
          'event_type': 'FIRE_DETECTED',
          'severity': 'critical',
          'source': 'sensor',
          'message': 'Api terdeteksi',
          'status': 'active',
          'triggered_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });

    when(() => deviceRepo.listStatuses())
        .thenAnswer((_) async => [normal, danger]);
    when(() => dashboardRepo.getSummary()).thenAnswer((_) async => summary);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DeviceRepository>.value(value: deviceRepo),
          Provider<DashboardRepository>.value(value: dashboardRepo),
          Provider<RealtimeService>.value(value: FakeRealtimeService()),
        ],
        child: const MaterialApp(home: AnalyticsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rata-rata asap'), findsOneWidget);
    expect(find.textContaining('370', findRichText: true), findsOneWidget);
    expect(find.text('1 / 2', findRichText: true), findsOneWidget);
    expect(find.text('620'), findsWidgets);
    expect(find.text('Api terdeteksi'), findsOneWidget);
    expect(find.text('FFF-03 · Menunggu'), findsOneWidget);
  });

  testWidgets('history lists events and acknowledges from detail sheet', (
    tester,
  ) async {
    final deviceRepo = MockDeviceRepository();
    final eventRepo = MockEventRepository();
    final status = _status(
      deviceId: 'FFF-03',
      name: 'Sei Sebangau',
      location: 'Sei Sebangau',
      risk: RiskLevel.bahaya,
      connection: DeviceConnection.online,
      smoke: 342,
      flame: true,
    );
    final event = Event(
      id: 'event-1',
      deviceId: 'uuid-FFF-03',
      eventType: 'FIRE_DETECTED',
      severity: EventSeverity.critical,
      source: 'sensor',
      message: 'Potensi kebakaran terdeteksi.',
      status: EventStatus.active,
      triggeredAt: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );
    final acknowledged = Event(
      id: event.id,
      deviceId: event.deviceId,
      eventType: event.eventType,
      severity: event.severity,
      source: event.source,
      message: event.message,
      status: EventStatus.acknowledged,
      triggeredAt: event.triggeredAt,
      acknowledgedAt: DateTime.now().toUtc(),
      createdAt: event.createdAt,
    );

    when(() => deviceRepo.listAllDevices())
        .thenAnswer((_) async => [status.device]);
    when(
      () => eventRepo.listEvents(
        severity: null,
        eventType: null,
        page: 1,
        perPage: 20,
      ),
    ).thenAnswer(
      (_) async =>
          Paginated<Event>(items: [event], page: 1, perPage: 20, total: 1),
    );
    when(() => eventRepo.acknowledge('event-1'))
        .thenAnswer((_) async => acknowledged);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(
            value: FakeAuthController(canOperateValue: true),
          ),
          Provider<DeviceRepository>.value(value: deviceRepo),
          Provider<EventRepository>.value(value: eventRepo),
          Provider<RealtimeService>.value(value: FakeRealtimeService()),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HARI INI'), findsOneWidget);
    expect(find.text('FFF-03'), findsOneWidget);
    expect(find.text('Api terdeteksi'), findsOneWidget);

    await tester.tap(find.text('Api terdeteksi'));
    await tester.pumpAndSettle();

    expect(find.text('Detail Kejadian'), findsOneWidget);
    expect(find.text('Tandai Ditangani'), findsOneWidget);

    await tester.ensureVisible(find.text('Tandai Ditangani'));
    await tester.tap(find.text('Tandai Ditangani'));
    await tester.pumpAndSettle();

    verify(() => eventRepo.acknowledge('event-1')).called(1);
    expect(find.text('Status kejadian diperbarui.'), findsOneWidget);
  });

  testWidgets('add node relies on the server-generated device ID', (
    tester,
  ) async {
    final auth = FakeAuthController(canManageDevicesValue: true);
    final realtime = FakeRealtimeService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<DeviceRepository>.value(value: MockDeviceRepository()),
          Provider<GeocodingRepository>.value(value: MockGeocodingRepository()),
          Provider<ProvisioningService>.value(value: MockProvisioningService()),
          Provider<RealtimeService>.value(value: realtime),
        ],
        child: const MaterialApp(home: AddNodeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ID perangkat'), findsNothing);
    expect(find.textContaining('dibuat otomatis oleh server'), findsOneWidget);
  });

  test('device repository lets the backend assign the device ID', () async {
    final tokenStore = MockSecureTokenStore();
    when(() => tokenStore.readAccessToken()).thenAnswer((_) async => 'token');
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        '{"data":{"id":"uuid-1","device_id":"FFF-ABCDEFGH",'
        '"name":"Pos Sebangau","location_name":"Pos Sebangau",'
        '"status":"offline","firmware_version":""}}',
        201,
      );
    });
    final apiClient = ApiClient(
      baseUrl: 'http://localhost:8080',
      tokenStore: tokenStore,
      httpClient: client,
    );
    final repository = DeviceRepository(apiClient: apiClient);

    final device = await repository.createDevice(
      name: 'Pos Sebangau',
      locationName: 'Pos Sebangau',
      latitude: -2.2,
      longitude: 113.9,
    );

    expect(device.deviceId, 'FFF-ABCDEFGH');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/devices');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.containsKey('device_id'), isFalse);
    expect(body.containsKey('firmware_version'), isFalse);
    expect(body['location_name'], 'Pos Sebangau');
  });

  test('geocoding repository returns the backend label', () async {
    final tokenStore = MockSecureTokenStore();
    when(() => tokenStore.readAccessToken()).thenAnswer((_) async => 'token');
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"data":{"label":"Sebangau, Palangka Raya"}}', 200);
    });
    final apiClient = ApiClient(
      baseUrl: 'http://localhost:8080',
      tokenStore: tokenStore,
      httpClient: client,
    );
    final repository = GeocodingRepository(apiClient: apiClient);

    final label = await repository.reverseLabel(
      latitude: -2.2,
      longitude: 113.9,
    );

    expect(label, 'Sebangau, Palangka Raya');
    expect(captured.url.path, '/api/v1/geocode/reverse');
    expect(captured.url.queryParameters['lat'], '-2.200000');
    expect(captured.url.queryParameters['lon'], '113.900000');
  });

  test('provisioning service sends SoftAP payload', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"ok":true}', 200);
    });
    final service = ProvisioningService(
      baseUrl: 'http://192.168.4.1',
      client: client,
    );

    await service.provision(
      ssid: 'Pos-Sebangau',
      password: 'rahasia123',
      deviceId: 'FFF-09',
      name: 'Sei Sebangau',
      locationName: 'Sei Sebangau',
      latitude: -2.2,
      longitude: 113.9,
    );

    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'http://192.168.4.1/provision');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['ssid'], 'Pos-Sebangau');
    expect(body['password'], 'rahasia123');
    expect(body['device_id'], 'FFF-09');
    expect(body['latitude'], -2.2);
    expect(body['longitude'], 113.9);
  });

  test('provisioning service surfaces firmware errors', () async {
    final client = MockClient(
      (_) async => http.Response('{"error":"WiFi gagal tersambung"}', 400),
    );
    final service = ProvisioningService(
      baseUrl: 'http://192.168.4.1',
      client: client,
    );

    await expectLater(
      service.provision(
        ssid: 'Pos-Sebangau',
        password: '',
        deviceId: 'FFF-09',
        name: 'Sei Sebangau',
        locationName: 'Sei Sebangau',
        latitude: -2.2,
        longitude: 113.9,
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.message,
          'message',
          'WiFi gagal tersambung',
        ),
      ),
    );
  });
}
