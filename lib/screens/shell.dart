import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/update_widgets.dart';
import 'item_detail.dart';
import 'item_form.dart';
import 'items_screen.dart';
import 'meetings_screen.dart';
import 'announcements_screen.dart';
import 'bep_screen.dart';
import 'clash_reports_screen.dart';
import 'schedule_screen.dart';
import 'notifications_screen.dart';
import 'project_setup_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';

/// Windows: dark sidebar, list panel and details. Phone: bottom tabs.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => UpdatePrompt(child: isWide(context) ? const _WideShell() : const _PhoneShell());
}

// ===================================================================== Windows

class _WideShell extends StatelessWidget {
  const _WideShell();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final body = switch (s.section) {
      Section.ballInCourt || Section.allItems => const _ItemsWorkspace(),
      Section.meetings => const MeetingsScreen(),
      Section.schedule => const ScheduleScreen(),
      Section.bep => const BepScreen(),
      Section.clashReports => const ClashReportsScreen(),
      Section.announcements => const AnnouncementsScreen(),
      Section.notifications => const NotificationsScreen(),
      Section.team => const TeamScreen(),
      Section.setup => const ProjectSetupScreen(),
      Section.settings || Section.more => const SettingsScreen(),
    };
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(children: [
        const _Sidebar(),
        Expanded(child: Column(children: [const UpdateBanner(), Expanded(child: body)])),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final p = s.project!;
    Widget item(Section section, IconData icon, String label, {int badge = 0, bool hot = false}) {
      final on = s.section == section;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: on ? c.sideSel.withValues(alpha: 0.26) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => s.open(section),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(icon, size: 20, color: on ? c.sideAccent : c.sideMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 14, color: c.sideInk, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: hot ? c.accent : c.sideInk.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$badge',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hot ? c.accentInk : c.sideMuted)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    final scale = s.appearance.textScale;
    return Container(
      width: 248 * (scale > 1 ? scale.clamp(1.0, 1.25).toDouble() : 1.0),
      color: c.side,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BrandLogo(height: 18, onDark: c.sideIsDark),
            const SizedBox(height: 8),
            AppWordmark(size: 15, color: c.sideAccent),
          ]),
        ),
        const SizedBox(height: 18),
        Material(
          color: c.sideInk.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.sideLine)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showProjectPicker(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(p.code, style: condensed(15, color: c.accentInk)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PROJECT', style: TextStyle(fontSize: 11, letterSpacing: 0.9, color: c.sideMuted)),
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.sideInk)),
                  ]),
                ),
                Icon(Icons.unfold_more, size: 18, color: c.sideMuted),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (s.myRole != Role.viewer)
          item(Section.ballInCourt, Icons.adjust, 'My Ball in Court', badge: s.ballInCourtItems.length, hot: true),
        item(Section.allItems, Icons.format_list_bulleted, 'All Items', badge: s.openCount),
        item(Section.meetings, Icons.groups_2_outlined, 'Meetings', badge: s.meetings.where((m) => m.isUpcoming).length),
        item(Section.schedule, Icons.view_timeline_outlined, 'Schedule'),
        item(Section.bep, Icons.menu_book_outlined, 'BEP'),
        item(Section.clashReports, Icons.table_view_outlined, 'Clash Reports'),
        item(Section.announcements, Icons.campaign_outlined, 'Announcements', badge: s.newAnnouncements, hot: true),
        item(Section.notifications, Icons.notifications_none, 'Notifications', badge: s.unreadCount, hot: true),
        item(Section.team, Icons.groups_outlined, 'Team', badge: s.isAdmin ? s.pendingPeople.length + s.invites.where((i) => i.status == 'suggested').length : 0, hot: true),
        if (s.isAdmin) item(Section.setup, Icons.tune, 'Project Setup'),
        const Spacer(),
        Container(height: 1, color: c.sideLine),
        const SizedBox(height: 8),
        item(Section.settings, Icons.settings_outlined, 'Settings'),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.sideSel.withValues(alpha: 0.3), shape: BoxShape.circle),
              child: Text(s.me?.initials ?? '?',
                  style: TextStyle(color: c.sideAccent, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.me?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.sideInk)),
                Text(_roleLine(s),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.sideMuted)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

