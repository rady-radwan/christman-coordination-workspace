import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../util/minutes_pdf.dart';
import '../util/save_file.dart';
import '../widgets/common.dart';
import 'item_detail.dart';
import 'notifications_screen.dart';

// =====================================================================
// Meetings section: list on the left, minutes on the right (Windows);
// list then minutes page (phone).
// =====================================================================

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final wide = isWide(context);
    final header = PageHeader(
      title: 'Coordination Meetings',
      actions: [
        if (s.canEditMeetings)
          FilledButton.icon(
            onPressed: () => openMeetingForm(context),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Meeting'),
          ),
        const SizedBox(width: 8),
      ],
    );
    if (!wide) {
      return Column(children: [
        header,
        Expanded(
          child: _MeetingList(onOpen: (m) {
            s.selectMeeting(m.id);
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text('Meeting ${m.number}')),
                body: MeetingDetail(meetingId: m.id, phone: true),
              ),
            ));
          }),
        ),
      ]);
    }
    return Column(children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: s.view.listW,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.panel),
              child: _MeetingList(onOpen: (m) => s.selectMeeting(m.id)),
            ),
          ),
          ResizeHandle(
            showLine: true,
            onDrag: (dx) => s.setSizes(s.view.copyWith(listW: s.view.listW + dx)),
            onReset: () => s.setSizes(s.view.copyWith(listW: 420)),
          ),
          Expanded(
            child: ColoredBox(
              color: c.surface,
              child: s.selectedMeeting == null
                  ? EmptyState(
                      icon: Icons.groups_outlined,
                      title: s.meetings.isEmpty ? 'No meetings yet' : 'Pick a meeting',
                      body: s.meetings.isEmpty
                          ? (s.canEditMeetings
                              ? 'Click New Meeting to schedule one, pick the items to discuss, and record the minutes.'
                              : 'Meeting minutes from the Christman VDC team show here.')
                          : 'Select a meeting on the left to read its minutes or download them as a PDF.',
                    )
                  : MeetingDetail(key: ValueKey(s.selectedMeetingId), meetingId: s.selectedMeetingId!),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _MeetingList extends StatelessWidget {
  const _MeetingList({required this.onOpen});
  final void Function(Meeting m) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = DateTime.now();
    final upcoming = s.meetings.where((m) => m.endsAt.isAfter(now)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = s.meetings.where((m) => !m.endsAt.isAfter(now)).toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    if (s.meetings.isEmpty) {
      return const EmptyState(icon: Icons.event_note_outlined, title: 'No meetings yet');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (upcoming.isNotEmpty) ...[
          SectionLabel('Upcoming · ${upcoming.length}'),
          const SizedBox(height: 8),
          for (final m in upcoming) _MeetingCard(meeting: m, selected: m.id == s.selectedMeetingId, onTap: () => onOpen(m)),
          const SizedBox(height: 12),
        ],
        if (past.isNotEmpty) ...[
          SectionLabel('Past meetings · ${past.length}'),
          const SizedBox(height: 8),
          for (final m in past) _MeetingCard(meeting: m, selected: m.id == s.selectedMeetingId, onTap: () => onOpen(m)),
        ],
      ],
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting, required this.selected, required this.onTap});
  final Meeting meeting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final m = meeting;
    final d = m.startsAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Text(const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][d.month - 1],
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accentText, letterSpacing: 0.8)),
                  Text('${d.day}', style: condensed(24, color: c.ink)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Meeting ${m.number}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentText)),
                  Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    [weekdayDate(d).split(',').first, timeText(d), if (m.location.isNotEmpty) m.location].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    _Meta(icon: Icons.people_outline, text: '${m.attendees.where((a) => a.present).length}/${m.attendees.length}'),
                    _Meta(icon: Icons.format_list_bulleted, text: '${m.items.length} items'),
                    _Meta(
                      icon: Icons.task_alt,
                      text: m.actions.isEmpty ? 'No actions' : '${m.openActions} open of ${m.actions.length}',
                      strong: m.openActions > 0,
                    ),
                    if (!m.hasMinutes && !m.isUpcoming) const _Meta(icon: Icons.edit_note, text: 'No minutes yet'),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.strong = false});
  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: strong ? c.accentText : c.muted),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 12.5, color: strong ? c.accentText : c.muted, fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
    ]);
  }
}

// =====================================================================
// Minutes page
// =====================================================================

class MeetingDetail extends StatelessWidget {
  const MeetingDetail({super.key, required this.meetingId, this.phone = false});
  final String meetingId;
  final bool phone;

