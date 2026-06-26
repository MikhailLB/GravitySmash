import 'package:flutter/material.dart';

import '../env/orbit_facade.dart';
import '../orbit/fcm_conductor.dart';
import '../orbit/net_sensor.dart';
import '../orbit/prefs_vault.dart';
import 'orbit_web_shell.dart' deferred as shell;

// ============================================================
// PUSH OPT-IN PAGE — Promo screen offered once before the
// WebShell opens.  Two outcomes:
//
//   [Accept] → triggers system permission dialog via
//              FcmConductor.requestPushPermission.  When the
//              user denies it, mark a 3-day cooldown.  When the
//              system denies (Android 13+), set the os-denied
//              memo so we never ask again.
//   [Skip]   → cooldown only.
//
// Either way the user is forwarded to the WebShell.  This page
// is never shown to organic users (they never see the gray
// flow at all).
// ============================================================

class PushOptInPage extends StatefulWidget {
  const PushOptInPage({
    super.key,
    required this.vault,
    required this.conductor,
    required this.sensor,
    required this.targetUrl,
  });

  final PrefsVault vault;
  final FcmConductor conductor;
  final NetSensor sensor;
  final String targetUrl;

  @override
  State<PushOptInPage> createState() => _PushOptInPageState();
}

class _PushOptInPageState extends State<PushOptInPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final granted = await widget.conductor.requestPushPermission();
    if (!granted) {
      await widget.vault.writePushPromoCooldown(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 +
            OrbitFacade.pushPromoCooldownSeconds,
      );
    }
    if (!mounted) return;
    await _gotoShell();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.vault.writePushPromoCooldown(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          OrbitFacade.pushPromoCooldownSeconds,
    );
    if (!mounted) return;
    await _gotoShell();
  }

  Future<void> _gotoShell() async {
    await shell.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => shell.OrbitWebShell(
          url: widget.targetUrl,
          vault: widget.vault,
          conductor: widget.conductor,
          sensor: widget.sensor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final asset = isLandscape
        ? 'assets/flow/Horizontal_Notifications_Screen.png'
        : 'assets/flow/Vertical_Notifications_Screen.png';

    return Scaffold(
      backgroundColor: const Color(0xFF050A1A),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              width: size.width,
              height: size.height,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF050A1A),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
            if (!isLandscape)
              Positioned(
                left: size.width * 0.08,
                right: size.width * 0.08,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AcceptCta(onTap: _onAccept, busy: _busy, glow: _glow),
                    const SizedBox(height: 14),
                    _SkipChip(onTap: _onSkip, busy: _busy),
                  ],
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.34,
                      child: _AcceptCta(
                        onTap: _onAccept,
                        busy: _busy,
                        glow: _glow,
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SkipChip(
                      onTap: _onSkip,
                      busy: _busy,
                      compact: true,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AcceptCta extends StatefulWidget {
  const _AcceptCta({
    required this.onTap,
    required this.busy,
    required this.glow,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool busy;
  final AnimationController glow;
  final bool compact;

  @override
  State<_AcceptCta> createState() => _AcceptCtaState();
}

class _AcceptCtaState extends State<_AcceptCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final inactive = widget.busy;
    return GestureDetector(
      onTapDown: inactive ? null : (_) => setState(() => _pressed = true),
      onTapUp: inactive
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
      onTapCancel: inactive ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: widget.glow,
          builder: (_, _) {
            final glow = widget.glow.value;
            return Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                vertical: widget.compact ? 12 : 18,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(38),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF7340FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(
                      alpha: 0.30 + glow * 0.35,
                    ),
                    blurRadius: 22 + glow * 12,
                    spreadRadius: glow * 2.5,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: widget.busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF050A1A),
                          ),
                        ),
                      )
                    : Text(
                        'Accept',
                        style: TextStyle(
                          color: const Color(0xFF050A1A),
                          fontWeight: FontWeight.w900,
                          fontSize: widget.compact ? 16 : 20,
                          letterSpacing: 1.4,
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SkipChip extends StatefulWidget {
  const _SkipChip({
    required this.onTap,
    required this.busy,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool busy;
  final bool compact;

  @override
  State<_SkipChip> createState() => _SkipChipState();
}

class _SkipChipState extends State<_SkipChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.busy ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.busy
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
      onTapCancel:
          widget.busy ? null : () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: widget.busy ? 0.45 : (_pressed ? 0.55 : 0.92),
        duration: const Duration(milliseconds: 90),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 8),
          child: Text(
            'Skip',
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.compact ? 16 : 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
