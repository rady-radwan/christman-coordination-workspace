import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/formula.dart' show colLetters;
import '../util/xlsx.dart';

/// Shows a worksheet the way Excel does: column widths, row heights, merged cells,
/// fills, borders, fonts, alignment and pictures, on white "paper".
class ExcelSheetView extends StatefulWidget {
  const ExcelSheetView({super.key, required this.book, required this.sheet});
  final XlsxBook book;
  final XlsxSheet sheet;

  @override
  State<ExcelSheetView> createState() => _ExcelSheetViewState();
}

class _ExcelSheetViewState extends State<ExcelSheetView> {
  final _h = ScrollController();
  final _v = ScrollController();
  double? _zoom;

  static const _maxRows = 1500;
  static const _headW = 44.0;
  static const _headH = 22.0;

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final sheet = widget.sheet;
    final book = widget.book;

    // Used area: cells with text or a look, merges and pictures.
    var lastRow = -1, lastCol = -1;
    sheet.cells.forEach((r, row) {
      row.forEach((col, cell) {
        if (cell.text.isNotEmpty || book.style(cell.style).hasLook) {
          lastRow = math.max(lastRow, r);
          lastCol = math.max(lastCol, col);
        }
      });
    });
    for (final m in sheet.merges) {
      lastRow = math.max(lastRow, m.r2);
      lastCol = math.max(lastCol, m.c2);
    }
    for (final p in sheet.pictures) {
      lastRow = math.max(lastRow, p.toRow ?? p.row);
      lastCol = math.max(lastCol, p.toCol ?? p.col);
    }
    if (lastRow < 0) {
      return Center(child: Text('This sheet is empty.', style: TextStyle(color: c.muted)));
    }
    final cut = lastRow >= _maxRows;
    final rows = math.min(lastRow, _maxRows - 1) + 2; // one spare row and column, like Excel's grid
    final cols = math.min(lastCol, 200) + 2;

    return LayoutBuilder(builder: (context, box) {
      // Column / row positions at 100%.
      final colX = <double>[0];
      for (var i = 0; i < cols; i++) {
        colX.add(colX.last + sheet.colPx(i));
      }
      final rowY = <double>[0];
      for (var i = 0; i < rows; i++) {
        rowY.add(rowY.last + sheet.rowPx(i));
      }
      final fit = ((box.maxWidth - _headW - 4) / colX.last).clamp(0.3, 1.0).toDouble();
      final z = _zoom ?? (fit < 1 ? math.max(fit, 0.6) : 1.0);

      final toolbar = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconButton(tooltip: 'Smaller', onPressed: () => setState(() => _zoom = (z - 0.1).clamp(0.3, 3.0).toDouble()), icon: const Icon(Icons.zoom_out)),
          SizedBox(width: 52, child: Text('${(z * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Larger', onPressed: () => setState(() => _zoom = (z + 0.1).clamp(0.3, 3.0).toDouble()), icon: const Icon(Icons.zoom_in)),
          TextButton(onPressed: () => setState(() => _zoom = 1), child: const Text('100%')),
          TextButton(onPressed: () => setState(() => _zoom = fit), child: const Text('Fit width')),
          if (sheet.chartCount > 0)
            Text('  ${sheet.chartCount} chart${sheet.chartCount == 1 ? '' : 's'} on this sheet open in Excel only.', style: TextStyle(fontSize: 13, color: c.muted)),
          if (cut) Text('  Showing the first $_maxRows rows.', style: TextStyle(fontSize: 13, color: c.muted)),
        ]),
      );

