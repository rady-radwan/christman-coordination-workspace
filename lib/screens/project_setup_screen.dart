import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';

/// Switch between the projects this person is on (the admin can also create one).
Future<void> showProjectPicker(BuildContext context) async {
  final s = context.read<AppState>();
  final picked = await showDialog<Object>(
    context: context,
    builder: (ctx) {
      final c = CwColors.of(ctx);
      return AlertDialog(
        title: const Text('Projects'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, children: [
                for (final p in s.projects)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    selected: p.id == s.project?.id,
                    selectedTileColor: c.accentSoft,
                    leading: Container(
                      width: 52,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: brandCopper, borderRadius: BorderRadius.circular(8)),
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(p.code, style: condensed(15, color: const Color(0xFF1A1512))),
                        ),
                      ),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([if (p.location.isNotEmpty) p.location, if (p.archived) 'Archived'].join(' · ')),
                    onTap: () => Navigator.pop(ctx, p),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          if (s.isAdmin)
            TextButton.icon(onPressed: () => Navigator.pop(ctx, 'new'), icon: const Icon(Icons.add), label: const Text('New project')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      );
    },
  );
  if (!context.mounted) return;
  if (picked is Project) {
    try {
      await s.selectProject(picked);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  } else if (picked == 'new') {
    await showNewProjectDialog(context);
  }
}

/// Admin: name + abbreviation; standard trades and item types are added automatically.
Future<void> showNewProjectDialog(BuildContext context) async {
  final s = context.read<AppState>();
  final name = TextEditingController();
  final code = TextEditingController();
  String? error;
  var busy = false;
  var codeTyped = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New project'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Project name'),
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Newcastle Medical Center'),
              onChanged: (v) {
                // Suggest initials as the abbreviation until the admin types one.
                if (!codeTyped) code.text = _initials(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            const FieldLabel('Abbreviation', hint: 'starts every item number'),
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: const InputDecoration(hintText: 'e.g. NMC', counterText: ''),
              onChanged: (_) => setState(() => codeTyped = true),
            ),
            const SizedBox(height: 8),
            Text('Item numbers will look like ${code.text.isEmpty ? 'NMC' : code.text.toUpperCase()}-CL-001.',
                style: TextStyle(fontSize: 13, color: CwColors.of(ctx).muted)),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: CwColors.of(ctx).urgentText, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final n = name.text.trim();
                    final cd = code.text.trim().toUpperCase();
                    if (n.isEmpty || !RegExp(r'^[A-Z0-9]{1,8}$').hasMatch(cd)) {
                      setState(() => error = 'Enter a name and an abbreviation of capital letters or numbers (up to 8).');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await s.createProject(n, cd);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setState(() {
                        busy = false;
                        error = e.toString();
                      });
                    }
                  },
            child: const Text('Create Project'),
          ),
        ],
      ),
    ),
  );
}

String _initials(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z0-9]').hasMatch(w) && w.toLowerCase() != 'project')
    .map((w) => w[0].toUpperCase())
    .take(8)
    .join();

