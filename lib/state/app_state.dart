import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../data/api.dart';
import '../models.dart';
import '../theme.dart';
import '../util/dates.dart';
import 'settings.dart';

/// The parts of the app reached from the sidebar (Windows) or the bottom tabs (phone).
enum Section { ballInCourt, allItems, notifications, team, setup, settings }

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
  AppState(this.api, this.settings) : appearance = settings.appearance;

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
  bool loadingProject = false;

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
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _debounce?.cancel();
    _saveLook?.cancel();
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
    selectedItemId = null;
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
    ]);
    trades = results[0] as List<Trade>;
    types = results[1] as List<ItemType>;
    members = results[2] as List<Member>;
    people = {for (final x in results[3] as List<Profile>) x.id: x};
    items = results[4] as List<Item>;
    notifications = results[5] as List<AppNotification>;
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
      (item.tradeIds.contains(myTradeId) || item.bicTradeId == myTradeId);

  /// Can this person pass the ball on [item]?
  bool canPassBall(Item item) {
    if (!item.status.isActive) return false;
    if (myRole.isCoord) return true;
    return myRole.isTrade && myTradeId != null && item.bicTradeId == myTradeId;
  }

  // ------------------------------------------------------------------ lookups

  Trade? tradeById(String? id) => id == null ? null : trades.where((t) => t.id == id).firstOrNull;
  ItemType? typeById(String? id) => id == null ? null : types.where((t) => t.id == id).firstOrNull;
  Profile? person(String? id) => id == null ? null : people[id];
  Item? itemById(String? id) => id == null ? null : items.where((i) => i.id == id).firstOrNull;
  Item? get selectedItem => itemById(selectedItemId);

  /// "Mechanical · Hart Mechanical", or "Christman VDC" for the coordinator.
  String bicLabel(String? tradeId) => tradeById(tradeId)?.label ?? 'Christman VDC';
  String bicName(String? tradeId) => tradeById(tradeId)?.name ?? 'Christman VDC';

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
      list = items.where((i) => i.bicTradeId != null && i.bicTradeId == myTradeId);
    } else if (r.isCoord) {
      list = items.where((i) => i.bicTradeId == null);
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
      if (filterTradeId != null && !i.tradeIds.contains(filterTradeId) && i.bicTradeId != filterTradeId) return false;
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

  /// Moves the ball to a trade (or back to the coordinator when [tradeId] is null).
  Future<void> passBall(Item item, String? tradeId, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    final values = <String, dynamic>{'bic_trade_id': tradeId};
    // Handing an open item to a trade means the trade is now reviewing it.
    if (myRole.isCoord && tradeId != null && (item.status == ItemStatus.open || item.status == ItemStatus.responseSubmitted || item.status == ItemStatus.modelUpdated)) {
      values['status'] = ItemStatus.inReview.db;
    }
    await updateItem(item, values);
  }

  Future<void> setStatus(Item item, ItemStatus status, String note) async {
    if (note.trim().isNotEmpty) await api.addComment(item, note);
    await updateItem(item, {'status': status.db});
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
    } else if (appearance != const Appearance()) {
      unawaited(api.savePrefs(appearance.toJson()).catchError((_) {}));
    }
  }

  Timer? _saveLook;

  /// Changes the look right away and saves it on this device and on the account.
  void setAppearance(Appearance a) {
    if (a == appearance) return;
    appearance = a;
    notifyListeners();
    unawaited(settings.setAppearance(a));
    _saveLook?.cancel();
    // Wait a moment so dragging the text-size slider doesn't save on every step.
    _saveLook = Timer(const Duration(milliseconds: 700), () {
      if (me != null) unawaited(api.savePrefs(a.toJson()).catchError((_) {}));
    });
  }

  Future<void> setThemeMode(ThemeMode m) async => setAppearance(appearance.copyWith(mode: m));

  Future<void> toggleTheme(Brightness current) =>
      setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
