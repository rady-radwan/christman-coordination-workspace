import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../data/api.dart';
import '../models.dart';
import '../theme.dart';
import '../config.dart';
import '../util/dates.dart';
import '../util/update_check.dart';
import 'settings.dart';
import 'view_prefs.dart';

export 'view_prefs.dart';

/// The parts of the app reached from the sidebar (Windows) or the bottom tabs (phone).
/// [more] is the phone's "More" menu.
enum Section { ballInCourt, allItems, meetings, schedule, bep, clashReports, announcements, notifications, team, setup, settings, more }

/// How the All Items list is grouped.
enum ListMode { list, byDate, byArea }

enum DueFilter { any, overdue, thisWeek, noDate }

enum SortBy { due, priority, newest, number }

extension SortByLabel on SortBy {
  String get label => switch (this) {
        SortBy.due => 'Due date',
        SortBy.priority => 'Priority',
        SortBy.newest => 'Newest',
        SortBy.number => 'Number',
      };
}

extension DueFilterLabel on DueFilter {
  String get label => switch (this) {
        DueFilter.any => 'Any due date',
        DueFilter.overdue => 'Overdue',
        DueFilter.thisWeek => 'Due this week',
        DueFilter.noDate => 'No due date',
      };
}

class AppState extends ChangeNotifier {
  AppState(this.api, this.settings)
      : appearance = settings.appearance,
        view = settings.view;

  final Api api;
  final Settings settings;

  // ------------------------------------------------------------------ session
  bool booting = true;
  String? bootError;
  Profile? me;
  StreamSubscription<dynamic>? _authSub;

  // ------------------------------------------------------------------ data
  List<Project> projects = [];
  Project? project;
  List<Member> myMemberships = [];
  List<Member> members = [];
  Map<String, Profile> people = {};
  List<Trade> trades = [];
  List<ItemType> types = [];
  List<Item> items = [];
  List<AppNotification> notifications = [];
  List<Invite> invites = [];
  List<Meeting> meetings = [];
  List<ScheduleTask> schedule = [];
  List<BepSection> bepSections = [];
  List<BepFile> bepFiles = [];
  List<ClashReport> clashReports = [];
  List<Announcement> announcements = [];
  String? selectedReportId;
  bool loadingProject = false;
  String? selectedMeetingId;

  /// Goes up whenever discussion or history changes, so an open item reloads its thread.
  int threadVersion = 0;

  // ------------------------------------------------------------------ view
  Section section = Section.allItems;
  String? selectedItemId;
  ListMode listMode = ListMode.list;
  String search = '';
  String? filterTradeId;
  String? filterTypeId;
  String filterStatus = 'active'; // active, all, or a status db name
  String? filterLevel;
  Priority? filterPriority;
  DueFilter filterDue = DueFilter.any;
  SortBy sortBy = SortBy.due;

  /// This person's theme, colors, font and text size.
  Appearance appearance;

  // ------------------------------------------------------------------ start-up

  Future<void> init() async {
    _authSub = api.authChanges.listen((s) {
      if (s.event == AuthChangeEvent.signedIn && me == null) {
        unawaited(_afterSignIn());
      } else if (s.event == AuthChangeEvent.signedOut) {
        _clear();
      }
    }, onError: (_) {});
    try {
      if (api.myId != null) await _afterSignIn();
    } catch (e) {
      bootError = e.toString();
    }
    booting = false;
    notifyListeners();
    unawaited(checkForUpdate());
    _updateTimer = Timer.periodic(const Duration(hours: 2), (_) => unawaited(checkForUpdate()));
  }

  // ------------------------------------------------------------------ new versions

  /// A newer version than this one, when published.
  AppRelease? update;

  /// "Later" was pressed on the banner (this session only).
  bool updateHidden = false;
  DateTime? updateCheckedAt;
  Timer? _updateTimer;

  /// Looks for a newer version. Returns true when one is available.
  Future<bool> checkForUpdate() async {
    final r = await fetchLatestRelease();
    updateCheckedAt = DateTime.now();
    if (r != null && compareVersions(r.version, appVersion) > 0) {
      final isNew = update?.version != r.version;
      update = r;
      if (isNew) updateHidden = false;
    } else if (r != null) {
      update = null;
    }
    notifyListeners();
    return update != null;
  }

  void hideUpdate() {
    updateHidden = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _debounce?.cancel();
    _saveLook?.cancel();
    _updateTimer?.cancel();
    api.stopListening();
    super.dispose();
  }

