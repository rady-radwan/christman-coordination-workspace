import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import 'item_detail.dart';

/// The bell: new items, ball-in-court changes, responses, replies and sign-ups.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final list = s.notifications;
    final wide = isWide(context);

    Future<void> openOne(AppNotification n) async {
      await s.openNotification(n);
      if (!wide && n.itemId != null && s.itemById(n.itemId) != null && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: n.itemId!)));
      }
    }

    return Column(children: [
      PageHeader(
        title: 'Notifications',
        subtitle: s.unreadCount == 0 ? 'All caught up' : '${s.unreadCount} new',
        actions: [
          if (s.unreadCount > 0)
            TextButton.icon(onPressed: () => s.markAllRead(), icon: const Icon(Icons.done_all, size: 18), label: const Text('Mark all read')),
          if (list.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: () async {
                if (await confirm(context, 'Clear all notifications?', 'This only clears your own list.', ok: 'Clear')) {
                  await s.clearNotifications();
                }
              },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      Expanded(
        child: list.isEmpty
            ? const EmptyState(
                icon: Icons.notifications_none,
                title: 'No notifications',
                body: 'You hear about new items for your trade, the ball coming to you, responses and replies here.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final n = list[i];
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Material(
                        color: n.isRead ? c.surface : c.accentSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: n.isRead ? c.line : c.accent.withValues(alpha: 0.5)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => openOne(n),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(n.icon, color: n.isRead ? c.muted : c.accentText),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(n.title,
                                      style: TextStyle(fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800, fontSize: 14, color: c.ink)),
                                  if (n.body.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink2)),
                                  ],
                                ]),
                              ),
                              const SizedBox(width: 8),
                              Text(agoText(n.createdAt), style: TextStyle(fontSize: 12, color: c.muted)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
