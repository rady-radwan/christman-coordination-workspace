import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';

/// Color for each kind of schedule task.
Color taskColor(TaskKind k, CwColors c) => switch (k) {
      TaskKind.coordination => c.dark ? const Color(0xFF5B9BEA) : const Color(0xFF1F6FD1),
      TaskKind.signOff => c.dark ? const Color(0xFF5FBF83) : const Color(0xFF2E7D4F),
      TaskKind.modelDue => c.dark ? const Color(0xFFB391E8) : const Color(0xFF6B3FA0),
      TaskKind.milestone => c.dark ? const Color(0xFFEF9154) : const Color(0xFFC2410C),
      TaskKind.other => c.dark ? const Color(0xFF9AA0A6) : const Color(0xFF5F6670),
    };

enum _View { timeline, list }

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  _View _view = _View.timeline;
  TaskKind? _kind;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final tasks = s.schedule.where((t) => _kind == null || t.kind == _kind).toList()
      ..sort((a, b) {
        final d = a.start.compareTo(b.start);
        return d != 0 ? d : a.sort.compareTo(b.sort);
      });
    return Column(children: [
      PageHeader(
        title: 'Coordination Schedule',
        actions: [
          if (s.canEditSchedule)
            FilledButton.icon(
              onPressed: () => openTaskForm(context),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Task'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            const ProjectStatusStrip(wrap: true),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<_View>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _View.timeline, label: Text('Timeline'), icon: Icon(Icons.view_timeline_outlined, size: 18)),
                  ButtonSegment(value: _View.list, label: Text('List'), icon: Icon(Icons.view_list_outlined, size: 18)),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
              CwChip(label: 'All', selected: _kind == null, onTap: () => setState(() => _kind = null)),
              for (final k in TaskKind.values)
                CwChip(label: k.label, icon: k.icon, selected: _kind == k, onTap: () => setState(() => _kind = _kind == k ? null : k)),
            ]),
            const SizedBox(height: 14),
            if (s.schedule.isEmpty)
              EmptyState(
                icon: Icons.view_timeline_outlined,
                title: 'No schedule yet',
                body: s.canEditSchedule
                    ? 'Add the coordination work by area, the sign-off dates and the model due dates. '
                        'Everyone on the project sees it here, and the top bar shows the current week and the next sign-off.'
                    : 'The Christman VDC team adds the coordination schedule here.',
                action: s.canEditSchedule
                    ? FilledButton.icon(onPressed: () => openTaskForm(context), icon: const Icon(Icons.add), label: const Text('Add the first task'))
                    : null,
              )
            else if (tasks.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text('Nothing of this kind on the schedule.', style: TextStyle(color: c.muted)))
            else if (_view == _View.timeline)
              _Timeline(tasks: tasks)
            else
              _TaskList(tasks: tasks),
          ],
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ project status

/// "Coordination week 6 of 20 · Now: … · Next sign-off: … · Next meeting: …"
class ProjectStatusStrip extends StatelessWidget {
  const ProjectStatusStrip({super.key, this.wrap = false, this.compact = false});

  /// Wrap onto several lines (pages) instead of one scrolling line (top bar).
  final bool wrap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final today = dayOnly(DateTime.now());
    final chips = <Widget>[];

    Widget chip(IconData icon, String label, String value, {Color? color, VoidCallback? onTap, String? tip}) {
      final col = color ?? c.accentText;
      final body = Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 5 : 7),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: col),
          const SizedBox(width: 7),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$label  ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c.muted)),
            TextSpan(text: value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          ])),
        ]),
      );
      return Tooltip(
        message: tip ?? '',
        child: onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: body),
      );
    }

    void toSchedule() => s.open(Section.schedule);

    final week = s.coordinationWeek;
    if (week != null) {
      final total = s.coordinationWeeks;
      chips.add(chip(Icons.calendar_view_week, 'COORDINATION', total == null ? 'Week $week' : 'Week $week of $total',
          onTap: toSchedule, tip: 'Counted from the coordination start date'));
    }
    final now = s.currentWork;
    if (now.isNotEmpty) {
      final t = now.first;
      final left = t.end.difference(today).inDays;
      chips.add(chip(Icons.layers_outlined, 'NOW', '${t.name}${now.length > 1 ? ' +${now.length - 1}' : ''} · ${left == 0 ? 'ends today' : 'ends in $left ${left == 1 ? 'day' : 'days'}'}',
          color: taskColor(TaskKind.coordination, c), onTap: toSchedule, tip: now.map((x) => '${x.name}: ${shortDate(x.start)} – ${shortDate(x.end)}').join('\n')));
    }
    final so = s.nextSignOff;
    if (so != null) {
      final days = so.end.difference(today).inDays;
      chips.add(chip(Icons.verified_outlined, 'NEXT SIGN-OFF',
          '${so.name} · ${weekdayDate(so.end)} · ${days == 0 ? 'today' : '$days ${days == 1 ? 'day' : 'days'}'}',
          color: days <= 3 ? c.urgentText : taskColor(TaskKind.signOff, c), onTap: toSchedule));
    }
    final md = s.nextModelDue;
    if (md != null && !compact) {
      chips.add(chip(Icons.view_in_ar_outlined, 'MODELS DUE', weekdayDate(md.end), color: taskColor(TaskKind.modelDue, c), onTap: toSchedule));
    }
    final meet = s.nextMeeting;
    if (meet != null) {
      chips.add(chip(Icons.groups_outlined, 'NEXT MEETING', '${weekdayDate(meet.startsAt).split(',').first} ${shortDate(meet.startsAt)} · ${timeText(meet.startsAt)}',
          onTap: () {
        s.selectMeeting(meet.id);
        s.open(Section.meetings);
      }));
    }

    if (chips.isEmpty) {
      if (!s.canEditSchedule) return const SizedBox.shrink();
      return Align(
        alignment: wrap ? Alignment.centerLeft : Alignment.center,
        child: TextButton.icon(
          onPressed: toSchedule,
          icon: const Icon(Icons.view_timeline_outlined, size: 18),
          label: const Text('Add the coordination schedule to see the week and next sign-off here'),
        ),
      );
    }
    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [for (final w in chips) Padding(padding: const EdgeInsets.only(right: 8), child: w)]),
    );
  }
}

