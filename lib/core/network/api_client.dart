import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/token_pair.dart';
import '../config/server_config.dart';
import '../storage/secure_token_store.dart';
import '../utils/json_utils.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this._tokenStore,
    http.Client? httpClient,
  }) : _baseUrl = ServerConfig.normalize(baseUrl),
       _httpClient = httpClient ?? http.Client();

  String _baseUrl;
  final SecureTokenStore _tokenStore;
  final http.Client _httpClient;

  String get baseUrl => _baseUrl;

  Future<bool>? _refreshFuture;
  void Function()? onUnauthorized;

  void updateBaseUrl(String baseUrl) {
    final normalized = ServerConfig.normalize(baseUrl);
    if (normalized == _baseUrl) return;
    _baseUrl = normalized;
    _refreshFuture = null;
  }

  Future<void> probeHealth(String baseUrl) async {
    final normalized = ServerConfig.normalize(baseUrl);
    final response = await _raw('GET', Uri.parse('$normalized/healthz'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final response = await _send(
      'GET',
      path,
      query: query,
      authenticated: authenticated,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      authenticated: authenticated,
      idempotencyKey: idempotencyKey,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final response = await _send(
      'PATCH',
      path,
      body: body,
      authenticated: authenticated,
    );
    return _decodeObject(response);
  }

  Future<void> delete(String path, {bool authenticated = true}) async {
    await _send('DELETE', path, authenticated: authenticated);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    final uri = _buildUri(path, query);
    var token = authenticated ? await _tokenStore.readAccessToken() : null;
    var response = await _raw(
      method,
      uri,
      body: body,
      token: token,
      idempotencyKey: idempotencyKey,
    );

    if (authenticated && response.statusCode == 401 && !_isAuthPath(path)) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        token = await _tokenStore.readAccessToken();
        response = await _raw(
          method,
          uri,
          body: body,
          token: token,
          idempotencyKey: idempotencyKey,
        );

        if (response.statusCode == 401) {
          await _tokenStore.clear();
          onUnauthorized?.call();
          throw const ApiException(
            'Sesi berakhir. Silakan masuk kembali.',
            code: 'unauthorized',
            statusCode: 401,
          );
        }
      } else {
        await _tokenStore.clear();
        onUnauthorized?.call();
        throw const ApiException(
          'Sesi berakhir. Silakan masuk kembali.',
          code: 'unauthorized',
          statusCode: 401,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    throw _toException(response);
  }

  Future<http.Response> _raw(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? token,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    try {
      late final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = _httpClient.get(uri, headers: headers);
          break;
        case 'POST':
          request = _httpClient.post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          );
          break;
        case 'PATCH':
          request = _httpClient.patch(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          );
          break;
        case 'DELETE':
          request = _httpClient.delete(uri, headers: headers);
          break;
        default:
          throw ApiException('Metode HTTP tidak didukung: $method');
      }

      return await request.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const ApiException(
        'Waktu koneksi habis. Periksa jaringan lalu coba lagi.',
        code: 'timeout',
      );
    } on http.ClientException {
      throw const ApiException(
        'Tidak dapat terhubung ke server. Periksa koneksi internet.',
        code: 'network',
      );
    }
  }

  Future<bool> _refreshAccessToken() {
    final running = _refreshFuture;
    if (running != null) {
      return running;
    }

    final future = _performRefresh();
    _refreshFuture = future;
    future.whenComplete(() {
      _refreshFuture = null;
    });
    return future;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final response = await _raw(
        'POST',
        _buildUri('/api/v1/auth/refresh', null),
        body: {'refresh_token': refreshToken},
      );

      if (response.statusCode != 200) {
        return false;
      }

      final decoded = _decodeObject(response);
      final data = parseMap(decoded['data']);
      final tokens = TokenPair.fromJson(data);
      if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
        return false;
      }

      await _tokenStore.saveTokens(tokens);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl$normalizedPath');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  bool _isAuthPath(String path) {
    return path.contains('/auth/login') || path.contains('/auth/refresh');
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final raw = response.body.trim();
    if (raw.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return parseMap(decoded);
      }
    } catch (_) {
      throw const ApiException(
        'Respons server tidak dapat dibaca.',
        code: 'invalid_response',
      );
    }

    throw const ApiException(
      'Respons server tidak sesuai.',
      code: 'invalid_response',
    );
  }

  ApiException _toException(http.Response response) {
    var code = 'http_${response.statusCode}';
    var message = _defaultMessage(response.statusCode);

    try {
      final decoded = _decodeObject(response);
      final error = parseMap(decoded['error']);
      code = error['code']?.toString() ?? code;
      message = error['message']?.toString() ?? message;
    } catch (_) {
      // Keep the fallback message when the error body is not valid JSON.
    }

    return ApiException(message, code: code, statusCode: response.statusCode);
  }

  String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Permintaan tidak valid.';
      case 401:
        return 'Sesi berakhir. Silakan masuk kembali.';
      case 403:
        return 'Anda tidak memiliki akses untuk tindakan ini.';
      case 404:
        return 'Data tidak ditemukan.';
      case 409:
        return 'Data sedang diproses atau sudah ada.';
      case 422:
        return 'Data yang dikirim belum valid.';
      case 429:
        return 'Terlalu banyak percobaan. Coba lagi nanti.';
      default:
        return 'Terjadi kesalahan pada server.';
    }
  }

  void close() {
    _httpClient.close();
  }
}
