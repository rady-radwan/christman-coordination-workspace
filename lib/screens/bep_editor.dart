import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/bep_blocks.dart';
import '../util/docx.dart';
import '../util/pick_file.dart';
import '../widgets/bep_view.dart';
import '../widgets/common.dart';

/// Full-page editor for one BEP section (like a small Word page): headings, text, lists,
/// checklists, tables, note boxes, lines and pictures. Admin only.
Future<void> openBepSectionEditor(BuildContext context, {BepSection? section}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => BepSectionEditor(section: section)));
}

/// Saves imported Word sections as new BEP sections (pictures are uploaded).
Future<int> saveImportedSections(AppState s, List<(String, List<BepBlock>)> sections) async {
  var sort = s.bepSections.isEmpty ? 0 : s.bepSections.map((x) => x.sort).reduce((a, b) => a > b ? a : b) + 1;
  for (final (title, blocks) in sections) {
    await _uploadPictures(s, blocks);
    await s.api.saveBepSection(values: {
      'project_id': s.project!.id,
      'title': title.length > 120 ? title.substring(0, 120) : title,
      'content': blocksToJson(blocks),
      'body': blocksPlainText(blocks),
      'sort': sort++,
    });
  }
  await s.reloadBep();
  return sections.length;
}

Future<void> _uploadPictures(AppState s, List<BepBlock> blocks) async {
  for (final b in blocks) {
    if (b.type == 'img' && b.bytes != null) {
      final png = b.bytes!.length > 4 && b.bytes![0] == 0x89 && b.bytes![1] == 0x50;
      b.path = await s.api.uploadFile(s.project!.id, 'bep', b.bytes!, png ? 'picture.png' : 'picture.jpg');
      b.bytes = null;
    }
  }
}

class BepSectionEditor extends StatefulWidget {
  const BepSectionEditor({super.key, this.section});
  final BepSection? section;

  @override
  State<BepSectionEditor> createState() => _BepSectionEditorState();
}