String _roleLine(AppState s) {
  final r = s.myRole;
  final trade = s.myTrade;
  if (r.isTrade && trade != null) return '${trade.name} · ${r.label}';
  final company = s.me?.company ?? '';
  return [company, r.label].where((x) => x.isNotEmpty).join(' · ');
}

/// Top bar + list panel + details, for My Ball in Court and All Items.
class _ItemsWorkspace extends StatelessWidget {
  const _ItemsWorkspace();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final ball = s.section == Section.ballInCourt;
    return Column(children: [
      _TopBar(title: ball ? 'My Ball in Court' : 'Coordination Items'),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.panel, border: Border(right: BorderSide(color: c.line))),
              child: ItemListPanel(ballInCourt: ball),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.surface,
              child: s.selectedItem == null
                  ? EmptyState(
                      icon: Icons.touch_app_outlined,
                      title: 'Pick an item',
                      body: s.items.isEmpty
                          ? (s.canCreateItems ? 'No items yet. Click New Item to raise the first one.' : 'No items on this project yet.')
                          : 'Select an item on the left to see its details and discussion.',
                    )
                  : ItemDetail(key: ValueKey(s.selectedItemId), itemId: s.selectedItemId!),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s.project?.name ?? '', style: TextStyle(fontSize: 12, color: c.muted)),
          Text(title, style: condensed(26, color: c.ink)),
        ]),
        const SizedBox(width: 20),
        // Coordination week, current work, next sign-off, next meeting.
        const Expanded(child: ProjectStatusStrip(compact: true)),
        const SizedBox(width: 12),
        SizedBox(width: 300, child: const SearchBox()),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => s.refresh().catchError((Object e) {
            if (context.mounted) showError(context, e);
          }),
          icon: const Icon(Icons.refresh),
          style: IconButton.styleFrom(side: BorderSide(color: c.line2), minimumSize: const Size(44, 44)),
        ),
        const SizedBox(width: 8),
        _BellButton(onTap: () => s.open(Section.notifications)),
        if (s.canCreateItems) ...[
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => openItemForm(context),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New Item'),
          ),
        ],
      ]),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final n = s.unreadCount;
    return Badge(
      isLabelVisible: n > 0,
      label: Text(n > 99 ? '99+' : '$n'),
      backgroundColor: const Color(0xFFB3261E),
      child: IconButton(
        tooltip: n > 0 ? 'Notifications, $n new' : 'Notifications',
        onPressed: onTap,
        icon: const Icon(Icons.notifications_none),
        style: IconButton.styleFrom(side: BorderSide(color: c.line2), minimumSize: const Size(44, 44)),
      ),
    );
  }
}

// ===================================================================== Phone

class _PhoneShell extends StatelessWidget {
  const _PhoneShell();

  static const _tabs = [Section.ballInCourt, Section.allItems, Section.meetings, Section.notifications, Section.more];

