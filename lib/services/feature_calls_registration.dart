import 'package:flutter/foundation.dart';
import 'call_service.dart';

/// Register call-related background features.
Future<void> registerCallsFeature() async {
  final stopwatch = Stopwatch()..start();
  debugPrint('Calls feature registration started');

  try {
    // Register Hive adapters and open the call history box used by the UI.
    CallService.registerAdapters();
    await CallService().initializeLocalCache();
  } catch (e) {
    debugPrint('Calls registration error: $e');
  }

  debugPrint('Calls feature registered in ${stopwatch.elapsedMilliseconds} ms');
}
