/// Mobile/Desktop implementation for file downloads using dart:io.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Download a file by URL on mobile/desktop platforms.
///
/// Uses Dio to download the file to the app's documents directory.
/// Returns the path where the file was saved.
Future<String> downloadFile(String url, String filename) async {
  final dio = Dio();

  // Get the downloads/documents directory based on platform
  Directory downloadDir;
  if (Platform.isAndroid) {
    // On Android, prefer external storage downloads folder
    downloadDir = Directory('/storage/emulated/0/Download');
    if (!await downloadDir.exists()) {
      // Fallback to app documents directory
      downloadDir = await getApplicationDocumentsDirectory();
    }
  } else if (Platform.isIOS) {
    downloadDir = await getApplicationDocumentsDirectory();
  } else {
    // Desktop platforms
    downloadDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  }

  final filePath = '${downloadDir.path}/$filename';

  try {
    await dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          final progress = (received / total * 100).toStringAsFixed(0);
          debugPrint('Download progress: $progress%');
        }
      },
    );
    debugPrint('File downloaded to: $filePath');
    return filePath;
  } catch (e) {
    debugPrint('Download failed: $e');
    rethrow;
  }
}

/// Check if downloads are supported on this platform.
bool isDownloadSupported() => true;
