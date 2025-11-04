import 'dart:io';
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
      final MediaInfo? info = await VideoCompress.compressVideo(
        inputFile.path,
        quality: quality,
        deleteOrigin: deleteOrigin,
      );
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
