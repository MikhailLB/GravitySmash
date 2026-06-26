// ============================================================
// ORBIT DECISION — Parsed reply from the configuration endpoint.
//
// Schema (per backend contract):
//   { "ok": bool, "url": String?, "expires": int?, "message": String? }
//
// `ok=true && url!=null`  → render the WebShell with that URL.
// `ok=false`              → render the offline Arena game.
// `ok=true && url==null`  → treated as the offline case.
// ============================================================

class OrbitDecision {
  const OrbitDecision({
    required this.granted,
    this.target,
    this.expiresAt,
    this.serverNote,
  });

  final bool granted;
  final String? target;
  final int? expiresAt;
  final String? serverNote;

  bool get hasTarget => granted && target != null && target!.isNotEmpty;

  factory OrbitDecision.fromMap(Map<String, dynamic> json) {
    return OrbitDecision(
      granted: json['ok'] as bool? ?? false,
      target: json['url'] as String?,
      expiresAt: json['expires'] as int?,
      serverNote: json['message'] as String?,
    );
  }

  factory OrbitDecision.failure(String reason) =>
      OrbitDecision(granted: false, serverNote: reason);
}
