import 'endpoint_secret.dart';
import 'legal_links.dart';
import 'tracker_secrets.dart';

// ============================================================
// ORBIT FACADE — Single read-only entry point for app-level
// constants and lazily descrambled credentials.
//
// All other services should import from `OrbitFacade` rather
// than the cipher-backed env files directly.  Switching seeds
// or rotating credentials therefore only needs touching one
// place per consumer.
// ============================================================

class OrbitFacade {
  OrbitFacade._();

  /// Bundle id of the published Android binary.
  static const String bundleId = 'com.legendgrav.gravitysmash';

  /// Google Play store package id (mirrors `bundleId` on Android).
  static const String storeId = 'com.legendgrav.gravitysmash';

  /// Friendly display name used in toasts/notification titles.
  static const String displayName = 'Gravity Smash';

  /// iOS-only App Store numeric id (left empty for Android builds).
  static const String trackerAppId = '';

  /// Backend POST endpoint that decides "show webview" or "show game".
  static String get orbitEndpoint => resolveOrbitEndpoint();

  /// AppsFlyer Dev Key for SDK initialisation + GCD auth header.
  static String get trackerKey => resolveTrackerKey();

  /// Firebase project number (sender id) for push routing.
  static String get messagingProjectId => resolveMessagingProject();

  /// Privacy/support links exposed both in white and gray flows.
  static String get privacyPolicyUrl => privacyPolicyPageUrl;
  static String get supportUrl => supportPageUrl;
  static String get publisherSite => publisherSiteUrl;

  /// 3 days in seconds — duration we suppress the push promo screen
  /// after a "Skip" tap, per TZ.
  static const int pushPromoCooldownSeconds = 3 * 24 * 60 * 60;

  /// Seconds to wait before re-asking AppsFlyer GCD when the initial
  /// install conversion data returns `af_status = Organic`.
  static const int organicReconfirmSeconds = 5;

  /// Maximum time we are willing to wait for the AppsFlyer install
  /// conversion callback before falling back to organic routing.
  static const int attributionTimeoutSeconds = 30;

  /// Tighter timeout for returning users — the SDK has already been
  /// initialised, so attribution is either cached or unavailable.
  static const int returningAttributionTimeoutSeconds = 10;

  /// Timeout for the deep link callback wait.
  static const int deepLinkTimeoutSeconds = 5;
}
