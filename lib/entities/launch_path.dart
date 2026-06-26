// ============================================================
// LAUNCH PATH — Persisted decision describing what the user
// should see on every cold start once the very first run is over.
//
// • `firstBoot`  — the install has not been resolved yet.  The
//                  Boot Gate runs the full attribution lookup.
// • `webOrbit`   — the user was attributed to a paid source and
//                  the backend handed back a URL.  Subsequent
//                  cold starts go straight to the web shell.
// • `arenaOnly`  — the user was organic / unattributed and the
//                  backend declined to hand out a URL.  The arena
//                  game becomes the permanent experience.
// ============================================================

enum LaunchPath {
  firstBoot,
  webOrbit,
  arenaOnly;

  static LaunchPath parse(String? raw) {
    switch (raw) {
      case 'webOrbit':
      case 'online':
        return LaunchPath.webOrbit;
      case 'arenaOnly':
      case 'offline':
        return LaunchPath.arenaOnly;
      default:
        return LaunchPath.firstBoot;
    }
  }

  String get persistKey {
    switch (this) {
      case LaunchPath.firstBoot:
        return 'firstBoot';
      case LaunchPath.webOrbit:
        return 'webOrbit';
      case LaunchPath.arenaOnly:
        return 'arenaOnly';
    }
  }
}
