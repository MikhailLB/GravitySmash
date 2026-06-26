import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../arena/arena_page.dart';
import '../entities/launch_path.dart';
import '../env/orbit_facade.dart';
import '../orbit/attribution_tracker.dart';
import '../orbit/fcm_conductor.dart';
import '../orbit/net_sensor.dart';
import '../orbit/orbit_config_client.dart';
import '../orbit/prefs_vault.dart';
import 'offline_guard_page.dart';
import 'push_optin_page.dart';
import 'orbit_web_shell.dart' deferred as shell;

// ============================================================
// BOOT GATE — Hosts the loading splash and orchestrates the
// gray-flow routing decision on every cold start.
//
//   firstBoot  → connectivity check → tracker bootstrap →
//                attribution + deep link → POST orbit endpoint
//                → either WebShell (with push promo) or Arena.
//   webOrbit   → consume push URL if any, otherwise refresh
//                attribution + POST again, fall back to cached
//                URL if the network call fails.
//   arenaOnly  → ArenaHomePage directly.
//
// Visual states are exposed via `_LoadStage` so the progress
// bar advances at deterministic milestones.
// ============================================================

enum _LoadStage { booting, syncing, ready }

class BootGate extends StatefulWidget {
  const BootGate({
    super.key,
    required this.vault,
    required this.sensor,
    required this.tracker,
    required this.config,
    required this.conductor,
  });