  Future<void> _download(BuildContext context, AppState s, Meeting m) async {
    try {
      final bytes = await buildMinutesPdf(
        meeting: m,
        project: s.project!,
        recordedBy: s.person(m.createdBy)?.name ?? 'Christman VDC',
      );
      final kind = !m.hasMinutes && m.isUpcoming ? 'Agenda' : 'Minutes';
      final name = safeFileName('${s.project!.code} Meeting ${m.number} $kind ${dateToDb(m.startsAt)}.pdf');
      final msg = await saveOrShareFile(bytes, name);
      if (msg != null && context.mounted) showInfo(context, msg);
    } catch (e) {
      if (context.mounted) showError(context, 'Could not make the PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final m = s.meetings.where((x) => x.id == meetingId).firstOrNull;
    if (m == null) return const EmptyState(icon: Icons.search_off, title: 'Meeting not found');
    final coord = s.canEditMeetings;
    final pad = phone ? 16.0 : 24.0;

    Widget section(String title, Widget child, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionLabel(title, trailing: trailing),
            const SizedBox(height: 8),
            child,
          ]),
        );

    Future<void> togglePrep(int i, bool done) async {
      final list = [...m.prep];
      list[i].done = done;
      try {
        await s.saveMeeting(m, {'prep': list.map((a) => a.toJson()).toList()});
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> toggleAction(int i, bool done) async {
      final list = [...m.actions];
      list[i].done = done;
      try {
        await s.saveMeeting(m, {'actions': list.map((a) => a.toJson()).toList()});
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    void openItem(String itemId) {
      if (s.itemById(itemId) == null) {
        showInfo(context, 'That item is no longer on this project.');
        return;
      }
      s.selectItem(itemId);
      if (phone) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: itemId)));
      } else {
        s.setView(() => s.filterStatus = 'all');
        s.open(Section.allItems);
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, phone ? 12 : 20, pad, 48),
      children: [
        Text('MEETING ${m.number}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.accentText)),
        const SizedBox(height: 2),
        Text(m.title, style: condensed(phone ? 26 : 30, color: c.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _Meta(icon: Icons.event_outlined, text: weekdayDate(m.startsAt)),
          _Meta(icon: Icons.schedule, text: '${timeText(m.startsAt)} – ${timeText(m.endsAt)}'),
          if (m.location.isNotEmpty) _Meta(icon: Icons.place_outlined, text: m.location),
          if (m.nextMeeting != null)
            _Meta(icon: Icons.east, text: 'Next: ${weekdayDate(m.nextMeeting!)} · ${timeText(m.nextMeeting!)}'),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _download(context, s, m),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(!m.hasMinutes && m.isUpcoming ? 'Download Agenda (PDF)' : 'Download Minutes (PDF)'),
          ),
          if (coord)
            OutlinedButton.icon(
              onPressed: () => openMeetingForm(context, meeting: m),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(m.isUpcoming && !m.hasMinutes ? 'Edit Agenda / Minutes' : (m.hasMinutes ? 'Edit Minutes' : 'Write Minutes')),
            ),
          if (coord)
            OutlinedButton.icon(
              onPressed: () => openMeetingForm(context, template: planNextMeeting(s, m)),
              icon: const Icon(Icons.event_repeat, size: 18),
              label: const Text('Plan Next Meeting'),
            ),
          if (coord)
            OutlinedButton.icon(
              onPressed: () async {
                if (!await confirm(context, 'Delete meeting ${m.number}?', 'Its minutes are removed for everyone.', ok: 'Delete', danger: true)) return;
                try {
                  await s.deleteMeeting(m);
                  if (phone && context.mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
        ]),

        section(
          m.agenda.isEmpty ? 'Agenda' : 'Agenda · ${m.agenda.length} topics${_totalMinutes(m.agenda) > 0 ? ' · ${_totalMinutes(m.agenda)} min' : ''}',
          m.agenda.isEmpty
              ? Text(coord ? 'No agenda yet. Use "Edit" to add the topics for this meeting.' : 'No agenda yet.', style: TextStyle(color: c.muted))
              : Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                  child: Column(children: [
                    for (var i = 0; i < m.agenda.length; i++)
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                            child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: c.accentText)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.agenda[i].text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.35))),
                          if (m.agenda[i].owner.isNotEmpty) ...[const SizedBox(width: 10), Text(m.agenda[i].owner, style: TextStyle(fontSize: 13, color: c.ink2))],
                          if (m.agenda[i].minutes > 0) ...[const SizedBox(width: 10), Text('${m.agenda[i].minutes} min', style: TextStyle(fontSize: 13, color: c.muted))],
                        ]),
                      ),
                  ]),
                ),
        ),

        if (m.prep.isNotEmpty || (coord && m.isUpcoming))
          section(
            'Before the meeting · ${m.prep.where((p) => !p.done).length} to do',
            m.prep.isEmpty
                ? Text('Nothing listed yet. Add what people must have done before they come.', style: TextStyle(color: c.muted))
                : Container(
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.accent.withValues(alpha: 0.5)),
                    ),
                    child: Column(children: [
                      for (var i = 0; i < m.prep.length; i++)
                        Container(
                          decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line))),
                          child: CheckboxListTile(
                            value: m.prep[i].done,
                            onChanged: coord ? (v) => togglePrep(i, v ?? false) : null,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              m.prep[i].text,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: m.prep[i].done ? TextDecoration.lineThrough : null,
                                color: m.prep[i].done ? c.muted : c.ink,
                              ),
                            ),
                            subtitle: Text([
                              if (m.prep[i].owner.isNotEmpty) 'Who: ${m.prep[i].owner}',
                              if (m.prep[i].due != null) 'By ${weekdayDate(m.prep[i].due!)}',
                            ].join('  ·  ')),
                          ),
                        ),
                    ]),
                  ),
          ),

        section(
          'Attendees · ${m.attendees.where((a) => a.present).length} present of ${m.attendees.length}',
          m.attendees.isEmpty
              ? Text('No attendees recorded.', style: TextStyle(color: c.muted))
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in m.attendees)
                    Container(
                      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                      decoration: BoxDecoration(
                        color: a.present ? c.surface2 : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.line),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(a.present ? Icons.check_circle : Icons.cancel_outlined, size: 18, color: a.present ? c.statusFg(ItemStatus.closed) : c.muted),
                        const SizedBox(width: 6),
                        Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: a.present ? c.ink : c.muted)),
                        if (a.company.isNotEmpty || a.role.isNotEmpty)
                          Text('  ${[a.company, a.role].where((x) => x.isNotEmpty).join(' · ')}', style: TextStyle(fontSize: 12.5, color: c.muted)),
                      ]),
                    ),
                ]),
        ),

        section(
          'Summary',
          Panel(
            child: SelectableText(
              m.summary.trim().isEmpty ? 'No summary yet.' : m.summary.trim(),
              style: TextStyle(fontSize: 15, height: 1.5, color: m.summary.trim().isEmpty ? c.muted : c.ink),
            ),
          ),
        ),

        section(
          'Items discussed · ${m.items.length}',
          m.items.isEmpty
              ? Text('No items were added to this meeting.', style: TextStyle(color: c.muted))
              : Column(children: [
                  for (final it in m.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => openItem(it.itemId),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              ItemNumber(it.number, size: 15),
                              if (it.priority.isNotEmpty) PriorityBadge(Priority.fromDb(it.priority)),
                              if (it.status.isNotEmpty) StatusBadge(ItemStatus.fromDb(it.status), short: true),
                              if (it.ball.isNotEmpty) _Meta(icon: Icons.adjust, text: it.ball),
                            ]),
                            const SizedBox(height: 4),
                            Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                            if (it.note.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(it.note.trim(), style: TextStyle(fontSize: 14, height: 1.45, color: c.ink2)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                ]),
        ),

        section(
          'Action items · ${m.openActions} open of ${m.actions.length}',
          m.actions.isEmpty
              ? Text('No action items.', style: TextStyle(color: c.muted))
              : Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                  child: Column(children: [
                    for (var i = 0; i < m.actions.length; i++)
                      Container(
                        decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line))),
                        child: CheckboxListTile(
                          value: m.actions[i].done,
                          onChanged: coord ? (v) => toggleAction(i, v ?? false) : null,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            m.actions[i].text,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: m.actions[i].done ? TextDecoration.lineThrough : null,
                              color: m.actions[i].done ? c.muted : c.ink,
                            ),
                          ),
                          subtitle: Text([
                            if (m.actions[i].owner.isNotEmpty) 'Owner: ${m.actions[i].owner}',
                            if (m.actions[i].due != null) 'Due ${weekdayDate(m.actions[i].due!)}',
                          ].join('  ·  ')),
                        ),
                      ),
                  ]),
                ),
        ),
        const SizedBox(height: 12),
        Text('Last updated ${dayTimeText(m.updatedAt)}', style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }
}

