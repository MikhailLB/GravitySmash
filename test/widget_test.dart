import 'package:flutter_test/flutter_test.dart';
import 'package:gravitysmash/app_root.dart';
import 'package:gravitysmash/orbit/attribution_tracker.dart';
import 'package:gravitysmash/orbit/fcm_conductor.dart';
import 'package:gravitysmash/orbit/net_sensor.dart';
import 'package:gravitysmash/orbit/orbit_config_client.dart';
import 'package:gravitysmash/orbit/prefs_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Boot gate renders the loading splash branding', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final vault = PrefsVault();
    await vault.warmUp();
    final sensor = NetSensor();
    final tracker = AttributionTracker();
    final config = OrbitConfigClient(vault);
    final conductor = FcmConductor(vault);

    await tester.pumpWidget(GravityOrbitApp(
      vault: vault,
      sensor: sensor,
      tracker: tracker,
      config: config,
      conductor: conductor,
    ));
    await tester.pump();

    expect(find.text('GRAVITY\nSMASH'), findsWidgets);
    expect(find.text('LOADING'), findsOneWidget);
  });
}
