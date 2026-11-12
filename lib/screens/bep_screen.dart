import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/bep_blocks.dart';
import '../util/dates.dart';
import '../util/docx.dart';
import '../util/pick_file.dart';
import '../util/save_file.dart';
import '../widgets/bep_view.dart';
import '../widgets/common.dart';
import 'bep_editor.dart';
import 'notifications_screen.dart';

/// Starting sections for a new BEP. The admin edits or deletes them.
const bepTemplate = <(String, String)>[
  (
    'Project Information & Contacts',
    '# Project\nName: \nAddress: \nOwner: \n\n# Christman VDC\nVDC Coordinator: \nEmail: \n\n# Trade BIM leads\n- Mechanical: \n- Plumbing: \n- Electrical: \n- Fire Protection: '
  ),
  (
    'Software & Versions',
    '- Authoring: Revit 20XX (do not upgrade during the project)\n- Coordination: Navisworks Manage 20XX\n- Exports: NWC from Revit, IFC only when agreed\n- File sharing: '
  ),
  (
    'Model Naming Convention',
    'Format: PROJECT-TRADE-AREA-LEVEL.rvt\nExample: NMC-MECH-A-L02.rvt\n\n# Trade codes\n- ARCH Architectural\n- STR Structural\n- MECH Mechanical (HVAC)\n- PLMB Plumbing\n- ELEC Electrical\n- FP Fire Protection\n\n# Rules\n- No spaces; use dashes\n- Keep the same file name for every upload (no dates in the name)'
  ),
  (
    'Levels & Grids',
    '# Levels (Top of Slab)\n- Level 1: 0\'-0"\n- Level 2: \n- Level 3: \n- Roof: \n\n# Rules\n- Use the architect\'s level names exactly\n- Copy/Monitor grids and levels from the architectural model'
  ),
  (
    'Coordinates & Base Point',
    'Project Base Point: \nSurvey Point: \nTrue North angle: \n\n- Link all models Origin to Origin / Shared Coordinates\n- Check alignment with the structural model before every upload'
  ),
  (
    'Model Breakdown & Worksets',
    '- One model per trade per building / area\n- Worksets: by system (Supply, Return, Exhaust, Hangers…)\n- Remove unused links, views and CAD imports before upload'
  ),
  (
    'Level of Development (LOD)',
    '- Coordination: LOD 350 for all MEP and FP\n- Model all hangers, supports and access zones above 2"\n- Include insulation thickness on duct and pipe'
  ),
  (
    'Model Submission Schedule',
    '- Upload updated models every: \n- Due by: (day and time) before the coordination meeting\n- Upload to: \n- Format: NWC + RVT'
  ),
  (
    'Clash Detection Rules & Tolerances',
    '- Hard clash tolerance: 1/2"\n- Clearance for access / maintenance: as per spec\n# Priority\n- 1. Gravity (sanitary, storm)\n- 2. Large duct\n- 3. Pressurized pipe\n- 4. Cable tray / conduit\n- 5. Small pipe and conduit'
  ),
  (
    'Coordination Meeting Process',
    '- Weekly meeting: (day, time, place / Teams link)\n- Review new clashes and open items by area and level\n- Ball in court is tracked in this app; respond before the next meeting\n- Sign-off when an area has no open items'
  ),
  (
    'File Sharing & Deliverables',
    '- Coordinated models signed off per area\n- Fabrication / spool drawings from the signed-off model\n- As-built model at closeout\n- All files in the Files list of this BEP'
  ),
];

class BepScreen extends StatefulWidget {
  const BepScreen({super.key});

  @override
  State<BepScreen> createState() => _BepScreenState();
}