/// Admin: project details, trades and item types (with their abbreviations).
class ProjectSetupScreen extends StatelessWidget {
  const ProjectSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.isAdmin) {
      return const EmptyState(icon: Icons.lock_outline, title: 'Admin only', body: 'Only the admin changes project setup.');
    }
    return Column(children: [
      PageHeader(
        title: 'Project Setup',
        actions: [
          OutlinedButton.icon(onPressed: () => showNewProjectDialog(context), icon: const Icon(Icons.add, size: 18), label: const Text('New Project')),
          const SizedBox(width: 8),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ProjectDetails(key: ValueKey(s.project!.id)),
                  const SizedBox(height: 24),
                  const _TradesTable(),
                  const SizedBox(height: 24),
                  const _TypesTable(),
                ]),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _ProjectDetails extends StatefulWidget {
  const _ProjectDetails({super.key});

  @override
  State<_ProjectDetails> createState() => _ProjectDetailsState();
}

class _ProjectDetailsState extends State<_ProjectDetails> {
  late final Project p = context.read<AppState>().project!;
  late final _name = TextEditingController(text: p.name);
  late final _code = TextEditingController(text: p.code);
  late final _location = TextEditingController(text: p.location);
  late final _buildings = TextEditingController(text: p.buildings.join(', '));
  late final _levels = TextEditingController(text: p.levels.join(', '));
  late final _zones = TextEditingController(text: p.zones.join(', '));
  late int _dueDays = p.defaultDueDays;
  late bool _archived = p.archived;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _location, _buildings, _levels, _zones]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _list(TextEditingController c) => c.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  Future<void> _save() async {
    final s = context.read<AppState>();
    final code = _code.text.trim().toUpperCase();
    if (code != p.code &&
        !await confirm(context, 'Change the abbreviation?',
            'New items will be numbered $code-…. Existing item numbers stay the same.', ok: 'Change')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await s.updateProject({
        'name': _name.text.trim(),
        'code': code,
        'location': _location.text.trim(),
        'buildings': _list(_buildings),
        'levels': _list(_levels),
        'zones': _list(_zones),
        'default_due_days': _dueDays,
        'archived': _archived,
      });
      if (mounted) showInfo(context, 'Project saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    Widget field(String label, TextEditingController ctrl, {String? hint, String? note}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [FieldLabel(label, hint: note), TextField(controller: ctrl, decoration: InputDecoration(hintText: hint))],
        );
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Project details', style: condensed(22, color: c.ink)),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 10, children: [
          SizedBox(width: 420, child: field('Project name', _name)),
          SizedBox(width: 180, child: field('Abbreviation', _code, hint: 'e.g. NMC')),
          SizedBox(width: 300, child: field('Location', _location, hint: 'City, State')),
        ]),
        const SizedBox(height: 10),
        field('Buildings', _buildings, hint: 'e.g. Building A, Building B', note: 'separate with commas'),
        const SizedBox(height: 10),
        field('Levels', _levels, hint: 'e.g. Level 1, Level 2, Level 3, Roof', note: 'used in drop-downs and the By Area view'),
        const SizedBox(height: 10),
        field('Zones / areas', _zones, hint: 'e.g. Zone A, Zone B, Corridor 3B'),
        const SizedBox(height: 14),
        Wrap(spacing: 20, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Default response time: ', style: TextStyle(fontWeight: FontWeight.w600)),
            DropdownButton<int>(
              value: _dueDays,
              items: [1, 2, 3, 5, 7, 10, 14].map((d) => DropdownMenuItem(value: d, child: Text('$d days'))).toList(),
              onChanged: (v) => setState(() => _dueDays = v ?? _dueDays),
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(value: _archived, onChanged: (v) => setState(() => _archived = v)),
            const SizedBox(width: 6),
            const Text('Archived (project finished)'),
          ]),
        ]),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save Project')),
        ),
      ]),
    );
  }
}

