import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';

/// Starting values for a new item, e.g. from a row of a clash report.
class ItemPrefill {
  ItemPrefill({
    this.typeCode,
    this.title = '',
    this.description = '',
    this.level = '',
    this.grid = '',
    this.clashTest = '',
    this.clashId = '',
    this.viewpoint = '',
    this.photos = const [],
  });
  final String? typeCode;
  final String title;
  final String description;
  final String level;
  final String grid;
  final String clashTest;
  final String clashId;
  final String viewpoint;
  final List<Uint8List> photos;
}

/// New item, or edit an existing one (coordinators and the admin only).
Future<void> openItemForm(BuildContext context, {Item? item, ItemPrefill? prefill}) => openForm<void>(
      context,
      title: item == null ? 'New coordination item' : 'Edit ${item.number}',
      builder: (_) => _ItemForm(item: item, prefill: prefill),
    );

class _ItemForm extends StatefulWidget {
  const _ItemForm({this.item, this.prefill});
  final Item? item;
  final ItemPrefill? prefill;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  late final AppState s = context.read<AppState>();
  late final Item? it = widget.item;
  late final ItemPrefill? pre = widget.item == null ? widget.prefill : null;

  late String? _typeId = it?.typeId ??
      s.types.where((t) => t.active && t.code == pre?.typeCode).firstOrNull?.id ??
      s.types.where((t) => t.active).firstOrNull?.id;
  late final _title = TextEditingController(text: it?.title ?? pre?.title ?? '');
  late final _desc = TextEditingController(text: it?.description ?? pre?.description ?? '');
  late Priority _priority = it?.priority ?? Priority.medium;
  late final _building = TextEditingController(text: it?.building ?? (s.project!.buildings.length == 1 ? s.project!.buildings.first : ''));
  late final _level = TextEditingController(text: it?.level ?? pre?.level ?? '');
  late final _zone = TextEditingController(text: it?.zone ?? '');
  late final _grid = TextEditingController(text: it?.grid ?? pre?.grid ?? '');
  late final _clashTest = TextEditingController(text: it?.clashTest ?? pre?.clashTest ?? '');
  late final _clashId = TextEditingController(text: it?.clashId ?? pre?.clashId ?? '');
  late final _viewpoint = TextEditingController(text: it?.viewpoint ?? pre?.viewpoint ?? '');
  late final _revitIds = TextEditingController(text: it?.revitIds ?? '');
  late final _sheet = TextEditingController(text: it?.sheet ?? '');
  late final Set<String> _trades = {...?it?.tradeIds};
  late final Set<String> _bic = {...?it?.bicTradeIds};
  late DateTime? _due = it == null ? _defaultDue() : it!.dueDate;
  late bool _needsRfi = it?.needsRfi ?? false;
  late final _rfi = TextEditingController(text: it?.rfiNumber ?? '');
  late List<FormPhoto> _photos = [...?it?.photos.map(FormPhoto.stored), ...?pre?.photos.map(FormPhoto.fresh)];
  bool _busy = false;
  String _busyText = '';
  String? _error;