      final width = _headW + colX.last * z;
      final height = _headH + rowY.last * z;
      final paper = SizedBox(
        width: width,
        height: height,
        child: Stack(clipBehavior: Clip.hardEdge, children: _cells(sheet, book, colX, rowY, rows, cols, z)),
      );

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        toolbar,
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: c.line), color: Colors.white),
            clipBehavior: Clip.antiAlias,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: Scrollbar(
                controller: _v,
                thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 1,
                child: Scrollbar(
                  controller: _h,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: SingleChildScrollView(controller: _v, child: paper),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  List<Widget> _cells(XlsxSheet sheet, XlsxBook book, List<double> colX, List<double> rowY, int rows, int cols, double z) {
    final out = <Widget>[
      Positioned.fill(child: CustomPaint(painter: _GridPainter(colX, rowY, z, sheet.showGridLines, _headW, _headH))),
    ];

    // Merged areas: the top-left cell covers the whole area.
    final mergeAt = <int, XlsxMerge>{};
    final covered = <int>{};
    int key(int r, int c) => r * 20000 + c;
    for (final m in sheet.merges) {
      if (m.r1 >= rows || m.c1 >= cols) continue;
      mergeAt[key(m.r1, m.c1)] = m;
      for (var r = m.r1; r <= m.r2; r++) {
        for (var c = m.c1; c <= m.c2; c++) {
          if (r != m.r1 || c != m.c1) covered.add(key(r, c));
        }
      }
    }

    double x(int col) => _headW + colX[math.min(col, colX.length - 1)] * z;
    double y(int row) => _headH + rowY[math.min(row, rowY.length - 1)] * z;

    final texts = <Widget>[];
    final looks = <Widget>[];
    sheet.cells.forEach((r, row) {
      if (r >= rows) return;
      row.forEach((col, cell) {
        if (col >= cols || covered.contains(key(r, col))) return;
        final st = book.style(cell.style);
        final m = mergeAt[key(r, col)];
        final r2 = m?.r2 ?? r, c2 = m?.c2 ?? col;
        final left = x(col), top = y(r);
        final w = x(c2 + 1) - left, h = y(r2 + 1) - top;
        if (w <= 0 || h <= 0) return;

        if (st.hasLook) {
          looks.add(Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: st.fill == null ? null : Color(st.fill!),
                border: Border(
                  left: _side(st.left, z),
                  right: _side(st.right, z),
                  top: _side(st.top, z),
                  bottom: _side(st.bottom, z),
                ),
              ),
            ),
          ));
        }

        if (cell.text.isEmpty) return;
        final v = cell.value;
        final isNum = v is num;
        var h1 = st.hAlign;
        if (h1.isEmpty || h1 == 'general') h1 = isNum ? 'right' : (v is bool || v is! String ? 'center' : 'left');
        if (h1 == 'centerContinuous' || h1 == 'distributed') h1 = 'center';
        if (h1 == 'fill' || h1 == 'justify') h1 = 'left';

        // Text that does not wrap runs over empty cells to its right (like Excel).
        var spanW = w;
        if (!st.wrap && m == null && h1 == 'left') {
          var next = c2 + 1;
          while (next < cols && next - col < 30) {
            final n = sheet.cells[r]?[next];
            if ((n != null && n.text.isNotEmpty) || mergeAt.containsKey(key(r, next)) || covered.contains(key(r, next))) break;
            next++;
          }
          spanW = x(next) - left;
        }

        final style = TextStyle(
          fontSize: st.fontSize * 4 / 3 * z,
          height: 1.2,
          color: Color(st.fontColor ?? 0xFF000000),
          fontWeight: st.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: st.italic ? FontStyle.italic : FontStyle.normal,
          decoration: TextDecoration.combine([
            if (st.underline) TextDecoration.underline,
            if (st.strike) TextDecoration.lineThrough,
          ]),
          decorationColor: Color(st.fontColor ?? 0xFF000000),
        );
        final align = switch (h1) { 'center' => TextAlign.center, 'right' => TextAlign.right, _ => TextAlign.left };
        final vAlign = switch (st.vAlign) { 'top' => -1.0, 'center' || 'distributed' || 'justify' => 0.0, _ => 1.0 };
        final hAlign = switch (h1) { 'center' => 0.0, 'right' => 1.0, _ => -1.0 };
        final pad = 3 * z + st.indent * 9 * z;

        texts.add(Positioned(
          left: left,
          top: top,
          width: spanW,
          height: h,
          child: ClipRect(
            child: Padding(
              padding: EdgeInsets.only(left: h1 == 'left' ? pad : 2 * z, right: h1 == 'right' ? pad : 2 * z, top: z, bottom: z),
              child: Align(
                alignment: Alignment(hAlign, vAlign),
                child: Text(
                  cell.text,
                  textAlign: align,
                  softWrap: st.wrap,
                  maxLines: st.wrap ? null : 1,
                  overflow: TextOverflow.clip,
                  style: style,
                ),
              ),
            ),
          ),
        ));
      });
    });

    out.addAll(looks);
    out.addAll(texts);

    for (final p in sheet.pictures) {
      if (p.row >= rows || p.col >= cols) continue;
      final left = x(p.col) + p.colOff * z;
      final top = y(p.row) + p.rowOff * z;
      double w, h;
      if (p.toRow != null && p.toCol != null) {
        w = x(p.toCol!) + p.toColOff * z - left;
        h = y(p.toRow!) + p.toRowOff * z - top;
      } else {
        w = (p.width ?? 100) * z;
        h = (p.height ?? 80) * z;
      }
      if (w <= 0 || h <= 0) continue;
      out.add(Positioned(left: left, top: top, width: w, height: h, child: Image.memory(p.bytes, fit: BoxFit.fill, gaplessPlayback: true)));
    }
    return out;
  }

  BorderSide _side(XlsxLine? l, double z) {
    if (l == null) return BorderSide.none;
    final w = switch (l.style) { 'medium' || 'mediumDashed' || 'mediumDashDot' || 'mediumDashDotDot' => 2.0, 'thick' || 'double' => 3.0, 'hair' => 0.5, _ => 1.0 };
    return BorderSide(color: Color(l.color ?? 0xFF000000), width: math.max(0.5, w * math.min(z, 1.5)));
  }
}

