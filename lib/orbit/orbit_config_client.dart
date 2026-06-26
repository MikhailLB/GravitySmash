import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../entities/orbit_decision.dart';
import '../env/orbit_facade.dart';
import 'browserish_client.dart';
import 'prefs_vault.dart';

// ============================================================
// ORBIT CONFIG CLIENT — Posts the attribution body to the
// orbit configuration endpoint and translates the response into
// an `OrbitDecision`.
//
// On success the URL+expiry are cached in PrefsVault so a
// subsequent cold start with no network can still reuse the
// last-known target.
// ============================================================

class OrbitConfigClient {
  OrbitConfigClient(this._vault, {http.Client? transport})
      : _transport = transport ?? orbitHttp;

  final PrefsVault _vault;
  final http.Client _transport;

  static const Duration _timeout = Duration(seconds: 15);

  Future<OrbitDecision> requestDecision(Map<String, dynamic> body) async {
    final endpoint = OrbitFacade.orbitEndpoint;
    if (endpoint.isEmpty) {
      if (kDebugMode) {
        debugPrint('[OrbitConfigClient] endpoint missing, skipping POST');
      }
      return OrbitDecision.failure('endpoint missing');
    }

    if (kDebugMode) {
      debugPrint('[OrbitConfigClient] POST -> $endpoint');
    }

    try {
      final response = await _transport
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[OrbitConfigClient] http ${response.statusCode}');
        }
        return OrbitDecision.failure('http_${response.statusCode}');
      }

      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        return OrbitDecision.failure('malformed_json');
      }

      final decision = OrbitDecision.fromMap(parsed);
      if (decision.hasTarget) {
        if (kDebugMode) {
          debugPrint('[OrbitConfigClient] target=${decision.target}');
        }
        // Cache write failures must NOT mask a successful network
        // decision — we still want to render the WebShell even if
        // the keychain is unavailable for some reason.
        try {
          await _vault.writeServedUrl(decision.target!);
          final expires = decision.expiresAt;
          if (expires != null) {
            await _vault.writeServedExpires(expires);
          }
        } catch (cacheError) {
          if (kDebugMode) {
            debugPrint('[OrbitConfigClient] cache write failed: $cacheError');
          }
        }
      } else if (kDebugMode) {
        debugPrint(
          '[OrbitConfigClient] server declined: '
          '${decision.serverNote ?? "no message"}',
        );
      }
      return decision;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[OrbitConfigClient] error $error');
      }
      return OrbitDecision.failure(error.toString());
    }
  }

  /// Convenience wrapper used by the boot gate when the warm
  /// session was triggered by a push tap.  The push URL is
  /// shown immediately to the user, while we still re-POST in
  /// the background so the cached target stays fresh for the
  /// next cold start.
  void refreshInBackground(Map<String, dynamic> body) {
    // Intentionally fire-and-forget: failures are absorbed by
    // `requestDecision` and reflected only via the cached
    // target being left untouched.
    unawaited(requestDecision(body));
  }

  Future<String?> readCachedTarget() => _vault.readServedUrl();
}
