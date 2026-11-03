import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Things kept on this device. The look (theme, font, text size) is saved on the
/// person's account too; this copy is used on the sign-in screen and while starting up.
class Settings {
  Settings._(this._prefs);
  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  Appearance get appearance {
    final raw = _prefs.getString('appearance');
    if (raw == null) return const Appearance();
    try {
      return Appearance.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Appearance();
    }
  }

  Future<void> setAppearance(Appearance a) => _prefs.setString('appearance', jsonEncode(a.toJson()));

  String? get lastProjectId => _prefs.getString('last_project');
  Future<void> setLastProjectId(String id) => _prefs.setString('last_project', id);

  /// Email typed last time on the sign-in screen.
  String get lastEmail => _prefs.getString('last_email') ?? '';
  Future<void> setLastEmail(String email) => _prefs.setString('last_email', email);
}
