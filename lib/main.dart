import 'dart:io' show HttpClient, Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/firebase_options.dart';
import 'package:pay_go/pages/auth_gate.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/notification_service.dart';
import 'package:pay_go/widgets/notification_handler.dart';
import 'package:pay_go/widgets/incoming_call_listener.dart';

// You will need to generate this file using the FlutterFire CLI
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Make sure you have configured Firebase for your project.
  // For a new project, you need to run `flutterfire configure`
  // which will generate a `lib/firebase_options.dart` file.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions
        .currentPlatform, // Uncomment this line after generating firebase_options.dart
  );
  final overrideBaseUrl = await _resolveAndroidLocalBaseUrl();
  await ApiService().initialize(overrideBaseUrl: overrideBaseUrl);

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pay Go',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const IncomingCallListener(
        child: NotificationHandler(child: AuthGate()),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

Future<String?> _resolveAndroidLocalBaseUrl() async {
  if (kReleaseMode || kIsWeb) {
    return null;
  }

  if (!Platform.isAndroid) {
    return null;
  }

  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final candidates = <String>[];

    if (androidInfo.isPhysicalDevice) {
      candidates.addAll([
        'http://localhost:3000/api',
        'http://10.0.2.2:3000/api',
      ]);
    } else {
      candidates.addAll([
        'http://10.0.2.2:3000/api',
        'http://localhost:3000/api',
      ]);
    }

    for (final candidate in candidates) {
      if (await _isServerReachable(candidate)) {
        return candidate;
      }
    }

    debugPrint(
      'ApiService: Unable to reach local API using default candidates. '
      'Start the backend, run `adb reverse tcp:3000 tcp:3000` for tethered '
      'devices or expose the server on your LAN, then restart the app.',
    );
  } catch (err) {
    debugPrint('Failed to resolve Android base URL override: $err');
  }

  return null;
}

Future<bool> _isServerReachable(String baseUrl) async {
  try {
    final uri = Uri.parse(baseUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.openUrl('HEAD', uri);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain();
    client.close(force: true);
    return response.statusCode >= 200 && response.statusCode < 500;
  } catch (_) {
    return false;
  }
}
