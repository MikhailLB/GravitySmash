import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env/legal_links.dart';
import '../views/legal_doc_page.dart';

// ============================================================
// ARENA — White (offline) mode: original Gravity Smash gameplay.
// Used as the in-store demonstration content for organic users.
// ============================================================

class ArenaHomePage extends StatefulWidget {
  const ArenaHomePage({super.key});

  @override
  State<ArenaHomePage> createState() => _ArenaHomePageState();
}

class _ArenaHomePageState extends State<ArenaHomePage> {
  late Future<PlayerProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = PlayerProfile.load();
  }

  Future<void> _reload() async {
    setState(() => _profileFuture = PlayerProfile.load());
  }

  Future<void> _showRunResult(GameResult result) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _RunResultDialog(result: result),
    );
  }

  Future<void> _openWebView(String title, String value) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocPage(title: title, url: value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlayerProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? PlayerProfile.empty();
        return Scaffold(
          body: _SpaceScaffold(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    const _GameTitle(fontSize: 50),
                    const SizedBox(height: 18),
                    _StatsPanel(profile: profile),
                    const Spacer(),
                    _NeonButton(
                      text: 'PLAY',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () async {
                        final result = await Navigator.of(context)
                            .push<GameResult>(
                              MaterialPageRoute<GameResult>(
                                builder: (_) => GameScreen(profile: profile),
                              ),
                            );
                        if (result != null) {
                          await profile.applyResult(result);
                          await _reload();
                          await _showRunResult(result);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    _NeonButton(
                      text: 'UPGRADES',
                      icon: Icons.auto_awesome_rounded,
                      onPressed: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => UpgradeScreen(profile: profile),
                          ),
                        );
                        await _reload();
                      },
                    ),
                    const SizedBox(height: 14),
                    _NeonButton(
                      text: 'HOW TO PLAY',
                      icon: Icons.help_outline_rounded,
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _HowToPlaySheet(),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallLinkButton(
                            text: 'Privacy Policy',
                            onPressed: () =>
                                _openWebView('Privacy Policy', privacyPolicyPageUrl),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SmallLinkButton(
                            text: 'Support',
                            onPressed: () =>
                                _openWebView('Support', supportPageUrl),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key, required this.profile});

  final PlayerProfile profile;

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  late PlayerProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile.copy();
  }

  Future<void> _buy(UpgradeType type) async {
    final cost = _profile.upgradeCost(type);
    if (!_profile.canUpgrade(type) || _profile.shards < cost) {
      return;
    }
    setState(() {
      _profile.shards -= cost;
      _profile.setUpgrade(type, _profile.upgradeLevel(type) + 1);
    });
    await _profile.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _SpaceScaffold(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'UPGRADES',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    _ShardBadge(value: _profile.shards),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: UpgradeType.values
                        .map(
                          (type) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _UpgradeCard(
                              type: type,
                              level: _profile.upgradeLevel(type),
                              cost: _profile.upgradeCost(type),
                              canBuy:
                                  _profile.canUpgrade(type) &&
                                  _profile.shards >= _profile.upgradeCost(type),
                              onBuy: () => _buy(type),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.profile});

  final PlayerProfile profile;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final math.Random _random = math.Random();
  final List<Planet> _planets = [];
  final List<Hazard> _hazards = [];
  final List<Pickup> _pickups = [];
  final List<Offset> _trail = [];

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  Offset _ball = Offset.zero;
  Offset _velocity = Offset.zero;
  Offset? _dragCurrent;
  int _orbitIndex = 0;
  double _angle = 0;
  double _pulse = 0;
  double _comboTimer = 0;
  double _messageTimer = 0;
  double _launchGrace = 0;
  double _sectorTimer = 0;
  bool _flying = false;
  bool _paused = false;
  bool _ended = false;
  int _level = 1;
  int _score = 0;
  int _earned = 0;
  int _lives = 3;
  int _combo = 1;
  String _message = 'Drag toward your target, then release!';

  double get _ballRadius => 13 + widget.profile.power * 1.4;
  double get _launchSpeed => 420 + widget.profile.power * 52;
  double get _smashRadius => 52 + widget.profile.power * 18;
  double get _magnetPower => widget.profile.magnet * 0.7;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setupLevel(Size size) {
    _size = size;
    _planets.clear();
    _hazards.clear();
    _pickups.clear();
    final count = (_level + 2).clamp(3, 6);
    final top = size.height * 0.18;
    final bottom = size.height * 0.78;
    final moveRange = _level >= 3
        ? (10 + _level * 2).clamp(10, 34).toDouble()
        : 0.0;
    for (var i = 0; i < count; i++) {
      final t = count == 1 ? 0.5 : i / (count - 1);
      final xWave = math.sin((_level * 0.8) + i * 1.75) * size.width * 0.25;
      final x = size.width * 0.5 + xWave + (_random.nextDouble() - 0.5) * 24;
      final y = top + (bottom - top) * t;
      _planets.add(
        Planet(
          position: Offset(x.clamp(76, size.width - 76), y),
          radius: 35 + _random.nextDouble() * 14,
          kind: PlanetKind.values[(i + _level) % PlanetKind.values.length],
          crystalAngle: -math.pi / 2 + (_random.nextDouble() - 0.5) * 1.2,
          shielded: _level > 2 && i.isOdd,
          movePhase: _random.nextDouble() * math.pi * 2,
          moveSpeed: _level >= 3 ? 0.45 + _random.nextDouble() * 0.45 : 0,
          moveRange: moveRange,
        ),
      );
    }
    if (_level >= 2) {
      final hazardCount = (_level ~/ 2).clamp(1, 3);
      for (var i = 0; i < hazardCount; i++) {
        _hazards.add(
          Hazard(
            position: Offset(
              64 + _random.nextDouble() * (size.width - 128),
              top + _random.nextDouble() * (bottom - top),
            ),
            radius: 20 + _random.nextDouble() * 9,
            spin: _random.nextDouble() * math.pi * 2,
          ),
        );
      }
    }
    final pickupCount = (1 + _level ~/ 3).clamp(1, 3);
    for (var i = 0; i < pickupCount; i++) {
      _pickups.add(
        Pickup(
          position: Offset(
            54 + _random.nextDouble() * (size.width - 108),
            top + _random.nextDouble() * (bottom - top),
          ),
          value: 4 + _level,
        ),
      );
    }
    _orbitIndex = 0;
    _angle = -math.pi / 2;
    _flying = false;
    _dragCurrent = null;
    _launchGrace = 0;
    _velocity = Offset.zero;
    _trail.clear();
    _sectorTimer = _level >= 4
        ? (34 - _level * 1.5).clamp(18, 34).toDouble()
        : 0;
    _placeBallOnOrbit();
    _showMessage(
      _level >= 4
          ? 'Timed sector: clear crystals fast!'
          : 'Level $_level: smash every crystal',
    );
  }

  void _placeBallOnOrbit() {
    final planet = _planets[_orbitIndex];
    _ball =
        planet.currentPosition +
        Offset(math.cos(_angle), math.sin(_angle)) *
            (planet.radius + _ballRadius + 8);
  }

  void _tick(Duration elapsed) {
    if (_paused || _ended || _size == Size.zero) {
      _last = elapsed;
      return;
    }
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    _update(dt.clamp(0.001, 0.032));
    if (mounted) {
      setState(() {});
    }
  }

  void _update(double dt) {
    _pulse = (_pulse - dt).clamp(0, 1);
    _messageTimer = (_messageTimer - dt).clamp(0, 3);
    _comboTimer = (_comboTimer - dt).clamp(0, 3);
    _launchGrace = (_launchGrace - dt).clamp(0, 0.2);
    if (_sectorTimer > 0) {
      _sectorTimer = (_sectorTimer - dt).clamp(0, 40);
      if (_sectorTimer <= 0) {
        _showMessage('Sector timer expired!');
        _loseLife();
        return;
      }
    }
    if (_comboTimer <= 0 && _combo > 1) {
      _combo = 1;
    }
    for (final planet in _planets) {
      planet.movePhase += planet.moveSpeed * dt;
      planet.offset = planet.moveRange == 0
          ? Offset.zero
          : Offset(math.sin(planet.movePhase) * planet.moveRange, 0);
    }
    for (final hazard in _hazards) {
      hazard.spin += dt * 1.6;
    }
    if (_flying) {
      if (_magnetPower > 0) {
        Planet? nearest;
        var best = double.infinity;
        for (final planet in _planets) {
          final d = (planet.currentPosition - _ball).distance;
          if (d < best) {
            best = d;
            nearest = planet;
          }
        }
        if (nearest != null && best < 190) {
          final pull = (nearest.currentPosition - _ball).normalized();
          _velocity += pull * (80 * _magnetPower * dt);
        }
      }
      for (final hazard in _hazards) {
        final distance = (_ball - hazard.position).distance;
        if (distance < hazard.radius * 5.5) {
          final pull = (hazard.position - _ball).normalized();
          _velocity += pull * (130 + _level * 9) * dt;
        }
      }
      _ball += _velocity * dt;
      _trail.add(_ball);
      if (_trail.length > 18) {
        _trail.removeAt(0);
      }
      for (final hazard in _hazards) {
        if ((_ball - hazard.position).distance < hazard.radius + _ballRadius) {
          _showMessage('Black hole hit!');
          _loseLife();
          return;
        }
      }
      for (final pickup in _pickups) {
        if (pickup.alive &&
            (_ball - pickup.position).distance < 18 + _ballRadius) {
          pickup.alive = false;
          _score += pickup.value * 8 * _combo;
          _earned += pickup.value;
          _extendCombo();
          _showMessage('+${pickup.value} shards • combo x$_combo');
        }
      }
      for (var i = 0; i < _planets.length; i++) {
        if (i == _orbitIndex && _launchGrace > 0) {
          continue;
        }
        final planet = _planets[i];
        final captureDistance = planet.radius + _ballRadius + 16;
        if ((_ball - planet.currentPosition).distance < captureDistance) {
          _orbitIndex = i;
          _angle = math.atan2(
            _ball.dy - planet.currentPosition.dy,
            _ball.dx - planet.currentPosition.dx,
          );
          _flying = false;
          _velocity = Offset.zero;
          _hitCrystal(planet, precise: true);
          break;
        }
      }
      if (_ball.dx < -70 ||
          _ball.dx > _size.width + 70 ||
          _ball.dy < -70 ||
          _ball.dy > _size.height + 70) {
        _loseLife();
      }
    } else {
      _angle += (1.35 + _level * 0.035) * dt;
      _placeBallOnOrbit();
      _trail.add(_ball);
      if (_trail.length > 22) {
        _trail.removeAt(0);
      }
      _hitCrystal(_planets[_orbitIndex], precise: true);
    }

    if (_planets.every((planet) => !planet.crystalAlive)) {
      _score += 150 * _level;
      _earned += 8 + _level * 2;
      _level++;
      _showMessage('Sector cleared!');
      _setupLevel(_size);
    }
  }

  void _extendCombo() {
    _combo = (_combo + 1).clamp(1, 9);
    _comboTimer = 3;
  }

  void _showMessage(String value) {
    _message = value;
    _messageTimer = 2.2;
  }

  void _hitCrystal(Planet planet, {required bool precise}) {
    if (!planet.crystalAlive) {
      return;
    }
    final crystal = planet.crystalPosition;
    final distance = (_ball - crystal).distance;
    final required = precise ? 31 + _ballRadius : _smashRadius;
    if (distance > required) {
      return;
    }
    if (planet.shielded) {
      planet.shielded = false;
      _score += 25 * _combo;
      _extendCombo();
      _showMessage('Shield cracked • combo x$_combo');
      return;
    }
    planet.crystalAlive = false;
    _score += (100 + _level * 18) * _combo;
    _earned += 3 + (_level / 2).floor() + (_combo ~/ 3);
    _extendCombo();
    _showMessage('Crystal smashed • combo x$_combo');
    _pulse = 1;
  }

  void _loseLife() {
    _lives--;
    if (_lives + widget.profile.shield <= 0) {
      _finish();
      return;
    }
    _orbitIndex = _orbitIndex.clamp(0, _planets.length - 1);
    _angle = -math.pi / 2;
    _flying = false;
    _dragCurrent = null;
    _launchGrace = 0;
    _combo = 1;
    _comboTimer = 0;
    _velocity = Offset.zero;
    _trail.clear();
    _placeBallOnOrbit();
    _showMessage('Careful! Aim before launch');
  }

  void _finish() {
    if (_ended) {
      return;
    }
    _ended = true;
    Navigator.of(
      context,
    ).pop(GameResult(score: _score, shards: _earned, level: _level));
  }

  void _startAim(DragDownDetails details) {
    if (_paused || _flying || _ended) {
      return;
    }
    setState(() => _dragCurrent = details.localPosition);
  }

  void _updateAim(DragUpdateDetails details) {
    if (_paused || _flying || _ended || _dragCurrent == null) {
      return;
    }
    setState(() => _dragCurrent = details.localPosition);
  }

  void _launch(DragEndDetails details) {
    if (_paused || _flying || _ended) {
      return;
    }
    var direction = _dragCurrent == null ? Offset.zero : _dragCurrent! - _ball;
    if (direction.distance < 22) {
      direction = Offset(-math.sin(_angle), math.cos(_angle));
    }
    final strength = (direction.distance / 120).clamp(0.55, 1.35);
    setState(() {
      _dragCurrent = null;
      _velocity = direction.normalized() * _launchSpeed * strength;
      _flying = true;
      _launchGrace = 0.18;
      _pulse = 0.6;
      _showMessage('Launch!');
    });
  }

  void _smash() {
    if (_paused || _ended) {
      return;
    }
    _pulse = 1;
    for (final planet in _planets) {
      _hitCrystal(planet, precise: false);
    }
    if (_flying) {
      _velocity *= 1.08;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _size && size.width > 0 && size.height > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _setupLevel(size));
              }
            });
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _smash,
            onPanDown: _startAim,
            onPanUpdate: _updateAim,
            onPanEnd: _launch,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/gravity_smash_space_background.webp',
                  fit: BoxFit.cover,
                ),
                CustomPaint(
                  painter: GamePainter(
                    planets: _planets,
                    hazards: _hazards,
                    pickups: _pickups,
                    ball: _ball,
                    trail: _trail,
                    pulse: _pulse,
                    ballRadius: _ballRadius,
                    aimEnd: _dragCurrent,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            _HudChip(label: 'LVL', value: '$_level'),
                            _HudChip(label: 'SCORE', value: '$_score'),
                            if (_combo > 1) ...[
                              _HudChip(label: 'COMBO', value: 'x$_combo'),
                            ],
                            if (_sectorTimer > 0) ...[
                              _HudChip(
                                label: 'TIME',
                                value: _sectorTimer.ceil().toString(),
                              ),
                            ],
                            _HudChip(label: 'SHARDS', value: '+$_earned'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (
                              var i = 0;
                              i < (_lives + widget.profile.shield).clamp(0, 6);
                              i++
                            )
                              const Padding(
                                padding: EdgeInsets.only(right: 5),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFFF2D9B),
                                  size: 20,
                                ),
                              ),
                            const Spacer(),
                            IconButton.filledTonal(
                              onPressed: () =>
                                  setState(() => _paused = !_paused),
                              icon: Icon(
                                _paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _messageTimer > 0 ? 1 : 0,
                          child: _ObjectiveBanner(
                            text: _message,
                            crystalsLeft: _planets
                                .where((planet) => planet.crystalAlive)
                                .length,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 240),
                          opacity: _paused ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !_paused,
                            child: _PauseMenu(
                              onResume: () => setState(() => _paused = false),
                              onReturn: _finish,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Drag toward a planet to aim • Release to fly • Tap to smash nearby crystals',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xCCDCF9FF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class GamePainter extends CustomPainter {
  GamePainter({
    required this.planets,
    required this.hazards,
    required this.pickups,
    required this.ball,
    required this.trail,
    required this.pulse,
    required this.ballRadius,
    required this.aimEnd,
  });

  final List<Planet> planets;
  final List<Hazard> hazards;
  final List<Pickup> pickups;
  final Offset ball;
  final List<Offset> trail;
  final double pulse;
  final double ballRadius;
  final Offset? aimEnd;

  @override
  void paint(Canvas canvas, Size size) {
    _drawAmbient(canvas, size);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x6600D4FF);
    for (final planet in planets) {
      canvas.drawCircle(
        planet.currentPosition,
        planet.radius + ballRadius + 8,
        orbitPaint,
      );
    }

    for (var i = 1; i < trail.length; i++) {
      final t = i / trail.length;
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0x0000D4FF),
          const Color(0xAA00D4FF),
          t,
        )!
        ..strokeWidth = 2 + t * 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(trail[i - 1], trail[i], paint);
    }

    for (final planet in planets) {
      _drawPlanet(canvas, planet);
      if (planet.crystalAlive) {
        _drawCrystal(canvas, planet);
      }
    }

    for (final hazard in hazards) {
      _drawHazard(canvas, hazard);
    }

    for (final pickup in pickups) {
      if (pickup.alive) {
        _drawPickup(canvas, pickup);
      }
    }

    if (aimEnd != null) {
      _drawAim(canvas, aimEnd!);
    }

    if (pulse > 0) {
      final pulsePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * pulse
        ..color = const Color(0xFF00D4FF).withValues(alpha: pulse * 0.75);
      canvas.drawCircle(ball, 34 + (1 - pulse) * 95, pulsePaint);
      canvas.drawCircle(ball, 14 + (1 - pulse) * 58, pulsePaint);
    }

    _drawBall(canvas);
  }

  void _drawAmbient(Canvas canvas, Size size) {
    final nebula = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.55, -0.35),
        radius: 0.9,
        colors: [
          const Color(0xFF9B30FF).withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, nebula);

    final starPaint = Paint()..color = const Color(0xAAE9FBFF);
    for (var i = 0; i < 34; i++) {
      final x = ((i * 83) % 997) / 997 * size.width;
      final y = ((i * 149) % 991) / 991 * size.height;
      final radius = 0.8 + (i % 4) * 0.35;
      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
  }

  void _drawAim(Canvas canvas, Offset drag) {
    final vector = ball - drag;
    if (vector.distance < 8) {
      return;
    }
    final end = ball + vector.normalized() * vector.distance.clamp(42, 145);
    final aimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD84A).withValues(alpha: 0.9);
    canvas.drawLine(ball, end, aimPaint);
    canvas.drawCircle(
      end,
      8,
      Paint()
        ..color = const Color(0xFFFFD84A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(end, 5, Paint()..color = const Color(0xFFFFFFFF));
  }

  void _drawHazard(Canvas canvas, Hazard hazard) {
    final center = hazard.position;
    canvas.drawCircle(
      center,
      hazard.radius * 1.75,
      Paint()
        ..color = const Color(0xFF9B30FF).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(center, hazard.radius, Paint()..color = Colors.black);
    canvas.drawCircle(
      center,
      hazard.radius * 2.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFF2D9B).withValues(alpha: 0.42),
    );
    final swirlPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF2D9B);
    final rect = Rect.fromCircle(center: center, radius: hazard.radius * 1.35);
    canvas.drawArc(rect, hazard.spin, math.pi * 1.35, false, swirlPaint);
    canvas.drawArc(
      rect.deflate(7),
      -hazard.spin * 1.2,
      math.pi * 1.1,
      false,
      swirlPaint..color = const Color(0xFF00D4FF),
    );
  }

  void _drawPickup(Canvas canvas, Pickup pickup) {
    final path = Path()
      ..moveTo(pickup.position.dx, pickup.position.dy - 15)
      ..lineTo(pickup.position.dx + 13, pickup.position.dy)
      ..lineTo(pickup.position.dx, pickup.position.dy + 15)
      ..lineTo(pickup.position.dx - 13, pickup.position.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFD84A).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD84A));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  void _drawPlanet(Canvas canvas, Planet planet) {
    final glow = Paint()
      ..color = planet.color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(planet.currentPosition, planet.radius * 1.22, glow);

    final shader =
        RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [
            planet.color.withValues(alpha: 0.85),
            const Color(0xFF151B34),
            const Color(0xFF060917),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(
          Rect.fromCircle(
            center: planet.currentPosition,
            radius: planet.radius,
          ),
        );
    canvas.drawCircle(
      planet.currentPosition,
      planet.radius,
      Paint()..shader = shader,
    );

    final crackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = planet.color.withValues(alpha: 0.9);
    for (var i = 0; i < 7; i++) {
      final a = i * math.pi * 2 / 7 + planet.crystalAngle;
      final start =
          planet.currentPosition +
          Offset(math.cos(a), math.sin(a)) * (planet.radius * 0.24);
      final end =
          planet.currentPosition +
          Offset(math.cos(a + 0.25), math.sin(a + 0.25)) *
              (planet.radius * 0.82);
      canvas.drawLine(start, end, crackPaint);
    }

    canvas.drawCircle(
      planet.currentPosition,
      planet.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = planet.color.withValues(alpha: 0.85),
    );
  }

  void _drawCrystal(Canvas canvas, Planet planet) {
    final pos = planet.crystalPosition;
    if (planet.shielded) {
      canvas.drawCircle(
        pos,
        27,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF9B30FF).withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        pos,
        27,
        Paint()
          ..color = const Color(0xFF9B30FF).withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    final path = Path()
      ..moveTo(pos.dx, pos.dy - 18)
      ..lineTo(pos.dx + 12, pos.dy)
      ..lineTo(pos.dx, pos.dy + 18)
      ..lineTo(pos.dx - 12, pos.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF00D4FF).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFF00D4FF));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFE9FBFF),
    );
  }

  void _drawBall(Canvas canvas) {
    final glow = Paint()
      ..color = const Color(0xFF00D4FF).withValues(alpha: 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(ball, ballRadius * 1.8, glow);
    canvas.drawCircle(
      ball,
      ballRadius,
      Paint()..color = const Color(0xFFE9FBFF),
    );
    canvas.drawCircle(
      ball,
      ballRadius * 0.72,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE9FBFF), Color(0xFF00D4FF), Color(0xFF17206A)],
        ).createShader(Rect.fromCircle(center: ball, radius: ballRadius)),
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}

