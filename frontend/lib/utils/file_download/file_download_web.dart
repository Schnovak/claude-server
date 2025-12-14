/// Web implementation for file downloads using dart:html.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Download a file by URL on web platform.
///
/// Uses an anchor element with download attribute to trigger browser download.
Future<void> downloadFile(String url, String filename) async {
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
}

/// Check if downloads are supported on this platform.
bool isDownloadSupported() => true;
