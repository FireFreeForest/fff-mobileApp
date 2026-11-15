import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/utils/json_utils.dart';

class ProvisioningException implements Exception {
  const ProvisioningException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProvisioningStatus {
  const ProvisioningStatus({required this.raw});

  final Map<String, dynamic> raw;

  String get firmwareVersion =>
      raw['firmware_version']?.toString() ?? raw['version']?.toString() ?? '';

  String get deviceId => raw['device_id']?.toString() ?? '';
}

class ProvisioningService {
  ProvisioningService({
    this.baseUrl = 'http://192.168.4.1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<ProvisioningStatus> checkStatus() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProvisioningException(
          'Node merespons dengan status ${response.statusCode}.',
        );
      }

      final decoded = response.body.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(response.body);
      return ProvisioningStatus(
        raw: decoded is Map<String, dynamic> ? decoded : const {},
      );
    } on TimeoutException {
      throw const ProvisioningException(
        'Node tidak merespons. Pastikan ponsel tersambung ke WiFi FFF-Setup.',
      );
    } on http.ClientException {
      throw const ProvisioningException(
        'Tidak dapat menghubungi node. Sambungkan ponsel ke WiFi FFF-Setup.',
      );
    } on FormatException {
      throw const ProvisioningException(
        'Respons node tidak dapat dibaca. Coba sambungkan ulang.',
      );
    }
  }

  Future<void> provision({
    required String ssid,
    required String password,
    required String deviceId,
    required String name,
    required String locationName,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/provision'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ssid': ssid,
              'password': password,
              'device_id': deviceId,
              'name': name,
              'location_name': locationName,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }

      var message = 'Node menolak konfigurasi (${response.statusCode}).';
      final decoded = _tryDecode(response.body);
      final error = decoded['error'];
      final detail = decoded['message'];
      if (error is String && error.trim().isNotEmpty) {
        message = error;
      } else if (detail is String && detail.trim().isNotEmpty) {
        message = detail;
      }
      throw ProvisioningException(message);
    } on TimeoutException {
      throw const ProvisioningException(
        'Waktu penyambungan habis. Periksa kembali koneksi FFF-Setup lalu coba lagi.',
      );
    } on http.ClientException {
      throw const ProvisioningException(
        'Tidak dapat mengirim konfigurasi. Pastikan ponsel masih terhubung ke FFF-Setup.',
      );
    }
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? parseMap(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }
}