// ------------------------------------------------------------------ timeline

class _Timeline extends StatefulWidget {
  const _Timeline({required this.tasks});
  final List<ScheduleTask> tasks;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final _scroll = ScrollController();
  bool _scrolledToToday = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = MediaQuery.sizeOf(context).width >= 700;
      final labelW = wide ? s.view.taskColW.clamp(ViewPrefs.taskColMin, box.maxWidth * 0.5).toDouble() : 150.0;
      final tasks = widget.tasks;
      final today = dayOnly(DateTime.now());
      var first = tasks.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b);
      var last = tasks.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
      if (today.isBefore(first)) first = today;
      if (today.isAfter(last)) last = today;
      first = first.subtract(Duration(days: first.weekday - 1));
      last = last.add(Duration(days: 7 - last.weekday + 7));
      final days = last.difference(first).inDays + 1;
      final barsW = box.maxWidth - labelW - (wide ? 9 : 0) - 2;
      final fitW = (barsW / days).clamp(1.0, ViewPrefs.dayMax).toDouble();
      final fit = s.view.dayW <= 0;
      final dayW = fit ? fitW : s.view.dayW;
      void zoom(double to) => s.setSizes(s.view.copyWith(dayW: to.clamp(ViewPrefs.dayMin, ViewPrefs.dayMax).toDouble()));

      final controls = Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Zoom', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2)),
          IconButton(tooltip: 'Zoom out', onPressed: () => zoom(dayW / 1.25), icon: const Icon(Icons.zoom_out)),
          SizedBox(
            width: 220,
            child: Slider(
              value: dayW.clamp(ViewPrefs.dayMin, ViewPrefs.dayMax).toDouble(),
              min: ViewPrefs.dayMin,
              max: ViewPrefs.dayMax,
              onChanged: zoom,
            ),
          ),
          IconButton(tooltip: 'Zoom in', onPressed: () => zoom(dayW * 1.25), icon: const Icon(Icons.zoom_in)),
          CwChip(label: 'Fit to screen', icon: Icons.fit_screen_outlined, selected: fit, onTap: () => s.setSizes(s.view.copyWith(dayW: 0))),
          CwChip(label: 'Weeks', selected: !fit && (dayW - 20).abs() < 0.5, onTap: () => zoom(20)),
          CwChip(label: 'Months', selected: !fit && (dayW - 6).abs() < 0.5, onTap: () => zoom(6)),
        ]),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        controls,
        _chart(context, s, c, tasks, today, first, last, days, dayW, labelW, wide),
      ]);
    });
  }

  Widget _chart(BuildContext context, AppState s, CwColors c, List<ScheduleTask> tasks, DateTime today, DateTime first, DateTime last, int days,
      double dayW, double labelW, bool wide) {

    const rowH = 46.0;
    const headH = 44.0;
    final width = days * dayW;
    double x(DateTime d) => d.difference(first).inDays * dayW;

    final weeks = <DateTime>[];
    for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 7))) {
      weeks.add(d);
    }
    // When zoomed out, label every 2nd or 4th week so the dates don't overlap.
    final labelEvery = (78 / (dayW * 7)).ceil().clamp(1, 8);
    if (!_scrolledToToday) {
      _scrolledToToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo((x(today) - 200).clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      });
    }
    final start = s.project?.coordinationStart;

    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Task names (fixed)
        Container(
          width: labelW,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
          child: Column(children: [
            Container(
              height: headH,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: c.surface2,
              child: Text('TASK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: c.muted)),
            ),
            for (final t in tasks)
              InkWell(
                onTap: () => _openTask(context, t),
                child: Container(
                  height: rowH,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(children: [
                    Icon(t.kind.icon, size: 16, color: taskColor(t.kind, c)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        if (t.area.isNotEmpty)
                          Text(t.area, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.muted)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        if (wide)
          SizedBox(
            height: headH + rowH * tasks.length,
            child: ResizeHandle(
              onDrag: (dx) => s.setSizes(s.view.copyWith(taskColW: labelW + dx)),
              onReset: () => s.setSizes(s.view.copyWith(taskColW: 280)),
            ),
          ),
        // Bars (scroll sideways)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scroll,
            child: SizedBox(
              width: width,
              height: headH + rowH * tasks.length,
              child: Stack(children: [
                // week columns + header
                for (var i = 0; i < weeks.length; i++) ...[
                  Positioned(
                    left: x(weeks[i]),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: c.line),
                  ),
                  if (i % labelEvery == 0)
                  Positioned(
                    left: x(weeks[i]) + 6,
                    top: 6,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(shortDate(weeks[i]), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.ink2)),
                      if (start != null && !weeks[i].isBefore(start.subtract(Duration(days: start.weekday - 1))))
                        Text('Wk ${weeks[i].difference(start).inDays ~/ 7 + 1}', style: TextStyle(fontSize: 10.5, color: c.muted)),
                    ]),
                  ),
                ],
                Positioned(left: 0, right: 0, top: headH - 1, child: Container(height: 1, color: c.line)),
                for (var r = 0; r < tasks.length; r++)
                  Positioned(left: 0, right: 0, top: headH + rowH * r, child: Container(height: 1, color: c.line.withValues(alpha: 0.6))),
                // today
                Positioned(
                  left: x(today) + dayW / 2 - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: c.urgentText.withValues(alpha: 0.8)),
                ),
                Positioned(
                  left: x(today) + dayW / 2 - 22,
                  top: headH - 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: c.urgentText, borderRadius: BorderRadius.circular(4)),
                    child: Text('TODAY', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: c.surface)),
                  ),
                ),
                // bars
                for (var r = 0; r < tasks.length; r++) _bar(context, tasks[r], r, x, dayW, headH, rowH, today),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bar(BuildContext context, ScheduleTask t, int r, double Function(DateTime) x, double dayW, double headH, double rowH, DateTime today) {
    final c = CwColors.of(context);
    final col = taskColor(t.kind, c);
    final top = headH + rowH * r;
    final late = t.isLate(today);
    final tip = '${t.name}\n${shortDate(t.start)} – ${shortDate(t.end)} (${t.days} ${t.days == 1 ? 'day' : 'days'}) · ${t.percent}% done';
    if (t.isPoint) {
      // One-day sign-offs and milestones: a diamond.
      return Positioned(
        left: x(t.start) + dayW / 2 - 9,
        top: top + rowH / 2 - 9,
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: () => _openTask(context, t),
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: t.percent >= 100 ? col.withValues(alpha: 0.45) : col,
                  border: late ? Border.all(color: c.urgentText, width: 2) : null,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final w = t.days * dayW;
    return Positioned(
      left: x(t.start) + 1,
      top: top + 10,
      child: Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => _openTask(context, t),
          child: Container(
            width: w - 2,
            height: rowH - 20,
            decoration: BoxDecoration(
              color: col.withValues(alpha: c.dark ? 0.28 : 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: late ? c.urgentText : col, width: late ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              FractionallySizedBox(widthFactor: t.percent / 100, child: Container(color: col.withValues(alpha: 0.75))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.percent > 0 ? '${t.percent}%' : '',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.dark ? Colors.white : const Color(0xFF111111)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

void _openTask(BuildContext context, ScheduleTask t) {
  final s = context.read<AppState>();
  if (s.canEditSchedule) {
    openTaskForm(context, task: t);
  } else {
    showDialog<void>(context: context, builder: (_) => _TaskView(task: t));
  }
}

class _TaskView extends StatelessWidget {
  const _TaskView({required this.task});
  final ScheduleTask task;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final t = task;
    return AlertDialog(
      title: Text(t.name),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(t.kind.icon, size: 18, color: taskColor(t.kind, c)),
            const SizedBox(width: 6),
            Text(t.kind.label, style: TextStyle(fontWeight: FontWeight.w700, color: taskColor(t.kind, c))),
            if (t.area.isNotEmpty) Text('  ·  ${t.area}', style: TextStyle(color: c.ink2)),
          ]),
          const SizedBox(height: 10),
          Text('${weekdayDate(t.start)} – ${weekdayDate(t.end)}  (${t.days} ${t.days == 1 ? 'day' : 'days'})'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: t.percent / 100, minHeight: 8, borderRadius: BorderRadius.circular(4), color: taskColor(t.kind, c)),
          const SizedBox(height: 4),
          Text('${t.percent}% done', style: TextStyle(fontSize: 13, color: c.muted)),
          if (t.tradeIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final tr in s.tradesIn(t.tradeIds)) Tag(tr.name)]),
          ],
          if (t.notes.isNotEmpty) ...[const SizedBox(height: 10), Text(t.notes)],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// ------------------------------------------------------------------ list

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});
  final List<ScheduleTask> tasks;

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final late = tasks.where((t) => t.isLate(today)).toList();
    final now = tasks.where((t) => t.isCurrent(today)).toList();
    final next = tasks.where((t) => t.start.isAfter(today) && t.percent < 100).toList();
    final done = tasks.where((t) => t.percent >= 100).toList();
    Widget group(String title, List<ScheduleTask> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionLabel('$title · ${list.length}'),
              const SizedBox(height: 8),
              for (final t in list) _TaskCard(task: t),
            ]),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      group('Behind schedule', late),
      group('Now', now),
      group('Coming up', next),
      group('Done', done),
    ]);
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});
  final ScheduleTask task;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final t = task;
    final col = taskColor(t.kind, c);
    final today = dayOnly(DateTime.now());
    final String when;
    if (t.percent >= 100) {
      when = 'Done';
    } else if (t.isLate(today)) {
      final d = today.difference(t.end).inDays;
      when = '$d ${d == 1 ? 'day' : 'days'} late';
    } else if (t.start.isAfter(today)) {
      final d = t.start.difference(today).inDays;
      when = t.isPoint ? 'In $d ${d == 1 ? 'day' : 'days'}' : 'Starts in $d ${d == 1 ? 'day' : 'days'}';
    } else {
      final d = t.end.difference(today).inDays;
      when = d == 0 ? 'Ends today' : '$d ${d == 1 ? 'day' : 'days'} left';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.isLate(today) ? c.urgentText : c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openTask(context, t),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(t.kind.icon, color: col, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    Text(when,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: t.isLate(today) ? c.urgentText : (t.percent >= 100 ? c.muted : c.ink2))),
                  ]),
                  Text(
                    [t.kind.label, if (t.area.isNotEmpty) t.area, t.isPoint ? weekdayDate(t.start) : '${shortDate(t.start)} – ${shortDate(t.end)} · ${t.days} days']
                        .join('  ·  '),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  if (!t.isPoint || t.percent > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: LinearProgressIndicator(value: t.percent / 100, minHeight: 6, borderRadius: BorderRadius.circular(3), color: col, backgroundColor: c.pill)),
                      const SizedBox(width: 8),
                      Text('${t.percent}%', style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ],
                  if (t.tradeIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final tr in s.tradesIn(t.tradeIds)) Tag(tr.name)]),
                  ],
                  if (t.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(t.notes, style: TextStyle(fontSize: 13, color: c.ink2)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ add / edit task

Future<void> openTaskForm(BuildContext context, {ScheduleTask? task}) => showDialog<void>(
      context: context,
      builder: (_) => _TaskForm(task: task),
    );

class _TaskForm extends StatefulWidget {
  const _TaskForm({this.task});
  final ScheduleTask? task;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  late final AppState s = context.read<AppState>();
  late final ScheduleTask? t = widget.task;
  late final _name = TextEditingController(text: t?.name ?? '');
  late final _area = TextEditingController(text: t?.area ?? '');
  late final _notes = TextEditingController(text: t?.notes ?? '');
  late TaskKind _kind = t?.kind ?? TaskKind.coordination;
  late DateTime _start = t?.start ?? dayOnly(DateTime.now());
  late DateTime _end = t?.end ?? dayOnly(DateTime.now()).add(const Duration(days: 13));
  late int _percent = t?.percent ?? 0;
  late final Set<String> _trades = {...?t?.tradeIds};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 6));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the task a name.');
      return;
    }
    if (_end.isBefore(_start)) {
      setState(() => _error = 'The end date is before the start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await s.saveTask(t, {
        'name': _name.text.trim(),
        'kind': _kind.db,
        'area': _area.text.trim(),
        'start_date': dateToDb(_start),
        'end_date': dateToDb(_end),
        'trade_ids': _trades.toList(),
        'percent': _percent,
        'notes': _notes.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final p = s.project!;
    final areas = <String>{
      for (final b in p.buildings.isEmpty ? [''] : p.buildings)
        for (final l in p.levels) [b, l].where((x) => x.isNotEmpty).join(' · '),
    }.where((x) => x.isNotEmpty).toList();
    final oneDay = _kind == TaskKind.signOff || _kind == TaskKind.milestone || _kind == TaskKind.modelDue;

    return AlertDialog(
      title: Text(t == null ? 'Add schedule task' : 'Edit schedule task'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Kind'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in TaskKind.values)
                CwChip(
                  label: k.label,
                  icon: k.icon,
                  selected: _kind == k,
                  onTap: () => setState(() {
                    _kind = k;
                    if (k == TaskKind.signOff || k == TaskKind.milestone || k == TaskKind.modelDue) _end = _start;
                  }),
                ),
            ]),
            const SizedBox(height: 10),
            const FieldLabel('Name'),
            TextField(
              controller: _name,
              autofocus: t == null,
              decoration: InputDecoration(
                hintText: switch (_kind) {
                  TaskKind.coordination => 'e.g. Level 2 Hospital MEP coordination',
                  TaskKind.signOff => 'e.g. Level 2 Hospital sign-off',
                  TaskKind.modelDue => 'e.g. Weekly model upload',
                  TaskKind.milestone => 'e.g. Start of Level 3 install',
                  TaskKind.other => 'Task name',
                },
              ),
            ),
            const SizedBox(height: 10),
            FieldLabel('Area', hint: areas.isEmpty ? 'building · level · zone' : 'type or pick'),
            Row(children: [
              Expanded(child: TextField(controller: _area, decoration: const InputDecoration(hintText: 'e.g. Hospital · Level 2'))),
              if (areas.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Pick from the project levels',
                  icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                  onSelected: (v) => setState(() => _area.text = v),
                  itemBuilder: (_) => areas.map((a) => PopupMenuItem(value: a, child: Text(a))).toList(),
                ),
            ]),
            const SizedBox(height: 10),
            FieldLabel(oneDay ? 'Date' : 'Dates'),
            Wrap(spacing: 10, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await _pick(_start);
                  if (d == null) return;
                  setState(() {
                    final len = _end.difference(_start);
                    _start = d;
                    _end = oneDay ? d : d.add(len);
                  });
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(oneDay ? weekdayDate(_start) : 'Start: ${weekdayDate(_start)}'),
              ),
              if (!oneDay)
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await _pick(_end);
                    if (d != null) setState(() => _end = d);
                  },
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text('End: ${weekdayDate(_end)}'),
                ),
            ]),
            if (!oneDay)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${_end.difference(_start).inDays + 1} days', style: TextStyle(fontSize: 13, color: c.muted)),
              ),
            const SizedBox(height: 10),
            const FieldLabel('Trades', hint: 'optional'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tr in s.trades)
                CwChip(
                  label: tr.name,
                  selected: _trades.contains(tr.id),
                  onTap: () => setState(() => _trades.contains(tr.id) ? _trades.remove(tr.id) : _trades.add(tr.id)),
                ),
            ]),
            const SizedBox(height: 10),
            FieldLabel('Progress', hint: '$_percent% done'),
            Slider(
              value: _percent.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$_percent%',
              onChanged: (v) => setState(() => _percent = v.round()),
            ),
            const FieldLabel('Notes', hint: 'optional'),
            TextField(controller: _notes, minLines: 2, maxLines: 5),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        if (t != null)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (!await confirm(context, 'Delete "${t!.name}"?', 'It is removed from the schedule for everyone.', ok: 'Delete', danger: true)) {
                      return;
                    }
                    try {
                      await s.deleteTask(t!);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
            child: Text('Delete', style: TextStyle(color: c.urgentText)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(t == null ? 'Add Task' : 'Save')),
      ],
    );
  }
}
