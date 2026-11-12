import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/api.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../util/pick_file.dart';
import '../util/save_file.dart';
import '../util/xlsx.dart';
import '../widgets/common.dart';
import '../widgets/excel_view.dart';
import 'item_form.dart';
import 'notifications_screen.dart';

/// Colors for the usual Navisworks clash statuses.
Color clashStatusColor(String s, CwColors c) {
  final l = s.toLowerCase();
  if (l.contains('new')) return c.dark ? const Color(0xFFF2867E) : const Color(0xFFC62828);
  if (l.contains('active')) return c.dark ? const Color(0xFFF0C55A) : const Color(0xFFB7791F);
  if (l.contains('review')) return c.dark ? const Color(0xFF8AB8F0) : const Color(0xFF1F6FD1);
  if (l.contains('approv')) return c.dark ? const Color(0xFFC9AAF2) : const Color(0xFF6B3FA0);
  if (l.contains('resolv') || l.contains('closed')) return c.dark ? const Color(0xFF7BC896) : const Color(0xFF2E7D4F);
  return c.muted;
}

class ClashReportsScreen extends StatelessWidget {
  const ClashReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final wide = isWide(context);
    final header = PageHeader(
      title: 'Clash Reports',
      actions: [
        if (s.canEditReports)
          FilledButton.icon(
            onPressed: () => uploadClashReport(context),
            icon: const Icon(Icons.upload_file, size: 20),
            label: const Text('Upload Report'),
          ),
        const SizedBox(width: 8),
      ],
    );
    final list = _ReportList(onOpen: (r) {
      s.selectReport(r.id);
      if (!wide) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(appBar: AppBar(title: Text(r.title)), body: ClashReportView(reportId: r.id, phone: true)),
        ));
      }
    });
    if (!wide) return Column(children: [header, Expanded(child: list)]);
    return Column(children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: s.view.listW,
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.panel),
              child: list,
            ),
          ),
          ResizeHandle(
            showLine: true,
            onDrag: (dx) => s.setView(s.view.copyWith(listW: s.view.listW + dx)),
            onReset: () => s.setView(s.view.copyWith(listW: 420)),
          ),
          Expanded(
            child: ColoredBox(
              color: c.surface,
              child: s.selectedReport == null
                  ? EmptyState(
                      icon: Icons.table_view_outlined,
                      title: s.clashReports.isEmpty ? 'No clash reports yet' : 'Pick a report',
                      body: s.clashReports.isEmpty
                          ? (s.canEditReports
                              ? 'Upload the Excel clash report from Navisworks. Everyone on the project can read it here and download it.'
                              : 'Clash reports from the Christman VDC team show here.')
                          : 'Select a report on the left to see its clashes.',
                    )
                  : ClashReportView(key: ValueKey(s.selectedReportId), reportId: s.selectedReportId!),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.onOpen});
  final void Function(ClashReport r) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    if (s.clashReports.isEmpty) return const EmptyState(icon: Icons.table_view_outlined, title: 'No clash reports yet');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        for (final r in s.clashReports)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: r.id == s.selectedReportId ? c.accent : c.line, width: r.id == s.selectedReportId ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onOpen(r),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.table_view_outlined, size: 18, color: Color(0xFF1D7044)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    ]),
                    const SizedBox(height: 2),
                    Text('${weekdayDate(r.reportDate)} · ${r.rowCount} clashes · ${fileSizeText(r.sizeBytes)}', style: TextStyle(fontSize: 13, color: c.muted)),
                    if (r.statuses.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final e in r.statuses.entries) _StatusCount(name: e.key, count: e.value),
                      ]),
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({required this.name, required this.count, this.selected, this.onTap});
  final String name;
  final int count;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final col = clashStatusColor(name, c);
    final on = selected ?? false;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: on ? col : col.withValues(alpha: c.dark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: col.withValues(alpha: 0.6)),
      ),
      child: Text('$name  $count', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : col)),
    );
    return onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: body);
  }
}

// =====================================================================
// Upload (admin)
// =====================================================================

