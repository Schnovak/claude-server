/// Stub implementation for non-web platforms
String? getCurrentHost() {
  // On non-web platforms, we don't have automatic host detection
  // Users should provide the server host manually or use debug mode
  return null;
}
