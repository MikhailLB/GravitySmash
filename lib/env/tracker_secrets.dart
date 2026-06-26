import '../cipher/string_cipher.dart';

// ============================================================
// TRACKER SECRETS — AppsFlyer dev key, Firebase project number,
// and GCD (Get Conversion Data) endpoint pieces.
//
// Real values are pasted in from `tool/encode_keys.dart`.  The
// placeholders below will be replaced once the manager hands over
// the production-grade credentials.  Until then `resolveTrackerKey`
// returns the placeholder string and `AttributionTracker` simply
// emits the request without an Authorization header — the server
// is free to ignore or accept the install based on signature.
// ============================================================

/// Returns the AppsFlyer Dev Key for SDK initialisation.
/// Plain value: "ruJhEkJPjGLN8zCsMsSNDW"
String resolveTrackerKey() {
  const bytes = <int>[
    151, 95, 16, 122, 235, 150, 225, 121, 101, 120,
    23, 230, 80, 11, 204, 237, 155, 158, 59, 54, 17, 143,
  ];
  if (bytes.isEmpty) return '';
  return unscramble(bytes);
}

/// Firebase project number (sender id) for FCM message routing.
/// Plain value: "474505537194"
String resolveMessagingProject() {
  const bytes = <int>[
    209, 29, 110, 39, 158, 200, 158, 26, 56, 14, 98, 156,
  ];
  if (bytes.isEmpty) return '';
  return unscramble(bytes);
}

/// Builds the GCD retry endpoint:
///   {host}{path}{appId}?device_id={deviceId}
/// Used by AttributionTracker when AppsFlyer first emits Organic.
String buildConversionFallback(String appId, String deviceId) {
  const host = <int>[
    141, 94, 46, 98, 221, 199, 132, 6, 104, 92, 63, 219, 12, 26,
    161, 255, 166, 157, 27, 30, 57, 161, 211, 156, 203, 73, 53, 127,
  ];
  const path = <int>[
    202, 67, 52, 97, 218, 156, 199, 69, 80, 91, 58, 220, 9, 94,
    249, 170, 248, 221, 71,
  ];
  if (host.isEmpty) return '';
  return '${unscramble(host)}${unscramble(path)}$appId?device_id=$deviceId';
}