// =====================================================================
// New meeting / agenda / minutes (admin)
// =====================================================================

Widget _ownerMenu(List<String> owners, ValueChanged<String> onPick) => PopupMenuButton<String>(
      tooltip: 'Pick',
      icon: const Icon(Icons.arrow_drop_down),
      onSelected: onPick,
      itemBuilder: (_) => owners.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
    );

int _totalMinutes(List<AgendaItem> a) => a.fold(0, (sum, x) => sum + x.minutes);

/// [template] pre-fills a new meeting (used by "Plan Next Meeting").
Future<void> openMeetingForm(BuildContext context, {Meeting? meeting, Meeting? template}) => openForm<void>(
      context,
      title: meeting != null
          ? 'Meeting ${meeting.number} — agenda and minutes'
          : (template != null ? 'Plan the next meeting' : 'New coordination meeting'),
      builder: (_) => _MeetingForm(meeting: meeting, template: template),
    );

/// The next meeting, pre-filled from [m]: same title, place and people; open action items
/// become "before the meeting" tasks; items still open become follow-up topics.
Meeting planNextMeeting(AppState s, Meeting m) {
  final start = m.nextMeeting ?? m.startsAt.add(const Duration(days: 7));
  final openActions = m.actions.where((a) => !a.done).toList();
  final followUps = m.items.where((i) => s.itemById(i.itemId)?.status.isActive ?? false).toList();
  return Meeting(
    id: '',
    projectId: m.projectId,
    number: 0,
    title: m.title,
    startsAt: start,
    durationMin: m.durationMin,
    location: m.location,
    attendees: m.attendees.map((a) => Attendee(name: a.name, company: a.company, role: a.role, userId: a.userId)).toList(),
    agenda: [
      if (openActions.isNotEmpty) AgendaItem(text: 'Review open action items from meeting ${m.number}', owner: 'Christman VDC', minutes: 10),
      for (final i in followUps) AgendaItem(text: 'Follow up: ${i.number} — ${i.title}', owner: i.ball, minutes: 5),
      AgendaItem(text: 'New clashes and items by area', owner: 'Christman VDC', minutes: 20),
      AgendaItem(text: 'Schedule, sign-offs and model submissions', owner: 'Christman VDC', minutes: 10),
    ],
    prep: [
      for (final a in openActions) ActionItem(text: a.text, owner: a.owner, due: a.due),
      ActionItem(text: 'Upload your latest model before the meeting', owner: 'All trades', due: start.subtract(const Duration(days: 1))),
    ],
    updatedAt: DateTime.now(),
  );
}

