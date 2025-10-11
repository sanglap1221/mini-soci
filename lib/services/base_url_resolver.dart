import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Handles discovery and persistence of the API base URL across devices and networks.
class BaseUrlResolver {
  BaseUrlResolver({
    DeviceInfoPlugin? deviceInfo,
    Future<SharedPreferences> Function()? prefsLoader,
    void Function(String message)? logger,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _log =
           logger ??
           ((String message) {
             if (kDebugMode) {
               debugPrint('BaseUrlResolver: $message');
             }
           });

  // Dart define overrides.
  static const String _dartDefineGlobalBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _dartDefineDeviceBaseUrl = String.fromEnvironment(
    'API_DEVICE_BASE_URL',
    defaultValue: '',
  );
  static const String _dartDefineEmulatorBaseUrl = String.fromEnvironment(
    'API_EMULATOR_BASE_URL',
    defaultValue: '',
  );
  static const String _dartDefineWebBaseUrl = String.fromEnvironment(
    'API_WEB_BASE_URL',
    defaultValue: '',
  );

  // Environment defaults.
  static const String _androidEmulatorDefault = 'http://10.0.2.2:3000/api';
  static const String _androidPhysicalDefault = 'http://localhost:3000/api';
  static const String _iosSimulatorDefault = 'http://localhost:3000/api';
  static const String _desktopDefault = 'http://localhost:3000/api';
  static const Duration _probeTimeout = Duration(seconds: 2);
  static const String _prefsKeyLastKnownBaseUrl = 'api_service.last_base_url';

  final DeviceInfoPlugin _deviceInfo;
  final Future<SharedPreferences> Function() _prefsLoader;
  final void Function(String message) _log;

  AndroidDeviceInfo? _cachedAndroidInfo;
  IosDeviceInfo? _cachedIosInfo;
  SharedPreferences? _prefs;
  String? _baseUrl;
  String? _lastKnownBaseUrl;
  Future<String>? _baseUrlFuture;

  Future<void> initialize({String? overrideBaseUrl}) async {
    if (overrideBaseUrl != null && overrideBaseUrl.isNotEmpty) {
      final normalized = _normalizeBaseUrl(overrideBaseUrl);
      if (normalized.isEmpty) {
        throw ArgumentError('overrideBaseUrl cannot be empty');
      }
      _baseUrl = normalized;
      _baseUrlFuture = Future.value(_baseUrl);
      await _persistWorkingBaseUrl(normalized);
      return;
    }

    if (_baseUrl != null) return;

    _baseUrlFuture ??= _resolveBaseUrl();
    final resolved = await _baseUrlFuture!;
    _baseUrl ??= resolved;
  }

  void overrideBaseUrl(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      throw ArgumentError('baseUrl cannot be empty');
    }
    _baseUrl = normalized;
    _baseUrlFuture = Future.value(_baseUrl);
    unawaited(_persistWorkingBaseUrl(normalized));
  }

  Future<String> prepareBaseUrl() async {
    if (_baseUrl != null && _baseUrl!.isNotEmpty) {
      return _baseUrl!;
    }

    try {
      await initialize();
      final value = _baseUrl;
      if (value == null || value.isEmpty) {
        throw StateError('Base URL not initialized');
      }
      return value;
    } catch (e) {
      _log('Failed to prepare base URL: $e');
      rethrow;
    }
  }

  String get baseUrl => _baseUrl ?? _defaultBaseUrlSync;

  String get serverBaseUrl {
    final uri = Uri.parse(_baseUrl ?? _defaultBaseUrlSync);
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

  Future<String> _resolveBaseUrl() async {
    final candidates = await _collectCandidateBaseUrls();
    final resolved = await _probeBaseUrls(candidates);
    if (resolved != null) {
      return resolved;
    }

    final fallback = _normalizeBaseUrl(_desktopDefault);
    _log('Unable to reach any candidate base URL. Falling back to $fallback');
    return fallback;
  }

  Future<List<String>> _collectCandidateBaseUrls() async {
    final candidates = <String>[];

    void addCandidate(String? value) {
      if (value == null || value.isEmpty) return;
      final normalized = _normalizeBaseUrl(value);
      if (normalized.isEmpty) return;
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    if (_dartDefineGlobalBaseUrl.isNotEmpty) {
      addCandidate(_dartDefineGlobalBaseUrl);
      return candidates;
    }

    final stored = await _loadPersistedBaseUrl();
    addCandidate(stored);
    final subnetCandidates = await _generateSubnetCandidates(
      referenceBase: stored,
    );
    for (final candidate in subnetCandidates) {
      addCandidate(candidate);
    }

    if (kIsWeb) {
      addCandidate(_dartDefineWebBaseUrl);
      addCandidate(_desktopDefault);
      return candidates;
    }

    if (Platform.isAndroid) {
      final androidInfo = await _safeAndroidInfo();
      final isPhysicalDevice = androidInfo?.isPhysicalDevice ?? false;

      if (isPhysicalDevice) {
        addCandidate(_dartDefineDeviceBaseUrl);
        addCandidate(_androidPhysicalDefault);
        addCandidate(_androidEmulatorDefault);
      } else {
        addCandidate(_dartDefineEmulatorBaseUrl);
        addCandidate(_androidEmulatorDefault);
        addCandidate(_androidPhysicalDefault);
      }

      if (isPhysicalDevice) {
        final physicalSubnetCandidates = await _generateSubnetCandidates(
          referenceBase: stored ?? _androidPhysicalDefault,
        );
        for (final candidate in physicalSubnetCandidates) {
          addCandidate(candidate);
        }
      }
      return candidates;
    }

    if (Platform.isIOS) {
      final iosInfo = await _safeIosInfo();
      final isPhysicalDevice = iosInfo?.isPhysicalDevice ?? false;
      if (isPhysicalDevice) {
        addCandidate(_dartDefineDeviceBaseUrl);
      }
      addCandidate(_iosSimulatorDefault);
      final iosSubnetCandidates = await _generateSubnetCandidates(
        referenceBase: stored ?? _iosSimulatorDefault,
      );
      for (final candidate in iosSubnetCandidates) {
        addCandidate(candidate);
      }
      return candidates;
    }

    addCandidate(_desktopDefault);
    return candidates;
  }

  Future<List<String>> _generateSubnetCandidates({
    String? referenceBase,
  }) async {
    if (kIsWeb) {
      return const [];
    }

    final prefixes = await _localNetworkPrefixes();
    if (prefixes.isEmpty) {
      return const [];
    }

    final normalizedReference =
        referenceBase != null && referenceBase.isNotEmpty
        ? _normalizeBaseUrl(referenceBase)
        : _normalizeBaseUrl(
            _lastKnownBaseUrl ??
                (_dartDefineDeviceBaseUrl.isNotEmpty
                    ? _dartDefineDeviceBaseUrl
                    : _androidPhysicalDefault),
          );

    Uri referenceUri;
    try {
      referenceUri = Uri.parse(
        normalizedReference.isNotEmpty
            ? normalizedReference
            : _androidPhysicalDefault,
      );
    } catch (_) {
      referenceUri = Uri.parse(_androidPhysicalDefault);
    }

    final scheme = referenceUri.scheme.isNotEmpty
        ? referenceUri.scheme
        : 'http';
    final port = referenceUri.hasPort ? referenceUri.port : 3000;
    final path = referenceUri.path.isNotEmpty ? referenceUri.path : '/api';

    final suffixes = <String>{
      '2',
      '3',
      '4',
      '5',
      '10',
      '15',
      '20',
      '25',
      '30',
      '40',
      '50',
      '60',
      '80',
      '90',
      '100',
      '101',
      '120',
      '150',
      '180',
      '200',
    };

    final hostParts = referenceUri.host.split('.');
    if (hostParts.length == 4) {
      final last = hostParts.last;
      if (int.tryParse(last) != null) {
        suffixes.add(last);
      }
    }

    final results = <String>[];
    for (final prefix in prefixes) {
      for (final suffix in suffixes) {
        final host = '$prefix.$suffix';
        final candidate = Uri(
          scheme: scheme,
          host: host,
          port: port == 0 ? null : port,
          path: path,
        ).toString();
        results.add(candidate);
      }
    }

    return results;
  }

  Future<Set<String>> _localNetworkPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4) continue;
          if (address.isLoopback) continue;

          final parts = address.address.split('.');
          if (parts.length != 4) continue;

          final first = int.tryParse(parts[0]);
          final second = int.tryParse(parts[1]);
          if (first == null || second == null) continue;

          final isPrivate =
              first == 10 ||
              (first == 172 && second >= 16 && second <= 31) ||
              (first == 192 && second == 168);

          if (!isPrivate) continue;

          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    } catch (e) {
      _log('Failed to list network interfaces: $e');
    }

    return prefixes;
  }