class _BepScreenState extends State<BepScreen> {
  final _keys = <String, GlobalKey>{};
  final _open = <String>{}; // long sections that are unfolded
  String? _trade; // filter for files: null = all

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  void _jump(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.02);
  }

  Future<void> _addTemplate(AppState s) async {
    try {
      var sort = 0;
      for (final (title, body) in bepTemplate) {
        final blocks = blocksFromText(body);
        await s.api.saveBepSection(values: {
          'project_id': s.project!.id,
          'title': title,
          'content': blocksToJson(blocks),
          'body': blocksPlainText(blocks),
          'sort': sort++,
        });
      }
      await s.reloadBep();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Drag the sections into a new order (or use the arrows), then save.
  Future<void> _arrange(AppState s) async {
    final list = [...s.bepSections];
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final c = CwColors.of(ctx);
        void move(int from, int to) => setState(() => list.insert(to, list.removeAt(from)));
        return AlertDialog(
          title: const Text('Arrange sections'),
          content: SizedBox(
            width: 520,
            height: (list.length * 58.0 + 40).clamp(160.0, 520.0).toDouble(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Drag a section by its handle, or use the arrows.', style: TextStyle(fontSize: 13, color: c.muted)),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: list.length,
                  onReorder: (from, to) => move(from, to > from ? to - 1 : to),
                  itemBuilder: (ctx, i) => Material(
                    key: ValueKey(list[i].id),
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 4, right: 0),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(cursor: SystemMouseCursors.grab, child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.drag_indicator, color: c.muted))),
                      ),
                      title: Text('${i + 1}. ${list[i].title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'To the top', visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => move(i, 0), icon: const Icon(Icons.vertical_align_top, size: 19)),
                        IconButton(tooltip: 'Up', visualDensity: VisualDensity.compact, onPressed: i == 0 ? null : () => move(i, i - 1), icon: const Icon(Icons.arrow_upward, size: 19)),
                        IconButton(tooltip: 'Down', visualDensity: VisualDensity.compact, onPressed: i == list.length - 1 ? null : () => move(i, i + 1), icon: const Icon(Icons.arrow_downward, size: 19)),
                        IconButton(tooltip: 'To the bottom', visualDensity: VisualDensity.compact, onPressed: i == list.length - 1 ? null : () => move(i, list.length - 1), icon: const Icon(Icons.vertical_align_bottom, size: 19)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save order')),
          ],
        );
      }),
    );
    if (save != true) return;
    try {
      for (var i = 0; i < list.length; i++) {
        if (list[i].sort != i) await s.api.saveBepSection(id: list[i].id, values: {'sort': i});
      }
      await s.reloadBep();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Turns a Word BEP into sections (one per top heading), with tables and pictures.
  Future<void> _importWord(AppState s) async {
    final f = await pickOneFile(extensions: const ['docx'], label: 'Word document');
    if (f == null || !mounted) return;
    DocxContent content;
    try {
      content = await compute(readDocx, f.bytes);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final parts = content.sections();
    final pictures = content.blocks.where((b) => b.type == 'img').length;
    final tables = content.blocks.where((b) => b.type == 'table').length;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import ${f.name}'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Found ${parts.length} section${parts.length == 1 ? '' : 's'}, $tables table${tables == 1 ? '' : 's'} and $pictures picture${pictures == 1 ? '' : 's'}.'),
            if (content.skippedPictures > 0) Text('${content.skippedPictures} very large pictures will be left out.', style: TextStyle(color: CwColors.of(ctx).muted)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(shrinkWrap: true, children: [
                for (var i = 0; i < parts.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${i + 1}. ${parts[i].$1}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('The new sections are added after the ones you already have.', style: TextStyle(fontSize: 12.5, color: CwColors.of(ctx).muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          if (parts.length > 1) OutlinedButton(onPressed: () => Navigator.pop(ctx, 'one'), child: const Text('All in one section')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'many'), child: Text(parts.length > 1 ? 'Create ${parts.length} sections' : 'Import')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Importing… pictures are being uploaded.'))])),
    );
    try {
      final list = choice == 'one' ? [(f.name.replaceFirst(RegExp(r'\.docx$', caseSensitive: false), ''), content.blocks)] : parts;
      final n = await saveImportedSections(s, list);
      if (mounted) {
        Navigator.of(context).pop();
        showInfo(context, 'Added $n section${n == 1 ? '' : 's'} from ${f.name}.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final wide = isWide(context);
    final admin = s.canEditBep;

    final header = PageHeader(
      title: wide ? 'BIM Execution Plan' : 'BEP',
      actions: [
        if (admin && wide) ...[
          TextButton.icon(onPressed: () => _importWord(s), icon: const Icon(Icons.description_outlined, size: 20), label: const Text('Import Word')),
          const SizedBox(width: 4),
          if (s.bepSections.length > 1) ...[
            OutlinedButton.icon(onPressed: () => _arrange(s), icon: const Icon(Icons.swap_vert, size: 20), label: const Text('Arrange')),
            const SizedBox(width: 8),
          ],
          OutlinedButton.icon(onPressed: () => openBepSectionEditor(context), icon: const Icon(Icons.add, size: 20), label: const Text('Add Section')),
          const SizedBox(width: 8),
        ],
        if (admin)
          FilledButton.icon(onPressed: () => uploadBepFile(context), icon: const Icon(Icons.upload_file, size: 20), label: Text(wide ? 'Upload File' : 'File')),
        if (admin && !wide)
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'add') openBepSectionEditor(context);
              if (v == 'arrange') _arrange(s);
              if (v == 'word') _importWord(s);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'add', child: Text('Add section')),
              if (s.bepSections.length > 1) const PopupMenuItem(value: 'arrange', child: Text('Arrange sections')),
              const PopupMenuItem(value: 'word', child: Text('Import Word file')),
            ],
          ),
        const SizedBox(width: 8),
      ],
    );

    final sections = _Sections(
      keyFor: _keyFor,
      onJump: _jump,
      onTemplate: () => _addTemplate(s),
      onArrange: () => _arrange(s),
      onImport: () => _importWord(s),
      open: _open,
      onToggle: (id) => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id)),
      onAll: (all) => setState(() {
        _open.clear();
        if (all) _open.addAll(s.bepSections.map((x) => x.id));
      }),
    );
    final files = _FilesPanel(trade: _trade, onTrade: (t) => setState(() => _trade = t));

    if (!wide) {
      return DefaultTabController(
        length: 2,
        child: Column(children: [
          header,
          Material(
            color: c.surface,
            child: TabBar(tabs: [
              const Tab(text: 'Rules & Notes'),
              Tab(text: 'Files (${s.bepFiles.where((f) => !f.isMain).length})'),
            ]),
          ),
          Expanded(child: TabBarView(children: [sections, files])),
        ]),
      );
    }
    return Column(children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ColoredBox(color: c.surface, child: sections)),
          ResizeHandle(
            showLine: true,
            onDrag: (dx) => s.setSizes(s.view.copyWith(factsW: s.view.factsW - dx)),
            onReset: () => s.setSizes(s.view.copyWith(factsW: 300)),
          ),
          SizedBox(
            width: (s.view.factsW + 100).clamp(260.0, 620.0).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.panel),
              child: files,
            ),
          ),
        ]),
      ),
    ]);
  }
}