class _MeetingForm extends StatefulWidget {
  const _MeetingForm({this.meeting, this.template});
  final Meeting? meeting;
  final Meeting? template;

  @override
  State<_MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends State<_MeetingForm> {
  late final AppState s = context.read<AppState>();
  late final Meeting? m = widget.meeting;

  /// Where the starting values come from: the meeting being edited, or the plan for the next one.
  late final Meeting? src = widget.meeting ?? widget.template;

  late final _title = TextEditingController(text: src?.title ?? 'Weekly MEP Coordination Meeting');
  late final _location = TextEditingController(text: src?.location ?? (s.meetings.isEmpty ? '' : s.meetings.first.location));
  late final _summary = TextEditingController(text: m?.summary ?? '');
  late DateTime _start = src?.startsAt ?? _defaultStart();
  late int _duration = src?.durationMin ?? 60;
  late DateTime? _next = m?.nextMeeting;
  late final List<Attendee> _attendees =
      src == null || src!.attendees.isEmpty ? _teamAttendees() : src!.attendees.map((a) => Attendee.fromJson(a.toJson())).toList();
  late final List<AgendaItem> _agenda = (src?.agenda ?? const []).map((x) => AgendaItem.fromJson(x.toJson())).toList();
  late final List<ActionItem> _prep = (src?.prep ?? const []).map((x) => ActionItem.fromJson(x.toJson())).toList();
  late final Map<AgendaItem, TextEditingController> _agendaText = {for (final a in _agenda) a: TextEditingController(text: a.text)};
  late final Map<AgendaItem, TextEditingController> _agendaOwner = {for (final a in _agenda) a: TextEditingController(text: a.owner)};
  late final Map<ActionItem, TextEditingController> _prepText = {for (final a in _prep) a: TextEditingController(text: a.text)};
  late final Map<ActionItem, TextEditingController> _prepOwner = {for (final a in _prep) a: TextEditingController(text: a.owner)};
  late final List<MeetingItem> _items = (m?.items ?? const []).map((x) => MeetingItem.fromJson(x.toJson())).toList();
  late final List<ActionItem> _actions = (m?.actions ?? const []).map((x) => ActionItem.fromJson(x.toJson())).toList();
  late final Map<MeetingItem, TextEditingController> _notes = {for (final i in _items) i: TextEditingController(text: i.note)};
  late final Map<ActionItem, TextEditingController> _actionText = {for (final a in _actions) a: TextEditingController(text: a.text)};
  late final Map<ActionItem, TextEditingController> _actionOwner = {for (final a in _actions) a: TextEditingController(text: a.owner)};
  bool _busy = false;
  String? _error;

  DateTime _defaultStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 10);
  }

  /// A new meeting starts with everyone on the project team, marked present.
  List<Attendee> _teamAttendees() {
    final list = <Attendee>[];
    for (final mem in s.members) {
      final p = s.person(mem.userId);
      if (p == null || mem.role == Role.viewer) continue;
      list.add(Attendee(
        name: p.name,
        company: p.company,
        role: mem.role.isTrade ? (s.tradeById(mem.tradeId)?.name ?? mem.role.label) : mem.role.label,
        userId: p.id,
      ));
    }
    list.sort((a, b) => a.company.compareTo(b.company));
    return list;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _summary.dispose();
    for (final c in [
      ..._notes.values,
      ..._actionText.values,
      ..._actionOwner.values,
      ..._agendaText.values,
      ..._agendaOwner.values,
      ..._prepText.values,
      ..._prepOwner.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 3));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _addItems() async {
    final picked = await showDialog<List<Item>>(
      context: context,
      builder: (_) => _ItemPicker(already: _items.map((i) => i.itemId).toSet()),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final it in picked) {
        final mi = MeetingItem(
          itemId: it.id,
          number: it.number,
          title: it.title,
          status: it.status.db,
          priority: it.priority.name,
          ball: s.bicNames(it.bicTradeIds),
        );
        _items.add(mi);
        _notes[mi] = TextEditingController();
      }
    });
  }

  Future<void> _addFromTeam() async {
    final have = _attendees.map((a) => a.userId).whereType<String>().toSet();
    final team = s.members.where((mem) => !have.contains(mem.userId) && s.person(mem.userId) != null).toList();
    if (team.isEmpty) {
      showInfo(context, 'Everyone on the project team is already on the list.');
      return;
    }
    final chosen = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add people from the team'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final mem in team)
                CheckboxListTile(
                  value: chosen.contains(mem.userId),
                  onChanged: (v) => setD(() => v == true ? chosen.add(mem.userId) : chosen.remove(mem.userId)),
                  title: Text(s.person(mem.userId)!.name),
                  subtitle: Text(s.personLine(mem.userId)),
                  dense: true,
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      for (final id in chosen) {
        final p = s.person(id)!;
        final mem = s.memberOf(id);
        _attendees.add(Attendee(
          name: p.name,
          company: p.company,
          role: mem == null ? '' : (mem.role.isTrade ? (s.tradeById(mem.tradeId)?.name ?? mem.role.label) : mem.role.label),
          userId: id,
        ));
      }
    });
  }

  Future<void> _addGuest() async {
    final name = TextEditingController();
    final company = TextEditingController();
    final role = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a guest'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Name'),
            TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 8),
            const FieldLabel('Company'),
            TextField(controller: company, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 8),
            const FieldLabel('Trade / role', hint: 'e.g. Architect, Owner'),
            TextField(controller: role, textCapitalization: TextCapitalization.words),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _attendees.add(Attendee(name: name.text.trim(), company: company.text.trim(), role: role.text.trim())));
    }
  }

  void _addAction() {
    final a = ActionItem(text: '', due: DateTime.now().add(const Duration(days: 7)));
    setState(() {
      _actions.add(a);
      _actionText[a] = TextEditingController();
      _actionOwner[a] = TextEditingController();
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the meeting a title.');
      return;
    }
    for (final i in _items) {
      i.note = _notes[i]!.text.trim();
    }
    final actions = <ActionItem>[];
    for (final a in _actions) {
      a.text = _actionText[a]!.text.trim();
      a.owner = _actionOwner[a]!.text.trim();
      if (a.text.isNotEmpty) actions.add(a);
    }
    final agenda = <AgendaItem>[];
    for (final a in _agenda) {
      a.text = _agendaText[a]!.text.trim();
      a.owner = _agendaOwner[a]!.text.trim();
      if (a.text.isNotEmpty) agenda.add(a);
    }
    final prep = <ActionItem>[];
    for (final a in _prep) {
      a.text = _prepText[a]!.text.trim();
      a.owner = _prepOwner[a]!.text.trim();
      if (a.text.isNotEmpty) prep.add(a);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await s.saveMeeting(m, {
        'agenda': agenda.map((a) => a.toJson()).toList(),
        'prep': prep.map((a) => a.toJson()).toList(),
        'title': _title.text.trim(),
        'starts_at': _start.toUtc().toIso8601String(),
        'duration_min': _duration,
        'location': _location.text.trim(),
        'attendees': _attendees.map((a) => a.toJson()).toList(),
        'summary': _summary.text.trim(),
        'items': _items.map((i) => i.toJson()).toList(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'next_meeting': _next?.toUtc().toIso8601String(),
      });
      if (mounted) {
        Navigator.of(context).pop();
        showInfo(context, m == null ? 'Meeting created' : 'Meeting saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget labeled(String label, Widget field, {String? hint}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label, hint: hint), field]);
    final owners = <String>{
      ...s.trades.map((t) => t.name),
      'Christman VDC',
      ..._attendees.map((a) => a.name),
    }.toList();

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            labeled('Title', TextField(controller: _title)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
              SizedBox(
                width: wide ? 300 : double.infinity,
                child: labeled(
                  'Date and time',
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await _pickDateTime(_start);
                      if (d != null) setState(() => _start = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Align(alignment: Alignment.centerLeft, child: Text('${weekdayDate(_start)} · ${timeText(_start)}')),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: labeled(
                  'Length',
                  DropdownButtonFormField<int>(
                    initialValue: [30, 45, 60, 90, 120, 180].contains(_duration) ? _duration : 60,
                    items: [30, 45, 60, 90, 120, 180]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v < 60 ? '$v min' : '${v / 60 == v ~/ 60 ? v ~/ 60 : (v / 60).toStringAsFixed(1)} h')))
                        .toList(),
                    onChanged: (v) => setState(() => _duration = v ?? 60),
                  ),
                ),
              ),
              SizedBox(width: wide ? 280 : double.infinity, child: labeled('Location', TextField(controller: _location, decoration: const InputDecoration(hintText: 'e.g. Site trailer / Teams')))),
            ]),

            const SizedBox(height: 20),
            SectionLabel(
              'Agenda · ${_agenda.length} topics${_totalMinutes(_agenda) > 0 ? ' · ${_totalMinutes(_agenda)} min' : ''}',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  final a = AgendaItem(text: '', minutes: 10);
                  _agenda.add(a);
                  _agendaText[a] = TextEditingController();
                  _agendaOwner[a] = TextEditingController();
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add topic'),
              ),
            ),
            const SizedBox(height: 6),
            if (_agenda.isEmpty) Text('What will be discussed, in order.', style: TextStyle(color: c.muted)),
            for (var i = 0; i < _agenda.length; i++)
              Container(
                key: ObjectKey(_agenda[i]),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Row(children: [
                  Text('${i + 1}.', style: TextStyle(fontWeight: FontWeight.w800, color: c.accentText)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: TextField(controller: _agendaText[_agenda[i]], decoration: const InputDecoration(hintText: 'Topic', isDense: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _agendaOwner[_agenda[i]],
                      decoration: InputDecoration(
                        hintText: 'Lead',
                        isDense: true,
                        suffixIcon: _ownerMenu(owners, (v) => setState(() => _agendaOwner[_agenda[i]]!.text = v)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: [0, 5, 10, 15, 20, 30, 45, 60].contains(_agenda[i].minutes) ? _agenda[i].minutes : 0,
                    underline: const SizedBox.shrink(),
                    items: [0, 5, 10, 15, 20, 30, 45, 60]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? '— min' : '$v min')))
                        .toList(),
                    onChanged: (v) => setState(() => _agenda[i].minutes = v ?? 0),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: i == 0 ? null : () => setState(() => _agenda.insert(i - 1, _agenda.removeAt(i))),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Remove topic',
                    onPressed: () => setState(() {
                      final a = _agenda.removeAt(i);
                      _agendaText.remove(a)?.dispose();
                      _agendaOwner.remove(a)?.dispose();
                    }),
                    icon: Icon(Icons.close, size: 18, color: c.muted),
                  ),
                ]),
              ),

            const SizedBox(height: 20),
            SectionLabel(
              'Before the meeting · ${_prep.length}',
              trailing: TextButton.icon(
                onPressed: () => setState(() {
                  final a = ActionItem(text: '', due: _start.subtract(const Duration(days: 1)));
                  _prep.add(a);
                  _prepText[a] = TextEditingController();
                  _prepOwner[a] = TextEditingController();
                }),
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Add task'),
              ),
            ),
            const SizedBox(height: 4),
            Text('What each trade must have done before they come (e.g. upload the latest model, answer open items).',
                style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 6),
            for (final a in List.of(_prep))
              Container(
                key: ObjectKey(a),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Column(children: [
                  Row(children: [
                    Checkbox(value: a.done, onChanged: (v) => setState(() => a.done = v ?? false)),
                    Expanded(child: TextField(controller: _prepText[a], decoration: const InputDecoration(hintText: 'Task', isDense: true))),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        _prep.remove(a);
                        _prepText.remove(a)?.dispose();
                        _prepOwner.remove(a)?.dispose();
                      }),
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 48, right: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _prepOwner[a],
                          decoration: InputDecoration(
                            hintText: 'Who',
                            isDense: true,
                            suffixIcon: _ownerMenu(['All trades', ...owners], (v) => setState(() => _prepOwner[a]!.text = v)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: a.due ?? now,
                            firstDate: DateTime(now.year - 2),
                            lastDate: DateTime(now.year + 3),
                          );
                          if (d != null) setState(() => a.due = d);
                        },
                        icon: const Icon(Icons.event_outlined, size: 16),
                        label: Text(a.due == null ? 'By date' : shortDate(a.due!)),
                      ),
                    ]),
                  ),
                ]),
              ),

            const SizedBox(height: 20),
            SectionLabel('Attendees · ${_attendees.where((a) => a.present).length} present of ${_attendees.length}', trailing: Wrap(spacing: 4, children: [
              TextButton.icon(onPressed: _addFromTeam, icon: const Icon(Icons.group_add_outlined, size: 18), label: const Text('From team')),
              TextButton.icon(onPressed: _addGuest, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Guest')),
            ])),
            const SizedBox(height: 6),
            if (_attendees.isEmpty) Text('Nobody added yet.', style: TextStyle(color: c.muted)),
            for (final a in List.of(_attendees))
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
                child: Row(children: [
                  Checkbox(value: a.present, onChanged: (v) => setState(() => a.present = v ?? true)),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '   ${[a.company, a.role].where((x) => x.isNotEmpty).join(' · ')}', style: TextStyle(fontSize: 13, color: c.muted)),
                    ])),
                  ),
                  Text(a.present ? 'Present' : 'Absent', style: TextStyle(fontSize: 12.5, color: a.present ? c.ink2 : c.muted)),
                  IconButton(tooltip: 'Remove', onPressed: () => setState(() => _attendees.remove(a)), icon: Icon(Icons.close, size: 18, color: c.muted)),
                ]),
              ),

            const SizedBox(height: 20),
            const SectionLabel('Summary / minutes'),
            const SizedBox(height: 6),
            TextField(
              controller: _summary,
              minLines: 5,
              maxLines: 16,
              decoration: const InputDecoration(hintText: 'Main points, decisions and anything everyone needs to know.'),
            ),

            const SizedBox(height: 20),
            SectionLabel('Items discussed · ${_items.length}',
                trailing: TextButton.icon(onPressed: _addItems, icon: const Icon(Icons.playlist_add, size: 18), label: const Text('Add items'))),
            const SizedBox(height: 6),
            if (_items.isEmpty)
              Text('Add the open items to review. You can pick them by trade, level or priority.', style: TextStyle(color: c.muted)),
            for (final it in List.of(_items))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    ItemNumber(it.number, size: 15),
                    const SizedBox(width: 8),
                    Expanded(child: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(
                      tooltip: 'Remove from meeting',
                      onPressed: () => setState(() {
                        _items.remove(it);
                        _notes.remove(it)?.dispose();
                      }),
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                    ),
                  ]),
                  Text('${ItemStatus.fromDb(it.status).label} · Ball: ${it.ball}', style: TextStyle(fontSize: 12.5, color: c.muted)),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextField(
                      controller: _notes[it],
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(hintText: 'What was discussed or decided', isDense: true),
                    ),
                  ),
                ]),
              ),

            const SizedBox(height: 20),
            SectionLabel('Action items · ${_actions.length}',
                trailing: TextButton.icon(onPressed: _addAction, icon: const Icon(Icons.add_task, size: 18), label: const Text('Add action'))),
            const SizedBox(height: 6),
            if (_actions.isEmpty) Text('Who does what, by when.', style: TextStyle(color: c.muted)),
            for (final a in List.of(_actions))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Column(children: [
                  Row(children: [
                    Checkbox(value: a.done, onChanged: (v) => setState(() => a.done = v ?? false)),
                    Expanded(child: TextField(controller: _actionText[a], decoration: const InputDecoration(hintText: 'Action', isDense: true))),
                    IconButton(
                      tooltip: 'Remove action',
                      onPressed: () => setState(() {
                        _actions.remove(a);
                        _actionText.remove(a)?.dispose();
                        _actionOwner.remove(a)?.dispose();
                      }),
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 48, right: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _actionOwner[a],
                          decoration: InputDecoration(
                            hintText: 'Owner',
                            isDense: true,
                            suffixIcon: PopupMenuButton<String>(
                              tooltip: 'Pick owner',
                              icon: const Icon(Icons.arrow_drop_down),
                              onSelected: (v) => setState(() => _actionOwner[a]!.text = v),
                              itemBuilder: (_) => owners.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: a.due ?? now,
                            firstDate: DateTime(now.year - 2),
                            lastDate: DateTime(now.year + 3),
                          );
                          if (d != null) setState(() => a.due = d);
                        },
                        icon: const Icon(Icons.event_outlined, size: 16),
                        label: Text(a.due == null ? 'Due date' : shortDate(a.due!)),
                      ),
                    ]),
                  ),
                ]),
              ),

            const SizedBox(height: 20),
            labeled(
              'Next meeting',
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await _pickDateTime(_next ?? _start.add(const Duration(days: 7)));
                      if (d != null) setState(() => _next = d);
                    },
                    icon: const Icon(Icons.event_repeat, size: 18),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_next == null ? 'Not set' : '${weekdayDate(_next!)} · ${timeText(_next!)}'),
                    ),
                  ),
                ),
                if (_next != null) IconButton(tooltip: 'Clear', onPressed: () => setState(() => _next = null), icon: const Icon(Icons.close)),
              ]),
              hint: 'shown in the minutes',
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
        child: Row(children: [
          Expanded(
            child: _error == null
                ? const SizedBox.shrink()
                : Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
          ),
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(m == null ? 'Create Meeting' : 'Save Minutes'),
          ),
        ]),
      ),
    ]);
  }
}

