import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _prefKey = 'app.theme.mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_prefKey);
      if (stored != null) {
        mode.value = _decode(stored);
      }
    } catch (_) {
      // ignore read failures; keep default system mode
    }
  }

  Future<void> setMode(ThemeMode next) async {
    mode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, _encode(next));
    } catch (_) {
      // ignore write failures
    }
  }

  int _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  ThemeMode _decode(int v) {
    switch (v) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
        return ThemeMode.system;
    }
    // Fallback for unexpected stored values
    return ThemeMode.system;
  }
}
