/// Platform-conditional file download exports.
///
/// Uses conditional imports to select the correct implementation
/// for the current platform (web vs mobile/desktop).
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_mobile.dart';
