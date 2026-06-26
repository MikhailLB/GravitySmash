import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'browserish_client.dart';
import 'prefs_vault.dart';

// ============================================================
// FCM CONDUCTOR — Coordinates Firebase Messaging, local
// notification display, and routing of `url` payloads in/out
// of the gray flow.
//
// Push lifecycle (per TZ):
//   • App KILLED, user taps push  → `getInitialMessage` at boot
//                                  → SAVE url in PrefsVault.
//   • App BG/FG, user taps push   → `onMessageOpenedApp` /
//                                    foreground local tap
//                                  → fire callback, DO NOT save.
//
// Notification icon points to `@drawable/ic_notif_flame` — a
// monochrome flame distinct from the launcher icon.
// ============================================================

@pragma('vm:entry-point')
Future<void> _backgroundIsolateNoop(RemoteMessage _) async {
  // Display is handled by the OS, the URL is handled when the
  // foreground process resumes.  Nothing to do here.
}

class FcmConductor {
  FcmConductor(this._vault);

  final PrefsVault _vault;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  String? _registrationToken;
  bool _ready = false;

  /// Fired when the user taps a notification while the app is in
  /// foreground or background (URL must be applied live to the
  /// WebShell controller, NOT persisted).
  Function(String url)? onWarmTapUrl;

  /// Fired when the FCM token rotates so SplashScreen can re-POST
  /// to the orbit endpoint with the fresh token.
  Function(String newToken)? onTokenRotated;

  String? get registrationToken => _registrationToken;

  Future<void> bringOnline() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_backgroundIsolateNoop);
      await _prepareLocalChannel();
      _registrationToken = await _messaging!.getToken();

      _messaging!.onTokenRefresh.listen((token) {
        _registrationToken = token;
        onTokenRotated?.call(token);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final cold = await _messaging!.getInitialMessage();
      if (cold != null) {
        _onColdTap(cold);
      }

      _ready = true;
    } catch (_) {
      // Firebase not configured for this build — push silently
      // disabled.  Rest of the gray flow continues normally.
    }
  }

  Future<void> _prepareLocalChannel() async {
    const android = AndroidInitializationSettings('@drawable/ic_notif_flame');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    if (Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'gravity_orbit_channel',
          'Gravity Orbit Pulse',
          description: 'In-app gameplay alerts and operator messages.',
          importance: Importance.high,
        ),
      );
    }
  }

  Future<bool> requestPushPermission() async {
    if (_messaging == null) return false;
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    await _vault.markPushGranted(granted);
    if (!granted && settings.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markPushOsDenied();
    }
    return granted;
  }

  // ---- handlers -----------------------------------------------------------

  void _onForeground(RemoteMessage msg) async {
    if (!Platform.isAndroid) return; // iOS shows its own banners
    final notification = msg.notification;
    if (notification == null) return;

    AndroidNotificationDetails details;
    final imageUrl = notification.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final imageBytes = await _downloadBytes(imageUrl);
      if (imageBytes != null) {
        details = AndroidNotificationDetails(
          'gravity_orbit_channel',
          'Gravity Orbit Pulse',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notif_flame',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(imageBytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      } else {
        details = _plainDetails();
      }
    } else {
      details = _plainDetails();
    }

    final payload = msg.data.isNotEmpty ? jsonEncode(msg.data) : null;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  AndroidNotificationDetails _plainDetails() {
    return const AndroidNotificationDetails(
      'gravity_orbit_channel',
      'Gravity Orbit Pulse',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notif_flame',
    );
  }

  void _onLocalTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url != null && url.isNotEmpty) {
        onWarmTapUrl?.call(url);
      }
    } catch (_) {}
  }

  void _onWarmTap(RemoteMessage msg) {
    final url = msg.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onWarmTapUrl?.call(url);
    }
  }

  void _onColdTap(RemoteMessage msg) {
    final url = msg.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _vault.writePushUrl(url);
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final response = await orbitHttp
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}
