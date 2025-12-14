/// Stub implementation for unsupported platforms.
///
/// This file is used when neither dart:html nor dart:io is available.
Future<void> downloadFile(String url, String filename) {
  throw UnsupportedError('File download not supported on this platform');
}

/// Check if downloads are supported on this platform.
bool isDownloadSupported() => false;
