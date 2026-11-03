import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models.dart';

const _uuid = Uuid();

/// Private storage bucket; files live under <project id>/<item id>/.
const _bucket = 'files';

/// A message that can be shown to people as is.
class AppException implements Exception {
  AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything the app reads from or writes to the server (Supabase).
/// The permission rules themselves live in the database (supabase/schema.sql).
class Api {
  Api._();

  static Future<Api> connect() async {
    await Supabase.initialize(
      url: serverUrl,
      publishableKey: serverKey,
      // Implicit flow: the emailed link also works when it is pasted into the app.
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    return Api._();
  }

  SupabaseClient get _db => Supabase.instance.client;

  String? get myId => _db.auth.currentUser?.id;
  String? get myEmail => _db.auth.currentUser?.email;

  Stream<AuthState> get authChanges => _db.auth.onAuthStateChange;

  // ------------------------------------------------------------------ errors

  Future<T> guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      throw AppException(_friendlyAuth(e.message));
    } on PostgrestException catch (e) {
      throw AppException(_friendly(e.message));
    } on StorageException catch (e) {
      throw AppException(e.message.contains('row-level security')
          ? 'You do not have permission to add files to this project.'
          : 'Photo upload failed: ${e.message}');
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Could not reach the server. Check the internet connection and try again.');
    }
  }

  String _friendlyAuth(String m) {
    final l = m.toLowerCase();
    if (l.contains('not authorized') || l.contains('email address not authorized')) {
      return "Sign-in emails can't be sent to this address yet. The admin needs to finish the email setup.";
    }
    if (l.contains('rate limit') || l.contains('security purposes')) {
      return 'Too many codes were requested. Wait a few minutes and try again.';
    }
    if (l.contains('expired') || l.contains('invalid')) {
      return 'That code is wrong or has expired. Check the newest email, or send a new code.';
    }
    return m;
  }

  String _friendly(String m) {
    if (m.contains('row-level security')) return 'You do not have permission to do that.';
    if (m.contains('duplicate key') && m.contains('projects_code')) return 'Another project already uses that abbreviation.';
    if (m.contains('duplicate key') && m.contains('project_id_code')) return 'That abbreviation is already used on this project.';
    if (m.contains('duplicate key') && m.contains('profiles_email')) return 'Someone already uses that email.';
    if (m.contains('violates check constraint') && m.contains('code')) {
      return 'Abbreviations use capital letters and numbers only (projects up to 8, trades up to 6, types up to 4).';
    }
    if (m.contains('violates foreign key') && m.contains('project_members')) {
      return 'People are still assigned to this trade. Move them to another trade first.';
    }
    if (m.contains('schema cache') || m.contains('does not exist')) {
      return 'The server database is not set up yet. The admin needs to run the setup script.';
    }
    return m;
  }

  /// Runs an update and fails clearly when the database silently changed nothing.
  Future<List<Map<String, dynamic>>> _mustChange(Future<List<Map<String, dynamic>>> q) async {
    final rows = await q;
    if (rows.isEmpty) throw AppException('You do not have permission to do that.');
    return rows;
  }

  // ------------------------------------------------------------------ sign in

  Future<void> sendCode(String email) => guard(() async {
        await _db.auth.signInWithOtp(
          email: email.trim().toLowerCase(),
          shouldCreateUser: true,
          emailRedirectTo: signInRedirect,
        );
      });

  Future<void> verifyCode(String email, String code) => guard(() async {
        final res = await _db.auth.verifyOTP(
          email: email.trim().toLowerCase(),
          token: code.replaceAll(RegExp(r'\s'), ''),
          type: OtpType.email,
        );
        if (res.session == null && _db.auth.currentSession == null) {
          throw AppException('That code did not work. Send a new one and try again.');
        }
      });

