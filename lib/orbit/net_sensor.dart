import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

// ============================================================
// NET SENSOR — Two-stage connectivity probe.
//
// 1. Cheap radio check via connectivity_plus
//    (returns immediately, no DNS round-trip).
// 2. Optional DNS probe to detect the "captive portal" /
//    walled-garden case where the radio is up but the gateway
//    refuses outbound traffic.
//
// Boot Gate and the WebShell call `hasUplink()` before any HTTP
// work.  `radioStream` is consumed by the WebShell to instantly
// pivot to the offline fallback when the user drops Wi-Fi.
// ============================================================

class NetSensor {
  NetSensor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Returns `true` when at least one transport reports a link and
  /// a UDP DNS probe succeeds within ~3 seconds.
  Future<bool> hasUplink({Duration probeTimeout = const Duration(seconds: 3)}) async {
    final transports = await _connectivity.checkConnectivity();
    final radioUp = transports.any((t) => t != ConnectivityResult.none);
    if (!radioUp) return false;

    try {
      // Cloudflare 1.1.1.1 — minimal payload, never blocked by ISPs.
      final lookup = await InternetAddress.lookup('one.one.one.one')
          .timeout(probeTimeout);
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Live stream of radio-level connectivity changes.  WebShell uses
  /// this to instantly bail out to the offline fallback page rather
  /// than waiting for the next DNS lookup.
  Stream<List<ConnectivityResult>> get radioStream =>
      _connectivity.onConnectivityChanged;

  bool isOffline(List<ConnectivityResult> snapshot) =>
      snapshot.every((t) => t == ConnectivityResult.none);
}
