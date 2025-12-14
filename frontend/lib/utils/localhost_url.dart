import 'package:flutter/foundation.dart';

import 'localhost_url_stub.dart'
    if (dart.library.html) 'localhost_url_web.dart' as platform;

/// Helper for transforming localhost URLs to be accessible from the client.
///
/// When Claude runs a dev server on localhost:3000 on the server machine,
/// we need to transform that URL so the client can access it.
class LocalhostUrl {
  /// Checks if a URL points to localhost
  static bool isLocalhost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host == 'localhost' ||
             uri.host == '127.0.0.1' ||
             uri.host == '0.0.0.0';
    } catch (_) {
      return false;
    }
  }

  /// Transforms a localhost URL to be accessible from the current context.
  ///
  /// On web: Replaces localhost with the current page's hostname
  /// In debug mode: Returns the URL as-is (assumes local development)
  static String transform(String url, {String? serverHost}) {
    if (!isLocalhost(url)) return url;

    try {
      final uri = Uri.parse(url);

      // Use provided server host or detect from platform
      final host = serverHost ?? platform.getCurrentHost();

      // In debug mode with no server host, return as-is
      if (host == null) {
        return url;
      }

      // Create new URI with the server's host but keep the port from the localhost URL
      final newUri = Uri(
        scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
        host: host,
        port: uri.port,
        path: uri.path,
        query: uri.query.isEmpty ? null : uri.query,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      );

      return newUri.toString();
    } catch (_) {
      return url;
    }
  }

  /// Extracts the port from a localhost URL
  static int? getPort(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.port == 0 ? null : uri.port;
    } catch (_) {
      return null;
    }
  }
}
