import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/orbit_facade.dart';
import '../env/tracker_secrets.dart';
import 'browserish_client.dart';

// ============================================================
// ATTRIBUTION TRACKER — Thin wrapper over `appsflyer_sdk` that
// collects install conversion data, deep link payload and the
// AppsFlyer device id, then composes the POST body for the
// orbit configuration endpoint.
//
// Quirk handled here:  AppsFlyer occasionally fires the install
// callback with `af_status = "Organic"` for a freshly attributed
// paid install (race in the SDK's first-launch path).  We retry
// via the public GCD endpoint after a short wait so we never
// lose paid attribution for routing decisions.
// ============================================================

class AttributionTracker {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _resumePayload;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();
  bool _bootstrapped = false;

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final options = AppsFlyerOptions(
      afDevKey: OrbitFacade.trackerKey,
      appId: OrbitFacade.trackerAppId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData(_onInstallConversionData);
    _sdk!.onAppOpenAttribution((data) {
      _resumePayload = _flatten(data);
    });
    _sdk!.onDeepLinking((result) {
      final clickEvent = result.deepLink?.clickEvent;
      if (clickEvent != null) {
        _deepLinkPayload = Map<String, dynamic>.from(clickEvent);
      }
      if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
    });

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Future<void> _onInstallConversionData(dynamic raw) async {
    final payload = _flatten(raw);
    final status = payload['af_status'];

    if (status == 'Organic') {
      // Possible false-organic — re-confirm via GCD after a beat.
      await Future<void>.delayed(
        Duration(seconds: OrbitFacade.organicReconfirmSeconds),
      );
      final reconfirmed = await _pullFromGcd();
      _installPayload = reconfirmed ?? payload;
    } else {
      _installPayload = payload;
    }

    if (!_installReady.isCompleted) {
      _installReady.complete(_installPayload!);
    }
  }

  Map<String, dynamic> _flatten(dynamic data) {
    if (data is Map) {
      if (data['payload'] is Map) {
        return Map<String, dynamic>.from(data['payload'] as Map);
      }
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> _pullFromGcd() async {
    final uid = await fetchTrackerUid();
    if (uid == null || uid.isEmpty) return null;

    final appId = Platform.isIOS ? OrbitFacade.trackerAppId : OrbitFacade.bundleId;
    final url = buildConversionFallback(appId, uid);
    if (url.isEmpty) return null;

    try {
      final response = await orbitHttp
          .get(
            Uri.parse(url),
            headers: {
              'authorization': 'Bearer ${OrbitFacade.trackerKey}',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) return parsed;
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> awaitInstallData() {
    return _installReady.future.timeout(
      Duration(seconds: OrbitFacade.attributionTimeoutSeconds),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink({Duration? timeout}) async {
    final wait = timeout ??
        Duration(seconds: OrbitFacade.deepLinkTimeoutSeconds);
    try {
      await _deepLinkReady.future.timeout(wait);
    } catch (_) {}
  }

  Future<String?> fetchTrackerUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Builds the full POST body for the orbit configuration endpoint.
  /// Attribution data wins over deep link / resume data on conflict.
  Future<Map<String, dynamic>> composePostBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    // Order matters — the first writer wins for putIfAbsent.
    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _resumePayload?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await fetchTrackerUid() ?? '';
    body['bundle_id'] = OrbitFacade.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = OrbitFacade.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final fcmProject = OrbitFacade.messagingProjectId;
    if (fcmProject.isNotEmpty) {
      body['firebase_project_id'] = fcmProject;
    }

    if (kDebugMode) {
      debugPrint('[AttributionTracker] body=${jsonEncode(body)}');
    }
    return body;
  }
}
