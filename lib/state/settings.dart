import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choices saved on this device: theme, font and the last project opened.
class Settings {
  Settings._(this._prefs);
  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  ThemeMode get themeMode => switch (_prefs.getString('theme')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  Future<void> setThemeMode(ThemeMode m) => _prefs.setString('theme', m.name);

  /// Font family chosen in Settings; empty means the built-in Barlow.
  String get fontChoice => _prefs.getString('font') ?? '';
  Future<void> setFontChoice(String family) => _prefs.setString('font', family);

  String? get lastProjectId => _prefs.getString('last_project');
  Future<void> setLastProjectId(String id) => _prefs.setString('last_project', id);

  /// Email typed last time on the sign-in screen.
  String get lastEmail => _prefs.getString('last_email') ?? '';
  Future<void> setLastEmail(String email) => _prefs.setString('last_email', email);
}