class Planet {
  Planet({
    required this.position,
    required this.radius,
    required this.kind,
    required this.crystalAngle,
    required this.shielded,
    required this.movePhase,
    required this.moveSpeed,
    required this.moveRange,
  });

  final Offset position;
  final double radius;
  final PlanetKind kind;
  final double crystalAngle;
  double movePhase;
  double moveSpeed;
  double moveRange;
  Offset offset = Offset.zero;
  bool crystalAlive = true;
  bool shielded;

  Offset get crystalPosition =>
      currentPosition +
      Offset(math.cos(crystalAngle), math.sin(crystalAngle)) * (radius + 24);

  Offset get currentPosition => position + offset;

  Color get color => switch (kind) {
    PlanetKind.ice => const Color(0xFF00D4FF),
    PlanetKind.lava => const Color(0xFFFF6B2D),
    PlanetKind.tech => const Color(0xFF39FF14),
    PlanetKind.crystal => const Color(0xFF9B30FF),
  };
}

class Hazard {
  Hazard({required this.position, required this.radius, required this.spin});

  final Offset position;
  final double radius;
  double spin;
}

class Pickup {
  Pickup({required this.position, required this.value});

  final Offset position;
  final int value;
  bool alive = true;
}

enum PlanetKind { ice, lava, tech, crystal }

