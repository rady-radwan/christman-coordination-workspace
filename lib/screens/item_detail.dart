import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../editor/markup_editor.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'item_form.dart';

/// Full-screen item page for phones.
class ItemDetailPage extends StatelessWidget {
  const ItemDetailPage({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final item = s.itemById(itemId);
    return Scaffold(
      appBar: AppBar(title: item == null ? const Text('Item') : ItemNumber(item.number, size: 22)),
      body: item == null
          ? const EmptyState(icon: Icons.search_off, title: 'Item not found', body: 'It may have been deleted.')
          : ItemDetail(itemId: itemId, phone: true),
    );
  }
}

/// Item details, actions, discussion and history.
class ItemDetail extends StatefulWidget {
  const ItemDetail({super.key, required this.itemId, this.phone = false});
  final String itemId;
  final bool phone;

  @override
  State<ItemDetail> createState() => _ItemDetailState();
}

class _ItemDetailState extends State<ItemDetail> {
  List<Comment> _comments = [];
  List<ItemEvent> _events = [];
  int _loadedVersion = -1;
  bool _loading = false;
  bool _historyTab = false;
  final _reply = TextEditingController();
  final List<Uint8List> _replyPhotos = [];
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final (c, e) = await context.read<AppState>().api.thread(widget.itemId);
      if (!mounted) return;
      setState(() {
        _comments = c;
        _events = e;
      });
    } catch (_) {
      // Shown as an empty thread; the next change reloads it.
    } finally {
      _loading = false;
    }
  }

  Future<void> _act(Future<void> Function() run, {String? done}) async {
    try {
      await run();
      if (done != null && mounted) showInfo(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _send(AppState s, Item item) async {
    final text = _reply.text.trim();
    if (text.isEmpty && _replyPhotos.isEmpty) return;
    setState(() => _sending = true);
    try {
      await s.addComment(item, text, photos: List.of(_replyPhotos));
      _reply.clear();
      _replyPhotos.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final item = s.itemById(widget.itemId);
    if (item == null) return const EmptyState(icon: Icons.search_off, title: 'Item not found');
    if (s.threadVersion != _loadedVersion) {
      _loadedVersion = s.threadVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    final header = Container(
      padding: EdgeInsets.fromLTRB(widget.phone ? 16 : 24, widget.phone ? 12 : 20, widget.phone ? 16 : 24, 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!widget.phone) ItemNumber(item.number, size: 20),
          PriorityBadge(item.priority, large: true),
          StatusBadge(item.status, large: true),
          if (item.needsRfi) Tag(item.rfiNumber.isEmpty ? 'Needs RFI' : 'RFI ${item.rfiNumber}', icon: Icons.help_outline),
        ]),
        const SizedBox(height: 10),
        Text(item.title, style: condensed(widget.phone ? 26 : 30, color: c.ink)),
        if (item.isOverdue) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: c.urgentBg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              StatusDot(c.urgentText, size: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(style: TextStyle(color: c.urgentText, fontSize: 14), children: [
                  TextSpan(text: overdueText(item.overdueDays()), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                  TextSpan(text: ' — response was due ${weekdayDate(item.dueDate!)}. ${s.bicLabel(item.bicTradeId)} must act.'),
                ])),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _StatusPath(status: item.status),
        const SizedBox(height: 14),
        _ActionBar(item: item, act: _act),
      ]),
    );

    final facts = _Facts(item: item, events: _events);
    final thread = _thread(s, c, item);

    return LayoutBuilder(builder: (context, box) {
      final twoColumns = box.maxWidth >= 820;
      final pad = widget.phone ? 16.0 : 24.0;
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          header,
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
            child: twoColumns
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _description(item, c, thread)),
                    const SizedBox(width: 20),
                    SizedBox(width: 300, child: facts),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    facts,
                    const SizedBox(height: 20),
                    _description(item, c, thread),
                  ]),
          ),
        ],
      );
    });
  }

  Future<void> _markUpStored(AppState s, Item item, int i) async {
    try {
      final bytes = await s.api.photoBytes(item.photos[i]);
      if (!mounted) return;
      final done = await openMarkupEditor(context, bytes, title: 'Mark up photo ${i + 1} · ${item.number}');
      if (done == null) return;
      final ref = (await s.uploadItemPhotos(item, [done])).first;
      final next = List.of(item.photos)..[i] = ref;
      await s.updateItem(item, {'photos': next});
      if (mounted) showInfo(context, 'Photo ${i + 1} updated');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addPhotos(AppState s, Item item) async {
    final list = await pickAndMarkUp(context, camera: false);
    if (list.isEmpty) return;
    try {
      final refs = await s.uploadItemPhotos(item, list);
      await s.updateItem(item, {'photos': [...item.photos, ...refs]});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _removePhoto(AppState s, Item item, int i) async {
    if (!await confirm(context, 'Remove photo ${i + 1}?', 'It is removed from ${item.number} for everyone.', ok: 'Remove', danger: true)) {
      return;
    }
    try {
      await s.updateItem(item, {'photos': List.of(item.photos)..removeAt(i)});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _description(Item item, CwColors c, Widget thread) {
    final s = context.read<AppState>();
    final coord = s.myRole.isCoord;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (item.photos.isNotEmpty) ...[
        ItemGallery(
          key: ValueKey(item.photos.join()),
          refs: item.photos,
          onMarkUp: coord ? (i) => _markUpStored(s, item, i) : null,
          onAdd: coord ? () => _addPhotos(s, item) : null,
          onRemove: coord ? (i) => _removePhoto(s, item, i) : null,
        ),
        const SizedBox(height: 16),
      ] else if (coord) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _addPhotos(s, item),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add Photos / Screenshots'),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (item.description.isNotEmpty) ...[
        SelectableText(item.description, style: TextStyle(fontSize: 15, height: 1.5, color: c.ink2)),
        const SizedBox(height: 18),
      ],
      thread,
    ]);
  }

  Widget _thread(AppState s, CwColors c, Item item) {
    final entries = <(DateTime, Widget)>[];
    if (_historyTab) {
      for (final e in _events.reversed) {
        entries.add((e.createdAt, _EventLine(event: e, full: true)));
      }
    } else {
      for (final m in _comments) {
        entries.add((m.createdAt, _CommentBubble(comment: m, onChanged: _load)));
      }
      for (final e in _events.where((e) => e.kind == 'ball' || e.kind == 'status')) {
        entries.add((e.createdAt, _EventLine(event: e)));
      }
      entries.sort((a, b) => a.$1.compareTo(b.$1));
    }

    Widget tab(String label, bool on, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            margin: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? c.accent : Colors.transparent, width: 3))),
            child: Text(label,
                style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? c.ink : c.tabOff)),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          tab('Discussion (${_comments.length})', !_historyTab, () => setState(() => _historyTab = false)),
          tab('History (${_events.length})', _historyTab, () => setState(() => _historyTab = true)),
        ]),
      ),
      const SizedBox(height: 14),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_historyTab ? 'No history yet.' : 'No replies yet. Start the discussion below.',
              style: TextStyle(color: c.muted, fontSize: 14)),
        ),
      for (final e in entries) Padding(padding: const EdgeInsets.only(bottom: 12), child: e.$2),
      if (!_historyTab && s.canComment) ...[
        const SizedBox(height: 4),
        if (_replyPhotos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _replyPhotos.length; i++)
                PendingPhoto(bytes: _replyPhotos[i], onRemove: () => setState(() => _replyPhotos.removeAt(i))),
            ]),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line2)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _send(s, item),
                },
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AddPhotoButtons(compact: true, onAdded: (list) => setState(() => _replyPhotos.addAll(list))),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: IconButton.filled(
                tooltip: 'Send (Ctrl+Enter)',
                onPressed: _sending ? null : () => _send(s, item),
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 20),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// Open → In Review → Response → Verify → Closed, with On Hold / Voided shown on their own.
class _StatusPath extends StatelessWidget {
  const _StatusPath({required this.status});
  final ItemStatus status;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    if (status == ItemStatus.onHold || status == ItemStatus.voided) {
      return Text(status == ItemStatus.onHold ? 'This item is on hold.' : 'This item was voided.',
          style: TextStyle(fontSize: 14, color: c.muted, fontWeight: FontWeight.w600));
    }
    final at = ItemStatus.path.indexOf(status);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < ItemStatus.path.length; i++)
        _step(c, i, ItemStatus.path[i], done: i < at || status == ItemStatus.closed, now: i == at && status != ItemStatus.closed),
    ]);
  }

  Widget _step(CwColors c, int i, ItemStatus st, {required bool done, required bool now}) {
    final fg = now ? c.statusFg(st) : (done ? c.ink2 : c.muted);
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(
        color: now ? c.statusBg(st) : (done ? c.pill : Colors.transparent),
        borderRadius: BorderRadius.circular(999),
        border: now || done ? null : Border.all(color: c.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: now ? c.statusFg(st) : (done ? c.statusFg(ItemStatus.closed) : c.pill),
          ),
          child: done
              ? Icon(Icons.check, size: 14, color: c.surface)
              : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: now ? c.statusBg(st) : c.muted)),
        ),
        const SizedBox(width: 7),
        Text(st == ItemStatus.closed ? 'Resolved' : st.label,
            style: TextStyle(fontSize: 13, fontWeight: now ? FontWeight.w700 : FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// The buttons that fit the person's role.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.item, required this.act});
  final Item item;
  final Future<void> Function(Future<void> Function() run, {String? done}) act;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final buttons = <Widget>[];

    if (s.canRespond(item)) {
      buttons.add(FilledButton.icon(
        onPressed: () async {
          final note = await askNote(context,
              title: 'Submit response',
              body: 'Explain your answer. The ball goes back to the Christman coordinator.',
              ok: 'Submit Response',
              hint: 'Your response',
              required: true);
          if (note != null) await act(() => s.submitResponse(item, note), done: 'Response submitted');
        },
        icon: const Icon(Icons.reply, size: 18),
        label: const Text('Submit Response'),
      ));
      buttons.add(OutlinedButton.icon(
        onPressed: () async {
          final note = await askNote(context,
              title: 'Model updated',
              body: 'Tell the coordinator what changed in your model. The coordinator verifies it.',
              ok: 'Mark Model Updated');
          if (note != null) await act(() => s.markModelUpdated(item, note), done: 'Marked as model updated');
        },
        icon: const Icon(Icons.view_in_ar_outlined, size: 18),
        label: const Text('Model Updated'),
      ));
    }

    if (s.canPassBall(item)) {
      buttons.add(OutlinedButton.icon(
        onPressed: () async {
          final r = await showDialog<_PassResult>(context: context, builder: (_) => _PassBallDialog(item: item));
          if (r != null) {
            await act(() => s.passBall(item, r.tradeId, r.note), done: 'Ball passed to ${s.bicName(r.tradeId)}');
          }
        },
        icon: const Icon(Icons.east, size: 18),
        label: const Text('Pass Ball'),
      ));
    }

    if (s.myRole.isCoord) {
      buttons.add(PopupMenuButton<ItemStatus>(
        tooltip: 'Change status',
        onSelected: (st) async {
          final closing = st == ItemStatus.closed || st == ItemStatus.voided;
          final note = await askNote(context,
              title: '${closing ? (st == ItemStatus.closed ? 'Close' : 'Void') : 'Change status to ${st.label}'}',
              body: st == ItemStatus.closed
                  ? 'Mark ${item.number} as resolved and closed.'
                  : st == ItemStatus.voided
                      ? 'Void ${item.number} (canceled or raised by mistake).'
                      : (!item.status.isActive ? 'This reopens ${item.number}.' : null),
              ok: st == ItemStatus.closed ? 'Close Item' : (st == ItemStatus.voided ? 'Void Item' : 'Change Status'));
          if (note != null) await act(() => s.setStatus(item, st, note), done: 'Status: ${st.label}');
        },
        itemBuilder: (_) => ItemStatus.values
            .where((st) => st != item.status)
            .map((st) => PopupMenuItem(
                  value: st,
                  child: Row(children: [
                    StatusDot(CwColors.of(context).statusFg(st), size: 9),
                    const SizedBox(width: 10),
                    Text(!item.status.isActive && st.isActive ? 'Reopen as ${st.label}' : st.label),
                  ]),
                ))
            .toList(),
        child: IgnorePointer(
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            label: const Text('Change Status'),
          ),
        ),
      ));
      buttons.add(OutlinedButton.icon(
        onPressed: () => openItemForm(context, item: item),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      ));
    }

    buttons.add(PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) async {
        if (v == 'copy') {
          await Clipboard.setData(ClipboardData(text: '${item.number} — ${item.title}'));
          if (context.mounted) showInfo(context, 'Copied ${item.number}');
        } else if (v == 'delete') {
          final ok = await confirm(context, 'Delete ${item.number}?',
              'This removes the item, its discussion and history for everyone. Voiding keeps a record instead.',
              ok: 'Delete', danger: true);
          if (ok) await act(() => s.deleteItem(item), done: 'Deleted ${item.number}');
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'copy', child: Text('Copy number and title')),
        if (s.isAdmin) const PopupMenuItem(value: 'delete', child: Text('Delete item…')),
      ],
    ));

    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: buttons);
  }
}