  /// Pages reached from "More".
  static const _morePages = [Section.schedule, Section.bep, Section.clashReports, Section.announcements, Section.team, Section.setup, Section.settings, Section.more];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    var index = _tabs.indexOf(s.section);
    if (index < 0) index = _morePages.contains(s.section) ? 4 : 1;
    final Widget body = switch (s.section) {
      Section.ballInCourt => const _PhoneItems(ballInCourt: true),
      Section.allItems => const _PhoneItems(ballInCourt: false),
      Section.meetings => const MeetingsScreen(),
      Section.notifications => const NotificationsScreen(),
      Section.schedule => const _BackToMore(child: ScheduleScreen()),
      Section.bep => const _BackToMore(child: BepScreen()),
      Section.clashReports => const _BackToMore(child: ClashReportsScreen()),
      Section.announcements => const _BackToMore(child: AnnouncementsScreen()),
      Section.team => const _BackToMore(child: TeamScreen()),
      Section.setup => const _BackToMore(child: ProjectSetupScreen()),
      Section.settings => const _BackToMore(child: SettingsScreen()),
      Section.more => const _MorePage(),
    };
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(bottom: false, child: Column(children: [const UpdateBanner(), Expanded(child: body)])),
      floatingActionButton: s.canCreateItems && (index == 0 || index == 1)
          ? FloatingActionButton(
              tooltip: 'New Item',
              backgroundColor: c.accent,
              foregroundColor: c.accentInk,
              onPressed: () => openItemForm(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => s.open(_tabs[i]),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: s.ballInCourtItems.isNotEmpty, label: Text('${s.ballInCourtItems.length}'), child: const Icon(Icons.adjust)),
            label: 'My Ball',
          ),
          const NavigationDestination(icon: Icon(Icons.format_list_bulleted), label: 'Items'),
          const NavigationDestination(icon: Icon(Icons.groups_2_outlined), label: 'Meetings'),
          NavigationDestination(
            icon: Badge(isLabelVisible: s.unreadCount > 0, label: Text('${s.unreadCount}'), child: const Icon(Icons.notifications_none)),
            label: 'Alerts',
          ),
          NavigationDestination(icon: Badge(isLabelVisible: s.newAnnouncements > 0, label: Text('${s.newAnnouncements}'), child: const Icon(Icons.more_horiz)), label: 'More'),
        ],
      ),
    );
  }
}

/// Phone "More" tab: Schedule, Team, Project Setup, Settings.
class _MorePage extends StatelessWidget {
  const _MorePage();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    Widget tile(Section to, IconData icon, String title, String sub, {int badge = 0}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Icon(icon, color: c.accentText),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sub),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (badge > 0) Badge(label: Text('$badge')),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => s.open(to),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      children: [
        Text('More', style: condensed(28, color: c.ink)),
        const SizedBox(height: 12),
        tile(Section.schedule, Icons.view_timeline_outlined, 'Schedule', 'Coordination dates, sign-offs, model due dates'),
        tile(Section.bep, Icons.menu_book_outlined, 'BEP', 'BIM Execution Plan: rules, naming, levels, files'),
        tile(Section.clashReports, Icons.table_view_outlined, 'Clash Reports', 'Excel clash reports to view and download'),
        tile(Section.announcements, Icons.campaign_outlined, 'Announcements', 'Messages from the Christman VDC team', badge: s.newAnnouncements),
        tile(Section.team, Icons.groups_outlined, 'Team', 'People on ${s.project?.code ?? 'this project'}',
            badge: s.isAdmin ? s.pendingPeople.length + s.invites.where((i) => i.status == 'suggested').length : 0),
        if (s.isAdmin) tile(Section.setup, Icons.tune, 'Project Setup', 'Trades, item types, levels, dates'),
        tile(Section.settings, Icons.settings_outlined, 'Settings', 'Appearance, font, text size, account'),
      ],
    );
  }
}

/// A page opened from "More", with a way back.
class _BackToMore extends StatelessWidget {
  const _BackToMore({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.read<AppState>().open(Section.more),
            icon: const Icon(Icons.chevron_left),
            label: const Text('More'),
          ),
        ),
        Expanded(child: child),
      ]);
}

class _PhoneItems extends StatelessWidget {
  const _PhoneItems({required this.ballInCourt});
  final bool ballInCourt;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        decoration: BoxDecoration(color: c.head, border: Border(bottom: BorderSide(color: c.line))),
        child: Column(children: [
          Row(children: [
            const BrandLogo(height: 15),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => s.refresh().catchError((Object e) {
                if (context.mounted) showError(context, e);
              }),
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 6),
          Material(
            color: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.line2)),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showProjectPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Text(s.project?.code ?? '', style: condensed(16, color: c.accentText)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.project?.name ?? '',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  const Icon(Icons.unfold_more, size: 18),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const ProjectStatusStrip(compact: true),
        ]),
      ),
      Expanded(
        child: ItemListPanel(
          ballInCourt: ballInCourt,
          showTitle: true,
          onOpen: (item) {
            s.selectItem(item.id);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: item.id)));
          },
        ),
      ),
    ]);
  }
}
