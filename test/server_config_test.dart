import 'package:firefreeforest/core/config/server_config.dart';
import 'package:firefreeforest/core/network/api_client.dart';
import 'package:firefreeforest/core/storage/secure_token_store.dart';
import 'package:firefreeforest/shared/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  test('normalizes host without scheme and trims trailing slash', () {
    expect(
      ServerConfig.normalize(' 192.168.1.12:8080/ '),
      'http://192.168.1.12:8080',
    );
  });

  test('preserves https and a base path', () {
    expect(
      ServerConfig.normalize('https://api.example.com/fff/'),
      'https://api.example.com/fff',
    );
  });

  test('rejects empty, invalid, credentialed, and non-http URLs', () {
    expect(() => ServerConfig.normalize(' '), throwsFormatException);
    expect(
      () => ServerConfig.normalize('ftp://example.com'),
      throwsFormatException,
    );
    expect(
      () => ServerConfig.normalize('http://user:pass@example.com'),
      throwsFormatException,
    );
  });

  test('normalizeOrDefault falls back safely', () {
    expect(
      ServerConfig.normalizeOrDefault('not a url', 'http://localhost:8080'),
      'http://localhost:8080',
    );
  });

  test('displayLabel hides scheme and trailing path', () {
    expect(
      ServerConfig.displayLabel('http://192.168.1.12:8080'),
      '192.168.1.12:8080',
    );
  });

  testWidgets('server dialog probes health and returns normalized URL', (
    tester,
  ) async {
    final apiClient = ApiClient(
      baseUrl: 'http://old-server:8080',
      tokenStore: SecureTokenStore(),
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.12:8080/healthz');
        return http.Response('{"status":"ok"}', 200);
      }),
    );
    String? savedUrl;

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: apiClient,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  savedUrl = await showDialog<String>(
                    context: context,
                    builder: (_) => const ServerSettingsDialog(
                      currentUrl: 'http://old-server:8080',
                    ),
                  );
                },
                child: const Text('Buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.1.12:8080');
    await tester.tap(find.text('Tes & simpan'));
    await tester.pumpAndSettle();

    expect(savedUrl, 'http://192.168.1.12:8080');
  });
}
