import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
// Hive and other heavy services are initialized lazily in background.
import 'package:pay_go/firebase_options.dart';
import 'package:pay_go/pages/auth_gate.dart';
import 'package:pay_go/services/api_service.dart';
// background services are initialized by `registerBackgroundFeatures`
import 'package:pay_go/widgets/notification_handler.dart';
import 'package:pay_go/widgets/incoming_call_listener.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Minimal, blocking initialization required before showing the Feed:
      // - Firebase must be initialized before using FirebaseAuth/Firestore
      // - ApiService depends on Firebase and therefore must be created/used
      //   after Firebase.initializeApp completes.
      const overrideBaseUrl = 'https://mini-soco-backend-1-d2i9.onrender.com/api';
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // ApiService may reference FirebaseAuth/Firestore in its constructor;
      // initialize it only after Firebase has been initialized.
      await ApiService().initialize(overrideBaseUrl: overrideBaseUrl);

      // Navigate immediately to main app UI. Background features will be
      // initialized by `FeedPage` once the first frame is rendered.
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const IncomingCallListener(
            child: NotificationHandler(child: AuthGate()),
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Splash init error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    SizedBox(height: 16),
                    Text('Loading UI...'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text('Failed to start: $_error'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                        });
                        _initializeApp();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
