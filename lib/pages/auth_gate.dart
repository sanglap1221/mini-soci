import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pay_go/pages/homepage.dart';
import 'package:pay_go/pages/login_or_register.dart';
import 'package:pay_go/services/api_service.dart';
import 'package:pay_go/services/notification_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // User is signed in, send FCM token to server
        NotificationService().sendTokenToServer(ApiService());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // user is logged in
          if (snapshot.hasData) {
            return Homepage();
          }
          // user is NOT logged in
          else {
            return const LoginOrRegisterPage();
          }
        },
      ),
    );
  }
}