/// Pick items for a meeting agenda: open items, filtered by trade, level or priority.
class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.already});
  final Set<String> already;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String? _trade;
  String? _level;
  Priority? _priority;
  bool _includeClosed = false;
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final list = s.items.where((i) {
      if (widget.already.contains(i.id)) return false;
      if (!_includeClosed && !i.status.isActive) return false;
      if (_trade != null && !i.tradeIds.contains(_trade) && !i.bicTradeIds.contains(_trade)) return false;
      if (_level != null && i.level != _level) return false;
      if (_priority != null && i.priority != _priority) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final p = a.priority.index.compareTo(b.priority.index);
        return p != 0 ? p : a.number.compareTo(b.number);
      });

    DropdownButton<T> drop<T>(T value, List<(T, String)> options, ValueChanged<T> on) => DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          items: options.map((o) => DropdownMenuItem<T>(value: o.$1, child: Text(o.$2))).toList(),
          onChanged: (v) => on(v as T),
        );

    return AlertDialog(
      title: const Text('Add items to the meeting'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            drop<String?>(_trade, [(null, 'All trades'), ...s.trades.map((t) => (t.id, t.name))], (v) => setState(() => _trade = v)),
            drop<String?>(_level, [(null, 'All levels'), ...s.knownLevels.map((l) => (l, l))], (v) => setState(() => _level = v)),
            drop<Priority?>(_priority, [(null, 'Any priority'), ...Priority.values.map((p) => (p, p.label))], (v) => setState(() => _priority = v)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: _includeClosed, onChanged: (v) => setState(() => _includeClosed = v ?? false)),
              const Text('Include closed'),
            ]),
          ]),
          Row(children: [
            Text('${list.length} items', style: TextStyle(color: c.muted)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _picked.addAll(list.map((i) => i.id))), child: const Text('Select all shown')),
            TextButton(onPressed: () => setState(_picked.clear), child: const Text('Clear')),
          ]),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No items match.', style: TextStyle(color: c.muted)))
                : ListView(children: [
                    for (final i in list)
                      CheckboxListTile(
                        value: _picked.contains(i.id),
                        onChanged: (v) => setState(() => v == true ? _picked.add(i.id) : _picked.remove(i.id)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: Row(children: [
                          ItemNumber(i.number, size: 14),
                          const SizedBox(width: 8),
                          PriorityBadge(i.priority),
                          const SizedBox(width: 8),
                          Expanded(child: Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                        subtitle: Text([i.locationText, 'Ball: ${s.bicNames(i.bicTradeIds)}'].where((x) => x.isNotEmpty).join(' · ')),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, s.items.where((i) => _picked.contains(i.id)).toList()),
          child: Text('Add ${_picked.length} ${_picked.length == 1 ? 'item' : 'items'}'),
        ),
      ],
    );
  }
}
