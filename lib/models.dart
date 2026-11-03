import 'package:flutter/material.dart';

import 'util/bep_blocks.dart';

/// Coordination item status workflow:
/// Open -> Assigned / In Review -> Response Submitted -> Model Updated – Verify -> Resolved / Closed,
/// plus On Hold and Voided. Only the admin or a coordinator can close, void, hold or reopen.
enum ItemStatus {
  open('open', 'Open', 'Created; waiting for the coordinator or a trade'),
  inReview('in_review', 'Assigned / In Review', 'A trade is reviewing it'),
  responseSubmitted('response_submitted', 'Response Submitted', 'The trade answered; the coordinator reviews it'),
  modelUpdated('model_updated', 'Model Updated – Verify', 'The trade updated the model; the coordinator verifies it'),
  closed('closed', 'Resolved / Closed', 'Resolved and closed'),
  onHold('on_hold', 'On Hold', 'Paused for now'),
  voided('void', 'Voided', 'Canceled or created by mistake');

  const ItemStatus(this.db, this.label, this.meaning);
  final String db;
  final String label;
  final String meaning;

  static ItemStatus fromDb(String? s) => values.firstWhere((v) => v.db == s, orElse: () => open);

  /// Not closed and not voided.
  bool get isActive => this != closed && this != voided;

  /// Statuses where a missed due date counts as overdue.
  bool get canBeOverdue => this == open || this == inReview || this == responseSubmitted || this == modelUpdated;

  /// Short label for tight spaces.
  String get shortLabel => switch (this) {
        ItemStatus.inReview => 'In Review',
        ItemStatus.modelUpdated => 'Verify',
        ItemStatus.closed => 'Closed',
        _ => label,
      };

  /// The main path shown in the progress bar (On Hold and Voided are side states).
  static const path = [open, inReview, responseSubmitted, modelUpdated, closed];
}

enum Priority {
  urgent('Urgent'),
  critical('Critical'),
  high('High'),
  medium('Medium'),
  low('Low');

  const Priority(this.label);
  final String label;

  static Priority fromDb(String? s) => values.firstWhere((p) => p.name == s, orElse: () => Priority.medium);
}

/// What a person can do on one project. The admin can do everything on every project.
enum Role {
  admin('admin', 'Admin'),
  coordinator('coordinator', 'Coordinator'),
  tradeLead('trade_lead', 'Trade lead'),
  tradeMember('trade_member', 'Trade member'),
  viewer('viewer', 'Viewer (read only)');

  const Role(this.db, this.label);
  final String db;
  final String label;

  static Role fromDb(String? s) => values.firstWhere((r) => r.db == s, orElse: () => Role.viewer);

  bool get isCoord => this == admin || this == coordinator;
  bool get isTrade => this == tradeLead || this == tradeMember;
  bool get needsTrade => isTrade;

  /// Roles that can be given on a project (admin is account-wide).
  static const projectRoles = [coordinator, tradeLead, tradeMember, viewer];
}

DateTime? _ts(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

DateTime? _date(dynamic v) {
  if (v == null) return null;
  final p = (v as String).split('-');
  if (p.length < 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2].substring(0, 2)));
}

String dateToDb(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _strings(dynamic v) => v == null ? <String>[] : (v as List).map((e) => e.toString()).toList();

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.email,
    this.company = '',
    this.phone = '',
    this.isAdmin = false,
    this.status = 'approved',
    this.createdAt,
    this.prefs = const {},
  });

  final String id;
  final String name;
  final String email;
  final String company;
  final String phone;
  final bool isAdmin;
  final String status; // pending, approved, removed
  final DateTime? createdAt;

  /// This person's own look: theme, colors, font and text size (see Appearance).
  final Map<String, dynamic> prefs;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRemoved => status == 'removed';

  /// True right after the first sign-in, before the person typed their name.
  bool get needsDetails => company.trim().isEmpty && name == email.split('@').first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        company: (j['company'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        isAdmin: (j['is_admin'] ?? false) as bool,
        status: (j['status'] ?? 'pending') as String,
        createdAt: _ts(j['created_at']),
        prefs: (j['prefs'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.code,
    this.location = '',
    this.buildings = const [],
    this.levels = const [],
    this.zones = const [],
    this.defaultDueDays = 3,
    this.archived = false,
    this.coordinationStart,
    this.coordinationEnd,
  });

  final String id;
  final String name;
  final String code;
  final String location;
  final List<String> buildings;
  final List<String> levels;
  final List<String> zones;
  final int defaultDueDays;
  final bool archived;

  /// First and last day of MEP coordination (for "Coordination week 6 of 20").
  final DateTime? coordinationStart;
  final DateTime? coordinationEnd;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        code: (j['code'] ?? '') as String,
        location: (j['location'] ?? '') as String,
        buildings: _strings(j['buildings']),
        levels: _strings(j['levels']),
        zones: _strings(j['zones']),
        defaultDueDays: (j['default_due_days'] ?? 3) as int,
        archived: (j['archived'] ?? false) as bool,
        coordinationStart: _date(j['coordination_start']),
        coordinationEnd: _date(j['coordination_end']),
      );
}

