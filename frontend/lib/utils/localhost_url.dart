import '../services/api_client.dart';

/// Helper for transforming localhost URLs to use the backend proxy.
///
/// When Claude runs a dev server on localhost:3000 on the server machine,
/// we transform the URL to go through our backend proxy so the client
/// can access it regardless of where they're connecting from.
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

  /// Transforms a localhost URL to use the backend proxy.
  ///
  /// Converts http://localhost:3000/path to /api/proxy/3000/path?token=...
  /// which the backend will forward to the actual localhost server.
  ///
  /// [token] is required for authentication when loading in iframe/webview.
  static String transform(String url, {String? token}) {
    if (!isLocalhost(url)) return url;

    try {
      final uri = Uri.parse(url);
      final port = uri.port;

      // Port is required for proxy
      if (port == 0) {
        return url;
      }

      // Build path for the proxy endpoint
      final path = uri.path.isEmpty ? '' : uri.path;

      // Build query string, including original query params and token
      final queryParams = <String>[];
      if (uri.query.isNotEmpty) {
        queryParams.add(uri.query);
      }
      if (token != null) {
        queryParams.add('token=$token');
      }
      final query = queryParams.isEmpty ? '' : '?${queryParams.join('&')}';

      // Use the API base URL to build the proxy URL
      return '${ApiClient.baseUrl}/proxy/$port$path$query';
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