// =====================================================================
// Rules & notes
// =====================================================================

class _Sections extends StatelessWidget {
  const _Sections({
    required this.keyFor,
    required this.onJump,
    required this.onTemplate,
    required this.onArrange,
    required this.onImport,
    required this.open,
    required this.onToggle,
    required this.onAll,
  });
  final GlobalKey Function(String id) keyFor;
  final void Function(String id) onJump;
  final VoidCallback onTemplate, onArrange, onImport;
  final Set<String> open;
  final void Function(String id) onToggle;
  final void Function(bool all) onAll;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final admin = s.canEditBep;
    final list = s.bepSections;
    final pad = isWide(context) ? 24.0 : 14.0;

    if (list.isEmpty) {
      return ListView(padding: EdgeInsets.all(pad), children: [
        const _MainFileCard(),
        const SizedBox(height: 20),
        EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No BEP sections yet',
          body: admin
              ? 'Add the rules every trade must follow: naming conventions, levels, coordinates, software versions, upload schedule and more. You can also import your BEP Word file.'
              : 'The Christman VDC team will post the BIM Execution Plan here.',
          action: admin
              ? Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  FilledButton.icon(onPressed: onTemplate, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text('Start with standard BEP sections')),
                  OutlinedButton.icon(onPressed: onImport, icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Import Word file')),
                  OutlinedButton.icon(onPressed: () => openBepSectionEditor(context), icon: const Icon(Icons.add, size: 18), label: const Text('Blank section')),
                ])
              : null,
        ),
      ]);
    }

    final updated = list.map((x) => x.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final blocks = {for (final x in list) x.id: x.blocks};
    final long = {for (final x in list) if (blocksHeightEstimate(blocks[x.id]!) > 18) x.id};
    final allOpen = long.isNotEmpty && long.every(open.contains);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _MainFileCard(),
            const SizedBox(height: 16),
            // Contents
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('CONTENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.muted)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Last updated ${weekdayDate(updated)}', style: TextStyle(fontSize: 12, color: c.muted))),
                  if (long.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => onAll(!allOpen),
                      icon: Icon(allOpen ? Icons.unfold_less : Icons.unfold_more, size: 18),
                      label: Text(allOpen ? 'Fold all' : 'Unfold all'),
                    ),
                  if (admin && list.length > 1) TextButton.icon(onPressed: onArrange, icon: const Icon(Icons.swap_vert, size: 18), label: const Text('Arrange')),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < list.length; i++)
                    ActionChip(
                      label: Text('${i + 1}. ${list[i].title}'),
                      onPressed: () => onJump(list[i].id),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < list.length; i++)
              Padding(
                key: keyFor(list[i].id),
                padding: const EdgeInsets.only(bottom: 14),
                child: _SectionCard(
                  number: i + 1,
                  section: list[i],
                  blocks: blocks[list[i].id]!,
                  admin: admin,
                  foldable: long.contains(list[i].id),
                  unfolded: open.contains(list[i].id),
                  onToggle: () => onToggle(list[i].id),
                ),
              ),
            if (admin)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(onPressed: () => openBepSectionEditor(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add Section')),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.section,
    required this.blocks,
    required this.admin,
    required this.foldable,
    required this.unfolded,
    required this.onToggle,
  });
  final int number;
  final BepSection section;
  final List<BepBlock> blocks;
  final bool admin, foldable, unfolded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = CwColors.of(context);
    final view = blocks.isEmpty ? Text('Nothing written yet.', style: TextStyle(color: c.muted, fontStyle: FontStyle.italic)) : BepBlocksView(blocks);
    final folded = foldable && !unfolded;
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: foldable ? onToggle : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(8)),
                child: Text('$number', style: TextStyle(color: c.accentInk, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(section.title, style: condensed(21, color: c.ink))),
              if (foldable)
                IconButton(tooltip: unfolded ? 'Fold' : 'Show all', onPressed: onToggle, icon: Icon(unfolded ? Icons.unfold_less : Icons.unfold_more, size: 20)),
              if (admin) ...[
                IconButton(tooltip: 'Edit', onPressed: () => openBepSectionEditor(context, section: section), icon: const Icon(Icons.edit_outlined, size: 20)),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () async {
                    if (!await confirm(context, 'Delete "${section.title}"?', 'This section is removed from the BEP for everyone.', ok: 'Delete', danger: true)) return;
                    try {
                      await s.api.deleteBepSection(section.id);
                      await s.reloadBep();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, foldable ? 4 : 16),
          child: folded
              ? Stack(children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: view)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 90,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [c.card.withValues(alpha: 0), c.card],
                          ),
                        ),
                      ),
                    ),
                  ),
                ])
              : view,
        ),
        if (foldable)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Center(
              child: TextButton.icon(
                onPressed: onToggle,
                icon: Icon(unfolded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                label: Text(unfolded ? 'Show less' : 'Show more'),
              ),
            ),
          ),
      ]),
    );
  }
}

