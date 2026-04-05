import 'dart:io';

import 'package:crypto/crypto.dart';

/// Utilities for files: compute length and md5 checksum.
class FileUtils {
  /// Returns a map containing 'length' (int) and 'md5' (String hex)
  static Future<Map<String, dynamic>> diagnostics(File file) async {
    final length = await file.length();
    // Compute md5 using a streaming approach to avoid allocating entire file in memory.
    final digest = await _md5ForFile(file);
    return {'length': length, 'md5': digest};
  }

  static Future<String> _md5ForFile(File file) async {
    final input = file.openRead();
    final digestSink = _DigestAccumulatorSink();
    final byteSink = md5.startChunkedConversion(digestSink);
    await for (final chunk in input) {
      byteSink.add(chunk);
    }
    byteSink.close();
    final digest = digestSink.digest;
    return digest.toString();
  }
}

class _DigestAccumulatorSink implements Sink<Digest> {
  Digest? _d;
  @override
  void add(Digest data) {
    _d = data;
  }

  @override
  void close() {}

  Digest get digest => _d ?? Digest(List<int>.empty());
}
