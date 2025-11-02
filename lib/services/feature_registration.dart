import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'api_service.dart';
import 'call_service.dart';
import 'notification_service.dart';
import 'feature_chat_registration.dart';
import 'feature_calls_registration.dart';
import 'feature_donate_registration.dart';

/// registerBackgroundFeatures()
/// Runs non-essential or heavier initializations after the UI is visible.
/// Keeps the app feeling responsive by deferring work such as opening Hive
/// boxes, registering adapters, and starting long-lived listeners.
Future<void> registerBackgroundFeatures({String? overrideBaseUrl}) async {
  final stopwatch = Stopwatch()..start();

  debugPrint('Background feature registration started');

  // Initialize core background pieces in parallel first
  await Future.wait([
    _initHiveAndAdapters(),
    ApiService().initialize(overrideBaseUrl: overrideBaseUrl),
  ]);

  debugPrint(
    'Core background init completed in ${stopwatch.elapsedMilliseconds} ms',
  );

  // Register feature modules in parallel where safe. These are lightweight
  // and won't block the UI significantly. If a module needs heavier work,
  // it can defer further initialization until the module is opened.
  final moduleStopwatch = Stopwatch()..start();
  await Future.wait([
    registerCallsFeature(),
    registerChatFeature(),
    registerDonateFeature(),
    // Notifications may request permissions; run it but don't await critical path
    NotificationService().initialize(),
  ]);

  debugPrint(
    'Feature modules registered in ${moduleStopwatch.elapsedMilliseconds} ms',
  );
  debugPrint(
    'Background feature registration finished in ${stopwatch.elapsedMilliseconds} ms',
  );
}

Future<void> _initHiveAndAdapters() async {
  try {
    if (!Hive.isBoxOpen(CallService.callHistoryBoxName)) {
      await Hive.initFlutter();
    }
  } catch (e) {
    debugPrint('Hive init background: $e');
  }

  try {
    CallService.registerAdapters();
  } catch (e) {
    debugPrint('Register Hive adapters failed: $e');
  }
}
