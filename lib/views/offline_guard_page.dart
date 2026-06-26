import 'package:flutter/material.dart';

// ============================================================
// OFFLINE GUARD PAGE — Shown whenever connectivity is lost
// (cold-start no internet, drop during a WebShell session).
//
// Uses the project-specific background art so the UI stays
// on-brand with the rest of the gray flow.  The "Retry" button
// rebuilds the screen the caller provided through
// `nextRouteBuilder` — typically this routes back to the Boot
// Gate which then re-runs the full attribution stack.
// ============================================================

class OfflineGuardPage extends StatefulWidget {
  const OfflineGuardPage({super.key, required this.nextRouteBuilder});

  final WidgetBuilder nextRouteBuilder;

  @override
  State<OfflineGuardPage> createState() => _OfflineGuardPageState();
}

class _OfflineGuardPageState extends State<OfflineGuardPage>
    with TickerProviderStateMixin {
  bool _retrying = false;
  late final AnimationController _haloCtrl;
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
  }

  @override
  void dispose() {
    _haloCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRetry() async {
    if (_retrying) return;
    await _pressCtrl.forward();
    await _pressCtrl.reverse();
    setState(() => _retrying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.nextRouteBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final asset = isLandscape
        ? 'assets/flow/Horizontal_Nowifi_Screen.png'
        : 'assets/flow/Vertical_Nowifi_Screen.png';

    return Scaffold(
      backgroundColor: const Color(0xFF050A1A),
      body: Stack(
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
          // Gradient veil so the button has a stable contrast no
          // matter which background variant is loaded.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.45),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: size.width * (isLandscape ? 0.28 : 0.12),
            right: size.width * (isLandscape ? 0.28 : 0.12),
            bottom: isLandscape
                ? size.height * 0.10
                : size.height * 0.09,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 0.94)
                  .animate(CurvedAnimation(
                parent: _pressCtrl,
                curve: Curves.easeOut,
              )),
              child: SizedBox(
                height: 56,
                child: AnimatedBuilder(
                  animation: _haloCtrl,
                  builder: (_, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: _retrying
                          ? null
                          : const LinearGradient(
                              colors: [
                                Color(0xFF00D4FF),
                                Color(0xFF7340FF),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: _retrying
                          ? const Color(0xFF1A2350).withValues(alpha: 0.85)
                          : null,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(
                            alpha: 0.35 + _haloCtrl.value * 0.35,
                          ),
                          blurRadius: 22 + _haloCtrl.value * 12,
                          spreadRadius: _haloCtrl.value * 2,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _retrying ? null : _onRetry,
                        child: Center(
                          child: _retrying
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Color(0xFFE9FBFF),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 14),
                                    Text(
                                      'Re-syncing…',
                                      style: TextStyle(
                                        color: Color(0xFFE9FBFF),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'TRY AGAIN',
                                  style: TextStyle(
                                    color: Color(0xFF050A1A),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
