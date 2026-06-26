import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../orbit/fcm_conductor.dart';
import '../orbit/net_sensor.dart';
import '../orbit/prefs_vault.dart';
import 'offline_guard_page.dart';

// ============================================================
// ORBIT WEB SHELL — Full-screen WebView container that hosts
// the URL returned by the orbit configuration endpoint.
//
// Built-in protections (mapped to the TZ + gray guide):
//   • Immersive system UI, re-applied on resume.
//   • adjustResize + resizeToAvoidBottomInset:false + JS scroll
//     fix combo to keep keyboard from covering inputs.
//   • Safe-area inset killer for partner sites that leave gaps
//     on notched phones.
//   • Cookie acceptance + media autoplay for affiliate iframes.
//   • Too-many-redirects retry (max 3).
//   • Push warm-tap forwarding without persistence.
//   • Connectivity drop pivots to OfflineGuardPage immediately,
//     no second DNS round-trip.
// ============================================================

/// Hook for `deferred as shell` — prepares the WebView platform if
/// any pre-warming is needed by the host plugin.
Future<void> primeOrbitShell() async {
  // No-op today — the webview_flutter Android plugin warms up
  // lazily.  Kept around so future versions can hook in without
  // having to touch the boot gate.
}

class OrbitWebShell extends StatefulWidget {
  const OrbitWebShell({
    super.key,
    required this.url,
    required this.vault,
    required this.conductor,
    required this.sensor,
  });

  final String url;
  final PrefsVault vault;
  final FcmConductor conductor;
  final NetSensor sensor;

  @override
  State<OrbitWebShell> createState() => _OrbitWebShellState();
}

