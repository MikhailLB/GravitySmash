import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gravitysmash/orbit/orbit_config_client.dart';
import 'package:gravitysmash/orbit/prefs_vault.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Returning user POSTs to the orbit endpoint and reads back the URL',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final vault = PrefsVault();
    await vault.warmUp();

    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;

    final mock = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'ok': true,
          'url': 'https://graviitysmassh.com/landing/abc123',
          'expires': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = OrbitConfigClient(vault, transport: mock);

    final body = <String, dynamic>{
      'bundle_id': 'com.legendgrav.gravitysmash',
      'os': 'Android',
      'locale': 'en_US',
      'af_id': 'returning-uid-123',
    };
    final decision = await client.requestDecision(body);

    expect(decision.granted, isTrue);
    expect(decision.target, 'https://graviitysmassh.com/landing/abc123');
    expect(capturedUri, isNotNull);
    expect(
      capturedUri.toString(),
      contains('graviitysmassh.com/config.php'),
    );
    expect(capturedBody, isNotNull);
    expect(capturedBody!['bundle_id'], 'com.legendgrav.gravitysmash');
    expect(capturedBody!['af_id'], 'returning-uid-123');

    // The URL is also written to the secure cache so the next cold
    // start can reuse it.  We can only assert the network branch
    // here because FlutterSecureStorage has no test-runtime backend.
  });
}