enum UpgradeType { power, magnet, shield }

extension UpgradeTypeText on UpgradeType {
  String get title => switch (this) {
    UpgradeType.power => 'Smash Power',
    UpgradeType.magnet => 'Gravity Magnet',
    UpgradeType.shield => 'Extra Shield',
  };

  String get description => switch (this) {
    UpgradeType.power => 'Bigger tap shockwave and faster launch.',
    UpgradeType.magnet => 'Pulls the ball toward nearby planets.',
    UpgradeType.shield => 'Adds extra lives at the start of a run.',
  };

  IconData get icon => switch (this) {
    UpgradeType.power => Icons.flash_on_rounded,
    UpgradeType.magnet => Icons.explore_rounded,
    UpgradeType.shield => Icons.shield_rounded,
  };
}

class PlayerProfile {
  PlayerProfile({
    required this.shards,
    required this.bestScore,
    required this.power,
    required this.magnet,
    required this.shield,
  });

  int shards;
  int bestScore;
  int power;
  int magnet;
  int shield;

  static PlayerProfile empty() =>
      PlayerProfile(shards: 0, bestScore: 0, power: 0, magnet: 0, shield: 0);

  PlayerProfile copy() => PlayerProfile(
    shards: shards,
    bestScore: bestScore,
    power: power,
    magnet: magnet,
    shield: shield,
  );

