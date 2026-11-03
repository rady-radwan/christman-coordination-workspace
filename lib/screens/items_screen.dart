import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';

/// Search by number, title, clash ID or grid.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key});

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _ctrl = TextEditingController(text: context.read<AppState>().search);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.search.isEmpty && _ctrl.text.isNotEmpty) _ctrl.clear();
    return TextField(
      controller: _ctrl,
      onChanged: (v) => s.setView(() => s.search = v),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Search number, title, clash ID or grid',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  s.setView(() => s.search = '');
                },
              ),
      ),
    );
  }
}

/// The middle list (Windows) or the whole items page (phone).
class ItemListPanel extends StatelessWidget {
  const ItemListPanel({super.key, required this.ballInCourt, this.showTitle = false, this.onOpen});
  final bool ballInCourt;
  final bool showTitle;
  final void Function(Item item)? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final q = s.search.trim().toLowerCase();
    final list = ballInCourt
        ? s.ballInCourtItems.where((i) => q.isEmpty || i.searchText.contains(q)).toList()
        : s.filteredItems;

    void open(Item item) {
      if (onOpen != null) {
        onOpen!(item);
      } else {
        s.selectItem(item.id);
      }
    }

    final header = <Widget>[
      if (showTitle) ...[
        Text(ballInCourt ? 'My Ball in Court' : 'All Items', style: condensed(28, color: c.ink)),
        const SizedBox(height: 10),
        const SearchBox(),
        const SizedBox(height: 12),
      ],
      if (ballInCourt) _BallHeader(count: list.length, overdue: list.where((i) => i.isOverdue).length) else ...[
        _ModeTabs(),
        const SizedBox(height: 10),
        const _FilterRow(),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              '${list.length} ${list.length == 1 ? 'item' : 'items'}'
              '${s.filterStatus == 'active' ? ' not closed' : ''} · ${list.where((i) => i.isOverdue).length} overdue',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
          _SortMenu(),
        ]),
      ],
      const SizedBox(height: 8),
    ];

    final rows = <Widget>[];
    if (s.loadingProject && s.items.isEmpty) {
      rows.add(const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
    } else if (list.isEmpty) {
      rows.add(_emptyFor(context, s));
    } else if (!ballInCourt && s.listMode == ListMode.byDate) {
      final g = DateGroups(DateTime.now());
      for (final group in DateGroup.values) {
        final inGroup = list.where((i) => g.groupOf(i.createdAt) == group).toList();
        if (inGroup.isEmpty) continue;
        rows.add(_GroupHeader('${DateGroups.label(group)} · ${inGroup.length}'));
        rows.addAll(inGroup.map((i) => ItemCard(item: i, selected: i.id == s.selectedItemId, onTap: () => open(i))));
      }
    } else if (!ballInCourt && s.listMode == ListMode.byArea) {
      final keys = <String>{};
      for (final i in list) {
        keys.add(_areaKey(i));
      }
      final sorted = keys.toList()..sort((a, b) => a == 'No level' ? 1 : (b == 'No level' ? -1 : a.compareTo(b)));
      for (final k in sorted) {
        final inGroup = list.where((i) => _areaKey(i) == k).toList();
        rows.add(_GroupHeader('$k · ${inGroup.length}'));
        rows.addAll(inGroup.map((i) => ItemCard(item: i, selected: i.id == s.selectedItemId, onTap: () => open(i))));
      }
    } else {
      rows.addAll(list.map((i) => ItemCard(item: i, selected: i.id == s.selectedItemId, onTap: () => open(i))));
    }

    return RefreshIndicator(
      onRefresh: () => s.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [...header, ...rows],
      ),
    );
  }

  static String _areaKey(Item i) {
    if (i.level.isEmpty) return 'No level';
    return [i.building, i.level, i.zone].where((x) => x.isNotEmpty).join(' · ');
  }

  Widget _emptyFor(BuildContext context, AppState s) {
    if (ballInCourt) {
      if (s.myRole == Role.viewer) {
        return const EmptyState(
            icon: Icons.visibility_outlined, title: 'Read-only access', body: 'You can view every item under All Items.');
      }
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nothing waiting on you',
        body: s.myRole.isTrade
            ? 'No item has the ball in ${s.myTrade?.name ?? 'your trade'}\'s court right now.'
            : 'No item is waiting on the Christman VDC team right now.',
      );
    }
    if (s.items.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No items yet',
        body: s.canCreateItems ? 'Raise the first coordination item with New Item.' : 'Items raised by the coordinator show here.',
      );
    }
    return EmptyState(
      icon: Icons.filter_alt_off_outlined,
      title: 'No items match',
      body: 'Try another search or clear the filters.',
      action: OutlinedButton(onPressed: s.clearFilters, child: const Text('Clear filters')),
    );
  }
}

