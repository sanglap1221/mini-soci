import 'package:flutter/foundation.dart';

/// Simplified base URL resolver now that the app always targets a single
/// production backend. The class keeps the same external API so existing
/// callers (e.g. `ApiService`) continue to work without changes.
class BaseUrlResolver {
  BaseUrlResolver({void Function(String message)? logger})
    : _log = logger ?? _defaultLogger;

  static const String _defaultBaseUrl =
      'https://mini-soco-backend-1-d2i9.onrender.com/api';

  final void Function(String message) _log;
  String? _baseUrl;

  static void _defaultLogger(String message) {
    if (kDebugMode) {
      debugPrint('BaseUrlResolver: $message');
    }
  }

  Future<void> initialize({String? overrideBaseUrl}) async {
    final candidate = overrideBaseUrl?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      _baseUrl = _normalizeBaseUrl(candidate);
      _log('Using override base URL $_baseUrl');
      return;
    }

    _baseUrl ??= _normalizeBaseUrl(_defaultBaseUrl);
  }

  void overrideBaseUrl(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      throw ArgumentError('baseUrl cannot be empty');
    }
    _baseUrl = normalized;
    _log('Base URL overridden to $normalized');
  }

  Future<String> prepareBaseUrl() async {
    if (_baseUrl == null || _baseUrl!.isEmpty) {
      await initialize();
    }
    final value = _baseUrl;
    if (value == null || value.isEmpty) {
      throw StateError('Base URL not initialized');
    }
    return value;
  }

  String get baseUrl => _baseUrl ?? _normalizeBaseUrl(_defaultBaseUrl);

  String get serverBaseUrl {
    final uri = Uri.parse(baseUrl);
    final portSegment = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portSegment';
  }

  String getFullImageUrl(String relativePath) {
    if (relativePath.startsWith('http')) {
      return relativePath;
    }

    final base = serverBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = relativePath.replaceAll(RegExp(r'^/+'), '');
    return '$base/$cleanPath';
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }

    final uri = Uri.parse(trimmed);
    final normalizedPath = uri.path.isEmpty
        ? ''
        : uri.path.replaceAll(RegExp(r'/+$'), '');

    var sanitized = uri.replace(path: normalizedPath).toString();
    if (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    return sanitized;
  }
}