  bool _signingIn = false;

  Future<void> _afterSignIn() async {
    if (_signingIn) return;
    _signingIn = true;
    try {
      me = await api.loadMe();
      if (me != null) _applyAccountLook(me!);
      if (me == null) {
        bootError = 'Signed in, but your profile was not found. Ask the admin to check the server setup.';
      } else if (me!.isApproved) {
        await loadProjects();
        api.listen(_onChange);
      }
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  void _clear() {
    api.stopListening();
    me = null;
    projects = [];
    project = null;
    myMemberships = [];
    members = [];
    people = {};
    trades = [];
    types = [];
    items = [];
    notifications = [];
    invites = [];
    meetings = [];
    schedule = [];
    bepSections = [];
    bepFiles = [];
    clashReports = [];
    announcements = [];
    selectedReportId = null;
    selectedItemId = null;
    selectedMeetingId = null;
    section = Section.allItems;
    notifyListeners();
  }

  Future<void> sendCode(String email) async {
    await api.sendCode(email);
    await settings.setLastEmail(email.trim().toLowerCase());
  }

  Future<void> verifyCode(String email, String code) async {
    await api.verifyCode(email, code);
    await _afterSignIn();
  }

  Future<void> verifyLink(String link) async {
    await api.verifyLink(link);
    await _afterSignIn();
  }

  Future<void> signOut() async {
    try {
      await api.signOut();
    } finally {
      _clear();
    }
  }

  /// "Check again" on the waiting-for-approval screen.
  Future<void> refreshMe() async {
    me = await api.loadMe();
    if (me != null && me!.isApproved) {
      await loadProjects();
      api.listen(_onChange);
    }
    notifyListeners();
  }

  Future<void> updateMyDetails({required String name, required String company, required String phone}) async {
    await api.updateMe(name: name, company: company, phone: phone);
    me = await api.loadMe();
    notifyListeners();
  }

  // ------------------------------------------------------------------ projects

  Future<void> loadProjects() async {
    projects = await api.projects();
    final all = await api.members();
    myMemberships = all.where((m) => m.userId == me?.id).toList();
    if (projects.isEmpty) {
      project = null;
      notifyListeners();
      return;
    }
    final keep = project == null ? null : projects.where((p) => p.id == project!.id).firstOrNull;
    final last = projects.where((p) => p.id == settings.lastProjectId).firstOrNull;
    await selectProject(keep ?? last ?? projects.firstWhere((p) => !p.archived, orElse: () => projects.first));
  }

  Future<void> selectProject(Project p) async {
    final changed = project?.id != p.id;
    project = p;
    if (changed) {
      selectedItemId = null;
      selectedMeetingId = null;
      selectedReportId = null;
      _resetFilters();
    }
    await settings.setLastProjectId(p.id);
    loadingProject = true;
    notifyListeners();
    try {
      await loadProjectData();
    } finally {
      loadingProject = false;
      notifyListeners();
    }
  }

  void _resetFilters() {
    search = '';
    filterTradeId = null;
    filterTypeId = null;
    filterStatus = 'active';
    filterLevel = null;
    filterPriority = null;
    filterDue = DueFilter.any;
  }

  Future<void> loadProjectData() async {
    final p = project;
    if (p == null) return;
    final results = await Future.wait<Object>([
      api.trades(p.id),
      api.types(p.id),
      api.members(projectId: p.id),
      api.profiles(),
      api.items(p.id),
      api.notifications(),
      api.meetings(p.id),
      api.schedule(p.id),
      api.bepSections(p.id),
      api.bepFiles(p.id),
      api.clashReports(p.id),
      api.announcements(p.id),
    ]);
    trades = results[0] as List<Trade>;
    types = results[1] as List<ItemType>;
    members = results[2] as List<Member>;
    people = {for (final x in results[3] as List<Profile>) x.id: x};
    items = results[4] as List<Item>;
    notifications = results[5] as List<AppNotification>;
    meetings = results[6] as List<Meeting>;
    schedule = results[7] as List<ScheduleTask>;
    bepSections = results[8] as List<BepSection>;
    bepFiles = results[9] as List<BepFile>;
    clashReports = results[10] as List<ClashReport>;
    announcements = results[11] as List<Announcement>;
    await _loadInvites();
  }

  Future<void> _loadInvites() async {
    final p = project;
    if (p != null && (isAdmin || myRole == Role.tradeLead)) {
      invites = await api.invites(p.id);
    } else {
      invites = [];
    }
  }

  Future<Project> createProject(String name, String code) async {
    final p = await api.createProject(name: name, code: code);
    await loadProjects();
    final created = projects.firstWhere((x) => x.id == p.id, orElse: () => p);
    await selectProject(created);
    return created;
  }

  Future<void> updateProject(Map<String, dynamic> values) async {
    await api.updateProject(project!.id, values);
    projects = await api.projects();
    project = projects.firstWhere((x) => x.id == project!.id, orElse: () => project!);
    notifyListeners();
  }

  Future<void> reloadSetup() async {
    final p = project;
    if (p == null) return;
    trades = await api.trades(p.id);
    types = await api.types(p.id);
    notifyListeners();
  }

  Future<void> reloadTeam() async {
    final p = project;
    if (p == null) return;
    members = await api.members(projectId: p.id);
    people = {for (final x in await api.profiles()) x.id: x};
    await _loadInvites();
    notifyListeners();
  }

  // ------------------------------------------------------------------ live updates

  Timer? _debounce;
  final Set<String> _changed = {};

  void _onChange(String table) {
    _changed.add(table);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _applyChanges);
  }

  Future<void> _applyChanges() async {
    final t = Set<String>.of(_changed);
    _changed.clear();
    final p = project;
    try {
      if (t.contains('items') && p != null) items = await api.items(p.id);
      if (t.contains('item_comments') || t.contains('item_events')) threadVersion++;
      if (t.contains('notifications')) notifications = await api.notifications();
      if (t.contains('project_trades') && p != null) trades = await api.trades(p.id);
      if (t.contains('item_types') && p != null) types = await api.types(p.id);
      if (t.contains('meetings') && p != null) meetings = await api.meetings(p.id);
      if (t.contains('schedule_tasks') && p != null) schedule = await api.schedule(p.id);
      if (t.contains('bep_sections') && p != null) bepSections = await api.bepSections(p.id);
      if (t.contains('bep_files') && p != null) bepFiles = await api.bepFiles(p.id);
      if (t.contains('clash_reports') && p != null) clashReports = await api.clashReports(p.id);
      if (t.contains('announcements') && p != null) {
        announcements = await api.announcements(p.id);
        if (section == Section.announcements) markAnnouncementsSeen();
      }
      if (t.contains('profiles')) {
        people = {for (final x in await api.profiles()) x.id: x};
        final mine = await api.loadMe();
        if (mine != null) me = mine;
      }
      if (t.contains('project_members') || t.contains('projects')) {
        final before = project?.id;
        projects = await api.projects();
        final all = await api.members();
        myMemberships = all.where((m) => m.userId == me?.id).toList();
        if (p != null) members = all.where((m) => m.projectId == p.id).toList();
        if (projects.isEmpty) {
          project = null;
        } else if (before == null || !projects.any((x) => x.id == before)) {
          await selectProject(projects.first);
          return;
        } else {
          project = projects.firstWhere((x) => x.id == before);
        }
      }
      if (t.contains('invites') || t.contains('project_members')) await _loadInvites();
    } catch (_) {
      // A failed refresh is retried on the next change.
    }
    notifyListeners();
  }

  /// Pull everything again (the refresh button).
  Future<void> refresh() async {
    if (project == null) {
      await loadProjects();
    } else {
      await loadProjectData();
      threadVersion++;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ who am I here

  bool get isAdmin => me?.isAdmin ?? false;

  Member? get myMembership => project == null ? null : members.where((m) => m.userId == me?.id).firstOrNull;

  Role get myRole {
    if (isAdmin) return Role.admin;
    return myMembership?.role ?? Role.viewer;
  }

  String? get myTradeId => myMembership?.tradeId;
  Trade? get myTrade => tradeById(myTradeId);

  bool get canCreateItems => myRole.isCoord;
  bool get canComment => myRole != Role.viewer;

  /// Can this person submit a response / mark the model updated on [item]?
  bool canRespond(Item item) =>
      myRole.isTrade &&
      item.status.canBeOverdue &&
      myTradeId != null &&
      (item.tradeIds.contains(myTradeId) || item.bicTradeIds.contains(myTradeId));

  /// Can this person pass the ball on [item]?
  bool canPassBall(Item item) {
    if (!item.status.isActive) return false;
    if (myRole.isCoord) return true;
    return myRole.isTrade && myTradeId != null && item.bicTradeIds.contains(myTradeId);
  }

  // ------------------------------------------------------------------ lookups

  Trade? tradeById(String? id) => id == null ? null : trades.where((t) => t.id == id).firstOrNull;
  ItemType? typeById(String? id) => id == null ? null : types.where((t) => t.id == id).firstOrNull;
  Profile? person(String? id) => id == null ? null : people[id];
  Item? itemById(String? id) => id == null ? null : items.where((i) => i.id == id).firstOrNull;
  Item? get selectedItem => itemById(selectedItemId);

  /// "Mechanical · Hart Mechanical", or "Christman VDC" for the coordinator.
  /// Trades in the order set up for the project.
  List<Trade> tradesIn(Iterable<String> ids) => trades.where((t) => ids.contains(t.id)).toList();

  /// "Mechanical + Plumbing", or "Christman VDC" for the coordinator.
  String bicNames(List<String> ids) {
    final list = tradesIn(ids);
    return list.isEmpty ? 'Christman VDC' : list.map((t) => t.name).join(' + ');
  }

  /// With company names: "Mechanical · Hart Mechanical + Plumbing · Northline".
  String bicLabels(List<String> ids) {
    final list = tradesIn(ids);
    return list.isEmpty ? 'Christman VDC' : list.map((t) => t.label).join(' + ');
  }

  Member? memberOf(String userId) => members.where((m) => m.userId == userId).firstOrNull;

  /// "Hart Mechanical · Trade lead"
  String personLine(String? userId) {
    final p = person(userId);
    if (p == null) return '';
    final m = memberOf(p.id);
    final role = p.isAdmin ? 'Admin' : (m?.role.label ?? '');
    final company = p.company.isNotEmpty ? p.company : (tradeById(m?.tradeId)?.company ?? '');
    return [company, role].where((s) => s.isNotEmpty).join(' · ');
  }

  List<String> get knownLevels {
    final s = <String>{...?project?.levels, ...items.map((i) => i.level).where((l) => l.isNotEmpty)};
    return s.toList()..sort();
  }

  List<Profile> get pendingPeople => people.values.where((p) => p.isPending).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  // ------------------------------------------------------------------ lists

  /// What my trade (or, for coordinators, the Christman VDC team) must act on now.
  List<Item> get ballInCourtItems {
    final r = myRole;
    Iterable<Item> list;
    if (r.isTrade) {
      list = items.where((i) => myTradeId != null && i.bicTradeIds.contains(myTradeId));
    } else if (r.isCoord) {
      list = items.where((i) => i.ballWithCoordinator);
    } else {
      list = const [];
    }
    return _sorted(list.where((i) => i.status.isActive && i.status != ItemStatus.onHold).toList());
  }

  int get filterCount =>
      (filterTradeId != null ? 1 : 0) +
      (filterTypeId != null ? 1 : 0) +
      (filterStatus != 'active' ? 1 : 0) +
      (filterLevel != null ? 1 : 0) +
      (filterPriority != null ? 1 : 0) +
      (filterDue != DueFilter.any ? 1 : 0);

  /// All items after filters and search.
  List<Item> get filteredItems {
    final q = search.trim().toLowerCase();
    final now = DateTime.now();
    final groups = DateGroups(now);
    final weekEnd = groups.thisWeekStart.add(const Duration(days: 7));
    final list = items.where((i) {
      if (filterTradeId != null && !i.tradeIds.contains(filterTradeId) && !i.bicTradeIds.contains(filterTradeId)) return false;
      if (filterTypeId != null && i.typeId != filterTypeId) return false;
      if (filterStatus == 'active' && !i.status.isActive) return false;
      if (filterStatus != 'active' && filterStatus != 'all' && i.status.db != filterStatus) return false;
      if (filterLevel != null && i.level != filterLevel) return false;
      if (filterPriority != null && i.priority != filterPriority) return false;
      switch (filterDue) {
        case DueFilter.any:
          break;
        case DueFilter.overdue:
          if (!i.isOverdue) return false;
        case DueFilter.thisWeek:
          if (i.dueDate == null || i.dueDate!.isBefore(groups.thisWeekStart) || !i.dueDate!.isBefore(weekEnd)) return false;
        case DueFilter.noDate:
          if (i.dueDate != null) return false;
      }
      if (q.isNotEmpty && !i.searchText.contains(q)) return false;
      return true;
    }).toList();
    return _sorted(list);
  }

  int get overdueCount => items.where((i) => i.isOverdue).length;
  int get openCount => items.where((i) => i.status.isActive).length;

  List<Item> _sorted(List<Item> list) {
    int byNumber(Item a, Item b) {
      final t = a.number.compareTo(b.number);
      return t;
    }

    int byDue(Item a, Item b) {
      final ao = a.overdueDays(), bo = b.overdueDays();
      if (ao != bo) return bo.compareTo(ao);
      if (a.dueDate == null && b.dueDate != null) return 1;
      if (a.dueDate != null && b.dueDate == null) return -1;
      if (a.dueDate != null && b.dueDate != null) {
        final c = a.dueDate!.compareTo(b.dueDate!);
        if (c != 0) return c;
      }
      final p = a.priority.index.compareTo(b.priority.index);
      return p != 0 ? p : byNumber(a, b);
    }

    switch (sortBy) {
      case SortBy.due:
        list.sort((a, b) {
          // Closed items always go to the bottom.
          if (a.status.isActive != b.status.isActive) return a.status.isActive ? -1 : 1;
          return byDue(a, b);
        });
      case SortBy.priority:
        list.sort((a, b) {
          if (a.status.isActive != b.status.isActive) return a.status.isActive ? -1 : 1;
          final p = a.priority.index.compareTo(b.priority.index);
          return p != 0 ? p : byDue(a, b);
        });
      case SortBy.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortBy.number:
        list.sort(byNumber);
    }
    return list;
  }

  void setView(void Function() change) {
    change();
    notifyListeners();
  }

  void open(Section s) {
    section = s;
    if (s == Section.announcements) markAnnouncementsSeen();
    notifyListeners();
  }

  void selectItem(String? id) {
    selectedItemId = id;
    notifyListeners();
  }

  void clearFilters() {
    _resetFilters();
    notifyListeners();
  }

  // ------------------------------------------------------------------ item actions

  void _replace(Item updated) {
    final i = items.indexWhere((x) => x.id == updated.id);
    if (i >= 0) {
      items[i] = updated;
    } else {
      items.insert(0, updated);
    }
    notifyListeners();
  }

  Future<Item> createItem(Map<String, dynamic> values, {List<Uint8List> photos = const []}) async {
    final item = await api.createItem({...values, 'project_id': project!.id, 'created_by': me!.id}, photos: photos);
    _replace(item);
    selectedItemId = item.id;
    notifyListeners();
    return item;
  }

  Future<Item> updateItem(Item item, Map<String, dynamic> values) async {
    final updated = await api.updateItem(item.id, values);
    _replace(updated);
    threadVersion++;
    return updated;
  }

  Future<void> deleteItem(Item item) async {
    await api.deleteItem(item.id);
    items.removeWhere((i) => i.id == item.id);
    if (selectedItemId == item.id) selectedItemId = null;
    notifyListeners();
  }

  Future<void> addComment(Item item, String body, {List<Uint8List> photos = const []}) async {
    if (body.trim().isEmpty && photos.isEmpty) return;
    await api.addComment(item, body, photos: photos);
    threadVersion++;
    notifyListeners();
  }

  /// Uploads new photos (already marked up) and returns the item's full photo list.
  Future<List<String>> uploadItemPhotos(Item item, List<Uint8List> photos) async {
    final refs = <String>[];
    for (final b in photos) {
      refs.add(await api.uploadPhoto(item.projectId, item.id, b));
    }
    return refs;
  }

  /// Trade: answer the item; the ball goes back to the coordinator.
  Future<void> submitResponse(Item item, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    await updateItem(item, {'status': ItemStatus.responseSubmitted.db});
  }

  /// Trade: the model was changed; the coordinator verifies it.
  Future<void> markModelUpdated(Item item, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    await updateItem(item, {'status': ItemStatus.modelUpdated.db});
  }

  /// Sets who holds the ball: one or more trades, or the coordinator when [tradeIds] is empty.
  Future<void> passBall(Item item, List<String> tradeIds, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    final values = <String, dynamic>{'bic_trade_ids': tradeIds};
    // Handing an item to trades means they are now reviewing it.
    if (myRole.isCoord &&
        tradeIds.isNotEmpty &&
        (item.status == ItemStatus.open || item.status == ItemStatus.responseSubmitted || item.status == ItemStatus.modelUpdated)) {
      values['status'] = ItemStatus.inReview.db;
    }
    await updateItem(item, values);
  }

  Future<void> setStatus(Item item, ItemStatus status, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    await updateItem(item, {'status': status.db});
  }

  // ------------------------------------------------------------------ meetings

  Meeting? get selectedMeeting => meetings.where((m) => m.id == selectedMeetingId).firstOrNull;

  void selectMeeting(String? id) {
    selectedMeetingId = id;
    notifyListeners();
  }

  Future<Meeting> saveMeeting(Meeting? existing, Map<String, dynamic> values) async {
    final m = await api.saveMeeting(id: existing?.id, values: {...values, if (existing == null) 'project_id': project!.id});
    meetings = await api.meetings(project!.id);
    selectedMeetingId = m.id;
    notifyListeners();
    return m;
  }

  Future<void> deleteMeeting(Meeting m) async {
    await api.deleteMeeting(m.id);
    meetings.removeWhere((x) => x.id == m.id);
    if (selectedMeetingId == m.id) selectedMeetingId = null;
    notifyListeners();
  }

  Meeting? get nextMeeting {
    final now = DateTime.now();
    final upcoming = meetings.where((m) => m.endsAt.isAfter(now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return upcoming.firstOrNull;
  }

  // ------------------------------------------------------------------ schedule

  /// Meetings, the schedule, the BEP and clash reports are changed by the admin only.
  bool get canEditSchedule => isAdmin;
  bool get canEditMeetings => isAdmin;
  bool get canEditBep => isAdmin;
  bool get canEditReports => isAdmin;

  Future<void> saveTask(ScheduleTask? existing, Map<String, dynamic> values) async {
    await api.saveTask(id: existing?.id, values: {...values, if (existing == null) 'project_id': project!.id});
    schedule = await api.schedule(project!.id);
    notifyListeners();
  }

  Future<void> deleteTask(ScheduleTask t) async {
    await api.deleteTask(t.id);
    schedule.removeWhere((x) => x.id == t.id);
    notifyListeners();
  }

  // ------------------------------------------------------------------ BEP

  Future<void> reloadBep() async {
    final p = project;
    if (p == null) return;
    bepSections = await api.bepSections(p.id);
    bepFiles = await api.bepFiles(p.id);
    notifyListeners();
  }

  // ------------------------------------------------------------------ clash reports

  ClashReport? get selectedReport => clashReports.where((r) => r.id == selectedReportId).firstOrNull;

  void selectReport(String? id) {
    selectedReportId = id;
    notifyListeners();
  }

  Future<void> reloadReports() async {
    final p = project;
    if (p == null) return;
    clashReports = await api.clashReports(p.id);
    notifyListeners();
  }

  // ------------------------------------------------------------------ project status (top bar)

  /// "Coordination week 6" — counted from the project's coordination start (or the first schedule task).
  int? get coordinationWeek {
    final start = project?.coordinationStart ?? (schedule.isEmpty ? null : schedule.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b));
    if (start == null) return null;
    final days = dayOnly(DateTime.now()).difference(start).inDays;
    return days < 0 ? null : days ~/ 7 + 1;
  }

  /// Total coordination weeks, when an end date is known.
  int? get coordinationWeeks {
    final start = project?.coordinationStart ?? (schedule.isEmpty ? null : schedule.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b));
    final end = project?.coordinationEnd ?? (schedule.isEmpty ? null : schedule.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b));
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start).inDays ~/ 7 + 1;
  }

  /// Coordination work happening today.
  List<ScheduleTask> get currentWork {
    final today = dayOnly(DateTime.now());
    return schedule.where((t) => t.kind == TaskKind.coordination && t.isCurrent(today)).toList()
      ..sort((a, b) => a.end.compareTo(b.end));
  }

  /// The next sign-off (or milestone) that is not finished yet.
  ScheduleTask? get nextSignOff {
    final today = dayOnly(DateTime.now());
    final list = schedule
        .where((t) => (t.kind == TaskKind.signOff || t.kind == TaskKind.milestone) && !t.end.isBefore(today) && t.percent < 100)
        .toList()
      ..sort((a, b) => a.end.compareTo(b.end));
    return list.firstOrNull;
  }

  /// The next model submission due date.
  ScheduleTask? get nextModelDue {
    final today = dayOnly(DateTime.now());
    final list = schedule.where((t) => t.kind == TaskKind.modelDue && !t.end.isBefore(today) && t.percent < 100).toList()
      ..sort((a, b) => a.end.compareTo(b.end));
    return list.firstOrNull;
  }

  // ------------------------------------------------------------------ notifications

  Future<void> markRead(Iterable<AppNotification> list) async {
    final ids = list.where((n) => !n.isRead).map((n) => n.id).toList();
    if (ids.isEmpty) return;
    await api.markRead(ids);
    notifications = await api.notifications();
    notifyListeners();
  }

  Future<void> markAllRead() => markRead(notifications);

  Future<void> clearNotifications() async {
    await api.clearNotifications();
    notifications = [];
    notifyListeners();
  }

  Future<void> deleteNotifications(Iterable<AppNotification> list) async {
    final ids = list.map((n) => n.id).toList();
    if (ids.isEmpty) return;
    notifications = notifications.where((n) => !ids.contains(n.id)).toList();
    notifyListeners();
    await api.deleteNotifications(ids);
  }

  // ------------------------------------------------------------------ announcements

  bool get canEditAnnouncements => isAdmin;

  Future<void> reloadAnnouncements() async {
    final p = project;
    if (p == null) return;
    announcements = await api.announcements(p.id);
    notifyListeners();
  }

  /// Announcements posted by others since this person last opened the page.
  int get newAnnouncements {
    final p = project;
    if (p == null) return 0;
    final seen = settings.announcementsSeen(p.id);
    return announcements.where((a) => a.createdBy != me?.id && (seen == null || a.createdAt.isAfter(seen))).length;
  }

  void markAnnouncementsSeen() {
    final p = project;
    if (p == null) return;
    unawaited(settings.setAnnouncementsSeen(p.id, DateTime.now()));
  }

  /// Opens the item a notification points to (switching project if needed).
  Future<void> openNotification(AppNotification n) async {
    unawaited(markRead([n]));
    if (n.projectId != null && n.projectId != project?.id) {
      final p = projects.where((x) => x.id == n.projectId).firstOrNull;
      if (p != null) await selectProject(p);
    }
    if (n.itemId != null) {
      selectedItemId = n.itemId;
      section = Section.allItems;
      filterStatus = 'all';
    } else if (n.kind == 'signup' || n.kind == 'suggestion') {
      section = Section.team;
    } else if (n.kind == 'announcement') {
      section = Section.announcements;
      markAnnouncementsSeen();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ look (per person)

  ThemeMode get themeMode => appearance.mode;

  /// Uses the look saved on the account; a first sign-in keeps this device's look and saves it.
  void _applyAccountLook(Profile p) {
    if (p.prefs.isNotEmpty) {
      appearance = Appearance.fromJson(p.prefs);
      unawaited(settings.setAppearance(appearance));
      if (p.prefs['view'] is Map) {
        view = ViewPrefs.fromJson(p.prefs['view']);
        unawaited(settings.setView(view));
      }
    } else if (appearance != const Appearance() || view != const ViewPrefs()) {
      unawaited(api.savePrefs(_prefsJson()).catchError((_) {}));
    }
  }

  /// Everything saved on the account: the look plus the sizes.
  Map<String, dynamic> _prefsJson() => {...appearance.toJson(), 'view': view.toJson()};

  void _saveSoon() {
    _saveLook?.cancel();
    // Wait a moment so dragging a slider or a panel edge doesn't save on every step.
    _saveLook = Timer(const Duration(milliseconds: 700), () {
      if (me != null) unawaited(api.savePrefs(_prefsJson()).catchError((_) {}));
    });
  }

  /// This person's panel sizes, photo size and text sizes.
  ViewPrefs view;

  void setSizes(ViewPrefs v) {
    if (v == view) return;
    view = v;
    notifyListeners();
    unawaited(settings.setView(v));
    _saveSoon();
  }

  Timer? _saveLook;

  /// Changes the look right away and saves it on this device and on the account.
  void setAppearance(Appearance a) {
    if (a == appearance) return;
    appearance = a;
    notifyListeners();
    unawaited(settings.setAppearance(a));
    _saveSoon();
  }

  Future<void> setThemeMode(ThemeMode m) async => setAppearance(appearance.copyWith(mode: m));

  Future<void> toggleTheme(Brightness current) =>
      setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