class _BepSectionEditorState extends State<BepSectionEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.section?.title ?? '');
  late final List<BepBlock> _blocks = widget.section == null ? [BepBlock('p')] : [for (final b in widget.section!.blocks) b.copy()];
  bool _dirty = false;
  bool _busy = false;
  bool _preview = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _add(BepBlock b, {int? at}) {
    setState(() {
      _blocks.insert(at ?? _blocks.length, b);
      _dirty = true;
    });
  }

  Future<void> _addPicture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (x == null) return;
    _add(BepBlock('img', bytes: await x.readAsBytes()));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) showInfo(context, 'Nothing to paste. Copy text or a table in Word or Excel first.');
      return;
    }
    final blocks = textToBlocks(text);
    setState(() {
      if (_blocks.length == 1 && _blocks.first.isEmpty) _blocks.clear();
      _blocks.addAll(blocks);
      _dirty = true;
    });
    if (mounted) showInfo(context, 'Pasted ${blocks.length} part${blocks.length == 1 ? '' : 's'}${blocks.any((b) => b.type == 'table') ? ' (tables kept as tables)' : ''}.');
  }

  Future<void> _importWord() async {
    final f = await pickOneFile(extensions: const ['docx'], label: 'Word document');
    if (f == null) return;
    try {
      final content = await compute(readDocx, f.bytes);
      setState(() {
        if (_blocks.length == 1 && _blocks.first.isEmpty) _blocks.clear();
        _blocks.addAll(content.blocks);
        _dirty = true;
      });
      if (mounted) {
        showInfo(context, 'Added ${content.blocks.length} parts from ${f.name}${content.skippedPictures > 0 ? ' (${content.skippedPictures} large pictures left out)' : ''}.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    if (_title.text.trim().isEmpty) {
      showInfo(context, 'Give the section a title.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _uploadPictures(s, _blocks);
      final values = <String, dynamic>{
        'title': _title.text.trim(),
        'content': blocksToJson(_blocks),
        'body': blocksPlainText(_blocks),
      };
      if (widget.section == null) {
        final next = s.bepSections.isEmpty ? 0 : s.bepSections.map((x) => x.sort).reduce((a, b) => a > b ? a : b) + 1;
        await s.api.saveBepSection(values: {...values, 'project_id': s.project!.id, 'sort': next});
      } else {
        await s.api.saveBepSection(id: widget.section!.id, values: values);
      }
      await s.reloadBep();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return confirm(context, 'Leave without saving?', 'Your changes to this section will be lost.', ok: 'Leave', danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final wide = isWide(context);
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(widget.section == null ? 'New BEP section' : 'Edit section'),
          actions: [
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined, size: 20),
              label: Text(_preview ? 'Edit' : 'Preview'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 20),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: _preview ? _previewPane(c) : _editPane(c, wide),
          ),
        ),
        bottomNavigationBar: _preview ? null : _toolbar(c),
      ),
    );
  }

  Widget _previewPane(CwColors c) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_title.text, style: condensed(26, color: c.ink)),
          const SizedBox(height: 12),
          BepBlocksView(_blocks.where((b) => !b.isEmpty || b.type == 'hr').toList()),
        ],
      );

  Widget _editPane(CwColors c, bool wide) {
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 16, wide ? 24 : 12, 40),
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: _title,
          onChanged: (_) => _changed(),
          style: condensed(24, color: c.ink),
          decoration: const InputDecoration(labelText: 'Section title', hintText: 'e.g. Model Naming Convention'),
        ),
      ),
      itemCount: _blocks.length,
      onReorder: (from, to) => setState(() {
        if (to > from) to--;
        _blocks.insert(to, _blocks.removeAt(from));
        _dirty = true;
      }),
      itemBuilder: (context, i) {
        final b = _blocks[i];
        return Padding(
          key: ObjectKey(b),
          padding: const EdgeInsets.only(bottom: 10),
          child: _BlockCard(
            index: i,
            block: b,
            onChanged: _changed,
            onDelete: () => setState(() {
              _blocks.removeAt(i);
              _dirty = true;
            }),
            onDuplicate: () => _add(b.copy(), at: i + 1),
            onConvert: (t) => setState(() {
              _convert(b, t);
              _dirty = true;
            }),
          ),
        );
      },
    );
  }

  /// Changes a text-like block into another text-like type, keeping the words.
  void _convert(BepBlock b, String to) {
    final lines = switch (b.type) {
      'ul' || 'ol' || 'check' => b.items,
      'table' => [for (final r in b.rows) r.join(' ')],
      _ => b.text.split('\n'),
    };
    switch (to) {
      case 'h':
      case 'p':
      case 'note':
        b.text = to == 'h' ? lines.join(' ') : lines.join('\n');
      case 'ul':
      case 'ol':
      case 'check':
        b.items = lines.where((l) => l.trim().isNotEmpty).toList();
        b.checks = [for (final _ in b.items) false];
    }
    b.type = to;
  }

  Widget _toolbar(CwColors c) {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label)),
        );
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Text('Add:  ', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink2)),
            btn(Icons.title, 'Heading', () => _add(BepBlock('h'))),
            btn(Icons.notes, 'Text', () => _add(BepBlock('p'))),
            btn(Icons.format_list_bulleted, 'Bullets', () => _add(BepBlock('ul', items: ['']))),
            btn(Icons.format_list_numbered, 'Numbered', () => _add(BepBlock('ol', items: ['']))),
            btn(Icons.checklist, 'Checklist', () => _add(BepBlock('check', items: [''], checks: [false]))),
            btn(Icons.table_chart_outlined, 'Table', () => _add(BepBlock('table', rows: [
                  ['', '', ''],
                  ['', '', ''],
                  ['', '', ''],
                ]))),
            btn(Icons.info_outline, 'Note box', () => _add(BepBlock('note'))),
            btn(Icons.image_outlined, 'Picture', _addPicture),
            btn(Icons.horizontal_rule, 'Line', () => _add(BepBlock('hr'))),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(onPressed: _paste, icon: const Icon(Icons.content_paste, size: 18), label: const Text('Paste from Word / Excel')),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(onPressed: _importWord, icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Import Word file')),
          ]),
        ),
      ),
    );
  }
}

/// One block in the editor: a drag handle, its type and the editing fields.
class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.index,
    required this.block,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    required this.onConvert,
  });
  final int index;
  final BepBlock block;
  final VoidCallback onChanged, onDelete, onDuplicate;
  final void Function(String type) onConvert;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final textual = const ['h', 'p', 'note', 'ul', 'ol', 'check'].contains(block.type);
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(children: [
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator, color: c.muted)),
              ),
            ),
            if (textual)
              DropdownButton<String>(
                value: block.type,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final t in const ['h', 'p', 'ul', 'ol', 'check', 'note'])
                    DropdownMenuItem(value: t, child: Text(BepBlock.label(t), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2))),
                ],
                onChanged: (t) {
                  if (t != null && t != block.type) onConvert(t);
                },
              )
            else
              Text(BepBlock.label(block.type), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2)),
            const Spacer(),
            IconButton(tooltip: 'Duplicate', onPressed: onDuplicate, icon: const Icon(Icons.copy_all_outlined, size: 19)),
            IconButton(tooltip: 'Remove', onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 19)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: switch (block.type) {
            'h' => _HeadingEditor(block: block, onChanged: onChanged),
            'p' => _TextEditor(block: block, onChanged: onChanged, hint: 'Write here… Select words and press B for bold.'),
            'note' => _NoteEditor(block: block, onChanged: onChanged),
            'ul' || 'ol' => _ListEditor(block: block, onChanged: onChanged),
            'check' => _CheckEditor(block: block, onChanged: onChanged),
            'table' => _TableEditor(block: block, onChanged: onChanged),
            'img' => _PictureEditor(block: block, onChanged: onChanged),
            _ => Divider(color: c.line, thickness: 2),
          },
        ),
      ]),
    );
  }
}

