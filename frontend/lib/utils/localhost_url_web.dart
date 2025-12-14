// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation - gets the current page's hostname
String? getCurrentHost() {
  try {
    return html.window.location.hostname;
  } catch (_) {
    return null;
  }
}