class Trade {
  Trade({required this.id, required this.projectId, required this.name, required this.code, this.company = '', this.sort = 0});

  final String id;
  final String projectId;
  final String name;
  final String code;
  final String company;
  final int sort;

  /// "Mechanical · Hart Mechanical"
  String get label => company.isEmpty ? name : '$name · $company';

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        name: (j['name'] ?? '') as String,
        code: (j['code'] ?? '') as String,
        company: (j['company'] ?? '') as String,
        sort: (j['sort'] ?? 0) as int,
      );
}

class ItemType {
  ItemType({required this.id, required this.projectId, required this.name, required this.code, this.sort = 0, this.active = true});

  final String id;
  final String projectId;
  final String name;
  final String code;
  final int sort;
  final bool active;

  factory ItemType.fromJson(Map<String, dynamic> j) => ItemType(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        name: (j['name'] ?? '') as String,
        code: (j['code'] ?? '') as String,
        sort: (j['sort'] ?? 0) as int,
        active: (j['active'] ?? true) as bool,
      );
}

class Member {
  Member({required this.projectId, required this.userId, required this.role, this.tradeId});

  final String projectId;
  final String userId;
  final Role role;
  final String? tradeId;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        projectId: j['project_id'] as String,
        userId: j['user_id'] as String,
        role: Role.fromDb(j['role'] as String?),
        tradeId: j['trade_id'] as String?,
      );
}

class Item {
  Item({
    required this.id,
    required this.projectId,
    required this.typeId,
    required this.number,
    required this.title,
    this.description = '',
    this.priority = Priority.medium,
    this.status = ItemStatus.open,
    this.building = '',
    this.level = '',
    this.zone = '',
    this.grid = '',
    this.clashTest = '',
    this.clashId = '',
    this.viewpoint = '',
    this.revitIds = '',
    this.sheet = '',
    this.tradeIds = const [],
    this.bicTradeIds = const [],
    required this.bicSince,
    this.dueDate,
    this.needsRfi = false,
    this.rfiNumber = '',
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
    this.closedBy,
    this.photos = const [],
  });

  final String id;
  final String projectId;
  final String typeId;
  final String number;
  final String title;
  final String description;
  final Priority priority;
  final ItemStatus status;
  final String building;
  final String level;
  final String zone;
  final String grid;
  final String clashTest;
  final String clashId;
  final String viewpoint;
  final String revitIds;
  final String sheet;
  final List<String> tradeIds;

  /// Trades that must act now; empty means the ball is with the Christman coordinator.
  final List<String> bicTradeIds;

  bool get ballWithCoordinator => bicTradeIds.isEmpty;
  final DateTime bicSince;
  final DateTime? dueDate;
  final bool needsRfi;
  final String rfiNumber;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final String? closedBy;

  /// Stored photo references ("sb:<path>"), already marked up.
  final List<String> photos;

  /// Whole days past the due date, or 0 when not overdue.
  int overdueDays([DateTime? now]) {
    if (dueDate == null || !status.canBeOverdue) return 0;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = today.difference(dueDate!).inDays;
    return d > 0 ? d : 0;
  }

  bool get isOverdue => overdueDays() > 0;