class _PassResult {
  _PassResult(this.tradeId, this.note);
  final String? tradeId;
  final String note;
}

class _PassBallDialog extends StatefulWidget {
  const _PassBallDialog({required this.item});
  final Item item;

  @override
  State<_PassBallDialog> createState() => _PassBallDialogState();
}

class _PassBallDialogState extends State<_PassBallDialog> {
  static const _vdc = '__vdc__';
  String? _target;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final item = widget.item;
    // Coordinators can pass to any trade; a trade only to the other trades on this item.
    final trades = s.myRole.isCoord ? s.trades : s.trades.where((t) => item.tradeIds.contains(t.id) && t.id != s.myTradeId).toList();
    final options = <(String, String, String)>[
      if (item.bicTradeId != null) (_vdc, 'Christman VDC', 'Back to the coordinator'),
      ...trades.where((t) => t.id != item.bicTradeId).map((t) => (t.id, t.name, t.company.isEmpty ? t.code : t.company)),
    ];
    return AlertDialog(
      title: Text('Pass the ball on ${item.number}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Now with: ${s.bicLabel(item.bicTradeId)}', style: TextStyle(color: c.muted)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final o in options)
                  RadioListTile<String>(
                    value: o.$1,
                    groupValue: _target,
                    onChanged: (v) => setState(() => _target = v),
                    title: Text(o.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(o.$3),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          TextField(controller: _note, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'What should they do? (optional)')),
          if (!s.myRole.isCoord && options.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No other trade is on this item. Ask the coordinator to add one.', style: TextStyle(color: c.muted)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _target == null
              ? null
              : () => Navigator.pop(context, _PassResult(_target == _vdc ? null : _target, _note.text)),
          child: const Text('Pass Ball'),
        ),
      ],
    );
  }
}

