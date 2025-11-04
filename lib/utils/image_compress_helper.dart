import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Compress images for upload. Returns a new File under temporary directory.
class ImageCompressHelper {
  static Future<File> compressImageFile(
    File inputFile, {
    int quality = 85,
    int maxWidth = 1080,
    int maxHeight = 1080,
    bool keepExif = true,
  }) async {
    final ext = inputFile.path.split('.').last.toLowerCase();
    final targetFormat = (ext == 'png')
        ? CompressFormat.png
        : CompressFormat.jpeg;
    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/${const Uuid().v4()}.$ext';

    final resultBytes = await FlutterImageCompress.compressWithFile(
      inputFile.absolute.path,
      quality: quality,
      minWidth: maxWidth,
      minHeight: maxHeight,
      keepExif: keepExif,
      format: targetFormat,
    );

    if (resultBytes == null) {
      // If compression failed for any reason, return original file
      return inputFile;
    }

    final outFile = File(outPath);
    await outFile.writeAsBytes(resultBytes);
    return outFile;
  }
}
