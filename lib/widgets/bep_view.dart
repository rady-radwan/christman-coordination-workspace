import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../util/bep_blocks.dart';

/// Note box colors: (background, border/icon, icon).
(Color, Color, IconData) noteLook(String tone, CwColors c) => switch (tone) {
      'warning' => (c.dark ? const Color(0xFF3A2F12) : const Color(0xFFFFF4D6), const Color(0xFFD9A21B), Icons.warning_amber_rounded),
      'tip' => (c.dark ? const Color(0xFF15301F) : const Color(0xFFE5F5EA), const Color(0xFF2E9A55), Icons.lightbulb_outline),
      'important' => (c.dark ? const Color(0xFF3A1A18) : const Color(0xFFFDE7E5), const Color(0xFFD0453A), Icons.priority_high_rounded),
      _ => (c.dark ? const Color(0xFF14273D) : const Color(0xFFE6F0FB), const Color(0xFF2F7AD0), Icons.info_outline),
    };

/// Shows BEP blocks: headings, text, lists, checklists, tables, note boxes, lines and pictures.
class BepBlocksView extends StatelessWidget {
  const BepBlocksView(this.blocks, {super.key});
  final List<BepBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final base = TextStyle(fontSize: 15, height: 1.45, color: c.ink);
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final gap = i == 0 ? 0.0 : (b.type == 'h' ? 14.0 : 8.0);
      out.add(Padding(padding: EdgeInsets.only(top: gap), child: _block(context, b, c, base)));
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out));
  }

  Widget _block(BuildContext context, BepBlock b, CwColors c, TextStyle base) {
    switch (b.type) {
      case 'h':
        return switch (b.level) {
          1 => Text(b.text, style: condensed(22, color: c.ink)),
          2 => Text(b.text, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: c.ink)),
          _ => Text(b.text.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: c.accentText)),
        };
      case 'p':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final line in b.text.split('\n'))
            line.trim().isEmpty ? const SizedBox(height: 8) : Padding(padding: const EdgeInsets.only(bottom: 2), child: richLine(line, base, labels: true)),
        ]);
      case 'ul':
      case 'ol':
        {
          final counters = <int, int>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final raw in b.items)
              if (raw.trim().isNotEmpty)
                () {
                  final depth = (RegExp(r'^ *').stringMatch(raw)!.length ~/ 2).clamp(0, 4);
                  counters.removeWhere((k, _) => k > depth);
                  final n = counters[depth] = (counters[depth] ?? 0) + 1;
                  return Padding(
                    padding: EdgeInsets.only(left: 4.0 + depth * 22, bottom: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: b.type == 'ol' ? 28 : 18,
                        child: b.type == 'ol'
                            ? Text(depth == 0 ? '$n.' : '${String.fromCharCode(96 + ((n - 1) % 26) + 1)}.', style: base.copyWith(fontWeight: FontWeight.w700, color: c.accentText))
                            : Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: depth == 0 ? c.accent : null, border: Border.all(color: c.accent, width: 1.4), shape: BoxShape.circle),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(child: richLine(raw.trim(), base)),
                    ]),
                  );
                }(),
          ]);
        }
      case 'check':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < b.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    i < b.checks.length && b.checks[i] ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: i < b.checks.length && b.checks[i] ? c.accent : c.muted,
                  ),
                ),
                Expanded(child: richLine(b.items[i], base)),
              ]),
            ),
        ]);
      case 'table':
        return BepTableView(block: b);
      case 'note':
        {
          final (bg, line, icon) = noteLook(b.tone, c);
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: line, width: 4))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1, right: 10), child: Icon(icon, color: line, size: 22)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final l in b.text.split('\n')) l.trim().isEmpty ? const SizedBox(height: 6) : richLine(l, base),
                ]),
              ),
            ]),
          );
        }
      case 'hr':
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, thickness: 1, color: c.line));
      case 'img':
        return BepPicture(block: b);
    }
    return const SizedBox.shrink();
  }
}

/// A line with **bold** parts; with [labels], a short "Label:" start is bold too.
Widget richLine(String line, TextStyle base, {bool labels = false}) {
  final spans = <TextSpan>[];
  var rest = line;
  if (labels && !rest.contains('**')) {
    final m = RegExp(r'^([^:]{1,32}):(\s|$)(.*)$').firstMatch(rest);
    if (m != null && !m.group(1)!.contains('http')) {
      return Text.rich(TextSpan(style: base, children: [
        TextSpan(text: '${m.group(1)}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: m.group(3)),
      ]));
    }
  }
  final parts = rest.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null));
  }
  return Text.rich(TextSpan(style: base, children: spans));
}

class BepTableView extends StatelessWidget {
  const BepTableView({super.key, required this.block});
  final BepBlock block;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final rows = block.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(builder: (context, box) {
      const minCol = 130.0;
      final fits = cols * minCol <= box.maxWidth;
      final table = Table(
        border: TableBorder.all(color: c.line, width: 1, borderRadius: BorderRadius.circular(8)),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: fits ? null : {for (var i = 0; i < cols; i++) i: const FixedColumnWidth(170)},
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: BoxDecoration(color: block.header && r == 0 ? c.surface2 : (r.isEven ? null : c.surface2.withValues(alpha: 0.35))),
              children: [
                for (var col = 0; col < cols; col++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: richLine(
                      col < rows[r].length ? rows[r][col] : '',
                      TextStyle(fontSize: 14, height: 1.35, color: c.ink, fontWeight: block.header && r == 0 ? FontWeight.w800 : FontWeight.w400),
                    ),
                  ),
              ],
            ),
        ],
      );
      if (fits) return table;
      return Scrollbar(
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 8), child: SizedBox(width: cols * 170.0, child: table)),
      );
    });
  }
}

/// A picture in a BEP section (loaded from the server, or not uploaded yet).
class BepPicture extends StatefulWidget {
  const BepPicture({super.key, required this.block, this.maxHeight = 420});
  final BepBlock block;
  final double maxHeight;

  @override
  State<BepPicture> createState() => _BepPictureState();
}

class _BepPictureState extends State<BepPicture> {
  Future<Uint8List>? _bytes;

  Future<Uint8List> _load() {
    final b = widget.block.bytes;
    if (b != null) return Future.value(b);
    return context.read<AppState>().api.fileBytes(widget.block.path);
  }

  @override
  void didUpdateWidget(covariant BepPicture old) {
    super.didUpdateWidget(old);
    if (old.block.path != widget.block.path || old.block.bytes != widget.block.bytes) _bytes = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    _bytes ??= _load();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.hasError) {
            return Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
              child: Text('Picture could not be loaded', style: TextStyle(color: c.muted)),
            );
          }
          if (!snap.hasData) {
            return Container(height: 120, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2));
          }
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: Stack(children: [
                  InteractiveViewer(maxScale: 6, child: Image.memory(snap.data!, fit: BoxFit.contain)),
                  Positioned(right: 4, top: 4, child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))),
                ]),
              ),
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(snap.data!, fit: BoxFit.contain, gaplessPlayback: true)),
              ),
            ),
          );
        },
      ),
      if (widget.block.caption.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(widget.block.caption, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: c.muted)),
        ),
    ]);
  }
}
