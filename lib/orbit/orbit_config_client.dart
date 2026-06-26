import 'dart:convert';

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
  OrbitConfigClient(this._vault);

  final PrefsVault _vault;

  static const Duration _timeout = Duration(seconds: 15);

  Future<OrbitDecision> requestDecision(Map<String, dynamic> body) async {
    final endpoint = OrbitFacade.orbitEndpoint;
    if (endpoint.isEmpty) {
      return OrbitDecision.failure('endpoint missing');
    }

    try {
      final response = await orbitHttp
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return OrbitDecision.failure('http_${response.statusCode}');
      }

      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        return OrbitDecision.failure('malformed_json');
      }

      final decision = OrbitDecision.fromMap(parsed);
      if (decision.hasTarget) {
        await _vault.writeServedUrl(decision.target!);
        final expires = decision.expiresAt;
        if (expires != null) {
          await _vault.writeServedExpires(expires);
        }
      }
      return decision;
    } catch (error) {
      return OrbitDecision.failure(error.toString());
    }
  }

  Future<String?> readCachedTarget() => _vault.readServedUrl();
}
