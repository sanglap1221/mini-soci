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

    if (forceRefresh) {
      _log('Force refreshing token...');
    }

    try {
      // CRITICAL FIX: Pass shouldRefresh (which includes forceRefresh) to getIdToken
      final token = await user.getIdToken(shouldRefresh);
      if (token != null) {
        _lastTokenRefresh = now;
        final tokenPreview = token.length > 20 
            ? '${token.substring(0, 20)}...' 
            : token;
        _log('Token obtained: $tokenPreview (forceRefresh=$forceRefresh)');
      }
      return token;
    } catch (e) {
      _log('Primary token fetch failed (shouldRefresh=$shouldRefresh): $e');
      // Fallback: force refresh if we haven't already
      if (!shouldRefresh) {
        try {
          _log('Attempting fallback token refresh...');
          final refreshed = await user.getIdToken(true);
          _lastTokenRefresh = now;
          return refreshed;
        } catch (refreshError) {
          _log('Fallback token refresh failed: $refreshError');
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
