import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../util/pick_file.dart';
import '../util/save_file.dart';
import '../widgets/common.dart';
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
        await s.api.saveBepSection(values: {'project_id': s.project!.id, 'title': title, 'body': body, 'sort': sort++});
      }
      await s.reloadBep();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _move(AppState s, int index, int by) async {
    final list = [...s.bepSections];
    final j = index + by;
    if (j < 0 || j >= list.length) return;
    final a = list.removeAt(index);
    list.insert(j, a);
    try {
      for (var i = 0; i < list.length; i++) {
        if (list[i].sort != i) await s.api.saveBepSection(id: list[i].id, values: {'sort': i});
      }
      await s.reloadBep();
    } catch (e) {
      if (mounted) showError(context, e);
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
          OutlinedButton.icon(onPressed: () => openBepSectionForm(context), icon: const Icon(Icons.add, size: 20), label: const Text('Add Section')),
          const SizedBox(width: 8),
        ],
        if (admin)
          FilledButton.icon(onPressed: () => uploadBepFile(context), icon: const Icon(Icons.upload_file, size: 20), label: const Text('Upload File')),
        const SizedBox(width: 8),
      ],
    );

    final sections = _Sections(
      keyFor: _keyFor,
      onJump: _jump,
      onTemplate: () => _addTemplate(s),
      onMove: (i, by) => _move(s, i, by),
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
              Tab(text: 'Files (${s.bepFiles.length})'),
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
          SizedBox(
            width: 400,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.panel, border: Border(left: BorderSide(color: c.line))),
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
  const _Sections({required this.keyFor, required this.onJump, required this.onTemplate, required this.onMove});
  final GlobalKey Function(String id) keyFor;
  final void Function(String id) onJump;
  final VoidCallback onTemplate;
  final void Function(int index, int by) onMove;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final admin = s.canEditBep;
    final list = s.bepSections;
    final pad = isWide(context) ? 24.0 : 14.0;

    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No BEP yet',
        body: admin
            ? 'Add the rules every trade must follow: naming conventions, levels, coordinates, software versions, upload schedule and more.'
            : 'The Christman VDC team will post the BIM Execution Plan here.',
        action: admin
            ? Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                FilledButton.icon(onPressed: onTemplate, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text('Start with standard BEP sections')),
                OutlinedButton.icon(onPressed: () => openBepSectionForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('Blank section')),
              ])
            : null,
      );
    }

    final updated = list.map((x) => x.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Last updated ${weekdayDate(updated)}', style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 10),
            // Contents
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CONTENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.muted)),
                const SizedBox(height: 8),
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
                  admin: admin,
                  first: i == 0,
                  last: i == list.length - 1,
                  onMove: (by) => onMove(i, by),
                ),
              ),
            if (admin)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(onPressed: () => openBepSectionForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add Section')),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.number, required this.section, required this.admin, required this.first, required this.last, required this.onMove});
  final int number;
  final BepSection section;
  final bool admin, first, last;
  final void Function(int by) onMove;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = CwColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
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
            if (admin) ...[
              IconButton(tooltip: 'Move up', onPressed: first ? null : () => onMove(-1), icon: const Icon(Icons.arrow_upward, size: 20)),
              IconButton(tooltip: 'Move down', onPressed: last ? null : () => onMove(1), icon: const Icon(Icons.arrow_downward, size: 20)),
              IconButton(tooltip: 'Edit', onPressed: () => openBepSectionForm(context, section: section), icon: const Icon(Icons.edit_outlined, size: 20)),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: section.body.trim().isEmpty
              ? Text('Nothing written yet.', style: TextStyle(color: c.muted, fontStyle: FontStyle.italic))
              : BepText(section.body),
        ),
      ]),
    );
  }
}

/// Shows BEP text with light formatting:
///   "# Heading"        a small heading
///   "- point"          a bullet
///   "Label: value"     the label in bold (short labels only)
class BepText extends StatelessWidget {
  const BepText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final base = TextStyle(fontSize: 15, height: 1.45, color: c.ink);
    final out = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 8));
      } else if (line.startsWith('#')) {
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 6, bottom: 4),
          child: Text(line.replaceFirst(RegExp(r'^#+\s*'), '').toUpperCase(),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: c.accentText)),
        ));
      } else if (RegExp(r'^\s*[-*•]\s+').hasMatch(line)) {
        final indent = RegExp(r'^\s*').stringMatch(line)!.length;
        out.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + indent * 8, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
            ),
            Expanded(child: _labelled(line.replaceFirst(RegExp(r'^\s*[-*•]\s+'), ''), base)),
          ]),
        ));
      } else {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 2), child: _labelled(line, base)));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out));
  }

  Widget _labelled(String line, TextStyle base) {
    final m = RegExp(r'^([^:]{1,32}):(\s|$)(.*)$').firstMatch(line);
    if (m == null || m.group(1)!.contains('http')) return Text(line, style: base);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: '${m.group(1)}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: m.group(3)),
    ]));
  }
}

Future<void> openBepSectionForm(BuildContext context, {BepSection? section}) async {
  final s = context.read<AppState>();
  final title = TextEditingController(text: section?.title ?? '');
  final body = TextEditingController(text: section?.body ?? '');
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(section == null ? 'New BEP section' : 'Edit section'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FieldLabel('Section title', hint: 'e.g. Model Naming Convention'),
              TextField(controller: title, autofocus: section == null),
              const SizedBox(height: 10),
              const FieldLabel('Rules and notes'),
              TextField(
                controller: body,
                minLines: 10,
                maxLines: 24,
                style: const TextStyle(fontSize: 14, height: 1.4),
                decoration: const InputDecoration(hintText: '# Heading\n- A rule or point\nLabel: value'),
              ),
              const SizedBox(height: 6),
              Text(
                'Tips: start a line with "# " for a heading, "- " for a bullet. "Label: value" shows the label in bold.',
                style: TextStyle(fontSize: 12.5, color: CwColors.of(ctx).muted),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
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
                    if (title.text.trim().isEmpty) {
                      setState(() => error = 'Give the section a title.');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      if (section == null) {
                        final next = s.bepSections.isEmpty ? 0 : s.bepSections.map((x) => x.sort).reduce((a, b) => a > b ? a : b) + 1;
                        await s.api.saveBepSection(values: {'project_id': s.project!.id, 'title': title.text.trim(), 'body': body.text, 'sort': next});
                      } else {
                        await s.api.saveBepSection(id: section.id, values: {'title': title.text.trim(), 'body': body.text});
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
            child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      ),
    ),
  );
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
    final files = s.bepFiles.where((f) => trade == null || f.tradeId == null || f.tradeId == trade).toList();
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