  DateTime _defaultDue() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: s.project?.defaultDueDays ?? 3));
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _building, _level, _zone, _grid, _clashTest, _clashId, _viewpoint, _revitIds, _sheet, _rfi]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_typeId == null) {
      setState(() => _error = 'Pick a type.');
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the item a short title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final fresh = _photos.where((p) => p.bytes != null).length;
    if (fresh > 0) setState(() => _busyText = 'Uploading $fresh ${fresh == 1 ? 'photo' : 'photos'}…');
    final trades = {..._trades, ..._bic}.toList();
    final values = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'priority': _priority.name,
      'building': _building.text.trim(),
      'level': _level.text.trim(),
      'zone': _zone.text.trim(),
      'grid': _grid.text.trim(),
      'clash_test': _clashTest.text.trim(),
      'clash_id': _clashId.text.trim(),
      'viewpoint': _viewpoint.text.trim(),
      'revit_ids': _revitIds.text.trim(),
      'sheet': _sheet.text.trim(),
      'trade_ids': trades,
      'bic_trade_ids': _bic.toList(),
      'due_date': _due == null ? null : dateToDb(_due!),
      'needs_rfi': _needsRfi,
      'rfi_number': _needsRfi ? _rfi.text.trim() : '',
    };
    try {
      if (it == null) {
        values['type_id'] = _typeId;
        // Given to a trade straight away = that trade is reviewing it.
        values['status'] = _bic.isEmpty ? ItemStatus.open.db : ItemStatus.inReview.db;
        final created = await s.createItem(values, photos: [for (final p in _photos) p.bytes!]);
        if (mounted) {
          Navigator.of(context).pop();
          showInfo(context, 'Created ${created.number}');
        }
      } else {
        // Moving the ball from the coordinator to a trade on an open item starts the review.
        if (it!.status == ItemStatus.open && it!.ballWithCoordinator && _bic.isNotEmpty) {
          values['status'] = ItemStatus.inReview.db;
        }
        // Keep stored photos in order; upload new or re-marked ones.
        final refs = <String>[];
        for (final p in _photos) {
          refs.add(p.ref ?? (await s.uploadItemPhotos(it!, [p.bytes!])).first);
        }
        values['photos'] = refs;
        await s.updateItem(it!, values);
        if (mounted) {
          Navigator.of(context).pop();
          showInfo(context, 'Saved ${it!.number}');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = '';
        });
      }
    }
  }

  Widget _text(TextEditingController ctrl, {String? hint, int lines = 1, bool autofocus = false}) => TextField(
        controller: ctrl,
        autofocus: autofocus,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        decoration: InputDecoration(hintText: hint),
      );

  /// A text field with a drop-down of the project's own list (levels, zones...).
  Widget _withList(TextEditingController ctrl, List<String> options, String hint) {
    if (options.isEmpty) return _text(ctrl, hint: hint);
    return Row(children: [
      Expanded(child: _text(ctrl, hint: hint)),
      PopupMenuButton<String>(
        tooltip: 'Pick from the project list',
        icon: const Icon(Icons.arrow_drop_down_circle_outlined),
        onSelected: (v) => setState(() => ctrl.text = v),
        itemBuilder: (_) => options.map((o) => PopupMenuItem(value: o, child: Text(o))).toList(),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final p = s.project!;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);
    Widget labeled(String label, Widget field, {String? hint}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label, hint: hint), field]);

    final types = s.types.where((t) => t.active || t.id == _typeId).toList();
    final typeCode = s.typeById(_typeId)?.code ?? '??';

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            if (it == null)
              Text('Number: ${p.code}-$typeCode-### (given automatically)', style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 8),
            labeled(
              'Type',
              it != null
                  ? Text('${s.typeById(_typeId)?.name ?? ''} — the type is part of the number and cannot change.',
                      style: TextStyle(color: c.ink2))
                  : DropdownButtonFormField<String>(
                      initialValue: _typeId,
                      items: types.map((t) => DropdownMenuItem(value: t.id, child: Text('${t.name}  (${t.code})'))).toList(),
                      onChanged: (v) => setState(() => _typeId = v),
                    ),
            ),
            const SizedBox(height: 10),
            labeled('Title', _text(_title, hint: 'e.g. Supply duct hits W14 beam at C-4', autofocus: it == null)),
            const SizedBox(height: 10),
            labeled('Description', _text(_desc, hint: 'What is the conflict and what do you need?', lines: 3)),
            const SizedBox(height: 14),
            const FieldLabel('Priority'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final pr in Priority.values)
                PriorityChip(priority: pr, selected: _priority == pr, onTap: () => setState(() => _priority = pr)),
            ]),
            const SizedBox(height: 18),
            SectionLabel(_photos.isEmpty ? 'Photos and screenshots' : 'Photos and screenshots · ${_photos.length}'),
            const SizedBox(height: 4),
            Text('Each photo opens in the markup editor: arrows, boxes, clouds, text. Click a photo to mark it up again.',
                style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 10),
            if (_photos.isNotEmpty) ...[
              PhotoStrip(photos: _photos, onChanged: (v) => setState(() => _photos = v)),
              const SizedBox(height: 10),
            ],
            AddPhotoButtons(onAdded: (list) => setState(() => _photos = [..._photos, ...list.map(FormPhoto.fresh)])),
            const SizedBox(height: 18),
            const SectionLabel('Location'),
            const SizedBox(height: 4),
            pair(labeled('Building', _withList(_building, p.buildings, 'e.g. Building A')),
                labeled('Level', _withList(_level, p.levels, 'e.g. Level 3'))),
            const SizedBox(height: 10),
            pair(labeled('Zone / area', _withList(_zone, p.zones, 'e.g. Zone B')),
                labeled('Grid lines', _text(_grid, hint: 'e.g. C-4 / D-5'))),
            const SizedBox(height: 18),
            const SectionLabel('Model reference'),
            const SizedBox(height: 4),
            pair(labeled('Navisworks clash test', _text(_clashTest, hint: 'e.g. MECH vs STRUCT – L3')),
                labeled('Clash ID', _text(_clashId, hint: 'e.g. 2147'))),
            const SizedBox(height: 10),
            pair(labeled('Viewpoint name', _text(_viewpoint, hint: 'e.g. L3-B-014')),
                labeled('Sheet number', _text(_sheet, hint: 'e.g. M-301'))),
            const SizedBox(height: 10),
            labeled('Revit element IDs', _text(_revitIds, hint: 'e.g. 1284731, 1290466')),
            const SizedBox(height: 18),
            const SectionLabel('Trades'),
            const SizedBox(height: 4),
            const FieldLabel('Trades involved', hint: 'tap all that apply'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in s.trades)
                CwChip(
                  label: t.company.isEmpty ? t.name : '${t.name} · ${t.company}',
                  selected: _trades.contains(t.id),
                  onTap: () => setState(() {
                    if (!_trades.remove(t.id)) _trades.add(t.id);
                    _bic.removeWhere((id) => !_trades.contains(id));
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            const FieldLabel('Ball in court', hint: 'who must act now — choose one or more trades'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              CwChip(
                label: 'Christman VDC (coordinator)',
                icon: Icons.adjust,
                selected: _bic.isEmpty,
                onTap: () => setState(_bic.clear),
              ),
              for (final t in s.trades)
                CwChip(
                  label: t.name,
                  icon: _bic.contains(t.id) ? Icons.adjust : null,
                  selected: _bic.contains(t.id),
                  onTap: () => setState(() {
                    if (!_bic.remove(t.id)) {
                      _bic.add(t.id);
                      _trades.add(t.id);
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Dates and RFI'),
            const SizedBox(height: 4),
            labeled(
              'Response due',
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due ?? now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 3),
                      );
                      if (d != null) setState(() => _due = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_due == null ? 'No due date' : weekdayDate(_due!)),
                    ),
                  ),
                ),
                if (_due != null)
                  IconButton(tooltip: 'Remove due date', onPressed: () => setState(() => _due = null), icon: const Icon(Icons.close)),
              ]),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _needsRfi,
              onChanged: (v) => setState(() => _needsRfi = v),
              title: const Text('Needs RFI', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('This design question needs a formal RFI'),
            ),
            if (_needsRfi) labeled('RFI number', _text(_rfi, hint: 'e.g. 112 (leave empty if not issued yet)')),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
            ),
          Row(children: [
            Expanded(child: Text(_busyText, style: TextStyle(fontSize: 13, color: c.muted))),
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(it == null ? 'Create Item' : 'Save Changes'),
            ),
          ]),
        ]),
      ),
    ]);
  }
}
