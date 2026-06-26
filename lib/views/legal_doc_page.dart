import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ============================================================
// LEGAL DOC PAGE — Lightweight WebView shell used to display
// the Privacy Policy / Support pages from the arena game menu.
//
// Always shows an AppBar so the user can return to the arena
// menu (the WebShell variant used in gray mode is full-screen
// and uses immersive mode instead).
// ============================================================

class LegalDocPage extends StatefulWidget {
  const LegalDocPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<LegalDocPage> createState() => _LegalDocPageState();
}

class _LegalDocPageState extends State<LegalDocPage> {
  late final WebViewController _controller;
  int _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050A1A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _loadProgress = p),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A1A),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF07102A),
        foregroundColor: const Color(0xFFE9FBFF),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loadProgress < 100)
            LinearProgressIndicator(
              value: _loadProgress / 100,
              color: const Color(0xFF00D4FF),
              backgroundColor: const Color(0xFF17206A),
            ),
        ],
      ),
    );
  }
}
