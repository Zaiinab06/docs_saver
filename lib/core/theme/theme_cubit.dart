import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  static const String prefsKey = 'theme_mode';
  final SharedPreferences? _prefs;

  ThemeCubit([this._prefs]) : super(_resolveInitialTheme(_prefs));

  static ThemeMode _resolveInitialTheme(SharedPreferences? prefs) {
    if (prefs == null) return ThemeMode.system;
    final saved = prefs.getString(prefsKey);
    if (saved == 'light') return ThemeMode.light;
    if (saved == 'dark') return ThemeMode.dark;
    if (saved == 'system') return ThemeMode.system;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(mode);
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      String value = 'system';
      if (mode == ThemeMode.light) value = 'light';
      if (mode == ThemeMode.dark) value = 'dark';
      await prefs.setString(prefsKey, value);
    } catch (_) {}
  }
}
