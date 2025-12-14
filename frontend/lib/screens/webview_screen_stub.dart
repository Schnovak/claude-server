import 'package:flutter/material.dart';

/// Stub implementation - should never be used
Widget buildPlatformWebView(String url) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        const Text('WebView not available on this platform'),
        const SizedBox(height: 8),
        SelectableText(url),
      ],
    ),
  );
}
