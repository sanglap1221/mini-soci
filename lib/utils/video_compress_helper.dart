import 'dart:io';
import 'dart:async';
import 'package:video_compress/video_compress.dart';

/// Helper for compressing videos on the client using the maintained
/// `video_compress` package.
class VideoCompressHelper {
  /// Compress the video at [inputFile] and return a File pointing to a
  /// compressed copy. Returns null if compression failed.
  static Future<File?> compressVideoFile(
    File inputFile, {
    VideoQuality quality = VideoQuality.MediumQuality,
    bool deleteOrigin = false,
  }) async {
    try {
      await VideoCompress.setLogLevel(0);
      // Run compression but guard against indefinite hangs by using a timeout.
      // If the compression takes longer than 2 minutes, cancel and fall back.
      final compressFuture = VideoCompress.compressVideo(
        inputFile.path,
        quality: quality,
        deleteOrigin: deleteOrigin,
      );
      MediaInfo? info;
      try {
        info = await compressFuture.timeout(const Duration(minutes: 2));
      } on TimeoutException {
        // Attempt to cancel the running compression (native side) and return null
        try {
          await VideoCompress.cancelCompression();
        } catch (_) {}
        return null;
      }
      final filePath = info?.file?.path ?? info?.path;
      if (filePath == null) return null;
      return File(filePath);
    } catch (_) {
      return null;
    }
  }

  /// Clear any cached compressed files.
  static Future<void> dispose() async {
    await VideoCompress.deleteAllCache();
  }
}
