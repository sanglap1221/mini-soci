import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Register chat-related background features.
Future<void> registerChatFeature() async {
  final stopwatch = Stopwatch()..start();
  debugPrint('Chat feature registration started');

  try {
    // Warm up API client or prefetch light chat metadata (non-blocking)
    // If you have a dedicated chat repository, initialize it here.
    await ApiService().initialize();
  } catch (e) {
    debugPrint('Chat registration error: $e');
  }

  debugPrint('Chat feature registered in ${stopwatch.elapsedMilliseconds} ms');
}