  static Future<PlayerProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerProfile(
      shards: prefs.getInt('shards') ?? 0,
      bestScore: prefs.getInt('bestScore') ?? 0,
      power: prefs.getInt('power') ?? 0,
      magnet: prefs.getInt('magnet') ?? 0,
      shield: prefs.getInt('shield') ?? 0,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('shards', shards);
    await prefs.setInt('bestScore', bestScore);
    await prefs.setInt('power', power);
    await prefs.setInt('magnet', magnet);
    await prefs.setInt('shield', shield);
  }

  Future<void> applyResult(GameResult result) async {
    shards += result.shards;
    bestScore = math.max(bestScore, result.score);
    await save();
  }

  int upgradeLevel(UpgradeType type) => switch (type) {
    UpgradeType.power => power,
    UpgradeType.magnet => magnet,
    UpgradeType.shield => shield,
  };

  void setUpgrade(UpgradeType type, int value) {
    switch (type) {
      case UpgradeType.power:
        power = value;
      case UpgradeType.magnet:
        magnet = value;
      case UpgradeType.shield:
        shield = value;
    }
  }

  int upgradeCost(UpgradeType type) => 35 + upgradeLevel(type) * 45;

  bool canUpgrade(UpgradeType type) => upgradeLevel(type) < 5;
}