class _TradesTable extends StatelessWidget {
  const _TradesTable();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Trades', style: condensed(22, color: c.ink))),
          OutlinedButton.icon(
            onPressed: () => _editTrade(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Trade'),
          ),
        ]),
        Text('The subcontractor company shows next to the trade everywhere (e.g. Mechanical · Hart Mechanical).',
            style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 10),
        for (final t in s.trades)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
            child: Row(children: [
              SizedBox(width: 64, child: Text(t.code, style: condensed(17, color: c.accentText))),
              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(t.company.isEmpty ? 'Company not set' : t.company, style: TextStyle(color: t.company.isEmpty ? c.muted : c.ink2))),
              Text('${s.members.where((m) => m.tradeId == t.id).length} people', style: TextStyle(fontSize: 13, color: c.muted)),
              IconButton(tooltip: 'Edit', onPressed: () => _editTrade(context, t), icon: const Icon(Icons.edit_outlined, size: 20)),
              IconButton(
                tooltip: 'Delete',
                onPressed: () async {
                  if (!await confirm(context, 'Delete ${t.name}?', 'Only possible while no item and no person uses it.', ok: 'Delete', danger: true)) return;
                  try {
                    await s.api.deleteTrade(t.id);
                    await s.reloadSetup();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _editTrade(BuildContext context, Trade? t) async {
    final s = context.read<AppState>();
    final r = await _codeDialog(context,
        title: t == null ? 'Add trade' : 'Edit ${t.name}',
        name: t?.name ?? '',
        code: t?.code ?? '',
        company: t?.company ?? '',
        withCompany: true,
        maxCode: 6);
    if (r == null) return;
    try {
      await s.api.saveTrade(
          id: t?.id, projectId: s.project!.id, name: r.name, code: r.code, company: r.company, sort: t?.sort ?? s.trades.length + 1);
      await s.reloadSetup();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _TypesTable extends StatelessWidget {
  const _TypesTable();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Item types', style: condensed(22, color: c.ink))),
          OutlinedButton.icon(
            onPressed: () => _editType(context, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Type'),
          ),
        ]),
        Text('The abbreviation is the middle part of the number, e.g. ${s.project?.code ?? 'NMC'}-CL-001. Turn a type off to hide it from new items.',
            style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 10),
        for (final t in s.types)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
            child: Row(children: [
              SizedBox(width: 64, child: Text(t.code, style: condensed(17, color: c.accentText))),
              Expanded(child: Text(t.name, style: TextStyle(fontWeight: FontWeight.w600, color: t.active ? c.ink : c.muted))),
              Text('${s.items.where((i) => i.typeId == t.id).length} items', style: TextStyle(fontSize: 13, color: c.muted)),
              Switch(
                value: t.active,
                onChanged: (v) async {
                  try {
                    await s.api.saveType(id: t.id, projectId: t.projectId, name: t.name, code: t.code, active: v, sort: t.sort);
                    await s.reloadSetup();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
              IconButton(tooltip: 'Edit', onPressed: () => _editType(context, t), icon: const Icon(Icons.edit_outlined, size: 20)),
            ]),
          ),
      ]),
    );
  }

  Future<void> _editType(BuildContext context, ItemType? t) async {
    final s = context.read<AppState>();
    final r = await _codeDialog(context,
        title: t == null ? 'Add item type' : 'Edit ${t.name}',
        name: t?.name ?? '',
        code: t?.code ?? '',
        maxCode: 4,
        note: t == null ? null : 'Changing the abbreviation only affects new items.');
    if (r == null) return;
    try {
      await s.api.saveType(
          id: t?.id, projectId: s.project!.id, name: r.name, code: r.code, active: t?.active ?? true, sort: t?.sort ?? s.types.length + 1);
      await s.reloadSetup();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _CodeResult {
  _CodeResult(this.name, this.code, this.company);
  final String name;
  final String code;
  final String company;
}

Future<_CodeResult?> _codeDialog(
  BuildContext context, {
  required String title,
  required String name,
  required String code,
  String company = '',
  bool withCompany = false,
  required int maxCode,
  String? note,
}) {
  final n = TextEditingController(text: name);
  final cd = TextEditingController(text: code);
  final co = TextEditingController(text: company);
  String? error;
  return showDialog<_CodeResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Name'),
            TextField(controller: n, autofocus: true, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 10),
            FieldLabel('Abbreviation', hint: 'up to $maxCode capital letters or numbers'),
            TextField(controller: cd, maxLength: maxCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(counterText: '')),
            if (withCompany) ...[
              const SizedBox(height: 10),
              const FieldLabel('Subcontractor company'),
              TextField(controller: co, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. Hart Mechanical')),
            ],
            if (note != null) ...[const SizedBox(height: 8), Text(note, style: TextStyle(fontSize: 13, color: CwColors.of(ctx).muted))],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: CwColors.of(ctx).urgentText, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final c = cd.text.trim().toUpperCase();
              if (n.text.trim().isEmpty || !RegExp('^[A-Z0-9]{1,$maxCode}\$').hasMatch(c)) {
                setState(() => error = 'Enter a name and an abbreviation (capital letters or numbers, up to $maxCode).');
                return;
              }
              Navigator.pop(ctx, _CodeResult(n.text.trim(), c, co.text.trim()));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
