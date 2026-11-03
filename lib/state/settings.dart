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

  /// When this person last looked at a project's announcements.
  DateTime? announcementsSeen(String projectId) {
    final ms = _prefs.getInt('ann_seen_$projectId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setAnnouncementsSeen(String projectId, DateTime t) => _prefs.setInt('ann_seen_$projectId', t.millisecondsSinceEpoch);

  /// The newest app version this person was already told about (so the pop-up shows once per version).
  String get updateShown => _prefs.getString('update_shown') ?? '';
  Future<void> setUpdateShown(String v) => _prefs.setString('update_shown', v);
}