class GameResult {
  const GameResult({
    required this.score,
    required this.shards,
    required this.level,
  });

  final int score;
  final int shards;
  final int level;
}

class _SpaceScaffold extends StatelessWidget {
  const _SpaceScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/gravity_smash_space_background.webp',
          fit: BoxFit.cover,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.1,
              colors: [
                const Color(0xFF101B4F).withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GameTitle extends StatelessWidget {
  const _GameTitle({required this.fontSize});

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
            colors: [Color(0xFFE9FBFF), Color(0xFF00D4FF), Color(0xFFFF2D9B)],
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

class _NeonButton extends StatelessWidget {
  const _NeonButton({
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.28),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xCC10245A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF00D4FF), width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallLinkButton extends StatelessWidget {
  const _SmallLinkButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE9FBFF),
        side: const BorderSide(color: Color(0xFF9B30FF)),
        backgroundColor: Colors.black.withValues(alpha: 0.28),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.profile});

  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _StatText(label: 'BEST', value: '${profile.bestScore}'),
          ),
          Expanded(
            child: _StatText(label: 'SHARDS', value: '${profile.shards}'),
          ),
          Expanded(
            child: _StatText(
              label: 'POWER',
              value: '${profile.power + profile.magnet + profile.shield}',
            ),
          ),
        ],
      ),
    );
  }
}