  final PrefsVault vault;
  final NetSensor sensor;
  final AttributionTracker tracker;
  final OrbitConfigClient config;
  final FcmConductor conductor;

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  _LoadStage _stage = _LoadStage.booting;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _drive();
  }

  Future<void> _drive() async {
    widget.conductor.onTokenRotated = _refreshTokenAtBackend;
    await widget.conductor.bringOnline().catchError((_) {});

    final path = widget.vault.readLaunchPath();
    switch (path) {
      case LaunchPath.firstBoot:
        await _runFirstBoot();
        break;
      case LaunchPath.webOrbit:
        await _runReturningOnline();
        break;
      case LaunchPath.arenaOnly:
        await _runArenaOnly();
        break;
    }
  }

  Future<void> _runFirstBoot() async {
    _bump(_LoadStage.booting);
    final up = await widget.sensor.hasUplink();
    if (!up) {
      // No network on the very first launch — show the arena game so
      // the user (and store reviewers running in airplane mode) always
      // get a working experience.  Crucially we do NOT persist the
      // launch path here so a future cold start with connectivity can
      // still upgrade the user to the web orbit if attribution arrives.
      _bump(_LoadStage.ready);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _gotoArena();
      return;
    }
    _bump(_LoadStage.syncing);

    await widget.tracker.bootstrap();
    await Future.wait([
      widget.tracker.awaitInstallData(),
      widget.tracker.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.composePostBody(
      locale: locale,
      pushToken: widget.conductor.registrationToken,
    );
    final decision = await widget.config.requestDecision(body);

    _bump(_LoadStage.ready);
    await Future<void>.delayed(const Duration(milliseconds: 380));

    if (decision.hasTarget) {
      await widget.vault.writeLaunchPath(LaunchPath.webOrbit);
      _gotoWebShell(decision.target!);
    } else {
      await widget.vault.writeLaunchPath(LaunchPath.arenaOnly);
      _gotoArena();
    }
  }

  Future<void> _runReturningOnline() async {
    _bump(_LoadStage.booting);
    final up = await widget.sensor.hasUplink();
    if (!up) {
      _bump(_LoadStage.ready);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _gotoOffline();
      return;
    }

    final pushUrl = await widget.vault.popPushUrl();
    if (pushUrl != null) {
      // Push tap wins the navigation race so the user sees the
      // operator-chosen page immediately.  We still kick off a
      // background refresh against the orbit endpoint so the
      // cached target is up-to-date for the next cold start.
      unawaited(_refreshTargetInBackground());
      _bump(_LoadStage.ready);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _gotoWebShell(pushUrl);
      return;
    }

    final cached = await widget.config.readCachedTarget();

    _bump(_LoadStage.syncing);
    await widget.tracker.bootstrap();
    await Future.wait([
      widget.tracker.awaitInstallData().timeout(
            Duration(
              seconds: OrbitFacade.returningAttributionTimeoutSeconds,
            ),
            onTimeout: () => <String, dynamic>{},
          ),
      widget.tracker.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.composePostBody(
      locale: locale,
      pushToken: widget.conductor.registrationToken,
    );
    if (kDebugMode) {
      debugPrint(
        '[BootGate] returning user — POST orbit endpoint for fresh URL',
      );
    }
    final decision = await widget.config.requestDecision(body);

    _bump(_LoadStage.ready);
    await Future<void>.delayed(const Duration(milliseconds: 380));

    if (decision.hasTarget) {
      _gotoWebShell(decision.target!);
      return;
    }
    if (cached != null) {
      _gotoWebShell(cached);
      return;
    }
    _gotoOffline();
  }

  Future<void> _runArenaOnly() async {
    _bump(_LoadStage.syncing);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _bump(_LoadStage.ready);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _gotoArena();
  }

  void _refreshTokenAtBackend(String token) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.composePostBody(
      locale: locale,
      pushToken: token,
    );
    widget.config.refreshInBackground(body);
  }

  /// Fire a config refresh without blocking navigation.
  /// Used after a push-tap warm boot so the cached target stays
  /// fresh even though the user is being navigated straight to
  /// the push URL.
  Future<void> _refreshTargetInBackground() async {
    try {
      await widget.tracker.bootstrap();
      final locale = Platform.localeName.replaceAll('-', '_');
      final body = await widget.tracker.composePostBody(
        locale: locale,
        pushToken: widget.conductor.registrationToken,
      );
      widget.config.refreshInBackground(body);
    } catch (_) {}
  }

  void _bump(_LoadStage stage) {
    if (!mounted) return;
    setState(() => _stage = stage);
  }

  Future<void> _gotoWebShell(String url) async {
    if (_navigated) return;
    _navigated = true;
    await shell.loadLibrary();
    await shell.primeOrbitShell();
    if (!mounted) return;

    if (widget.vault.shouldShowPushPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PushOptInPage(
            vault: widget.vault,
            conductor: widget.conductor,
            sensor: widget.sensor,
            targetUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => shell.OrbitWebShell(
            url: url,
            vault: widget.vault,
            conductor: widget.conductor,
            sensor: widget.sensor,
          ),
        ),
      );
    }
  }

  void _gotoArena() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ArenaHomePage()),
    );
  }

  void _gotoOffline() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineGuardPage(
          nextRouteBuilder: (_) => BootGate(
            vault: widget.vault,
            sensor: widget.sensor,
            tracker: widget.tracker,
            config: widget.config,
            conductor: widget.conductor,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.conductor.onTokenRotated = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final asset = isLandscape
        ? 'assets/flow/Horizontal_Loading_Screen.png'
        : 'assets/flow/Vertical_Loading_Screen.png';

    return Scaffold(
      backgroundColor: const Color(0xFF050A1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 1.6, sigmaY: 1.6),
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF050A1A),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.36),
            child: _GameLogo(fontSize: isLandscape ? 58 : 62),
          ),
          Align(
            alignment: const Alignment(0, 0.78),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 260 : 42,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'LOADING',
                    style: TextStyle(
                      letterSpacing: 5,
                      color: Color(0xFFE9FBFF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _StageBar(stage: _stage),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameLogo extends StatelessWidget {
  const _GameLogo({required this.fontSize});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          'GRAVITY\nSMASH',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            height: 0.82,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8
              ..color = const Color(0xFF17206A),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [
              Color(0xFFE9FBFF),
              Color(0xFF00D4FF),
              Color(0xFFFF2D9B),
            ],
          ).createShader(rect),
          child: Text(
            'GRAVITY\nSMASH',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              height: 0.82,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
              shadows: const [
                Shadow(color: Color(0xFF00D4FF), blurRadius: 18),
                Shadow(color: Color(0xFFFF2D9B), blurRadius: 26),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.stage});
  final _LoadStage stage;

  double get _ratio {
    switch (stage) {
      case _LoadStage.booting:
        return 0.12;
      case _LoadStage.syncing:
        return 0.65;
      case _LoadStage.ready:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9B30FF), width: 2),
        color: Colors.black.withValues(alpha: 0.55),
        boxShadow: const [
          BoxShadow(color: Color(0xAA00D4FF), blurRadius: 18),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _ratio),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => LinearProgressIndicator(
            value: value,
            backgroundColor: const Color(0xFF08102B),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
          ),
        ),
      ),
    );
  }
}