class _OrbitWebShellState extends State<OrbitWebShell>
    with WidgetsBindingObserver {
  late final WebViewController _ctrl;
  StreamSubscription<List<ConnectivityResult>>? _radioSub;
  bool _busy = true;
  bool _showingOffline = false;
  String? _lastTopUrl;
  int _redirectRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    // Intentionally do NOT call `setUserAgent`.  Letting the Android
    // System WebView use its built-in UA string is the safest option:
    // it always matches the real device's Chrome WebView version and
    // never carries any Flutter/Dart/bundle hints that fingerprinting
    // middleware could grep on.
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(_buildDelegate())
      ..enableZoom(false);

    _configurePlatform();
    _ctrl.loadRequest(Uri.parse(widget.url));

    widget.conductor.onWarmTapUrl = (url) {
      if (mounted) _ctrl.loadRequest(Uri.parse(url));
    };

    _radioSub = widget.sensor.radioStream.listen((snapshot) {
      if (widget.sensor.isOffline(snapshot)) {
        _pivotToOffline();
      }
    });
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  NavigationDelegate _buildDelegate() {
    return NavigationDelegate(
      onPageStarted: (_) {
        if (mounted) setState(() => _busy = true);
      },
      onPageFinished: (_) {
        if (mounted) setState(() => _busy = false);
        _redirectRetries = 0;
        _injectSafeAreaKill();
        _injectKeyboardFollower();
      },
      onWebResourceError: (error) {
        if (error.isForMainFrame != true) return;
        final desc = error.description.toLowerCase();
        final hopLoop = desc.contains('too_many_redirects') ||
            desc.contains('too many redirects') ||
            error.errorCode == -1007 ||
            error.errorCode == -9;
        if (hopLoop && _lastTopUrl != null && _redirectRetries < 3) {
          _redirectRetries++;
          _ctrl.loadRequest(Uri.parse(_lastTopUrl!));
          return;
        }
        _maybeShowOffline();
      },
      onHttpError: (_) {},
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (uri == null) return NavigationDecision.prevent;
        switch (uri.scheme) {
          case 'http':
          case 'https':
          case 'about':
          case 'data':
          case 'blob':
            if (request.isMainFrame) _lastTopUrl = request.url;
            return NavigationDecision.navigate;
          default:
            _hopExternal(uri);
            return NavigationDecision.prevent;
        }
      },
    );
  }

  void _configurePlatform() {
    if (!Platform.isAndroid) return;
    if (_ctrl.platform is! AndroidWebViewController) return;
    final platform = _ctrl.platform as AndroidWebViewController;
    platform.setMediaPlaybackRequiresUserGesture(false);
    platform.setOnShowFileSelector(_handleFileSelector);

    final cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(platform, true);
  }

  Future<List<String>> _handleFileSelector(FileSelectorParams params) async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result == null) return [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _hopExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _pivotToOffline() async {
    if (_showingOffline || !mounted) return;
    _showingOffline = true;
    final currentUrl = await _ctrl.currentUrl() ?? widget.url;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineGuardPage(
          nextRouteBuilder: (_) => OrbitWebShell(
            url: currentUrl,
            vault: widget.vault,
            conductor: widget.conductor,
            sensor: widget.sensor,
          ),
        ),
      ),
    );
  }

  Future<void> _maybeShowOffline() async {
    if (_showingOffline) return;
    final up = await widget.sensor.hasUplink();
    if (up) return;
    _pivotToOffline();
  }

  // Exact copy of the keyboard scroll fix from AdventureRoad/content_screen.dart.
  // IMPORTANT: behavior must be 'auto', NOT 'smooth' — smooth scroll conflicts
  // with the keyboard animation on Android and causes visible jitter.
  // Single setTimeout at 350ms — not multiple at 250/500/800ms.
  void _injectKeyboardFollower() {
    _ctrl.runJavaScript('''
(function() {
  if (window.__kbScrollFixApplied) return;
  window.__kbScrollFixApplied = true;

  function isInput(el) {
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }

  function doScroll() {
    var el = document.activeElement;
    if (!isInput(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var rect = el.getBoundingClientRect();
      var vpBottom = vp.offsetTop + vp.height;
      if (rect.bottom > vpBottom - 20 || rect.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (isInput(e.target)) {
      setTimeout(doScroll, 350);
    }
  });

  if (window.visualViewport) {
    var prevH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < prevH) { setTimeout(doScroll, 120); }
      prevH = h;
    });
  }
})();
''');
  }

  // Exact copy of safeAreaKill from AdventureRoad — NO keyboardOpen guard
  // (that guard was incorrectly causing the CSS to be skipped mid-session
  // on some Android OEM WebViews, leaving white bars visible).
  void _injectSafeAreaKill() {
    _ctrl.runJavaScript(r'''
(function() {
  if (window.__flsaRunning) return;
  window.__flsaRunning = true;

  var CSS_ID = '__flsa';
  var CSS_TEXT =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    'html,body,#__nuxt,#__layout,#app,#root,' +
    '.gameview-mobile-header{' +
      'padding-top:0!important;' +
      'padding-left:0!important;' +
      'padding-right:0!important;' +
      'margin-top:0!important;' +
    '}';

  function apply() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(CSS_ID);
    if (!s) {
      s = document.createElement('style');
      s.id = CSS_ID;
      head.appendChild(s);
    }
    if (s.textContent !== CSS_TEXT) s.textContent = CSS_TEXT;
    if (head.lastElementChild !== s) head.appendChild(s);
  }

  apply();

  ['pushState', 'replaceState'].forEach(function(fn) {
    var orig = history[fn];
    history[fn] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _radioSub?.cancel();
    widget.conductor.onWarmTapUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _onBack() async {
    if (await _ctrl.canGoBack()) {
      await _ctrl.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final vp = MediaQuery.of(context).viewPadding;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Portrait: top (status bar) + bottom (nav bar / gesture zone).
              // Landscape: left + right (camera cutout on the side).
              // In landscape immersive mode hides top/bottom system bars,
              // so only side cutouts need compensation.
              padding: isLandscape
                  ? EdgeInsets.only(left: vp.left, right: vp.right)
                  : EdgeInsets.only(top: vp.top, bottom: vp.bottom),
              child: WebViewWidget(controller: _ctrl),
            ),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
