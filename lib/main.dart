import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/firebase_options.dart';
import 'package:pay_go/pages/auth_gate.dart';
import 'package:pay_go/services/api_service.dart';

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
  await ApiService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pay Go',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
