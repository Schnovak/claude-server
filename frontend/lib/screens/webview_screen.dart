import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Conditional import for webview
import 'webview_screen_stub.dart'
    if (dart.library.io) 'webview_screen_mobile.dart'
    if (dart.library.html) 'webview_screen_web.dart';

/// Screen for viewing localhost URLs in-app.
///
/// On mobile: Uses WebView to display the URL
/// On web: Opens in new tab or shows in iframe
class WebViewScreen extends StatelessWidget {
  final String url;
  final String? title;

  const WebViewScreen({
    super.key,
    required this.url,
    this.title,
  });

  /// Opens a localhost URL appropriately for the platform.
  ///
  /// On mobile: Pushes WebViewScreen to navigator
  /// On web: Opens in new tab
  static Future<void> openUrl(BuildContext context, String url, {String? title}) async {
    if (kIsWeb) {
      // On web, open in new tab
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      // On mobile, use WebView
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WebViewScreen(url: url, title: title),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            tooltip: 'Open in browser',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Reload handled by platform implementation
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: buildPlatformWebView(url),
    );
  }
}
