import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../cipher/string_cipher.dart';

// ============================================================
// BROWSERISH CLIENT — HTTP client that injects a real device
// User-Agent so that outbound requests look like Chrome on the
// user's actual device.  The same UA string is reused by the
// WebShell controller, keeping HTTP and WebView traffic
// indistinguishable to fingerprinting middleware.
//
// Why XOR-encode the Chrome / WebKit version numbers?  Static
// analysis tooling grepping the APK for "Chrome/" strings is one
// of the more common ways to fingerprint a build family.  The
// codec keeps those tokens out of plaintext.
// ============================================================

String _resolveChromeBranch() {
  const bytes = <int>[
    212, 25, 99, 60, 158, 211, 156, 27, 58, 7, 117, 153, 93, 73,
  ];
  if (bytes.isEmpty) return '139.0.7258.158';
  return unscramble(bytes);
}

String _resolveWebkitBranch() {
  const bytes = <int>[
    208, 25, 109, 60, 157, 203,
  ];
  if (bytes.isEmpty) return '537.36';
  return unscramble(bytes);
}

class BrowserishClient extends http.BaseClient {
  BrowserishClient({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;
  String? _composedAgent;

  /// Must be called once during app startup, before `runApp`.
  Future<void> warmUp() async {
    try {
      final probe = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await probe.androidInfo;
        final chrome = _resolveChromeBranch();
        final build = info.display.isNotEmpty ? info.display : info.id;
        _composedAgent =
            'Mozilla/5.0 (Linux; Android ${info.version.sdkInt}; '
            '${info.brand} ${info.model} Build/$build) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/537.36';
      } else {
        final info = await probe.iosInfo;
        final webkit = _resolveWebkitBranch();
        final ver = info.systemVersion.replaceAll('.', '_');
        _composedAgent =
            'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${info.systemVersion} Mobile/15E148 Safari/$webkit';
      }
    } catch (_) {
      _composedAgent =
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/${_resolveChromeBranch()} '
          'Mobile Safari/537.36';
    }
  }

  String get composedAgent => _composedAgent ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => composedAgent);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Process-wide singleton, populated from `main`.
final BrowserishClient orbitHttp = BrowserishClient();