// =====================================================================
// Project BEP File (the main document, at the top)
// =====================================================================

class _MainFileCard extends StatefulWidget {
  const _MainFileCard();

  @override
  State<_MainFileCard> createState() => _MainFileCardState();
}

class _MainFileCardState extends State<_MainFileCard> {
  String? _busy; // 'open', 'download', 'upload'

  Future<void> _get(BepFile f, {required bool open}) async {
    final s = context.read<AppState>();
    setState(() => _busy = open ? 'open' : 'download');
    try {
      final bytes = await s.api.fileBytes(f.path);
      if (open) {
        await openFileBytes(bytes, f.fileName, mimeType: Api.mimeFor(f.fileName));
      } else {
        final msg = await saveOrShareFile(bytes, safeFileName(f.fileName), mimeType: Api.mimeFor(f.fileName));
        if (msg != null && mounted) showInfo(context, msg);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _upload(BepFile? old) async {
    final s = context.read<AppState>();
    final picked = await pickOneFile(extensions: const ['pdf', 'docx'], label: 'BEP document');
    if (picked == null || !mounted) return;
    setState(() => _busy = 'upload');
    try {
      final path = await s.api.uploadFile(s.project!.id, 'bep', picked.bytes, picked.name);
      await s.api.saveBepFile(values: {
        'project_id': s.project!.id,
        'name': picked.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        'description': '',
        'category': BepFile.mainCategory,
        'trade_id': null,
        'path': path,
        'file_name': picked.name,
        'size_bytes': picked.bytes.length,
      });
      // The old one stays in the Files list as the previous version.
      if (old != null) await s.api.saveBepFile(id: old.id, values: {'category': 'BEP document', 'name': '${old.name} (previous)'});
      await s.reloadBep();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final admin = s.canEditBep;
    final main = s.bepFiles.where((f) => f.isMain).firstOrNull;
    final label = Text('PROJECT BEP FILE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: c.accentText));
    Widget spin() => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

    if (main == null) {
      if (!admin) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.dashed, width: 1.5), color: c.surface2),
        child: Row(children: [
          Icon(Icons.picture_as_pdf_outlined, size: 34, color: c.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label,
              const SizedBox(height: 2),
              Text('Upload the main BEP document (PDF). Everyone on the project can open it from here.', style: TextStyle(fontSize: 14, color: c.ink2)),
            ]),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _busy != null ? null : () => _upload(null),
            icon: _busy == 'upload' ? spin() : const Icon(Icons.upload_file, size: 18),
            label: const Text('Upload BEP File'),
          ),
        ]),
      );
    }

    final buttons = Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        onPressed: _busy != null ? null : () => _get(main, open: true),
        icon: _busy == 'open' ? spin() : const Icon(Icons.open_in_new, size: 18),
        label: const Text('Open'),
      ),
      OutlinedButton.icon(
        onPressed: _busy != null ? null : () => _get(main, open: false),
        icon: _busy == 'download' ? spin() : const Icon(Icons.download, size: 18),
        label: const Text('Download'),
      ),
      if (admin)
        TextButton.icon(
          onPressed: _busy != null ? null : () => _upload(main),
          icon: _busy == 'upload' ? spin() : const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Replace'),
        ),
    ]);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c.accent, width: 5), top: BorderSide(color: c.line), right: BorderSide(color: c.line), bottom: BorderSide(color: c.line)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final info = Row(children: [
          Icon(fileIcon(main.fileName), size: 40, color: c.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label,
              const SizedBox(height: 2),
              Text(main.name, style: condensed(22, color: c.ink)),
              Text('${main.fileName} · ${fileSizeText(main.sizeBytes)} · updated ${weekdayDate(main.createdAt)}', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
        ]);
        if (box.maxWidth < 620) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 12), buttons]);
        }
        return Row(children: [Expanded(child: info), const SizedBox(width: 12), buttons]);
      }),
    );
  }
}