class _BallHeader extends StatelessWidget {
  const _BallHeader({required this.count, required this.overdue});
  final int count;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final who = s.myRole.isTrade ? (s.myTrade?.label ?? 'Your trade') : 'Christman VDC';
    return Panel(
      highlight: true,
      child: Row(children: [
        Icon(Icons.adjust, color: c.accentText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text('$count to act on now', style: TextStyle(fontSize: 13, color: c.ink2)),
          ]),
        ),
        if (overdue > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: c.urgentBg, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              StatusDot(c.urgentText, size: 8),
              const SizedBox(width: 6),
              Text('$overdue overdue', style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
      ]),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: SectionLabel(text));
}

class _ModeTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return SegmentedButton<ListMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: ListMode.list, label: Text('All'), icon: Icon(Icons.view_list_outlined, size: 18)),
        ButtonSegment(value: ListMode.byDate, label: Text('By Date'), icon: Icon(Icons.event_outlined, size: 18)),
        ButtonSegment(value: ListMode.byArea, label: Text('By Area'), icon: Icon(Icons.layers_outlined, size: 18)),
      ],
      selected: {s.listMode},
      onSelectionChanged: (v) => s.setView(() => s.listMode = v.first),
    );
  }
}

class _SortMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return PopupMenuButton<SortBy>(
      tooltip: 'Sort',
      initialValue: s.sortBy,
      onSelected: (v) => s.setView(() => s.sortBy = v),
      itemBuilder: (_) => SortBy.values.map((v) => PopupMenuItem(value: v, child: Text(v.label))).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: c.muted), children: [
          const TextSpan(text: 'Sort: '),
          TextSpan(text: s.sortBy.label, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
          const WidgetSpan(child: Icon(Icons.arrow_drop_down, size: 18)),
        ])),
      ),
    );
  }
}