  Future<String?> _probeBaseUrls(List<String> candidates) async {
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final isReachable = await _isReachable(candidate);
      if (isReachable) {
        await _persistWorkingBaseUrl(candidate);
        return candidate;
      }
    }
    return null;
  }

  Future<bool> _isReachable(String baseUrl) async {
    final uri = Uri.parse(baseUrl);
    try {
      final response = await http.head(uri).timeout(_probeTimeout);
      _log('Probe HEAD $baseUrl => ${response.statusCode}');
      return true;
    } catch (headError) {
      _log('HEAD probe failed for $baseUrl: $headError. Trying GET probe.');
      try {
        final response = await http.get(uri).timeout(_probeTimeout);
        _log('Probe GET $baseUrl => ${response.statusCode}');
        return true;
      } catch (getError) {
        _log('GET probe failed for $baseUrl: $getError');
        return false;
      }
    }
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await _prefsLoader();
  }

  Future<void> _persistWorkingBaseUrl(String value) async {
    final normalized = _normalizeBaseUrl(value);
    if (normalized.isEmpty) return;
    _lastKnownBaseUrl = normalized;
    try {
      final prefs = await _ensurePrefs();
      await prefs.setString(_prefsKeyLastKnownBaseUrl, normalized);
    } catch (e) {
      _log('Failed to persist base URL $normalized: $e');
    }
  }

  Future<String?> _loadPersistedBaseUrl() async {
    if (_lastKnownBaseUrl != null && _lastKnownBaseUrl!.isNotEmpty) {
      return _lastKnownBaseUrl;
    }
    try {
      final prefs = await _ensurePrefs();
      final stored = prefs.getString(_prefsKeyLastKnownBaseUrl);
      if (stored != null && stored.isNotEmpty) {
        _lastKnownBaseUrl = _normalizeBaseUrl(stored);
        return _lastKnownBaseUrl;
      }
    } catch (e) {
      _log('Failed to load persisted base URL: $e');
    }
    return null;
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
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

  Future<AndroidDeviceInfo?> _safeAndroidInfo() async {
    try {
      return _cachedAndroidInfo ??= await _deviceInfo.androidInfo;
    } catch (e) {
      _log('Failed to read Android device info: $e');
      return null;
    }
  }

  Future<IosDeviceInfo?> _safeIosInfo() async {
    try {
      return _cachedIosInfo ??= await _deviceInfo.iosInfo;
    } catch (e) {
      _log('Failed to read iOS device info: $e');
      return null;
    }
  }

  String get _defaultBaseUrlSync {
    if (_dartDefineGlobalBaseUrl.isNotEmpty) {
      return _normalizeBaseUrl(_dartDefineGlobalBaseUrl);
    }

    if (kIsWeb) {
      if (_dartDefineWebBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineWebBaseUrl);
      }
      return _normalizeBaseUrl(_desktopDefault);
    }

    if (Platform.isAndroid) {
      if (_dartDefineDeviceBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineDeviceBaseUrl);
      }
      if (_dartDefineEmulatorBaseUrl.isNotEmpty) {
        return _normalizeBaseUrl(_dartDefineEmulatorBaseUrl);
      }
      if (_lastKnownBaseUrl != null && _lastKnownBaseUrl!.isNotEmpty) {
        return _lastKnownBaseUrl!;
      }
      final androidInfo = _cachedAndroidInfo;
      if (androidInfo != null && androidInfo.isPhysicalDevice) {
        return _normalizeBaseUrl(_androidPhysicalDefault);
      }
      return _normalizeBaseUrl(_androidEmulatorDefault);
    }

    if (Platform.isIOS) {
      if (_lastKnownBaseUrl != null && _lastKnownBaseUrl!.isNotEmpty) {
        return _lastKnownBaseUrl!;
      }
      return _normalizeBaseUrl(_iosSimulatorDefault);
    }

    return _normalizeBaseUrl(_desktopDefault);
  }
}