Future<void> uploadClashReport(BuildContext context) async {
  final s = context.read<AppState>();
  final picked = await pickOneFile(extensions: const ['xlsx'], label: 'Excel workbook');
  if (picked == null || !context.mounted) return;
  XlsxBook book;
  try {
    book = await compute(readXlsx, picked.bytes);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final table = ClashTable.from(book.sheets[bestSheetIndex(book)]);
  final title = TextEditingController(text: picked.name.replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), ''));
  final notes = TextEditingController();
  var date = dayOnly(DateTime.now());
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Upload clash report'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${picked.name} · ${fileSizeText(picked.bytes.length)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${table.rows.length} clashes found on "${table.sheet.name}"'
              '${table.rowImages.isNotEmpty ? ' · ${table.rowImages.length} with pictures' : ''}',
              style: TextStyle(color: CwColors.of(ctx).muted),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Title'),
            TextField(controller: title),
            const SizedBox(height: 10),
            const FieldLabel('Report date'),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 1));
                if (d != null) setState(() => date = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Align(alignment: Alignment.centerLeft, child: Text(weekdayDate(date))),
            ),
            const SizedBox(height: 10),
            const FieldLabel('Notes', hint: 'optional — e.g. which tests, what changed'),
            TextField(controller: notes, minLines: 2, maxLines: 5),
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
                    if (title.text.trim().isEmpty) {
                      setState(() => error = 'Give the report a title.');
                      return;
                    }
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final path = await s.api.uploadFile(s.project!.id, 'clash-reports', picked.bytes, picked.name);
                      await s.api.saveClashReport(values: {
                        'project_id': s.project!.id,
                        'title': title.text.trim(),
                        'report_date': dateToDb(date),
                        'notes': notes.text.trim(),
                        'path': path,
                        'file_name': picked.name,
                        'size_bytes': picked.bytes.length,
                        'summary': {'rows': table.rows.length, 'statuses': table.statusCounts()},
                      });
                      await s.reloadReports();
                      final created = s.clashReports.where((r) => r.path == path).firstOrNull;
                      if (created != null) s.selectReport(created.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setState(() {
                        busy = false;
                        error = e.toString();
                      });
                    }
                  },
            child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Upload'),
          ),
        ],
      ),
    ),
  );
}

// =====================================================================
// Report viewer
// =====================================================================

class ClashReportView extends StatefulWidget {
  const ClashReportView({super.key, required this.reportId, this.phone = false});
  final String reportId;
  final bool phone;

  @override
  State<ClashReportView> createState() => _ClashReportViewState();
}

class _ClashReportViewState extends State<ClashReportView> {
  Future<(Uint8List, XlsxBook)>? _load;
  int _sheet = -1;
  ClashTable? _table;
  int _tableSheet = -1;
  final Map<int, bool> _excelMode = {};
  String _search = '';
  String? _status;

  Future<(Uint8List, XlsxBook)> _open(ClashReport r) async {
    final api = context.read<AppState>().api;
    final bytes = await api.fileBytes(r.path);
    final book = await compute(readXlsx, bytes);
    return (bytes, book);
  }

  Future<void> _download(ClashReport r, Uint8List? bytes) async {
    final api = context.read<AppState>().api;
    try {
      final b = bytes ?? await api.fileBytes(r.path);
      final msg = await saveOrShareFile(b, safeFileName(r.fileName), mimeType: Api.mimeFor(r.fileName));
      if (msg != null && mounted) showInfo(context, msg);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit(AppState s, ClashReport r) async {
    final title = TextEditingController(text: r.title);
    final notes = TextEditingController(text: r.notes);
    var date = r.reportDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Report details'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FieldLabel('Title'),
              TextField(controller: title),
              const SizedBox(height: 10),
              const FieldLabel('Report date'),
              OutlinedButton(
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 1));
                  if (d != null) setState(() => date = d);
                },
                child: Align(alignment: Alignment.centerLeft, child: Text(weekdayDate(date))),
              ),
              const SizedBox(height: 10),
              const FieldLabel('Notes'),
              TextField(controller: notes, minLines: 2, maxLines: 5),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await s.api.saveClashReport(id: r.id, values: {'title': title.text.trim(), 'report_date': dateToDb(date), 'notes': notes.text.trim()});
      await s.reloadReports();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final r = s.clashReports.where((x) => x.id == widget.reportId).firstOrNull;
    if (r == null) return const EmptyState(icon: Icons.search_off, title: 'Report not found');
    _load ??= _open(r);
    final pad = widget.phone ? 12.0 : 20.0;