  /// "Level 3 · Zone B · C-4 / D-5"
  String get locationText {
    final parts = <String>[
      if (building.isNotEmpty) building,
      if (level.isNotEmpty) level,
      if (zone.isNotEmpty) zone,
      if (grid.isNotEmpty) grid,
    ];
    return parts.join(' · ');
  }

  bool get hasModelRef =>
      clashTest.isNotEmpty || clashId.isNotEmpty || viewpoint.isNotEmpty || revitIds.isNotEmpty || sheet.isNotEmpty;

  /// Text that search looks through: number, title, clash ID, grid and more.
  String get searchText =>
      '$number $title $clashId $clashTest $grid $level $zone $building $viewpoint $revitIds $sheet $rfiNumber'.toLowerCase();

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        typeId: j['type_id'] as String,
        number: (j['number'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        priority: Priority.fromDb(j['priority'] as String?),
        status: ItemStatus.fromDb(j['status'] as String?),
        building: (j['building'] ?? '') as String,
        level: (j['level'] ?? '') as String,
        zone: (j['zone'] ?? '') as String,
        grid: (j['grid'] ?? '') as String,
        clashTest: (j['clash_test'] ?? '') as String,
        clashId: (j['clash_id'] ?? '') as String,
        viewpoint: (j['viewpoint'] ?? '') as String,
        revitIds: (j['revit_ids'] ?? '') as String,
        sheet: (j['sheet'] ?? '') as String,
        tradeIds: _strings(j['trade_ids']),
        bicTradeIds: _strings(j['bic_trade_ids']),
        bicSince: _ts(j['bic_since']) ?? DateTime.now(),
        dueDate: _date(j['due_date']),
        needsRfi: (j['needs_rfi'] ?? false) as bool,
        rfiNumber: (j['rfi_number'] ?? '') as String,
        createdBy: j['created_by'] as String,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
        updatedAt: _ts(j['updated_at']) ?? DateTime.now(),
        closedAt: _ts(j['closed_at']),
        closedBy: j['closed_by'] as String?,
        photos: _strings(j['photos']),
      );
}

class Comment {
  Comment({
    required this.id,
    required this.itemId,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.editedAt,
    this.photos = const [],
  });

  final String id;
  final String itemId;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Photo references added to the reply.
  final List<String> photos;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] as String,
        itemId: j['item_id'] as String,
        authorId: j['author_id'] as String,
        body: (j['body'] ?? '') as String,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
        editedAt: _ts(j['edited_at']),
        photos: _strings(j['attachments']),
      );
}

/// One line of an item's history: created, status, ball, priority, due, rfi, edited.
class ItemEvent {
  ItemEvent({
    required this.id,
    required this.itemId,
    this.actorId,
    required this.kind,
    this.fromValue = '',
    this.toValue = '',
    required this.createdAt,
  });

  final int id;
  final String itemId;
  final String? actorId;
  final String kind;
  final String fromValue;
  final String toValue;
  final DateTime createdAt;

  factory ItemEvent.fromJson(Map<String, dynamic> j) => ItemEvent(
        id: (j['id'] as num).toInt(),
        itemId: j['item_id'] as String,
        actorId: j['actor_id'] as String?,
        kind: (j['kind'] ?? '') as String,
        fromValue: (j['from_value'] ?? '') as String,
        toValue: (j['to_value'] ?? '') as String,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
      );

