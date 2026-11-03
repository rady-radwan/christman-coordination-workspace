import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/bep_blocks.dart';
import '../util/dates.dart';
import '../widgets/bep_view.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';

/// Colors for an announcement level: (strip/icon color, soft background, icon).
(Color, Color, IconData) announcementLook(String level, CwColors c) => switch (level) {
      'urgent' => (const Color(0xFFD0453A), c.dark ? const Color(0xFF3A1A18) : const Color(0xFFFDE7E5), Icons.error_outline),
      'important' => (const Color(0xFFD9A21B), c.dark ? const Color(0xFF3A2F12) : const Color(0xFFFFF4D6), Icons.priority_high_rounded),
      _ => (c.accent, c.accentSoft, Icons.campaign_outlined),
    };

/// Messages from the Christman VDC team to everyone on the project.
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final wide = isWide(context);
    final list = [...s.announcements]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Column(children: [
      PageHeader(
        title: 'Announcements',
        actions: [
          if (s.canEditAnnouncements)
            FilledButton.icon(
              onPressed: () => openAnnouncementForm(context),
              icon: const Icon(Icons.campaign_outlined, size: 20),
              label: Text(wide ? 'New Announcement' : 'New'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      Expanded(
        child: list.isEmpty
            ? EmptyState(
                icon: Icons.campaign_outlined,
                title: 'No announcements yet',
                body: s.canEditAnnouncements
                    ? 'Post something everyone on the project should know: deadlines, meeting changes, new rules. Everyone gets a notification.'
                    : 'Important messages from the Christman VDC team show here.',
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 16, wide ? 24 : 12, 60),
                children: [
                  for (final a in list)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _AnnouncementCard(a: a)),
                      ),
                    ),
                ],
              ),
      ),
    ]);
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.a});
  final Announcement a;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final (color, soft, icon) = announcementLook(a.level, c);
    final author = s.person(a.createdBy)?.name ?? 'Christman VDC';
    final edited = a.updatedAt.difference(a.createdAt).inMinutes > 1;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5), top: BorderSide(color: c.line), right: BorderSide(color: c.line), bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (a.level != 'info')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text(Announcement.levelLabel(a.level).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                if (a.pinned)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.push_pin, size: 14, color: c.accentText),
                    const SizedBox(width: 3),
                    Text('Pinned', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentText)),
                  ]),
              ]),
              if (a.level != 'info' || a.pinned) const SizedBox(height: 4),
              Text(a.title, style: condensed(22, color: c.ink)),
              Text('$author · ${raisedText(a.createdAt)}${edited ? ' · edited' : ''}', style: TextStyle(fontSize: 12.5, color: c.muted)),
            ]),
          ),
          if (s.canEditAnnouncements)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                try {
                  if (v == 'edit') await openAnnouncementForm(context, existing: a);
                  if (v == 'pin') {
                    await s.api.saveAnnouncement(id: a.id, values: {'pinned': !a.pinned});
                    await s.reloadAnnouncements();
                  }
                  if (v == 'delete' && context.mounted) {
                    if (!await confirm(context, 'Delete this announcement?', '"${a.title}" is removed for everyone.', ok: 'Delete', danger: true)) return;
                    await s.api.deleteAnnouncement(a.id);
                    await s.reloadAnnouncements();
                  }
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'pin', child: Text(a.pinned ? 'Unpin' : 'Pin to the top')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ]),
        if (a.body.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(left: 48, right: 8), child: BepBlocksView(textToBlocks(a.body))),
        ],
      ]),
    );
  }
}

/// Post a new announcement (everyone on the project is notified), or edit one.
Future<void> openAnnouncementForm(BuildContext context, {Announcement? existing}) async {
  final s = context.read<AppState>();
  final title = TextEditingController(text: existing?.title ?? '');
  final body = TextEditingController(text: existing?.body ?? '');
  var level = existing?.level ?? 'info';
  var pinned = existing?.pinned ?? false;
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = CwColors.of(ctx);
        return AlertDialog(
          title: Text(existing == null ? 'New announcement' : 'Edit announcement'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const FieldLabel('Title'),
                TextField(controller: title, autofocus: existing == null, decoration: const InputDecoration(hintText: 'e.g. Models due Thursday 2 PM this week')),
                const SizedBox(height: 10),
                const FieldLabel('Message'),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 14,
                  decoration: const InputDecoration(hintText: 'Write the details…\n- Lines starting with "- " become bullets\n**bold words**'),
                ),
                const SizedBox(height: 12),
                const FieldLabel('How important'),
                Wrap(spacing: 6, children: [
                  for (final l in Announcement.levels)
                    ChoiceChip(
                      avatar: Icon(announcementLook(l, c).$3, size: 16, color: announcementLook(l, c).$1),
                      label: Text(Announcement.levelLabel(l)),
                      selected: level == l,
                      onSelected: (_) => setState(() => level = l),
                    ),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pin to the top'),
                  value: pinned,
                  onChanged: (v) => setState(() => pinned = v),
                ),
                if (existing == null)
                  Text('Everyone on ${s.project?.code ?? 'the project'} gets a notification.', style: TextStyle(fontSize: 12.5, color: c.muted)),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty) {
                        setState(() => error = 'Give the announcement a title.');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final values = {'title': title.text.trim(), 'body': body.text.trim(), 'level': level, 'pinned': pinned};
                        if (existing == null) {
                          await s.api.saveAnnouncement(values: {...values, 'project_id': s.project!.id});
                        } else {
                          await s.api.saveAnnouncement(id: existing.id, values: values);
                        }
                        await s.reloadAnnouncements();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setState(() {
                          busy = false;
                          error = e.toString();
                        });
                      }
                    },
              child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(existing == null ? 'Post' : 'Save'),
            ),
          ],
        );
      },
    ),
  );
}