    return FutureBuilder<(Uint8List, XlsxBook)>(
      future: _load,
      builder: (context, snap) {
        final bytes = snap.data?.$1;
        final book = snap.data?.$2;
        final head = Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!widget.phone) Text(r.title, style: condensed(28, color: c.ink)),
            Text(
              '${weekdayDate(r.reportDate)} · ${r.fileName} · ${fileSizeText(r.sizeBytes)} · uploaded by ${s.person(r.uploadedBy)?.name ?? 'Christman VDC'}',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            if (r.notes.isNotEmpty) ...[const SizedBox(height: 6), Text(r.notes, style: TextStyle(fontSize: 14, color: c.ink2))],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _download(r, bytes),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download Excel'),
              ),
              if (s.canEditReports)
                OutlinedButton.icon(onPressed: () => _edit(s, r), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit Details')),
              if (s.canEditReports)
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!await confirm(context, 'Delete "${r.title}"?', 'The report and its Excel file are removed for everyone.', ok: 'Delete', danger: true)) return;
                    try {
                      await s.api.deleteClashReport(r);
                      s.selectReport(null);
                      await s.reloadReports();
                      if (widget.phone && context.mounted) Navigator.of(context).pop();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
            ]),
          ]),
        );

        if (snap.hasError) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            Expanded(
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Could not show this report',
                body: '${snap.error}\nYou can still download the Excel file.',
              ),
            ),
          ]);
        }
        if (book == null) {
          return Column(children: [head, const Expanded(child: Center(child: CircularProgressIndicator()))]);
        }

        if (_sheet < 0 || _sheet >= book.sheets.length) _sheet = book.activeSheet.clamp(0, book.sheets.length - 1);
        final sheet = book.sheets[_sheet];
        if (_tableSheet != _sheet || _table == null) {
          _table = ClashTable.from(sheet);
          _tableSheet = _sheet;
        }
        final table = _table!;
        final excel = _excelMode[_sheet] ?? !table.isClashList;

        final tabs = book.sheets.length < 2
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Row(children: [
                  for (var i = 0; i < book.sheets.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(i == _sheet ? Icons.grid_on : Icons.grid_view_outlined, size: 16),
                        label: Text(book.sheets[i].name),
                        selected: i == _sheet,
                        onSelected: (_) => setState(() {
                          _sheet = i;
                          _status = null;
                          _search = '';
                        }),
                      ),
                    ),
                ]),
              );

        final modeToggle = !table.isClashList
            ? null
            : SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.view_list_outlined, size: 18), label: Text('Clash list')),
                  ButtonSegment(value: true, icon: Icon(Icons.grid_on, size: 18), label: Text('Excel view')),
                ],
                selected: {excel},
                onSelectionChanged: (v) => setState(() => _excelMode[_sheet] = v.first),
              );

        if (excel) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            tabs,
            if (modeToggle != null) Padding(padding: EdgeInsets.fromLTRB(pad, 8, pad, 0), child: Align(alignment: Alignment.centerLeft, child: modeToggle)),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                child: ExcelSheetView(key: ValueKey('sheet$_sheet'), book: book, sheet: sheet),
              ),
            ),
          ]);
        }

        final statusCol = table.statusColumn;
        final q = _search.trim().toLowerCase();
        final visible = <int>[
          for (var i = 0; i < table.rows.length; i++)
            if ((q.isEmpty || table.rows[i].any((x) => x.toLowerCase().contains(q))) &&
                (_status == null || table.cell(i, statusCol) == _status))
              i,
        ];
        final counts = table.statusCounts();

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          tabs,
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (modeToggle != null) modeToggle,
              SizedBox(
                width: 280,
                child: TextField(
                  key: ValueKey('search$_sheet'),
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: 'Search clash name, grid, ID…'),
                ),
              ),
              for (final e in counts.entries)
                _StatusCount(
                  name: e.key,
                  count: e.value,
                  selected: _status == e.key,
                  onTap: () => setState(() => _status = _status == e.key ? null : e.key),
                ),
              Text('${visible.length} of ${table.rows.length} shown', style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
              child: _ClashGrid(table: table, visible: visible),
            ),
          ),
        ]);
      },
    );
  }
}

class _ClashGrid extends StatelessWidget {
  const _ClashGrid({required this.table, required this.visible});
  final ClashTable table;
  final List<int> visible;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final hasImages = table.rowImages.isNotEmpty && table.imageColumn >= 0;
    final statusCol = table.statusColumn;

