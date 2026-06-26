import 'package:flutter/material.dart';

import 'orbit/attribution_tracker.dart';
import 'orbit/fcm_conductor.dart';
import 'orbit/net_sensor.dart';
import 'orbit/orbit_config_client.dart';
import 'orbit/prefs_vault.dart';
import 'views/boot_gate.dart';

/// Top-level Material widget — keeps the `MaterialApp` config in
/// one place and forwards the gray-flow services down to the
/// boot gate.
class GravityOrbitApp extends StatelessWidget {
  const GravityOrbitApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gravity Smash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF050A1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D4FF),
          brightness: Brightness.dark,
        ),
      ),
      home: BootGate(
        vault: vault,
        sensor: sensor,
        tracker: tracker,
        config: config,
        conductor: conductor,
      ),
    );
  }
}