class _RunResultDialog extends StatelessWidget {
  const _RunResultDialog({required this.result});

  final GameResult result;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF07102A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF00D4FF)),
      ),
      title: const Text(
        'Run Complete',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ResultRow(label: 'Score', value: '${result.score}'),
          _ResultRow(label: 'Shards', value: '+${result.shards}'),
          _ResultRow(label: 'Reached', value: 'Level ${result.level}'),
          const SizedBox(height: 12),
          const Text(
            'Spend shards on upgrades and push deeper into the gravity sectors.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xBFE9FBFF)),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CONTINUE'),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xBFE9FBFF))),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _StatText extends StatelessWidget {
  const _StatText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xAAE9FBFF),
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({
    required this.type,
    required this.level,
    required this.cost,
    required this.canBuy,
    required this.onBuy,
  });

  final UpgradeType type;
  final int level;
  final int cost;
  final bool canBuy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF00D4FF), Color(0xFF9B30FF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Icon(type.icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  type.description,
                  style: const TextStyle(
                    color: Color(0xBFE9FBFF),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(
                    5,
                    (i) => Expanded(
                      child: Container(
                        height: 7,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: i < level
                              ? const Color(0xFF00D4FF)
                              : const Color(0x332A3A70),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: canBuy ? onBuy : null,
            child: Text(level >= 5 ? 'MAX' : '$cost'),
          ),
        ],
      ),
    );
  }
}

