import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../services/fcm_service.dart';
import '../services/realtime_service.dart';
import '../state/auth_controller.dart';
import 'router.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router;
  late final FcmService _fcmService;
  late final AuthController _authController;
  late final RealtimeService _realtimeService;
  late final VoidCallback _authListener;
  StreamSubscription<String>? _deviceTapSubscription;

  @override
  void initState() {
    super.initState();

    _authController = context.read<AuthController>();
    _fcmService = context.read<FcmService>();
    _realtimeService = context.read<RealtimeService>();
    _router = createRouter(_authController);

    _deviceTapSubscription = _fcmService.deviceTaps.listen(_handleDeviceTap);
    _authListener = _handleAuthChanged;
    _authController.addListener(_authListener);
    _handleAuthChanged();
  }

  void _handleDeviceTap(String deviceId) {
    if (deviceId.isEmpty) return;

    if (_authController.status != AuthStatus.authenticated) {
      return;
    }

    _fcmService.takePendingDeviceId();
    _router.go('/nodes/${Uri.encodeComponent(deviceId)}');
  }

  void _handleAuthChanged() {
    if (_authController.status != AuthStatus.authenticated) {
      unawaited(_realtimeService.stop());
      return;
    }

    unawaited(_realtimeService.start());

    final pendingDeviceId = _fcmService.takePendingDeviceId();
    if (pendingDeviceId == null || pendingDeviceId.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _router.go('/nodes/${Uri.encodeComponent(pendingDeviceId)}');
    });
  }

  @override
  void dispose() {
    _authController.removeListener(_authListener);
    _deviceTapSubscription?.cancel();
    unawaited(_realtimeService.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return MaterialApp.router(
      title: 'Fire Free Forest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.flutterMode,
      routerConfig: _router,
    );
  }
}
