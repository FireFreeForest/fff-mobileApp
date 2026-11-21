import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/config/server_config.dart';
import 'core/network/api_client.dart';
import 'core/storage/app_settings_store.dart';
import 'core/storage/secure_token_store.dart';
import 'core/theme/theme_controller.dart';
import 'data/auth_repository.dart';
import 'data/command_repository.dart';
import 'data/dashboard_repository.dart';
import 'data/device_repository.dart';
import 'data/event_repository.dart';
import 'data/geocoding_repository.dart';
import 'data/provisioning_service.dart';
import 'data/push_repository.dart';
import 'data/user_repository.dart';
import 'services/fcm_service.dart';
import 'services/realtime_service.dart';
import 'state/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final tokenStore = SecureTokenStore();
  final settingsStore = AppSettingsStore();
  final storedBaseUrl = await settingsStore.readApiBaseUrl();
  final initialBaseUrl = AppConfig.allowServerSwitch
      ? ServerConfig.normalizeOrDefault(
          storedBaseUrl,
          AppConfig.normalizedApiBaseUrl,
        )
      : AppConfig.normalizedApiBaseUrl;
  final apiClient = ApiClient(baseUrl: initialBaseUrl, tokenStore: tokenStore);
  final authRepository = AuthRepository(
    apiClient: apiClient,
    tokenStore: tokenStore,
  );
  final pushRepository = PushRepository(apiClient: apiClient);
  final userRepository = UserRepository(apiClient: apiClient);
  final deviceRepository = DeviceRepository(apiClient: apiClient);
  final geocodingRepository = GeocodingRepository(apiClient: apiClient);
  final commandRepository = CommandRepository(apiClient: apiClient);
  final dashboardRepository = DashboardRepository(apiClient: apiClient);
  final eventRepository = EventRepository(apiClient: apiClient);
  final provisioningService = ProvisioningService(
    baseUrl: AppConfig.provisioningBaseUrl,
  );
  final fcmService = FcmService(
    apiClient: apiClient,
    pushRepository: pushRepository,
    tokenStore: tokenStore,
  );
  final realtimeService = RealtimeService(
    apiClient: apiClient,
    apiBaseUrl: initialBaseUrl,
  );
  final themeController = ThemeController(settingsStore: settingsStore);
  await themeController.load();

  await fcmService.initialize();

  final authController = AuthController(
    authRepository: authRepository,
    tokenStore: tokenStore,
    fcmService: fcmService,
  );
  apiClient.onUnauthorized = authController.handleSessionExpired;

  unawaited(authController.bootstrap());

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<AppSettingsStore>.value(value: settingsStore),
        Provider<AuthRepository>.value(value: authRepository),
        Provider<DeviceRepository>.value(value: deviceRepository),
        Provider<GeocodingRepository>.value(value: geocodingRepository),
        Provider<CommandRepository>.value(value: commandRepository),
        Provider<DashboardRepository>.value(value: dashboardRepository),
        Provider<EventRepository>.value(value: eventRepository),
        Provider<ProvisioningService>.value(value: provisioningService),
        Provider<PushRepository>.value(value: pushRepository),
        Provider<UserRepository>.value(value: userRepository),
        Provider<FcmService>.value(value: fcmService),
        Provider<RealtimeService>.value(value: realtimeService),
        ChangeNotifierProvider<AuthController>.value(value: authController),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const App(),
    ),
  );
}