// =====================================================================
// Files
// =====================================================================

IconData fileIcon(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'xlsx' || 'xls' || 'csv' => Icons.table_view_outlined,
    'docx' || 'doc' || 'txt' => Icons.description_outlined,
    'rvt' || 'rte' || 'rfa' || 'nwc' || 'nwd' || 'nwf' || 'ifc' || 'dwg' => Icons.view_in_ar_outlined,
    'png' || 'jpg' || 'jpeg' => Icons.image_outlined,
    'zip' => Icons.folder_zip_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _FilesPanel extends StatelessWidget {
  const _FilesPanel({required this.trade, required this.onTrade});
  final String? trade;
  final void Function(String? t) onTrade;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final files = s.bepFiles.where((f) => !f.isMain && (trade == null || f.tradeId == null || f.tradeId == trade)).toList();
    final cats = <String>[
      ...BepFile.categories.where((k) => files.any((f) => f.category == k)),
      ...{for (final f in files) f.category}.where((k) => !BepFile.categories.contains(k)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
      children: [
        Row(children: [
          Expanded(child: Text('FILES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.muted))),
          if (s.trades.isNotEmpty)
            DropdownButton<String?>(
              value: trade,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All trades')),
                for (final t in s.trades) DropdownMenuItem<String?>(value: t.id, child: Text('For ${t.name}')),
              ],
              onChanged: onTrade,
            ),
        ]),
        const SizedBox(height: 8),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text(
              s.canEditBep ? 'Upload the BEP document, Revit templates, shared models and families for the trades.' : 'No files yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4),
            ),
          ),
        for (final cat in cats) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(cat, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink2)),
          ),
          for (final f in files.where((f) => f.category == cat)) _FileTile(file: f),
        ],
      ],
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({required this.file});
  final BepFile file;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _busy = false;

  Future<void> _download() async {
    final s = context.read<AppState>();
    final f = widget.file;
    setState(() => _busy = true);
    try {
      final bytes = await s.api.fileBytes(f.path);
      final msg = await saveOrShareFile(bytes, safeFileName(f.fileName), mimeType: Api.mimeFor(f.fileName));
      if (msg != null && mounted) showInfo(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final f = widget.file;
    final forWho = f.tradeId == null ? 'All trades' : (s.tradeById(f.tradeId)?.name ?? 'One trade');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : _download,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(fileIcon(f.fileName), color: c.accent)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  if (f.description.isNotEmpty) Text(f.description, style: TextStyle(fontSize: 13, color: c.ink2)),
                  const SizedBox(height: 2),
                  Text('$forWho · ${f.fileName} · ${fileSizeText(f.sizeBytes)} · ${shortDate(f.createdAt)}', style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
              _busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(tooltip: 'Download', onPressed: _download, icon: const Icon(Icons.download)),
              if (s.canEditBep)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await uploadBepFile(context, existing: f);
                    } else if (v == 'delete') {
                      if (!await confirm(context, 'Delete "${f.name}"?', 'The file is removed for everyone.', ok: 'Delete', danger: true)) return;
                      try {
                        await s.api.deleteBepFile(f);
                        await s.reloadBep();
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit details')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Upload a new BEP file, or edit the details of an [existing] one.
Future<void> uploadBepFile(BuildContext context, {BepFile? existing}) async {
  final s = context.read<AppState>();
  final PickedFile? picked = existing == null ? await pickOneFile() : null;
  if (existing == null && picked == null) return;
  if (!context.mounted) return;
  final baseName = existing?.name ?? picked!.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final name = TextEditingController(text: baseName);
  final desc = TextEditingController(text: existing?.description ?? '');
  var category = existing?.category ?? 'BEP document';
  if (!BepFile.categories.contains(category)) category = 'Other';
  String? trade = existing?.tradeId;
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Upload BEP file' : 'File details'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                existing == null ? '${picked!.name} · ${fileSizeText(picked!.bytes.length)}' : '${existing.fileName} · ${fileSizeText(existing.sizeBytes)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const FieldLabel('Name'),
              TextField(controller: name),
              const SizedBox(height: 10),
              const FieldLabel('Description', hint: 'optional'),
              TextField(controller: desc, minLines: 1, maxLines: 4),
              const SizedBox(height: 10),
              const FieldLabel('Type'),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: [for (final k in BepFile.categories) DropdownMenuItem(value: k, child: Text(k))],
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 10),
              const FieldLabel('For'),
              DropdownButtonFormField<String?>(
                initialValue: trade,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All trades')),
                  for (final t in s.trades) DropdownMenuItem<String?>(value: t.id, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => trade = v),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: TextStyle(color: CwColors.of(ctx).urgentText, fontWeight: FontWeight.w600)),
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
                    if (name.text.trim().isEmpty) {
                      setState(() => error = 'Give the file a name.');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final values = <String, dynamic>{
                        'name': name.text.trim(),
                        'description': desc.text.trim(),
                        'category': category,
                        'trade_id': trade,
                      };
                      if (existing == null) {
                        final path = await s.api.uploadFile(s.project!.id, 'bep', picked!.bytes, picked!.name);
                        await s.api.saveBepFile(values: {
                          ...values,
                          'project_id': s.project!.id,
                          'path': path,
                          'file_name': picked!.name,
                          'size_bytes': picked!.bytes.length,
                        });
                      } else {
                        await s.api.saveBepFile(id: existing.id, values: values);
                      }
                      await s.reloadBep();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setState(() {
                        busy = false;
                        error = e.toString();
                      });
                    }
                  },
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(existing == null ? 'Upload' : 'Save'),
          ),
        ],
      ),
    ),
  );
}
