import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/launch_path.dart';

// ============================================================
// PREFS VAULT — Persistent state used by every gray-flow service.
//
// Splits storage in two:
//   • `SharedPreferences` for non-sensitive flags (launch path,
//     notification cooldown, OS-deny memo, expiry timestamp).
//   • `FlutterSecureStorage` for URLs the user has been routed to
//     (config and push) so that they never end up in plain prefs.
// ============================================================

class PrefsVault {
  PrefsVault({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  static const _keyLaunchPath = 'gs.launch_path';
  static const _keyServedUrl = 'gs.served_url';
  static const _keyServedExpires = 'gs.served_expires';
  static const _keyPushUrl = 'gs.push_url';
  static const _keyPushPromoCooldown = 'gs.push_promo_cooldown';
  static const _keyPushGranted = 'gs.push_granted';
  static const _keyPushOsDenied = 'gs.push_os_denied';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---- launch path ----
  LaunchPath readLaunchPath() =>
      LaunchPath.parse(_prefs.getString(_keyLaunchPath));

  Future<void> writeLaunchPath(LaunchPath path) =>
      _prefs.setString(_keyLaunchPath, path.persistKey);

  // ---- served URL (kept in keystore-backed secure storage) ----
  Future<String?> readServedUrl() => _secure.read(key: _keyServedUrl);

  Future<void> writeServedUrl(String url) =>
      _secure.write(key: _keyServedUrl, value: url);

  int? readServedExpires() => _prefs.getInt(_keyServedExpires);

  Future<void> writeServedExpires(int expiresUnix) =>
      _prefs.setInt(_keyServedExpires, expiresUnix);

  bool isServedExpired() {
    final expires = readServedExpires();
    if (expires == null) return true;
    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowUnix >= expires;
  }

  // ---- one-shot push URL ----
  Future<String?> readPushUrl() => _secure.read(key: _keyPushUrl);

  Future<void> writePushUrl(String? url) async {
    if (url == null || url.isEmpty) {
      await _secure.delete(key: _keyPushUrl);
    } else {
      await _secure.write(key: _keyPushUrl, value: url);
    }
  }

  /// Atomically retrieve and clear the one-shot push URL.
  Future<String?> popPushUrl() async {
    final url = await _secure.read(key: _keyPushUrl);
    if (url != null) {
      await _secure.delete(key: _keyPushUrl);
    }
    return url;
  }

  // ---- push promo screen state ----
  bool isPushGranted() => _prefs.getBool(_keyPushGranted) ?? false;
  Future<void> markPushGranted(bool granted) =>
      _prefs.setBool(_keyPushGranted, granted);

  /// `true` once the OS has hard-rejected the system permission
  /// dialog.  Android cannot re-present the dialog after that, so
  /// we must stop showing the promo screen as well.
  bool isPushOsDenied() => _prefs.getBool(_keyPushOsDenied) ?? false;
  Future<void> markPushOsDenied() =>
      _prefs.setBool(_keyPushOsDenied, true);

  int? readPushPromoCooldown() => _prefs.getInt(_keyPushPromoCooldown);
  Future<void> writePushPromoCooldown(int untilUnix) =>
      _prefs.setInt(_keyPushPromoCooldown, untilUnix);

  /// Returns true if Boot Gate should display the push promo screen
  /// before forwarding the user to the WebShell.  Combines three
  /// signals: explicit grant, OS denial memo, and the optional
  /// "skipped for 3 days" cooldown.
  bool shouldShowPushPromo() {
    if (isPushGranted()) return false;
    if (isPushOsDenied()) return false;
    final until = readPushPromoCooldown();
    if (until == null) return true;
    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowUnix >= until;
  }
}