class _HeadingEditor extends StatefulWidget {
  const _HeadingEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_HeadingEditor> createState() => _HeadingEditorState();
}

class _HeadingEditorState extends State<_HeadingEditor> {
  late final _c = TextEditingController(text: widget.block.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _c,
          style: TextStyle(fontSize: b.level == 1 ? 21 : (b.level == 2 ? 17 : 14), fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: 'Heading'),
          onChanged: (v) {
            b.text = v;
            widget.onChanged();
          },
        ),
      ),
      const SizedBox(width: 10),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 1, label: Text('Large')),
          ButtonSegment(value: 2, label: Text('Medium')),
          ButtonSegment(value: 3, label: Text('Small')),
        ],
        selected: {b.level.clamp(1, 3)},
        onSelectionChanged: (v) => setState(() {
          b.level = v.first;
          widget.onChanged();
        }),
      ),
    ]);
  }
}

/// Multi-line text with a Bold button (wraps the selected words in **).
class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.block, required this.onChanged, required this.hint});
  final BepBlock block;
  final VoidCallback onChanged;
  final String hint;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _c = TextEditingController(text: widget.block.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _bold() {
    final sel = _c.selection;
    if (!sel.isValid || sel.isCollapsed) {
      showInfo(context, 'Select the words to make bold first.');
      return;
    }
    final t = _c.text;
    final picked = t.substring(sel.start, sel.end);
    final next = picked.startsWith('**') && picked.endsWith('**') && picked.length > 4 ? picked.substring(2, picked.length - 2) : '**$picked**';
    _c.value = TextEditingValue(text: t.replaceRange(sel.start, sel.end, next), selection: TextSelection(baseOffset: sel.start, extentOffset: sel.start + next.length));
    widget.block.text = _c.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: TextField(
          controller: _c,
          minLines: 2,
          maxLines: null,
          style: const TextStyle(fontSize: 15, height: 1.4),
          decoration: InputDecoration(hintText: widget.hint),
          onChanged: (v) {
            widget.block.text = v;
            widget.onChanged();
          },
        ),
      ),
      IconButton(tooltip: 'Bold', onPressed: _bold, icon: const Icon(Icons.format_bold)),
    ]);
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final b = widget.block;
    final (bg, line, _) = noteLook(b.tone, c);
    const names = {'info': 'Info', 'warning': 'Warning', 'tip': 'Tip', 'important': 'Important'};
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: line, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, children: [
          for (final t in BepBlock.tones)
            ChoiceChip(
              label: Text(names[t]!),
              selected: b.tone == t,
              onSelected: (_) => setState(() {
                b.tone = t;
                widget.onChanged();
              }),
            ),
        ]),
        const SizedBox(height: 8),
        _TextEditor(block: b, onChanged: widget.onChanged, hint: 'Text in the box…'),
      ]),
    );
  }
}

/// Bullets / numbered list: one point per line; two spaces at the start indent it.
class _ListEditor extends StatefulWidget {
  const _ListEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final _c = TextEditingController(text: widget.block.items.join('\n'));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _c,
        minLines: 3,
        maxLines: null,
        style: const TextStyle(fontSize: 15, height: 1.5),
        decoration: InputDecoration(hintText: widget.block.type == 'ol' ? 'First step\nSecond step' : 'First point\nSecond point'),
        onChanged: (v) {
          widget.block.items = v.split('\n');
          widget.onChanged();
        },
      ),
      const SizedBox(height: 4),
      Text('One point per line. Start a line with two spaces to indent it.', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}

class _CheckEditor extends StatefulWidget {
  const _CheckEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_CheckEditor> createState() => _CheckEditorState();
}

