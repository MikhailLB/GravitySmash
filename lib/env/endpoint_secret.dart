import '../cipher/string_cipher.dart';

// ============================================================
// ENDPOINT SECRET — XOR-scrambled config endpoint.
//
// The configuration backend POST URL is split into a host and
// path component, each stored as a scrambled byte array.  At
// runtime the two pieces are descrambled and concatenated.
// ============================================================

/// Returns the full configuration POST endpoint, descrambled at
/// runtime.  Returns an empty string when the byte arrays have
/// not been provisioned yet (forces the orbit client to short-
/// circuit instead of dialling a placeholder host).
String resolveOrbitEndpoint() {
  // Plain values (kept here for human reference, never compiled in):
  //   host -> "https://graviitysmassh.com"
  //   path -> "/config.php"
  const host = <int>[
    141, 94, 46, 98, 221, 199, 132, 6, 104, 77, 58, 222, 1, 24,
    251, 231, 165, 128, 9, 11, 38, 176, 152, 141, 138, 71,
  ];
  const path = <int>[
    202, 73, 53, 124, 200, 148, 204, 7, 127, 87, 43,
  ];

  if (host.isEmpty) return '';
  return unscramble(host) + unscramble(path);
}
