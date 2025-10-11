import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthTokenProvider {
  AuthTokenProvider({FirebaseAuth? firebaseAuth, Duration? refreshInterval})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _refreshInterval = refreshInterval ?? const Duration(minutes: 50);

  final FirebaseAuth _firebaseAuth;
  final Duration _refreshInterval;
  DateTime? _lastTokenRefresh;

  Future<String?> getToken({bool forceRefresh = false}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _log('getToken called without an authenticated user');
      return null;
    }

    final now = DateTime.now();
    final shouldRefresh =
        forceRefresh ||
        _lastTokenRefresh == null ||
        now.difference(_lastTokenRefresh!) >= _refreshInterval;

    try {
      final token = await user.getIdToken(shouldRefresh);
      _lastTokenRefresh = now;
      return token;
    } catch (e) {
      _log('Primary token fetch failed (shouldRefresh=$shouldRefresh): $e');
      if (!shouldRefresh) {
        try {
          final refreshed = await user.getIdToken(true);
          _lastTokenRefresh = now;
          return refreshed;
        } catch (refreshError) {
          _log('Forced token refresh failed: $refreshError');
          rethrow;
        }
      }
      rethrow;
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('AuthTokenProvider: $message');
    }
  }
}