class _CheckEditorState extends State<_CheckEditor> {
  final _controllers = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    while (b.checks.length < b.items.length) {
      b.checks.add(false);
    }
    for (final t in b.items) {
      _controllers.add(TextEditingController(text: t));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < b.items.length; i++)
        Row(children: [
          Checkbox(
            value: b.checks[i],
            onChanged: (v) => setState(() {
              b.checks[i] = v ?? false;
              widget.onChanged();
            }),
          ),
          Expanded(
            child: TextField(
              controller: _controllers[i],
              decoration: const InputDecoration(isDense: true, hintText: 'Item'),
              onChanged: (v) {
                b.items[i] = v;
                widget.onChanged();
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove item',
            onPressed: () => setState(() {
              b.items.removeAt(i);
              b.checks.removeAt(i);
              _controllers.removeAt(i).dispose();
              widget.onChanged();
            }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            b.items.add('');
            b.checks.add(false);
            _controllers.add(TextEditingController());
            widget.onChanged();
          }),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add item'),
        ),
      ),
    ]);
  }
}

/// A grid of cells with buttons to add or remove rows and columns.
class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  /// Bumped when the shape changes, so the cell fields are rebuilt with the right text.
  int _shape = 0;

  int get _cols => widget.block.rows.isEmpty ? 0 : widget.block.rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  void _edit(VoidCallback f) {
    setState(() {
      f();
      _shape++;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final b = widget.block;
    for (final r in b.rows) {
      while (r.length < _cols) {
        r.add('');
      }
    }
    final cols = _cols;
    const cellW = 170.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(onPressed: () => _edit(() => b.rows.add(List.filled(cols == 0 ? 1 : cols, '', growable: true))), icon: const Icon(Icons.add, size: 18), label: const Text('Row')),
        OutlinedButton.icon(
          onPressed: () => _edit(() {
            if (b.rows.isEmpty) b.rows.add(['']);
            for (final r in b.rows) {
              r.add('');
            }
          }),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Column'),
        ),
        FilterChip(
          label: const Text('First row is the heading'),
          selected: b.header,
          onSelected: (v) => _edit(() => b.header = v),
        ),
        Text('${b.rows.length} × $cols', style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
      const SizedBox(height: 8),
      Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Column remove buttons
            Row(children: [
              for (var col = 0; col < cols; col++)
                SizedBox(
                  width: cellW,
                  child: Center(
                    child: IconButton(
                      tooltip: 'Remove column ${col + 1}',
                      visualDensity: VisualDensity.compact,
                      onPressed: cols <= 1
                          ? null
                          : () => _edit(() {
                                for (final r in b.rows) {
                                  if (col < r.length) r.removeAt(col);
                                }
                              }),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ),
            ]),
            for (var r = 0; r < b.rows.length; r++)
              Row(children: [
                for (var col = 0; col < cols; col++)
                  Container(
                    width: cellW,
                    decoration: BoxDecoration(
                      color: b.header && r == 0 ? c.surface2 : null,
                      border: Border.all(color: c.line, width: 0.8),
                    ),
                    child: TextFormField(
                      key: ValueKey('cell-$_shape-$r-$col'),
                      initialValue: b.rows[r][col],
                      minLines: 1,
                      maxLines: 5,
                      style: TextStyle(fontSize: 14, fontWeight: b.header && r == 0 ? FontWeight.w800 : FontWeight.w400),
                      decoration: const InputDecoration(isDense: true, border: InputBorder.none, filled: false, contentPadding: EdgeInsets.all(8)),
                      onChanged: (v) {
                        b.rows[r][col] = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                IconButton(
                  tooltip: 'Remove row',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _edit(() => b.rows.removeAt(r)),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

class _PictureEditor extends StatefulWidget {
  const _PictureEditor({required this.block, required this.onChanged});
  final BepBlock block;
  final VoidCallback onChanged;

  @override
  State<_PictureEditor> createState() => _PictureEditorState();
}

class _PictureEditorState extends State<_PictureEditor> {
  late final _caption = TextEditingController(text: widget.block.caption);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _replace() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (x == null) return;
    final Uint8List bytes = await x.readAsBytes();
    setState(() {
      widget.block.bytes = bytes;
      widget.block.path = '';
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (b.bytes != null || b.path.isNotEmpty)
        BepPicture(key: ValueKey('${b.path}-${b.bytes?.length}'), block: b, maxHeight: 260)
      else
        OutlinedButton.icon(onPressed: _replace, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Choose a picture')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _caption,
            decoration: const InputDecoration(isDense: true, hintText: 'Caption (optional)'),
            onChanged: (v) {
              b.caption = v;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        if (b.bytes != null || b.path.isNotEmpty) TextButton(onPressed: _replace, child: const Text('Replace')),
      ]),
    ]);
  }
}