/// White sheet, light grid lines and the A B C / 1 2 3 headings.
class _GridPainter extends CustomPainter {
  _GridPainter(this.colX, this.rowY, this.z, this.grid, this.headW, this.headH);
  final List<double> colX, rowY;
  final double z, headW, headH;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFFE1E1E1)
      ..strokeWidth = 1;
    final head = Paint()..color = const Color(0xFFF3F3F3);
    final headLine = Paint()
      ..color = const Color(0xFFD0D0D0)
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, headH), head);
    canvas.drawRect(Rect.fromLTWH(0, 0, headW, size.height), head);

    final label = TextStyle(fontSize: 11, color: const Color(0xFF666666), fontWeight: FontWeight.w500);
    for (var i = 0; i < colX.length; i++) {
      final x = headW + colX[i] * z;
      if (grid) canvas.drawLine(Offset(x, headH), Offset(x, size.height), line);
      canvas.drawLine(Offset(x, 0), Offset(x, headH), headLine);
      if (i < colX.length - 1) {
        final w = (colX[i + 1] - colX[i]) * z;
        if (w > 12) _text(canvas, colLetters(i), label, Rect.fromLTWH(x, 0, w, headH));
      }
    }
    for (var i = 0; i < rowY.length; i++) {
      final y = headH + rowY[i] * z;
      if (grid) canvas.drawLine(Offset(headW, y), Offset(size.width, y), line);
      canvas.drawLine(Offset(0, y), Offset(headW, y), headLine);
      if (i < rowY.length - 1) {
        final h = (rowY[i + 1] - rowY[i]) * z;
        if (h > 9) _text(canvas, '${i + 1}', label, Rect.fromLTWH(0, y, headW, h));
      }
    }
    canvas.drawLine(Offset(headW, 0), Offset(headW, size.height), headLine);
    canvas.drawLine(Offset(0, headH), Offset(size.width, headH), headLine);
  }

  void _text(Canvas canvas, String s, TextStyle style, Rect r) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: r.width);
    tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.z != z || old.colX != colX || old.rowY != rowY || old.grid != grid;
}
