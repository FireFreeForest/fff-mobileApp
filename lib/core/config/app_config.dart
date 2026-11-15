import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String provisioningBaseUrl = String.fromEnvironment(
    'PROVISIONING_BASE_URL',
    defaultValue: 'http://192.168.4.1',
  );

  static const String regionLabel = String.fromEnvironment(
    'REGION_LABEL',
    defaultValue: 'Wilayah pemantauan',
  );

  static const bool allowServerSwitch = bool.fromEnvironment(
    'ALLOW_SERVER_SWITCH',
    defaultValue: kDebugMode,
  );

  static const int smokeThresholdAdc = 500;
  static const int smokeMaxAdc = 4095;

  static String get normalizedApiBaseUrl {
    if (apiBaseUrl.endsWith('/')) {
      return apiBaseUrl.substring(0, apiBaseUrl.length - 1);
    }
    return apiBaseUrl;
  }
}