/// Ball in court, facts, trades and RFI.
class _Facts extends StatelessWidget {
  const _Facts({required this.item, required this.events});
  final Item item;
  final List<ItemEvent> events;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final bic = s.tradeById(item.bicTradeId);
    final ballPath = events.where((e) => e.kind == 'ball').map((e) => e.toValue.split(' · ').first).toList();
    final type = s.typeById(item.typeId);

    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: c.muted)),
            const SizedBox(height: 2),
            SelectableText(v, style: TextStyle(fontSize: 14, height: 1.4, color: c.ink)),
          ]),
        );

    final modelRef = [
      if (item.clashTest.isNotEmpty) 'Test: ${item.clashTest}',
      if (item.clashId.isNotEmpty) 'Clash ID ${item.clashId}',
      if (item.viewpoint.isNotEmpty) 'Viewpoint ${item.viewpoint}',
      if (item.revitIds.isNotEmpty) 'Revit IDs ${item.revitIds}',
      if (item.sheet.isNotEmpty) 'Sheet ${item.sheet}',
    ].join('\n');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (item.status.isActive) ...[
        Panel(
          highlight: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.adjust, size: 16, color: c.accentText),
              const SizedBox(width: 6),
              Text('BALL IN COURT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.accentText)),
            ]),
            const SizedBox(height: 6),
            Text(bic?.name ?? 'Christman VDC', style: condensed(24, color: c.ink)),
            Text(
              [if ((bic?.company ?? '').isNotEmpty) bic!.company, if (bic == null) 'Coordinator', 'since ${shortDate(item.bicSince)}']
                  .join(' · '),
              style: TextStyle(fontSize: 14, color: c.ink2),
            ),
            if (ballPath.length > 1) ...[
              const SizedBox(height: 6),
              Text(ballPath.join('  →  '), style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ]),
        ),
        const SizedBox(height: 14),
      ],
      Panel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fact('Type', type == null ? '—' : '${type.name} (${type.code})'),
          fact('Location', item.locationText.isEmpty ? 'Not set' : item.locationText),
          if (modelRef.isNotEmpty) fact('Model reference', modelRef),
          fact('Raised', '${raisedText(item.createdAt)}\nby ${s.person(item.createdBy)?.name ?? 'someone'}'),
          fact('Response due', item.dueDate == null ? 'Not set' : weekdayDate(item.dueDate!)),
          if (item.closedAt != null)
            fact('Closed', '${raisedText(item.closedAt!)}${s.person(item.closedBy) != null ? '\nby ${s.person(item.closedBy)!.name}' : ''}'),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TRADES INVOLVED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: c.muted)),
          const SizedBox(height: 8),
          if (item.tradeIds.isEmpty)
            Text('None yet', style: TextStyle(color: c.muted))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final id in item.tradeIds)
                if (s.tradeById(id) != null) Tag(s.tradeById(id)!.label, strong: id == item.bicTradeId),
            ]),
        ]),
      ),
      if (s.myRole.isCoord || item.needsRfi) ...[
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Needs RFI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(item.needsRfi ? (item.rfiNumber.isEmpty ? 'RFI number not set yet' : 'RFI ${item.rfiNumber}') : 'Turn on to add the RFI number',
                    style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
            if (s.myRole.isCoord)
              Switch(
                value: item.needsRfi,
                onChanged: (on) async {
                  String rfi = item.rfiNumber;
                  if (on) {
                    final v = await askNote(context, title: 'RFI number', ok: 'Save', hint: 'e.g. 112 (leave empty if not issued yet)');
                    if (v == null) return;
                    rfi = v.trim();
                  }
                  try {
                    await s.updateItem(item, {'needs_rfi': on, 'rfi_number': on ? rfi : item.rfiNumber});
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment, required this.onChanged});
  final Comment comment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final author = s.person(comment.authorId);
    final mine = comment.authorId == s.me?.id;
    final isCoord = author != null && (author.isAdmin || s.memberOf(author.id)?.role == Role.coordinator);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Avatar(initials: author?.initials ?? '?', strong: isCoord),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text(author?.name ?? 'Former member', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(
              [s.personLine(comment.authorId), dayTimeText(comment.createdAt), if (comment.editedAt != null) 'edited']
                  .where((x) => x.isNotEmpty)
                  .join(' · '),
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ]),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.line),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (comment.body.isNotEmpty) SelectableText(comment.body, style: TextStyle(fontSize: 14, height: 1.45, color: c.ink)),
                  if (comment.photos.isNotEmpty) ...[
                    if (comment.body.isNotEmpty) const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (var i = 0; i < comment.photos.length; i++)
                        InkWell(
                          onTap: () => showPhotoViewer(context, comment.photos, i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(width: 160, height: 110, child: RefImage(comment.photos[i])),
                          ),
                        ),
                    ]),
                  ],
                ]),
              ),
              if (mine || s.isAdmin)
                PopupMenuButton<String>(
                  tooltip: 'Reply options',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_vert, size: 18, color: c.muted),
                  onSelected: (v) async {
                    try {
                      if (v == 'edit') {
                        final ctrl = TextEditingController(text: comment.body);
                        final text = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Edit reply'),
                            content: SizedBox(width: 440, child: TextField(controller: ctrl, minLines: 3, maxLines: 8, autofocus: true)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (text != null && text.trim().isNotEmpty) {
                          await s.api.editComment(comment.id, text);
                          onChanged();
                        }
                      } else if (v == 'delete') {
                        if (!context.mounted) return;
                        final ok = await confirm(context, 'Delete this reply?', 'It is removed for everyone.', ok: 'Delete', danger: true);
                        if (ok) {
                          await s.api.deleteComment(comment.id);
                          onChanged();
                        }
                      }
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  itemBuilder: (_) => [
                    if (mine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({required this.event, this.full = false});
  final ItemEvent event;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final who = s.person(event.actorId)?.name;
    final icon = switch (event.kind) {
      'ball' => Icons.east,
      'status' => Icons.flag_outlined,
      'created' => Icons.add_circle_outline,
      'priority' => Icons.priority_high,
      'due' => Icons.event_outlined,
      'rfi' => Icons.help_outline,
      _ => Icons.edit_outlined,
    };
    return Padding(
      padding: EdgeInsets.only(left: full ? 0 : 48),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: c.muted, height: 1.4), children: [
            TextSpan(text: event.describe(), style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600)),
            TextSpan(text: '  ·  ${who ?? 'System'} · ${dayTimeText(event.createdAt)}'),
          ])),
        ),
      ]),
    );
  }
}
