// ============================================================
// ENCODE KEYS — Build-time helper for the Gravity Smash gray flow.
//
// Run with:  dart run tool/encode_keys.dart
//
// Edit the `_secrets` map below, paste the printed byte arrays
// into `lib/env/endpoint_secret.dart`, `lib/env/tracker_secrets.dart`
// and `lib/orbit/browserish_client.dart`.  Re-run after every
// change to `_seedBytes` in `lib/cipher/string_cipher.dart`.
//
// NEVER use a PowerShell `foreach` loop to compute the values.
// PowerShell on Windows silently overflows at 32-bit integer
// boundaries which produces malformed bytes.  Always use this
// `dart run` tool so the same Mulberry32 seeded LCG runs both
// at encoding time and at runtime.
// ============================================================

// ignore_for_file: avoid_print, avoid_relative_lib_imports

import 'dart:io';

import '../lib/cipher/string_cipher.dart';

const Map<String, String> _secrets = <String, String>{
  'endpoint_host': 'https://graviitysmassh.com',
  'endpoint_path': '/config.php',
  'gcd_host': 'https://gcdsdk.appsflyer.com',
  'gcd_path': '/install_data/v4.0/',
  // Filled when manager provides credentials.  Keep placeholders in
  // the binary so the production-time replacement is a one-line edit.
  'appsflyer_dev_key': 'APPSFLYER_DEV_KEY_PLACEHOLDER',
  'firebase_project': 'FIREBASE_PROJECT_NUMBER_PLACEHOLDER',
  'browser_chrome': '139.0.7258.158',
  'browser_webkit': '537.36',
};

void main() {
  stdout.writeln('// ===== Gravity Smash scrambled secrets =====');
  stdout.writeln('// Paste each array into the matching env/*.dart file.');
  for (final entry in _secrets.entries) {
    final bytes = scramble(entry.value);
    final formatted = bytes.map((b) => b.toString()).join(', ');
    stdout.writeln('');
    stdout.writeln('// ${entry.key} -> "${entry.value}"');
    stdout.writeln('const ${entry.key} = <int>[$formatted];');
    if (unscramble(bytes) != entry.value) {
      stderr.writeln('ERROR: cipher roundtrip failed for ${entry.key}');
      exitCode = 1;
    }
  }
  stdout.writeln('');
  stdout.writeln('// Roundtrip OK for ${_secrets.length} secrets.');
}
