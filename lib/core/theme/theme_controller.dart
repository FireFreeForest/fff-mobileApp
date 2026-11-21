import 'package:flutter/material.dart';

import '../storage/app_settings_store.dart';

enum AppThemeMode { system, light, dark }

class ThemeController extends ChangeNotifier {
  ThemeController({required AppSettingsStore settingsStore})
    : _settingsStore = settingsStore;

  final AppSettingsStore _settingsStore;
  AppThemeMode _mode = AppThemeMode.system;
  bool _loaded = false;

  AppThemeMode get mode => _mode;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final stored = await _settingsStore.readThemeMode();
    _mode = switch (stored) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _settingsStore.saveThemeMode(switch (mode) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    });
  }

  ThemeMode get flutterMode => switch (_mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
