import 'dart:typed_data';

// ============================================================
// STRING CIPHER — Per-binary XOR string descrambler.
//
// Sensitive strings (config endpoint host/path, AppsFlyer dev key,
// Firebase sender id, GCD URL pieces, browser UA fragments) are
// stored as XOR-encoded byte arrays so that `strings`/`grep` over
// the compiled APK cannot trivially extract them.
//
// The seed below is intentionally unique to this binary so the
// derived key (and therefore the encoded byte arrays) cannot be
// recycled across sibling projects from the same publisher.
//
// To rotate the seed:
//   1. Edit `_seedBytes` to a new short ASCII phrase.
//   2. Run `dart run tool/encode_keys.dart` to regenerate arrays.
//   3. Paste the new byte arrays into `lib/env/*_secret.dart`.
// ============================================================

/// ASCII bytes for "g-rav!ty_o#bit"  — unique mnemonic for the
/// Gravity Smash gray binary.  Treated as opaque salt for the
/// derived 24-byte stream key.
const List<int> _seedBytes = <int>[
  0x67, 0x2D, 0x72, 0x61, 0x76, 0x21, 0x74, 0x79,
  0x5F, 0x6F, 0x23, 0x62, 0x69, 0x74,
];

Uint8List _deriveStreamKey() {
  // Mix the seed bytes through a Mulberry32-style hash, then expand
  // into 24 stream bytes via two interlocking LCGs.  Output length is
  // intentionally different from the chick-trip template's 16 bytes
  // — recompiling against this codec produces unrelated payloads.
  var hash = 0x9E3779B1;
  for (final byte in _seedBytes) {
    hash = (hash ^ byte) & 0xFFFFFFFF;
    hash = (hash * 0x85EBCA77) & 0xFFFFFFFF;
    hash = ((hash >> 13) | (hash << 19)) & 0xFFFFFFFF;
  }

  var streamA = hash == 0 ? 0x12345678 : hash;
  var streamB = ((hash << 1) ^ 0xDEADBEEF) & 0xFFFFFFFF;
  final out = Uint8List(24);
  for (var i = 0; i < out.length; i++) {
    streamA = (streamA * 1664525 + 1013904223) & 0xFFFFFFFF;
    streamB = (streamB * 22695477 + 1) & 0xFFFFFFFF;
    out[i] = ((streamA >> 17) ^ (streamB >> 9) ^ i) & 0xFF;
  }
  return out;
}

final Uint8List _streamKey = _deriveStreamKey();

/// XOR-decode a byte list back to its original UTF-8 string.
/// Pairs with `tool/encode_keys.dart` which uses the same key stream.
String unscramble(List<int> encoded) {
  if (encoded.isEmpty) return '';
  final out = Uint8List(encoded.length);
  for (var i = 0; i < encoded.length; i++) {
    out[i] = encoded[i] ^ _streamKey[i % _streamKey.length];
  }
  return String.fromCharCodes(out);
}

/// XOR-encode a plain string into a `List<int>` of bytes that
/// `unscramble` can later decode.  Intended for build-time tooling
/// only — release code should never see plaintext secrets.
List<int> scramble(String plain) {
  final bytes = plain.codeUnits;
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ _streamKey[i % _streamKey.length];
  }
  return out;
}