  /// Signs in with the link from the email, pasted into the app.
  Future<void> verifyLink(String pasted) => guard(() async {
        var link = pasted.trim();
        final uri = Uri.tryParse(link);
        if (uri == null) throw AppException('That does not look like the sign-in link.');
        final hash = uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
        if (hash != null && hash.isNotEmpty) {
          final type = uri.queryParameters['type'];
          await _db.auth.verifyOTP(
            tokenHash: hash,
            type: type == 'signup' ? OtpType.signup : OtpType.magiclink,
          );
          return;
        }
        if (uri.fragment.contains('access_token')) {
          await _db.auth.getSessionFromUrl(uri);
          return;
        }
        throw AppException('That does not look like the sign-in link. Copy the whole link from the email.');
      });

  Future<void> signOut() => guard(() => _db.auth.signOut());

  // ------------------------------------------------------------------ people

  Future<Profile?> loadMe() => guard(() async {
        final id = myId;
        if (id == null) return null;
        var row = await _db.from('profiles').select().eq('id', id).maybeSingle();
        if (row == null) {
          // The profile is made by a database trigger; give it a moment.
          await Future<void>.delayed(const Duration(milliseconds: 900));
          row = await _db.from('profiles').select().eq('id', id).maybeSingle();
        }
        return row == null ? null : Profile.fromJson(row);
      });

  Future<void> updateMe({required String name, required String company, required String phone}) => guard(() async {
        await _mustChange(_db
            .from('profiles')
            .update({'name': name.trim(), 'company': company.trim(), 'phone': phone.trim()})
            .eq('id', myId!)
            .select());
      });

  /// Saves this person's theme, colors, font and text size on their account.
  Future<void> savePrefs(Map<String, dynamic> prefs) => guard(() async {
        final id = myId;
        if (id == null) return;
        await _db.from('profiles').update({'prefs': prefs}).eq('id', id);
      });

  /// Everyone the signed-in person may see (the admin sees all accounts).
  Future<List<Profile>> profiles() => guard(() async {
        final rows = await _db.from('profiles').select().order('name');
        return rows.map(Profile.fromJson).toList();
      });

  Future<void> setProfileStatus(String userId, String status) => guard(() async {
        await _mustChange(_db.from('profiles').update({'status': status}).eq('id', userId).select());
      });

  Future<void> setAdmin(String userId, bool admin) => guard(() async {
        await _mustChange(_db.from('profiles').update({'is_admin': admin}).eq('id', userId).select());
      });

  // ------------------------------------------------------------------ projects

  Future<List<Project>> projects() => guard(() async {
        final rows = await _db.from('projects').select().order('name');
        return rows.map(Project.fromJson).toList();
      });

  Future<Project> createProject({required String name, required String code}) => guard(() async {
        final row = await _db.from('projects').insert({'name': name.trim(), 'code': code.trim().toUpperCase()}).select().single();
        return Project.fromJson(row);
      });

  Future<void> updateProject(String id, Map<String, dynamic> values) => guard(() async {
        await _mustChange(_db.from('projects').update(values).eq('id', id).select());
      });

  Future<List<Trade>> trades(String projectId) => guard(() async {
        final rows = await _db.from('project_trades').select().eq('project_id', projectId).order('sort').order('name');
        return rows.map(Trade.fromJson).toList();
      });

