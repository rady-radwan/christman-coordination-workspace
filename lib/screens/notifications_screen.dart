import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/update_widgets.dart';
import 'item_detail.dart';

/// The bell: new items, ball-in-court changes, responses, replies, announcements and sign-ups.
/// New ones are bright; ones already seen are dimmed. Any of them can be deleted.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final list = s.notifications;
    final unread = list.where((n) => !n.isRead).toList();
    final read = list.where((n) => n.isRead).toList();
    final wide = isWide(context);

    Future<void> openOne(AppNotification n) async {
      await s.openNotification(n);
      if (!wide && n.itemId != null && s.itemById(n.itemId) != null && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: n.itemId!)));
      }
    }

    Future<void> delete(Iterable<AppNotification> items) async {
      try {
        await s.deleteNotifications(items);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Widget tile(AppNotification n) {
      final dim = n.isRead;
      final card = Material(
        color: dim ? c.surface : c.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: dim ? c.line : c.accent.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openOne(n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(n.icon, color: dim ? c.muted : c.accentText)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title, style: TextStyle(fontWeight: dim ? FontWeight.w500 : FontWeight.w800, fontSize: 14, color: dim ? c.ink2 : c.ink)),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: dim ? c.muted : c.ink2)),
                  ],
                  const SizedBox(height: 2),
                  Text(agoText(n.createdAt), style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
              if (!dim)
                IconButton(
                  tooltip: 'Mark as read',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => s.markRead([n]),
                  icon: Icon(Icons.done, size: 19, color: c.muted),
                ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: () => delete([n]),
                icon: Icon(Icons.close, size: 19, color: c.muted),
              ),
            ]),
          ),
        ),
      );
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Dismissible(
              key: ValueKey('n${n.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: const Color(0xFFB3261E), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) => delete([n]),
              child: Opacity(opacity: dim ? 0.6 : 1, child: card),
            ),
          ),
        ),
      );
    }

    Widget heading(String text, {Widget? action}) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 0, 6),
              child: Row(children: [
                Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.muted))),
                if (action != null) action,
              ]),
            ),
          ),
        );

    return Column(children: [
      PageHeader(
        title: 'Notifications',
        subtitle: s.unreadCount == 0 ? 'All caught up' : '${s.unreadCount} new',
        actions: [
          if (s.unreadCount > 0)
            TextButton.icon(onPressed: () => s.markAllRead(), icon: const Icon(Icons.done_all, size: 18), label: Text(wide ? 'Mark all read' : 'Read all')),
          if (list.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Delete…',
              icon: const Icon(Icons.delete_sweep_outlined),
              onSelected: (v) async {
                if (v == 'read') {
                  await delete(read);
                } else if (v == 'all') {
                  if (await confirm(context, 'Delete all notifications?', 'This only clears your own list.', ok: 'Delete all', danger: true)) {
                    await delete(list);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'read', enabled: read.isNotEmpty, child: Text('Delete read ones (${read.length})')),
                PopupMenuItem(value: 'all', child: Text('Delete all (${list.length})')),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (s.update != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: const Padding(padding: EdgeInsets.only(bottom: 10), child: UpdateNotice()),
                ),
              ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyState(
                  icon: Icons.notifications_none,
                  title: 'No notifications',
                  body: 'You hear about new items for your trade, the ball coming to you, responses, replies and announcements here.',
                ),
              ),
            if (unread.isNotEmpty) heading('NEW'),
            for (final n in unread) tile(n),
            if (read.isNotEmpty)
              heading(
                'EARLIER',
                action: TextButton(onPressed: () => delete(read), child: const Text('Delete these')),
              ),
            for (final n in read) tile(n),
          ],
        ),
      ),
    ]);
  }
}

/// Title row used at the top of the Notifications, Team, Setup and Settings pages.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final s = context.watch<AppState>();
    final wide = isWide(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 14 : 12, wide ? 20 : 8, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(subtitle ?? (s.project?.name ?? ''), style: TextStyle(fontSize: 12, color: c.muted)),
            Text(title, style: condensed(wide ? 26 : 24, color: c.ink)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}