class _ShardBadge extends StatelessWidget {
  const _ShardBadge({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xAA20104E),
        border: Border.all(color: const Color(0xFFFFD84A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, color: Color(0xFFFFD84A), size: 18),
          const SizedBox(width: 5),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: Colors.black.withValues(alpha: 0.48),
        border: Border.all(color: const Color(0x8800D4FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xBFE9FBFF),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ObjectiveBanner extends StatelessWidget {
  const _ObjectiveBanner({required this.text, required this.crystalsLeft});

  final String text;
  final int crystalsLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.black.withValues(alpha: 0.5),
        border: Border.all(color: const Color(0x9900D4FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withValues(alpha: 0.18),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Crystals left: $crystalsLeft',
            style: const TextStyle(
              color: Color(0xBFE9FBFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseMenu extends StatelessWidget {
  const _PauseMenu({required this.onResume, required this.onReturn});

  final VoidCallback onResume;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PAUSED',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('RESUME'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onReturn,
            icon: const Icon(Icons.keyboard_return_rounded),
            label: const Text('RETURN'),
          ),
        ],
      ),
    );
  }
}

class _HowToPlaySheet extends StatelessWidget {
  const _HowToPlaySheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF07102A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to Play',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 14),
          Text(
            'Swipe while orbiting to launch the ball toward another planet.',
          ),
          SizedBox(height: 8),
          Text('Tap to trigger Gravity Smash and break nearby crystals.'),
          SizedBox(height: 8),
          Text(
            'Collect shards, buy upgrades, survive longer and chase a higher score.',
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(22),
    color: const Color(0xCC07102A),
    border: Border.all(color: const Color(0x9900D4FF)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF00D4FF).withValues(alpha: 0.18),
        blurRadius: 20,
      ),
    ],
  );
}

extension OffsetMath on Offset {
  Offset normalized() {
    final length = distance;
    if (length == 0) {
      return const Offset(1, 0);
    }
    return this / length;
  }
}
