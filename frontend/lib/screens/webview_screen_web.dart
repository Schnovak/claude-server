// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

/// Web implementation using iframe
Widget buildPlatformWebView(String url) {
  return _WebIframeView(url: url);
}

class _WebIframeView extends StatefulWidget {
  final String url;

  const _WebIframeView({required this.url});

  @override
  State<_WebIframeView> createState() => _WebIframeViewState();
}

class _WebIframeViewState extends State<_WebIframeView> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'webview-${DateTime.now().millisecondsSinceEpoch}';
    _registerViewFactory();
  }

  void _registerViewFactory() {
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = widget.url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'fullscreen';
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}