  /// Plain-language description, e.g. "Ball moved to Mechanical".
  String describe() {
    String st(String v) => ItemStatus.fromDb(v).label;
    String pr(String v) => Priority.fromDb(v).label;
    switch (kind) {
      case 'created':
        return 'Created the item';
      case 'status':
        return 'Status: ${st(fromValue)} → ${st(toValue)}';
      case 'ball':
        return fromValue.isEmpty ? 'Ball in court: $toValue' : 'Ball moved: $fromValue → $toValue';
      case 'priority':
        return 'Priority: ${pr(fromValue)} → ${pr(toValue)}';
      case 'due':
        if (toValue.isEmpty) return 'Removed the due date';
        return fromValue.isEmpty ? 'Set the due date to $toValue' : 'Due date: $fromValue → $toValue';
      case 'rfi':
        return toValue.isEmpty ? 'Turned off "Needs RFI"' : 'Needs RFI: ${toValue.replaceFirst('RFI ', '').isEmpty ? 'yes' : toValue}';
      case 'edited':
        return 'Edited: $toValue';
      default:
        return kind;
    }
  }
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.projectId,
    this.itemId,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final String kind;
  final String title;
  final String body;
  final String? projectId;
  final String? itemId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  IconData get icon => switch (kind) {
        'ball' => Icons.sports_baseball_outlined,
        'new_item' => Icons.add_circle_outline,
        'response' => Icons.reply_outlined,
        'closed' => Icons.check_circle_outline,
        'comment' => Icons.chat_bubble_outline,
        'signup' => Icons.person_add_alt_1_outlined,
        'suggestion' => Icons.group_add_outlined,
        'overdue' => Icons.alarm_outlined,
        'announcement' => Icons.campaign_outlined,
        _ => Icons.notifications_none,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num).toInt(),
        kind: (j['kind'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        projectId: j['project_id'] as String?,
        itemId: j['item_id'] as String?,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
        readAt: _ts(j['read_at']),
      );
}

/// An invitation (added by the admin) or a member suggestion (from a trade lead).
class Invite {
  Invite({
    required this.id,
    required this.email,
    this.name = '',
    this.company = '',
    required this.projectId,
    required this.role,
    this.tradeId,
    required this.status,
    this.suggestedBy,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String company;
  final String projectId;
  final Role role;
  final String? tradeId;
  final String status; // suggested, approved, rejected, used
  final String? suggestedBy;
  final DateTime createdAt;

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
        id: j['id'] as String,
        email: (j['email'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        company: (j['company'] ?? '') as String,
        projectId: j['project_id'] as String,
        role: Role.fromDb(j['role'] as String?),
        tradeId: j['trade_id'] as String?,
        status: (j['status'] ?? '') as String,
        suggestedBy: j['suggested_by'] as String?,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
      );
}

// ===================================================================== meetings

class Attendee {
  Attendee({required this.name, this.company = '', this.role = '', this.present = true, this.userId});
  String name;
  String company;
  String role;
  bool present;
  String? userId;

  Map<String, dynamic> toJson() =>
      {'name': name, 'company': company, 'role': role, 'present': present, if (userId != null) 'user_id': userId};

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
        name: (j['name'] ?? '') as String,
        company: (j['company'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        present: (j['present'] ?? true) as bool,
        userId: j['user_id'] as String?,
      );
}

/// An item discussed in a meeting, with what was said about it.
/// Number, title, status and ball are kept as they were at the meeting.
class MeetingItem {
  MeetingItem({
    required this.itemId,
    required this.number,
    required this.title,
    this.status = '',
    this.priority = '',
    this.ball = '',
    this.note = '',
  });
  String itemId;
  String number;
  String title;
  String status;
  String priority;
  String ball;
  String note;

  Map<String, dynamic> toJson() =>
      {'id': itemId, 'number': number, 'title': title, 'status': status, 'priority': priority, 'ball': ball, 'note': note};

  factory MeetingItem.fromJson(Map<String, dynamic> j) => MeetingItem(
        itemId: (j['id'] ?? '') as String,
        number: (j['number'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        priority: (j['priority'] ?? '') as String,
        ball: (j['ball'] ?? '') as String,
        note: (j['note'] ?? '') as String,
      );
}

class ActionItem {
  ActionItem({required this.text, this.owner = '', this.due, this.done = false});
  String text;
  String owner;
  DateTime? due;
  bool done;

  Map<String, dynamic> toJson() => {'text': text, 'owner': owner, 'due': due == null ? null : dateToDb(due!), 'done': done};

  factory ActionItem.fromJson(Map<String, dynamic> j) => ActionItem(
        text: (j['text'] ?? '') as String,
        owner: (j['owner'] ?? '') as String,
        due: _date(j['due']),
        done: (j['done'] ?? false) as bool,
      );
}

/// One agenda topic: what, who leads it, how many minutes.
class AgendaItem {
  AgendaItem({required this.text, this.owner = '', this.minutes = 0});
  String text;
  String owner;
  int minutes;

  Map<String, dynamic> toJson() => {'text': text, 'owner': owner, 'minutes': minutes};

  factory AgendaItem.fromJson(Map<String, dynamic> j) => AgendaItem(
        text: (j['text'] ?? '') as String,
        owner: (j['owner'] ?? '') as String,
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      );
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    v == null ? const [] : (v as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

class Meeting {
  Meeting({
    required this.id,
    required this.projectId,
    required this.number,
    required this.title,
    required this.startsAt,
    this.durationMin = 60,
    this.location = '',
    this.attendees = const [],
    this.summary = '',
    this.items = const [],
    this.actions = const [],
    this.agenda = const [],
    this.prep = const [],
    this.nextMeeting,
    this.createdBy,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final int number;
  final String title;
  final DateTime startsAt;
  final int durationMin;
  final String location;
  final List<Attendee> attendees;
  final String summary;
  final List<MeetingItem> items;
  final List<ActionItem> actions;

  /// Topics to cover, in order.
  final List<AgendaItem> agenda;

  /// What people must have done before they come.
  final List<ActionItem> prep;
  final DateTime? nextMeeting;
  final String? createdBy;
  final DateTime updatedAt;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMin));
  bool get isUpcoming => endsAt.isAfter(DateTime.now());
  bool get hasMinutes => summary.trim().isNotEmpty || items.any((i) => i.note.trim().isNotEmpty) || actions.isNotEmpty;
  int get openActions => actions.where((a) => !a.done).length;

  factory Meeting.fromJson(Map<String, dynamic> j) => Meeting(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        number: (j['number'] ?? 0) as int,
        title: (j['title'] ?? '') as String,
        startsAt: _ts(j['starts_at']) ?? DateTime.now(),
        durationMin: (j['duration_min'] ?? 60) as int,
        location: (j['location'] ?? '') as String,
        attendees: _maps(j['attendees']).map(Attendee.fromJson).toList(),
        summary: (j['summary'] ?? '') as String,
        items: _maps(j['items']).map(MeetingItem.fromJson).toList(),
        actions: _maps(j['actions']).map(ActionItem.fromJson).toList(),
        agenda: _maps(j['agenda']).map(AgendaItem.fromJson).toList(),
        prep: _maps(j['prep']).map(ActionItem.fromJson).toList(),
        nextMeeting: _ts(j['next_meeting']),
        createdBy: j['created_by'] as String?,
        updatedAt: _ts(j['updated_at']) ?? DateTime.now(),
      );
}

// ===================================================================== schedule

enum TaskKind {
  coordination('coordination', 'Coordination', Icons.layers_outlined),
  signOff('sign_off', 'Sign-off', Icons.verified_outlined),
  modelDue('model_due', 'Model due', Icons.view_in_ar_outlined),
  milestone('milestone', 'Milestone', Icons.flag_outlined),
  other('other', 'Other', Icons.event_note_outlined);

  const TaskKind(this.db, this.label, this.icon);
  final String db;
  final String label;
  final IconData icon;

  static TaskKind fromDb(String? s) => values.firstWhere((k) => k.db == s, orElse: () => other);
}

class ScheduleTask {
  ScheduleTask({
    required this.id,
    required this.projectId,
    required this.name,
    this.kind = TaskKind.coordination,
    this.area = '',
    required this.start,
    required this.end,
    this.tradeIds = const [],
    this.percent = 0,
    this.notes = '',
    this.sort = 0,
  });

  final String id;
  final String projectId;
  final String name;
  final TaskKind kind;
  final String area;
  final DateTime start;
  final DateTime end;
  final List<String> tradeIds;
  final int percent;
  final String notes;
  final int sort;

  /// Days in the task, counting both ends.
  int get days => end.difference(start).inDays + 1;
  bool get isPoint => days == 1;

  bool isDone([DateTime? now]) => percent >= 100;
  bool isCurrent(DateTime today) => !today.isBefore(start) && !today.isAfter(end) && percent < 100;
  bool isLate(DateTime today) => today.isAfter(end) && percent < 100;

  factory ScheduleTask.fromJson(Map<String, dynamic> j) => ScheduleTask(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        name: (j['name'] ?? '') as String,
        kind: TaskKind.fromDb(j['kind'] as String?),
        area: (j['area'] ?? '') as String,
        start: _date(j['start_date']) ?? DateTime.now(),
        end: _date(j['end_date']) ?? DateTime.now(),
        tradeIds: _strings(j['trade_ids']),
        percent: (j['percent'] ?? 0) as int,
        notes: (j['notes'] ?? '') as String,
        sort: (j['sort'] ?? 0) as int,
      );
}

// ===================================================================== BEP

class BepSection {
  BepSection({required this.id, required this.projectId, required this.title, this.body = '', this.content, this.sort = 0, this.updatedBy, required this.updatedAt});

  final String id;
  final String projectId;
  final String title;

  /// Plain-text copy (older sections only have this).
  final String body;

  /// Rich content (tables, lists, note boxes, pictures), or null for older sections.
  final Object? content;
  final int sort;
  final String? updatedBy;
  final DateTime updatedAt;

  /// The section as blocks (older plain-text sections are converted).
  List<BepBlock> get blocks => content is List ? blocksFromJson(content) : blocksFromText(body);

  factory BepSection.fromJson(Map<String, dynamic> j) => BepSection(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        content: j['content'],
        sort: (j['sort'] ?? 0) as int,
        updatedBy: j['updated_by'] as String?,
        updatedAt: _ts(j['updated_at']) ?? DateTime.now(),
      );
}

/// A file shared in the BEP (templates, BEP document, families…), for all trades or one trade.
class BepFile {
  BepFile({
    required this.id,
    required this.projectId,
    required this.name,
    this.description = '',
    this.category = 'Document',
    this.tradeId,
    required this.path,
    required this.fileName,
    this.sizeBytes = 0,
    this.uploadedBy,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String name;
  final String description;
  final String category;
  final String? tradeId;
  final String path;
  final String fileName;
  final int sizeBytes;
  final String? uploadedBy;
  final DateTime createdAt;

  static const categories = ['BEP document', 'Template', 'Shared model', 'Families / content', 'Standards', 'Other'];

  /// The main BEP document shown at the top of the BEP page.
  static const mainCategory = 'Project BEP File';
  bool get isMain => category == mainCategory;

  factory BepFile.fromJson(Map<String, dynamic> j) => BepFile(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        category: (j['category'] ?? 'Other') as String,
        tradeId: j['trade_id'] as String?,
        path: (j['path'] ?? '') as String,
        fileName: (j['file_name'] ?? '') as String,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        uploadedBy: j['uploaded_by'] as String?,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
      );
}

// ===================================================================== clash reports

class ClashReport {
  ClashReport({
    required this.id,
    required this.projectId,
    required this.title,
    required this.reportDate,
    this.notes = '',
    required this.path,
    required this.fileName,
    this.sizeBytes = 0,
    this.summary = const {},
    this.uploadedBy,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String title;
  final DateTime reportDate;
  final String notes;
  final String path;
  final String fileName;
  final int sizeBytes;

  /// {rows: 120, statuses: {New: 40, Active: 60, ...}} worked out when it was uploaded.
  final Map<String, dynamic> summary;
  final String? uploadedBy;
  final DateTime createdAt;

  int get rowCount => (summary['rows'] as num?)?.toInt() ?? 0;
  Map<String, int> get statuses =>
      ((summary['statuses'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));

  factory ClashReport.fromJson(Map<String, dynamic> j) => ClashReport(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        title: (j['title'] ?? '') as String,
        reportDate: _date(j['report_date']) ?? DateTime.now(),
        notes: (j['notes'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        fileName: (j['file_name'] ?? '') as String,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        summary: (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
        uploadedBy: j['uploaded_by'] as String?,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
      );
}

/// "2.4 MB"
String fileSizeText(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// A message from the admin to everyone on the project.
class Announcement {
  Announcement({
    required this.id,
    required this.projectId,
    required this.title,
    this.body = '',
    this.level = 'info',
    this.pinned = false,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String title;
  final String body;

  /// info, important or urgent
  final String level;
  final bool pinned;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const levels = ['info', 'important', 'urgent'];

  static String levelLabel(String l) => switch (l) { 'urgent' => 'Urgent', 'important' => 'Important', _ => 'Info' };

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        level: (j['level'] ?? 'info') as String,
        pinned: j['pinned'] == true,
        createdBy: j['created_by'] as String?,
        createdAt: _ts(j['created_at']) ?? DateTime.now(),
        updatedAt: _ts(j['updated_at']) ?? DateTime.now(),
      );
}