/// A menu choice that can carry a null value ("All trades").
class _Opt<T> {
  const _Opt(this.value, this.label);
  final T value;
  final String label;
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({required this.label, required this.active, required this.options, required this.onSelected, required this.current});
  final String label;
  final bool active;
  final List<_Opt<T>> options;
  final T current;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Opt<T>>(
      tooltip: label,
      onSelected: (o) => onSelected(o.value),
      itemBuilder: (_) => options
          .map((o) => PopupMenuItem<_Opt<T>>(
                value: o,
                child: Row(children: [
                  SizedBox(width: 26, child: o.value == current ? const Icon(Icons.check, size: 18) : null),
                  Flexible(child: Text(o.label)),
                ]),
              ))
          .toList(),
      child: IgnorePointer(child: CwChip(label: label, selected: active, onTap: () {}, trailing: Icons.arrow_drop_down)),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final trade = s.tradeById(s.filterTradeId);
    final type = s.typeById(s.filterTypeId);
    final statusLabel = switch (s.filterStatus) {
      'active' => 'Status: Not closed',
      'all' => 'Status: All',
      _ => 'Status: ${ItemStatus.fromDb(s.filterStatus).shortLabel}',
    };
    return Wrap(spacing: 6, runSpacing: 6, children: [
      _FilterMenu<String?>(
        label: trade == null ? 'Trade' : 'Trade: ${trade.code}',
        active: trade != null,
        current: s.filterTradeId,
        options: [const _Opt(null, 'All trades'), ...s.trades.map((t) => _Opt<String?>(t.id, t.label))],
        onSelected: (v) => s.setView(() => s.filterTradeId = v),
      ),
      _FilterMenu<String?>(
        label: type == null ? 'Type' : 'Type: ${type.code}',
        active: type != null,
        current: s.filterTypeId,
        options: [const _Opt(null, 'All types'), ...s.types.map((t) => _Opt<String?>(t.id, '${t.name} (${t.code})'))],
        onSelected: (v) => s.setView(() => s.filterTypeId = v),
      ),
      _FilterMenu<String>(
        label: statusLabel,
        active: s.filterStatus != 'active',
        current: s.filterStatus,
        options: [
          const _Opt('active', 'Not closed'),
          const _Opt('all', 'All, including closed'),
          ...ItemStatus.values.map((v) => _Opt(v.db, v.label)),
        ],
        onSelected: (v) => s.setView(() => s.filterStatus = v),
      ),
      _FilterMenu<String?>(
        label: s.filterLevel == null ? 'Level' : 'Level: ${s.filterLevel}',
        active: s.filterLevel != null,
        current: s.filterLevel,
        options: [const _Opt(null, 'All levels'), ...s.knownLevels.map((l) => _Opt<String?>(l, l))],
        onSelected: (v) => s.setView(() => s.filterLevel = v),
      ),
      _FilterMenu<Priority?>(
        label: s.filterPriority == null ? 'Priority' : s.filterPriority!.label,
        active: s.filterPriority != null,
        current: s.filterPriority,
        options: [const _Opt(null, 'Any priority'), ...Priority.values.map((p) => _Opt<Priority?>(p, p.label))],
        onSelected: (v) => s.setView(() => s.filterPriority = v),
      ),
      _FilterMenu<DueFilter>(
        label: s.filterDue == DueFilter.any ? 'Due' : s.filterDue.label,
        active: s.filterDue != DueFilter.any,
        current: s.filterDue,
        options: DueFilter.values.map((d) => _Opt(d, d.label)).toList(),
        onSelected: (v) => s.setView(() => s.filterDue = v),
      ),
      if (s.filterCount > 0)
        TextButton.icon(onPressed: s.clearFilters, icon: const Icon(Icons.close, size: 16), label: const Text('Clear')),
    ]);
  }
}

/// One item in a list: number, priority, status, title, type, location, ball in court, due.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap, this.selected = false});
  final Item item;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final type = s.typeById(item.typeId);
    final bic = s.tradeById(item.bicTradeId);
    final closed = !item.status.isActive;
    // Open items get a light tint of their priority color; closed ones stay plain.
    final look = priorityLook(item.priority, c);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: closed ? 0.62 : 1,
        child: Material(
          color: closed ? c.card : look.tint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? c.accent : (closed ? c.line : look.border), width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(selected ? 11 : 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ItemNumber(item.number),
                  const SizedBox(width: 8),
                  PriorityBadge(item.priority),
                  const Spacer(),
                  Flexible(child: StatusBadge(item.status, short: true)),
                ]),
                const SizedBox(height: 6),
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink, height: 1.3)),
                const SizedBox(height: 4),
                Text(
                  [type?.name ?? '', item.locationText].where((x) => x.isNotEmpty).join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  if (item.photos.isNotEmpty) ...[
                    Icon(Icons.photo_camera_outlined, size: 15, color: c.muted),
                    const SizedBox(width: 3),
                    Text('${item.photos.length}', style: TextStyle(fontSize: 13, color: c.muted)),
                    const SizedBox(width: 10),
                  ],
                  Icon(Icons.adjust, size: 15, color: c.ink2),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: bic?.name ?? 'Christman VDC', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink2)),
                        if ((bic?.company ?? '').isNotEmpty) TextSpan(text: '  ${bic!.company}', style: TextStyle(color: c.muted)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DueLabel(item),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
