import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root.dart';
import 'orbit/attribution_tracker.dart';
import 'orbit/browserish_client.dart';
import 'orbit/fcm_conductor.dart';
import 'orbit/net_sensor.dart';
import 'orbit/orbit_config_client.dart';
import 'orbit/prefs_vault.dart';

// ============================================================
// MAIN — Cold-start entry point.  Performs the minimum work
// required before `runApp` so the first frame can paint:
//   • Firebase + App Check init (silently swallows failure so
//     a missing google-services.json never crashes the app).
//   • System-chrome orientation and overlay defaults.
//   • Bootstraps the HTTP client UA cache.
//   • Constructs every gray-flow service and hands the assembly
//     to `GravityOrbitApp`.
//
// All heavy work (attribution wait, config POST, push token
// fetch) is deferred to the Boot Gate so the loading splash is
// already visible while it happens.
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );
  } catch (_) {
    // Firebase or App Check not provisioned — that is acceptable
    // for the offline arena experience.  Push / attribution will
    // simply be inert this session.
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await orbitHttp.warmUp();

  final vault = PrefsVault();
  await vault.warmUp();

  final sensor = NetSensor();
  final tracker = AttributionTracker();
  final config = OrbitConfigClient(vault);
  final conductor = FcmConductor(vault);

  runApp(GravityOrbitApp(
    vault: vault,
    sensor: sensor,
    tracker: tracker,
    config: config,
    conductor: conductor,
  ));
}