  Future<void> saveTrade({String? id, required String projectId, required String name, required String code, required String company, int sort = 0}) =>
      guard(() async {
        final values = {'project_id': projectId, 'name': name.trim(), 'code': code.trim().toUpperCase(), 'company': company.trim(), 'sort': sort};
        if (id == null) {
          await _db.from('project_trades').insert(values);
        } else {
          await _mustChange(_db.from('project_trades').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteTrade(String id) => guard(() async {
        await _mustChange(_db.from('project_trades').delete().eq('id', id).select());
      });

  Future<List<ItemType>> types(String projectId) => guard(() async {
        final rows = await _db.from('item_types').select().eq('project_id', projectId).order('sort').order('name');
        return rows.map(ItemType.fromJson).toList();
      });

  Future<void> saveType({String? id, required String projectId, required String name, required String code, bool active = true, int sort = 0}) =>
      guard(() async {
        final values = {'project_id': projectId, 'name': name.trim(), 'code': code.trim().toUpperCase(), 'active': active, 'sort': sort};
        if (id == null) {
          await _db.from('item_types').insert(values);
        } else {
          await _mustChange(_db.from('item_types').update(values).eq('id', id).select());
        }
      });

  Future<List<Member>> members({String? projectId}) => guard(() async {
        var q = _db.from('project_members').select();
        if (projectId != null) q = q.eq('project_id', projectId);
        final rows = await q;
        return rows.map(Member.fromJson).toList();
      });

  Future<void> setMember({required String projectId, required String userId, required Role role, String? tradeId}) =>
      guard(() async {
        await _db.from('project_members').upsert({
          'project_id': projectId,
          'user_id': userId,
          'role': role.db,
          'trade_id': role.needsTrade ? tradeId : null,
        });
      });

  Future<void> removeMember(String projectId, String userId) => guard(() async {
        await _mustChange(_db.from('project_members').delete().eq('project_id', projectId).eq('user_id', userId).select());
      });

  Future<List<Invite>> invites(String projectId) => guard(() async {
        final rows = await _db.from('invites').select().eq('project_id', projectId).order('created_at', ascending: false);
        return rows.map(Invite.fromJson).toList();
      });

  /// Admin: adds a person (status approved). Trade lead: suggests one (status suggested).
  Future<void> invite({
    required String projectId,
    required String email,
    required String name,
    required String company,
    required Role role,
    String? tradeId,
    bool suggestion = false,
  }) =>
      guard(() async {
        await _db.from('invites').insert({
          'project_id': projectId,
          'email': email.trim().toLowerCase(),
          'name': name.trim(),
          'company': company.trim(),
          'role': role.db,
          'trade_id': role.needsTrade ? tradeId : null,
          'status': suggestion ? 'suggested' : 'approved',
        });
      });

  Future<void> setInviteStatus(String id, String status) => guard(() async {
        await _mustChange(_db.from('invites').update({'status': status}).eq('id', id).select());
      });

  Future<void> deleteInvite(String id) => guard(() async {
        await _mustChange(_db.from('invites').delete().eq('id', id).select());
      });

  // ------------------------------------------------------------------ items

  Future<List<Item>> items(String projectId) => guard(() async {
        final rows = await _db.from('items').select().eq('project_id', projectId).order('created_at', ascending: false);
        return rows.map(Item.fromJson).toList();
      });

  /// Creates an item, uploading its (already marked-up) photos first.
  Future<Item> createItem(Map<String, dynamic> values, {List<Uint8List> photos = const []}) => guard(() async {
        final id = _uuid.v4();
        final refs = <String>[];
        for (final b in photos) {
          refs.add(await _upload(values['project_id'] as String, id, b));
        }
        final row = await _db.from('items').insert({...values, 'id': id, 'photos': refs}).select().single();
        return Item.fromJson(row);
      });

  Future<Item> updateItem(String id, Map<String, dynamic> values) => guard(() async {
        final rows = await _mustChange(_db.from('items').update(values).eq('id', id).select());
        return Item.fromJson(rows.first);
      });

  Future<void> deleteItem(String id) => guard(() async {
        await _mustChange(_db.from('items').delete().eq('id', id).select());
      });

  Future<(List<Comment>, List<ItemEvent>)> thread(String itemId) => guard(() async {
        final c = await _db.from('item_comments').select().eq('item_id', itemId).order('created_at');
        final e = await _db.from('item_events').select().eq('item_id', itemId).order('created_at').order('id');
        return (c.map(Comment.fromJson).toList(), e.map(ItemEvent.fromJson).toList());
      });

  Future<void> addComment(Item item, String body, {List<Uint8List> photos = const []}) => guard(() async {
        final refs = <String>[];
        for (final b in photos) {
          refs.add(await _upload(item.projectId, item.id, b));
        }
        await _db.from('item_comments').insert({'item_id': item.id, 'author_id': myId, 'body': body.trim(), 'attachments': refs});
      });

  Future<void> editComment(String id, String body) => guard(() async {
        await _mustChange(_db.from('item_comments').update({'body': body.trim()}).eq('id', id).select());
      });

  Future<void> deleteComment(String id) => guard(() async {
        await _mustChange(_db.from('item_comments').delete().eq('id', id).select());
      });

  // ------------------------------------------------------------------ meetings

  Future<List<Meeting>> meetings(String projectId) => guard(() async {
        final rows = await _db.from('meetings').select().eq('project_id', projectId).order('starts_at', ascending: false);
        return rows.map(Meeting.fromJson).toList();
      });

  Future<Meeting> saveMeeting({String? id, required Map<String, dynamic> values}) => guard(() async {
        final rows = id == null
            ? await _db.from('meetings').insert(values).select()
            : await _mustChange(_db.from('meetings').update(values).eq('id', id).select());
        return Meeting.fromJson(rows.first);
      });

  Future<void> deleteMeeting(String id) => guard(() async {
        await _mustChange(_db.from('meetings').delete().eq('id', id).select());
      });

  // ------------------------------------------------------------------ schedule

  Future<List<ScheduleTask>> schedule(String projectId) => guard(() async {
        final rows = await _db.from('schedule_tasks').select().eq('project_id', projectId).order('start_date').order('sort');
        return rows.map(ScheduleTask.fromJson).toList();
      });

  Future<void> saveTask({String? id, required Map<String, dynamic> values}) => guard(() async {
        if (id == null) {
          await _db.from('schedule_tasks').insert(values);
        } else {
          await _mustChange(_db.from('schedule_tasks').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteTask(String id) => guard(() async {
        await _mustChange(_db.from('schedule_tasks').delete().eq('id', id).select());
      });

  // ------------------------------------------------------------------ BEP

  Future<List<BepSection>> bepSections(String projectId) => guard(() async {
        final rows = await _db.from('bep_sections').select().eq('project_id', projectId).order('sort').order('created_at');
        return rows.map(BepSection.fromJson).toList();
      });

  Future<void> saveBepSection({String? id, required Map<String, dynamic> values}) => guard(() async {
        if (id == null) {
          await _db.from('bep_sections').insert(values);
        } else {
          await _mustChange(_db.from('bep_sections').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteBepSection(String id) => guard(() async {
        await _mustChange(_db.from('bep_sections').delete().eq('id', id).select());
      });

  Future<List<BepFile>> bepFiles(String projectId) => guard(() async {
        final rows = await _db.from('bep_files').select().eq('project_id', projectId).order('created_at', ascending: false);
        return rows.map(BepFile.fromJson).toList();
      });

  Future<void> saveBepFile({String? id, required Map<String, dynamic> values}) => guard(() async {
        if (id == null) {
          await _db.from('bep_files').insert(values);
        } else {
          await _mustChange(_db.from('bep_files').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteBepFile(BepFile f) => guard(() async {
        await _mustChange(_db.from('bep_files').delete().eq('id', f.id).select());
        await _db.storage.from(_bucket).remove([f.path]);
      });

  // ------------------------------------------------------------------ clash reports

  Future<List<ClashReport>> clashReports(String projectId) => guard(() async {
        final rows = await _db.from('clash_reports').select().eq('project_id', projectId).order('report_date', ascending: false).order('created_at', ascending: false);
        return rows.map(ClashReport.fromJson).toList();
      });

  Future<void> saveClashReport({String? id, required Map<String, dynamic> values}) => guard(() async {
        if (id == null) {
          await _db.from('clash_reports').insert(values);
        } else {
          await _mustChange(_db.from('clash_reports').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteClashReport(ClashReport r) => guard(() async {
        await _mustChange(_db.from('clash_reports').delete().eq('id', r.id).select());
        await _db.storage.from(_bucket).remove([r.path]);
      });

  // ------------------------------------------------------------------ announcements

  Future<List<Announcement>> announcements(String projectId) => guard(() async {
        final rows = await _db.from('announcements').select().eq('project_id', projectId).order('created_at', ascending: false);
        return rows.map(Announcement.fromJson).toList();
      });

  Future<void> saveAnnouncement({String? id, required Map<String, dynamic> values}) => guard(() async {
        if (id == null) {
          await _db.from('announcements').insert(values);
        } else {
          await _mustChange(_db.from('announcements').update(values).eq('id', id).select());
        }
      });

  Future<void> deleteAnnouncement(String id) => guard(() async {
        await _mustChange(_db.from('announcements').delete().eq('id', id).select());
      });

  // ------------------------------------------------------------------ files

  /// Largest file the server takes (Supabase free plan: 50 MB per file).
  static const maxFileBytes = 50 * 1024 * 1024;

  /// Uploads any file under <project>/<folder>/ and returns its storage path.
  Future<String> uploadFile(String projectId, String folder, Uint8List bytes, String fileName) => guard(() async {
        if (bytes.length > maxFileBytes) {
          throw AppException('That file is ${fileSizeText(bytes.length)}. Files can be up to ${fileSizeText(maxFileBytes)}.');
        }
        final clean = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
        final path = '$projectId/$folder/${_uuid.v4().substring(0, 8)}-$clean';
        await _db.storage.from(_bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mimeFor(fileName)),
            );
        return path;
      });

  final Map<String, Uint8List> _fileCache = {};

  /// Downloads a stored file (kept in memory for this session).
  Future<Uint8List> fileBytes(String path) => guard(() async {
        final cached = _fileCache[path];
        if (cached != null) return cached;
        final b = await _db.storage.from(_bucket).download(path);
        _fileCache[path] = b;
        return b;
      });

  static String mimeFor(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'pdf' => 'application/pdf',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'xls' => 'application/vnd.ms-excel',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  // ------------------------------------------------------------------ photos

  /// Uploads one JPEG photo and returns its reference ("sb:<path>").
  Future<String> uploadPhoto(String projectId, String itemId, Uint8List bytes) =>
      guard(() => _upload(projectId, itemId, bytes));

  Future<String> _upload(String projectId, String itemId, Uint8List bytes) async {
    final path = '$projectId/$itemId/${_uuid.v4()}.jpg';
    await _db.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return 'sb:$path';
  }

  static String _path(String ref) => ref.startsWith('sb:') ? ref.substring(3) : ref;

  final Map<String, (String, DateTime)> _signedUrls = {};
  final Map<String, Uint8List> _bytesCache = {};

  Future<String> _signedUrl(String ref) async {
    final path = _path(ref);
    final cached = _signedUrls[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final url = await guard(() => _db.storage.from(_bucket).createSignedUrl(path, 60 * 60 * 12));
    _signedUrls[path] = (url, DateTime.now().add(const Duration(hours: 11)));
    return url;
  }

  /// A picture that can be shown with Image(image: ...).
  Future<ImageProvider> image(String ref) async {
    final b = _bytesCache[_path(ref)];
    if (b != null) return MemoryImage(b);
    return NetworkImage(await _signedUrl(ref));
  }

  /// The photo's bytes (used to mark up an existing photo again).
  Future<Uint8List> photoBytes(String ref) => guard(() async {
        final path = _path(ref);
        final cached = _bytesCache[path];
        if (cached != null) return cached;
        final b = await _db.storage.from(_bucket).download(path);
        _bytesCache[path] = b;
        return b;
      });

  // ------------------------------------------------------------------ notifications

  Future<List<AppNotification>> notifications() => guard(() async {
        final rows = await _db.from('notifications').select().order('created_at', ascending: false).limit(150);
        return rows.map(AppNotification.fromJson).toList();
      });

  Future<void> markRead(List<int> ids) => guard(() async {
        if (ids.isEmpty) return;
        await _db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids);
      });

  Future<void> deleteNotifications(List<int> ids) => guard(() async {
        if (ids.isEmpty) return;
        await _db.from('notifications').delete().inFilter('id', ids);
      });

  Future<void> clearNotifications() => guard(() async {
        await _db.from('notifications').delete().eq('user_id', myId!);
      });

  // ------------------------------------------------------------------ live updates

  RealtimeChannel? _channel;

  /// Calls [onChange] with the table name whenever something the person can see changes.
  void listen(void Function(String table) onChange) {
    _channel?.unsubscribe();
    _channel = _db
        .channel('coordination-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (payload) => onChange(payload.table),
        )
        .subscribe();
  }

  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
  }
}