    // Column widths from the longest text (first 200 rows).
    final widths = <double>[
      for (var col = 0; col < table.headers.length; col++)
        if (hasImages && col == table.imageColumn)
          150
        else
          () {
            var longest = table.headers[col].length;
            for (var r = 0; r < table.rows.length && r < 200; r++) {
              final l = table.cell(r, col).length;
              if (l > longest) longest = l;
            }
            return (longest * 7.6 + 28).clamp(72.0, 320.0).toDouble();
          }(),
    ];
    // Hide columns that are empty everywhere.
    final cols = <int>[
      for (var col = 0; col < table.headers.length; col++)
        if ((hasImages && col == table.imageColumn) || table.rows.any((row) => col < row.length && row[col].isNotEmpty)) col,
    ];
    final total = cols.fold<double>(48, (sum, col) => sum + widths[col]);

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line), color: c.surface),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        final width = total < box.maxWidth ? box.maxWidth : total;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(children: [
              Container(
                color: c.surface2,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox(width: 48, child: Text('#', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted))),
                  for (final col in cols)
                    SizedBox(
                      width: widths[col],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          hasImages && col == table.imageColumn && table.headers[col].startsWith('Column ') ? 'View' : table.headers[col],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: c.ink2),
                        ),
                      ),
                    ),
                ]),
              ),
              Container(height: 1, color: c.line),
              Expanded(
                child: visible.isEmpty
                    ? Center(child: Text('No clashes match.', style: TextStyle(color: c.muted)))
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Container(height: 1, color: c.line),
                        itemBuilder: (context, i) {
                          final r = visible[i];
                          final pics = table.rowImages[r];
                          return InkWell(
                            onTap: () => showDialog<void>(context: context, builder: (_) => _ClashDetail(table: table, row: r)),
                            child: Container(
                              color: i.isOdd ? c.surface2.withValues(alpha: 0.5) : null,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              constraints: BoxConstraints(minHeight: hasImages ? 92 : 40),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                SizedBox(width: 48, child: Text('${r + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted))),
                                for (final col in cols)
                                  SizedBox(
                                    width: widths[col],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: hasImages && col == table.imageColumn
                                          ? (pics == null
                                              ? const SizedBox.shrink()
                                              : ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Image.memory(pics.first, height: 80, fit: BoxFit.cover, gaplessPlayback: true),
                                                ))
                                          : col == statusCol && table.cell(r, col).isNotEmpty
                                              ? Align(alignment: Alignment.centerLeft, child: _StatusLabel(table.cell(r, col)))
                                              : Text(table.cell(r, col), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink)),
                                    ),
                                  ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

/// The status pill without a count.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final col = clashStatusColor(name, c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: c.dark ? 0.18 : 0.10), borderRadius: BorderRadius.circular(999)),
      child: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: col)),
    );
  }
}

/// One clash: every column, the pictures large, and "Create Item".
class _ClashDetail extends StatelessWidget {
  const _ClashDetail({required this.table, required this.row});
  final ClashTable table;
  final int row;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final pics = table.rowImages[row] ?? const <Uint8List>[];
    final name = table.cell(row, table.nameColumn);
    final title = name.isNotEmpty ? name : 'Clash ${row + 1}';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final p in pics) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: InteractiveViewer(maxScale: 5, child: Image.memory(p, fit: BoxFit.contain)),
              ),
              const SizedBox(height: 10),
            ],
            for (var col = 0; col < table.headers.length; col++)
              if (table.cell(row, col).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 170, child: Text(table.headers[col], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.muted))),
                    Expanded(child: SelectableText(table.cell(row, col), style: const TextStyle(fontSize: 14))),
                  ]),
                ),
          ]),
        ),
      ),
      actions: [
        if (s.canCreateItems)
          OutlinedButton.icon(
            onPressed: () {
              final level = table.cell(row, table.levelColumn);
              final grid = table.cell(row, table.gridColumn);
              final extra = <String>[
                for (var col = 0; col < table.headers.length; col++)
                  if (table.cell(row, col).isNotEmpty &&
                      ![table.nameColumn, table.testColumn, table.idColumn, table.gridColumn, table.levelColumn, table.imageColumn].contains(col))
                    '${table.headers[col]}: ${table.cell(row, col)}',
              ];
              Navigator.pop(context);
              openItemForm(
                context,
                prefill: ItemPrefill(
                  typeCode: 'CL',
                  title: title,
                  description: extra.join('\n'),
                  level: level,
                  grid: grid,
                  clashTest: table.cell(row, table.testColumn),
                  clashId: table.cell(row, table.idColumn),
                  viewpoint: table.cell(row, table.viewpointColumn),
                  photos: pics,
                ),
              );
            },
            icon: const Icon(Icons.add_task, size: 18),
            label: const Text('Create Item'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
