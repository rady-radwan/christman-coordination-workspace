import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'formula.dart';
import 'numfmt.dart';

// =====================================================================
// What is read from an Excel file
// =====================================================================

/// One border line of a cell. [style] is Excel's name ("thin", "medium", "thick", "double", "dashed"…).
class XlsxLine {
  const XlsxLine(this.style, this.color);
  final String style;
  final int? color; // ARGB
}

/// How a cell looks (from styles.xml).
class XlsxStyle {
  const XlsxStyle({
    this.numFmt = 'General',
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.fontSize = 11,
    this.fontColor,
    this.fill,
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.hAlign = '',
    this.vAlign = '',
    this.wrap = false,
    this.indent = 0,
    this.rotation = 0,
  });

  final String numFmt;
  final bool bold, italic, underline, strike;
  final double fontSize; // points
  final int? fontColor; // ARGB
  final int? fill; // ARGB background
  final XlsxLine? left, right, top, bottom;
  final String hAlign; // left, center, right, fill, justify, centerContinuous, general ('')
  final String vAlign; // top, center, bottom ('' = bottom)
  final bool wrap;
  final int indent;
  final int rotation;

  bool get hasLook => fill != null || left != null || right != null || top != null || bottom != null;
}

class XlsxCell {
  XlsxCell(this.value, this.style, {this.formula});

  /// double, String, bool, XlError or null.
  Object? value;
  final int style;
  final String? formula;

  /// The text Excel shows.
  String text = '';
}

class XlsxMerge {
  const XlsxMerge(this.r1, this.c1, this.r2, this.c2);
  final int r1, c1, r2, c2;
}

/// A picture placed on a sheet. Offsets and sizes are in pixels.
class XlsxPicture {
  XlsxPicture({
    required this.bytes,
    required this.row,
    required this.col,
    this.rowOff = 0,
    this.colOff = 0,
    this.toRow,
    this.toCol,
    this.toRowOff = 0,
    this.toColOff = 0,
    this.width,
    this.height,
  });
  final Uint8List bytes;
  final int row, col;
  final double rowOff, colOff;
  final int? toRow, toCol;
  final double toRowOff, toColOff;
  final double? width, height;
}

/// One worksheet of an Excel file.
class XlsxSheet {
  XlsxSheet({
    required this.name,
    required this.rows,
    required this.images,
    required this.imageCols,
    required this.cells,
    this.colWidths = const {},
    this.hiddenCols = const {},
    this.rowHeights = const {},
    this.hiddenRows = const {},
    this.defaultColWidth = 9.140625,
    this.defaultRowHeight = 15,
    this.merges = const [],
    this.pictures = const [],
    this.showGridLines = true,
    this.chartCount = 0,
  });
  final String name;

  /// rows[r][c] — the text of each cell; every row has the same number of columns.
  final List<List<String>> rows;

  /// Pictures anchored on each row (0-based row index).
  final Map<int, List<Uint8List>> images;

  /// The column each picture sits in, per row.
  final Map<int, int> imageCols;

  /// Every cell with a value or a look: cells[row][col].
  final Map<int, Map<int, XlsxCell>> cells;

  /// Column widths in Excel "characters"; row heights in points.
  final Map<int, double> colWidths;
  final Set<int> hiddenCols;
  final Map<int, double> rowHeights;
  final Set<int> hiddenRows;
  final double defaultColWidth;
  final double defaultRowHeight;
  final List<XlsxMerge> merges;
  final List<XlsxPicture> pictures;
  final bool showGridLines;

  /// Charts on the sheet (not shown in the app).
  final int chartCount;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;

  /// Pixels at 100% zoom.
  double colPx(int c) => hiddenCols.contains(c) ? 0 : ((colWidths[c] ?? defaultColWidth) * 7).roundToDouble();
  double rowPx(int r) => hiddenRows.contains(r) ? 0 : ((rowHeights[r] ?? defaultRowHeight) * 4 / 3).roundToDouble();
}

class XlsxBook {
  XlsxBook(this.sheets, {this.styles = const [XlsxStyle()], this.activeSheet = 0});
  final List<XlsxSheet> sheets;
  final List<XlsxStyle> styles;

  /// The sheet Excel opens on.
  final int activeSheet;

  XlsxStyle style(int i) => i >= 0 && i < styles.length ? styles[i] : const XlsxStyle();
}

class XlsxException implements Exception {
  XlsxException(this.message);
  final String message;
  @override
  String toString() => message;
}

// =====================================================================
// Reading
// =====================================================================

/// Reads an .xlsx file: values, looks, merged cells, column widths and pictures.
/// Formulas show their saved result; when the file has no saved result, the app calculates it.
XlsxBook readXlsx(Uint8List bytes, {DateTime? now}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw XlsxException('This is not an .xlsx Excel file. Save it as "Excel Workbook (.xlsx)" and try again.');
  }

  Uint8List? raw(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    final content = f.content as List<int>;
    return content is Uint8List ? content : Uint8List.fromList(content);
  }

  XmlDocument? doc(String path) {
    final b = raw(path);
    if (b == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(b, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  final wb = doc('xl/workbook.xml');
  if (wb == null) throw XlsxException('This file has no worksheets. Is it an Excel workbook?');

  // Shared text
  final shared = <String>[];
  final ss = doc('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in _els(ss, 'si')) {
      // Phonetic hints (rPh) also contain <t>; skip them.
      shared.add(_els(si, 't').where((t) => (t.parentElement?.name.local ?? '') != 'rPh').map((t) => t.innerText).join());
    }
  }

  final theme = _themeColors(doc('xl/theme/theme1.xml'));
  final styles = _readStyles(doc('xl/styles.xml'), theme);

  // Workbook names (for formulas)
  final names = <String, String>{};
  for (final dn in _els(wb, 'definedName')) {
    final n = _attr(dn, 'name');
    if (n != null && _attr(dn, 'localSheetId') == null) names[n.toUpperCase()] = dn.innerText;
  }
  final activeTab = int.tryParse(_attr(_els(wb, 'workbookView').firstOrNull ?? XmlElement(XmlName('x')), 'activeTab') ?? '') ?? 0;

  final wbRels = _rels(doc('xl/_rels/workbook.xml.rels'));
  final parsed = <_RawSheet>[];
  var activeIndex = 0;
  var sheetNo = 0;
  for (final sh in _els(wb, 'sheet')) {
    final index = sheetNo++;
    final state = _attr(sh, 'state') ?? 'visible';
    final name = _attr(sh, 'name') ?? 'Sheet${parsed.length + 1}';
    final target = wbRels[_attr(sh, 'id') ?? ''];
    if (target == null || state != 'visible') continue;
    final path = _resolve('xl', target);
    final sheetDoc = doc(path);
    if (sheetDoc == null) continue;
    if (index == activeTab) activeIndex = parsed.length;
    parsed.add(_readSheet(name, path, sheetDoc, shared, styles, doc, raw));
  }
  if (parsed.isEmpty) throw XlsxException('No worksheets could be read from this file.');

  // Calculate formulas that were saved without a result.
  final host = _Host(parsed, names)..now = now;
  for (final s in parsed) {
    host.current = s;
    for (final row in s.cells.values) {
      for (final cell in row.values) {
        if (cell.formula != null && cell.value == null) host.calc(s, cell);
      }
    }
  }

  final sheets = <XlsxSheet>[];
  for (final s in parsed) {
    var maxRow = -1, maxCol = -1;
    s.cells.forEach((r, row) {
      row.forEach((c, cell) {
        cell.text = formatValue(cell.value, styles.length > cell.style ? styles[cell.style].numFmt : 'General');
        if (cell.text.isNotEmpty) {
          if (r > maxRow) maxRow = r;
          if (c > maxCol) maxCol = c;
        }
      });
    });
    for (final p in s.pictures) {
      if (p.row > maxRow) maxRow = p.row;
      if (p.col > maxCol) maxCol = p.col;
    }
    final rows = <List<String>>[
      for (var r = 0; r <= maxRow; r++) [for (var c = 0; c <= maxCol; c++) (s.cells[r]?[c]?.text ?? '').trim()],
    ];
    final images = <int, List<Uint8List>>{};
    final imageCols = <int, int>{};
    for (final p in s.pictures) {
      (images[p.row] ??= []).add(p.bytes);
      imageCols[p.row] = p.col;
    }
    sheets.add(XlsxSheet(
      name: s.name,
      rows: rows,
      images: images,
      imageCols: imageCols,
      cells: s.cells,
      colWidths: s.colWidths,
      hiddenCols: s.hiddenCols,
      rowHeights: s.rowHeights,
      hiddenRows: s.hiddenRows,
      defaultColWidth: s.defaultColWidth,
      defaultRowHeight: s.defaultRowHeight,
      merges: s.merges,
      pictures: s.pictures,
      showGridLines: s.showGridLines,
      chartCount: s.chartCount,
    ));
  }
  return XlsxBook(sheets, styles: styles, activeSheet: activeIndex);
}

class _RawSheet {
  _RawSheet(this.name);
  final String name;
  final cells = <int, Map<int, XlsxCell>>{};
  final colWidths = <int, double>{};
  final hiddenCols = <int>{};
  final rowHeights = <int, double>{};
  final hiddenRows = <int>{};
  double defaultColWidth = 9.140625;
  double defaultRowHeight = 15;
  final merges = <XlsxMerge>[];
  final pictures = <XlsxPicture>[];
  bool showGridLines = true;
  int chartCount = 0;
  int lastRow = 0, lastCol = 0;
}

_RawSheet _readSheet(
  String name,
  String path,
  XmlDocument sheetDoc,
  List<String> shared,
  List<XlsxStyle> styles,
  XmlDocument? Function(String) doc,
  Uint8List? Function(String) raw,
) {
  final s = _RawSheet(name);
  final root = sheetDoc.rootElement;

  final view = _els(root, 'sheetView').firstOrNull;
  if (view != null && _attr(view, 'showGridLines') == '0') s.showGridLines = false;

  final fmt = _els(root, 'sheetFormatPr').firstOrNull;
  if (fmt != null) {
    final drh = double.tryParse(_attr(fmt, 'defaultRowHeight') ?? '');
    if (drh != null && drh > 0) s.defaultRowHeight = drh;
    final dcw = double.tryParse(_attr(fmt, 'defaultColWidth') ?? '');
    final base = double.tryParse(_attr(fmt, 'baseColWidth') ?? '');
    if (dcw != null && dcw > 0) {
      s.defaultColWidth = dcw;
    } else if (base != null && base > 0) {
      s.defaultColWidth = base + 1.140625;
    }
  }

  for (final col in _els(root, 'col')) {
    final min = int.tryParse(_attr(col, 'min') ?? '');
    final max = int.tryParse(_attr(col, 'max') ?? '');
    if (min == null || max == null) continue;
    final w = double.tryParse(_attr(col, 'width') ?? '');
    final hidden = _attr(col, 'hidden') == '1' || _attr(col, 'hidden') == 'true';
    for (var c = min - 1; c < math.min(max, min + 300); c++) {
      if (w != null) s.colWidths[c] = w;
      if (hidden) s.hiddenCols.add(c);
    }
  }

  // Shared formulas: si -> (row, col, text)
  final sharedF = <String, (int, int, String)>{};
  var rowGuess = -1;
  for (final row in _els(root, 'row')) {
    final rAttr = int.tryParse(_attr(row, 'r') ?? '');
    final r = rAttr != null ? rAttr - 1 : rowGuess + 1;
    rowGuess = r;
    final ht = double.tryParse(_attr(row, 'ht') ?? '');
    if (ht != null) s.rowHeights[r] = ht;
    if (_attr(row, 'hidden') == '1' || _attr(row, 'hidden') == 'true') s.hiddenRows.add(r);
    var colGuess = -1;
    for (final c in row.childElements.where((e) => e.name.local == 'c')) {
      final ref = _attr(c, 'r');
      final col = ref != null ? _colIndex(ref) : colGuess + 1;
      colGuess = col;
      final style = int.tryParse(_attr(c, 's') ?? '') ?? 0;
      final value = _cellValue(c, shared);
      String? formula;
      final f = c.childElements.where((e) => e.name.local == 'f').firstOrNull;
      if (f != null) {
        final text = f.innerText;
        final si = _attr(f, 'si');
        if (_attr(f, 't') == 'shared' && si != null) {
          if (text.isNotEmpty) {
            sharedF[si] = (r, col, text);
            formula = text;
          } else {
            final master = sharedF[si];
            if (master != null) formula = shiftFormula(master.$3, r - master.$1, col - master.$2);
          }
        } else if (text.isNotEmpty) {
          formula = text;
        }
      }
      final look = style < styles.length && styles[style].hasLook;
      if (value == null && formula == null && !look) continue;
      (s.cells[r] ??= {})[col] = XlsxCell(value, style, formula: formula);
      if (r > s.lastRow) s.lastRow = r;
      if (col > s.lastCol) s.lastCol = col;
    }
  }

  for (final m in _els(root, 'mergeCell')) {
    final ref = _attr(m, 'ref');
    if (ref == null || !ref.contains(':')) continue;
    final parts = ref.split(':');
    final a = parseCellRef(parts[0]), b = parseCellRef(parts[1]);
    if (a == null || b == null) continue;
    s.merges.add(XlsxMerge(a.$1, a.$2, b.$1, b.$2));
  }

  // Pictures (and charts, which are only counted)
  final sheetRels = _rels(doc(_relsPathFor(path)));
  final sheetDir = path.substring(0, path.lastIndexOf('/'));
  for (final t in sheetRels.values.where((t) => t.contains('drawings/') && !t.contains('vmlDrawing'))) {
    final drawingPath = _resolve(sheetDir, t);
    final drawing = doc(drawingPath);
    if (drawing == null) continue;
    final drawingRels = _rels(doc(_relsPathFor(drawingPath)));
    final drawingDir = drawingPath.substring(0, drawingPath.lastIndexOf('/'));
    for (final anchor in drawing.rootElement.childElements) {
      if (_els(anchor, 'chart').isNotEmpty) {
        s.chartCount++;
        continue;
      }
      final from = anchor.childElements.where((e) => e.name.local == 'from').firstOrNull;
      final to = anchor.childElements.where((e) => e.name.local == 'to').firstOrNull;
      final ext = anchor.childElements.where((e) => e.name.local == 'ext').firstOrNull;
      final blip = _els(anchor, 'blip').firstOrNull;
      if (from == null || blip == null) continue;
      int? intOf(XmlElement? e, String n) => e == null ? null : int.tryParse(_els(e, n).firstOrNull?.innerText.trim() ?? '');
      double px(XmlElement? e, String n) => (intOf(e, n) ?? 0) / 9525.0;
      final r = intOf(from, 'row');
      final col = intOf(from, 'col');
      final media = drawingRels[_attr(blip, 'embed') ?? ''];
      if (r == null || col == null || media == null) continue;
      final bytes = raw(_resolve(drawingDir, media));
      if (bytes == null) continue;
      s.pictures.add(XlsxPicture(
        bytes: bytes,
        row: r,
        col: col,
        rowOff: px(from, 'rowOff'),
        colOff: px(from, 'colOff'),
        toRow: intOf(to, 'row'),
        toCol: intOf(to, 'col'),
        toRowOff: px(to, 'rowOff'),
        toColOff: px(to, 'colOff'),
        width: ext == null ? null : (double.tryParse(_attr(ext, 'cx') ?? '') ?? 0) / 9525.0,
        height: ext == null ? null : (double.tryParse(_attr(ext, 'cy') ?? '') ?? 0) / 9525.0,
      ));
    }
  }
  return s;
}

Object? _cellValue(XmlElement c, List<String> shared) {
  final t = _attr(c, 't');
  final v = c.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText;
  switch (t) {
    case 's':
      {
        final i = int.tryParse(v ?? '');
        return i != null && i >= 0 && i < shared.length ? shared[i] : null;
      }
    case 'inlineStr':
      {
        final s = _els(c, 't').map((e) => e.innerText).join();
        return s.isEmpty ? null : s;
      }
    case 'b':
      return v == null ? null : v == '1' || v == 'true';
    case 'str':
      return v;
    case 'e':
      return v == null ? null : XlError(v);
  }
  if (v == null || v.isEmpty) return null;
  return double.tryParse(v) ?? v;
}

/// Gives the calculator access to the cells, calculating others as needed.
class _Host implements FormulaHost {
  _Host(this.sheets, this.names);
  final List<_RawSheet> sheets;
  final Map<String, String> names;
  late _RawSheet current;
  DateTime? now;
  final _busy = <XlsxCell>{};

  _RawSheet _sheet(String? name) {
    if (name == null) return current;
    for (final s in sheets) {
      if (s.name.toLowerCase() == name.toLowerCase()) return s;
    }
    throw const XlError('#REF!');
  }

  void calc(_RawSheet s, XlsxCell cell) {
    if (_busy.contains(cell)) return; // circular
    _busy.add(cell);
    final before = current;
    current = s;
    try {
      cell.value = evaluateFormula(cell.formula!, this, now: now);
    } finally {
      current = before;
      _busy.remove(cell);
    }
  }

  @override
  Object? cellValue(String? sheet, int row, int col) {
    final s = _sheet(sheet);
    final cell = s.cells[row]?[col];
    if (cell == null) return null;
    if (cell.value == null && cell.formula != null) calc(s, cell);
    final v = cell.value;
    return v is String && v.isEmpty ? null : v;
  }

  @override
  int lastRow(String? sheet) => _sheet(sheet).lastRow;

  @override
  int lastCol(String? sheet) => _sheet(sheet).lastCol;

  @override
  String? definedName(String name) => names[name.toUpperCase()];
}

// =====================================================================
// Styles and colors
// =====================================================================

/// The 64 legacy indexed colors.
const _indexed = <int>[
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF, //
  0xFF000000, 0xFFFFFFFF, 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00, 0xFFFF00FF, 0xFF00FFFF,
  0xFF800000, 0xFF008000, 0xFF000080, 0xFF808000, 0xFF800080, 0xFF008080, 0xFFC0C0C0, 0xFF808080,
  0xFF9999FF, 0xFF993366, 0xFFFFFFCC, 0xFFCCFFFF, 0xFF660066, 0xFFFF8080, 0xFF0066CC, 0xFFCCCCFF,
  0xFF000080, 0xFFFF00FF, 0xFFFFFF00, 0xFF00FFFF, 0xFF800080, 0xFF800000, 0xFF008080, 0xFF0000FF,
  0xFF00CCFF, 0xFFCCFFFF, 0xFFCCFFCC, 0xFFFFFF99, 0xFF99CCFF, 0xFFFF99CC, 0xFFCC99FF, 0xFFFFCC99,
  0xFF3366FF, 0xFF33CCCC, 0xFF99CC00, 0xFFFFCC00, 0xFFFF9900, 0xFFFF6600, 0xFF666699, 0xFF969696,
  0xFF003366, 0xFF339966, 0xFF003300, 0xFF333300, 0xFF993300, 0xFF993366, 0xFF333399, 0xFF333333,
];

/// Office theme colors in the order Excel numbers them: lt1, dk1, lt2, dk2, accent1-6, hlink, folHlink.
List<int> _themeColors(XmlDocument? d) {
  const fallback = [
    0xFFFFFFFF, 0xFF000000, 0xFFE7E6E6, 0xFF44546A, 0xFF4472C4, 0xFFED7D31, //
    0xFFA5A5A5, 0xFFFFC000, 0xFF5B9BD5, 0xFF70AD47, 0xFF0563C1, 0xFF954F72,
  ];
  if (d == null) return fallback;
  final scheme = _els(d, 'clrScheme').firstOrNull;
  if (scheme == null) return fallback;
  final byName = <String, int>{};
  for (final e in scheme.childElements) {
    final srgb = _els(e, 'srgbClr').firstOrNull;
    final sys = _els(e, 'sysClr').firstOrNull;
    final hex = srgb != null ? _attr(srgb, 'val') : (sys != null ? _attr(sys, 'lastClr') : null);
    final v = int.tryParse(hex ?? '', radix: 16);
    if (v != null) byName[e.name.local] = 0xFF000000 | v;
  }
  const order = ['lt1', 'dk1', 'lt2', 'dk2', 'accent1', 'accent2', 'accent3', 'accent4', 'accent5', 'accent6', 'hlink', 'folHlink'];
  return [for (var i = 0; i < order.length; i++) byName[order[i]] ?? fallback[i]];
}

/// Lightens (tint > 0) or darkens (tint < 0) a color the way Excel does (on HSL lightness).
int _tint(int argb, double tint) {
  if (tint == 0) return argb;
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  var h = 0.0, s = 0.0;
  var l = (mx + mn) / 2;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
  double hue(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  double rr, gg, bb;
  if (s == 0) {
    rr = gg = bb = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    rr = hue(p, q, h + 1 / 3);
    gg = hue(p, q, h);
    bb = hue(p, q, h - 1 / 3);
  }
  int c(double x) => (x.clamp(0, 1) * 255).round();
  return 0xFF000000 | (c(rr) << 16) | (c(gg) << 8) | c(bb);
}

int? _color(XmlElement? e, List<int> theme) {
  if (e == null) return null;
  if (_attr(e, 'auto') == '1') return null;
  int? base;
  final rgb = _attr(e, 'rgb');
  if (rgb != null) {
    final v = int.tryParse(rgb, radix: 16);
    if (v != null) base = rgb.length <= 6 ? 0xFF000000 | v : v;
    if (base != null && (base >> 24) == 0) base = 0xFF000000 | base; // some writers leave alpha 00
  }
  final th = int.tryParse(_attr(e, 'theme') ?? '');
  if (th != null && th >= 0 && th < theme.length) base = theme[th];
  final ix = int.tryParse(_attr(e, 'indexed') ?? '');
  if (ix != null) {
    if (ix == 64) return null; // system foreground
    if (ix >= 0 && ix < _indexed.length) base = _indexed[ix];
  }
  if (base == null) return null;
  final tint = double.tryParse(_attr(e, 'tint') ?? '') ?? 0;
  return _tint(base, tint);
}

List<XlsxStyle> _readStyles(XmlDocument? d, List<int> theme) {
  if (d == null) return const [XlsxStyle()];
  XmlElement? child(XmlElement? e, String n) => e?.childElements.where((x) => x.name.local == n).firstOrNull;

  final custom = <int, String>{};
  for (final f in _els(d, 'numFmt')) {
    final id = int.tryParse(_attr(f, 'numFmtId') ?? '');
    if (id != null) custom[id] = _attr(f, 'formatCode') ?? 'General';
  }

  final fonts = <XmlElement>[for (final f in _els(d, 'fonts').firstOrNull?.childElements ?? const <XmlElement>[]) if (f.name.local == 'font') f];
  final fills = <XmlElement>[for (final f in _els(d, 'fills').firstOrNull?.childElements ?? const <XmlElement>[]) if (f.name.local == 'fill') f];
  final borders = <XmlElement>[for (final f in _els(d, 'borders').firstOrNull?.childElements ?? const <XmlElement>[]) if (f.name.local == 'border') f];

  bool flag(XmlElement? font, String n) {
    final e = child(font, n);
    if (e == null) return false;
    final v = _attr(e, 'val');
    return v == null || (v != '0' && v != 'false' && v != 'none');
  }

  XlsxLine? line(XmlElement? border, String side) {
    final e = child(border, side);
    if (e == null) return null;
    final st = _attr(e, 'style');
    if (st == null || st == 'none') return null;
    return XlsxLine(st, _color(child(e, 'color'), theme) ?? 0xFF000000);
  }

  final out = <XlsxStyle>[];
  final xfs = _els(d, 'cellXfs').firstOrNull;
  for (final xf in xfs?.childElements.where((e) => e.name.local == 'xf') ?? const <XmlElement>[]) {
    final numId = int.tryParse(_attr(xf, 'numFmtId') ?? '0') ?? 0;
    final fontId = int.tryParse(_attr(xf, 'fontId') ?? '0') ?? 0;
    final fillId = int.tryParse(_attr(xf, 'fillId') ?? '0') ?? 0;
    final borderId = int.tryParse(_attr(xf, 'borderId') ?? '0') ?? 0;
    final font = fontId < fonts.length ? fonts[fontId] : null;
    final fill = fillId < fills.length ? fills[fillId] : null;
    final border = borderId < borders.length ? borders[borderId] : null;
    final align = child(xf, 'alignment');

    int? fillColor;
    final pf = child(fill, 'patternFill');
    if (pf != null) {
      final type = _attr(pf, 'patternType') ?? 'none';
      if (type != 'none') fillColor = _color(child(pf, 'fgColor'), theme) ?? (type == 'solid' ? null : _color(child(pf, 'bgColor'), theme));
    } else {
      final gf = child(fill, 'gradientFill');
      if (gf != null) fillColor = _color(_els(gf, 'color').firstOrNull, theme);
    }

    var code = custom[numId] ?? builtInFormats[numId] ?? 'General';
    if (numId == 14) code = 'mm/dd/yyyy';
    final u = child(font, 'u');
    out.add(XlsxStyle(
      numFmt: code,
      bold: flag(font, 'b'),
      italic: flag(font, 'i'),
      underline: u != null && _attr(u, 'val') != 'none',
      strike: flag(font, 'strike'),
      fontSize: double.tryParse(_attr(child(font, 'sz') ?? XmlElement(XmlName('x')), 'val') ?? '') ?? 11,
      fontColor: _color(child(font, 'color'), theme),
      fill: fillColor,
      left: line(border, 'left') ?? line(border, 'start'),
      right: line(border, 'right') ?? line(border, 'end'),
      top: line(border, 'top'),
      bottom: line(border, 'bottom'),
      hAlign: align == null ? '' : _attr(align, 'horizontal') ?? '',
      vAlign: align == null ? '' : _attr(align, 'vertical') ?? '',
      wrap: align != null && (_attr(align, 'wrapText') == '1' || _attr(align, 'wrapText') == 'true'),
      indent: int.tryParse(align == null ? '' : _attr(align, 'indent') ?? '') ?? 0,
      rotation: int.tryParse(align == null ? '' : _attr(align, 'textRotation') ?? '') ?? 0,
    ));
  }
  if (out.isEmpty) out.add(const XlsxStyle());
  return out;
}

// =====================================================================
// XML helpers
// =====================================================================

Iterable<XmlElement> _els(XmlNode n, String local) => n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String? _attr(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

Map<String, String> _rels(XmlDocument? d) {
  final out = <String, String>{};
  if (d == null) return out;
  for (final r in _els(d, 'Relationship')) {
    final id = _attr(r, 'Id');
    final t = _attr(r, 'Target');
    if (id != null && t != null) out[id] = t;
  }
  return out;
}

String _relsPathFor(String path) {
  final i = path.lastIndexOf('/');
  return '${path.substring(0, i)}/_rels/${path.substring(i + 1)}.rels';
}

/// Resolves "../media/image1.png" against "xl/drawings".
String _resolve(String baseDir, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = baseDir.split('/').where((p) => p.isNotEmpty).toList();
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg.isNotEmpty && seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// "C12" → 2
int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch >= 65 && ch <= 90) {
      n = n * 26 + (ch - 64);
    } else if (ch >= 97 && ch <= 122) {
      n = n * 26 + (ch - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

/// Excel day number → "11/03/2026" or "11/03/2026 2:20 PM".
String excelDateText(double serial) =>
    serial == serial.truncateToDouble() ? formatDate(serial, 'mm/dd/yyyy') : formatDate(serial, serial < 1 ? 'h:mm AM/PM' : 'mm/dd/yyyy h:mm AM/PM');

// =====================================================================
// Clash report table: finds the header row and the usual clash columns.
// =====================================================================

class ClashTable {
  ClashTable._(this.sheet, this.headerRow, this.headers, this.rows, this.rowImages, this.imageColumn);

  final XlsxSheet sheet;

  /// Row number of the headings in the sheet (0-based), or -1 if none was found.
  final int headerRow;
  final List<String> headers;
  final List<List<String>> rows;

  /// Pictures for each data row (index into [rows]).
  final Map<int, List<Uint8List>> rowImages;

  /// Column where pictures are shown (index into [headers]), or -1.
  final int imageColumn;

  factory ClashTable.from(XlsxSheet sheet) {
    final all = sheet.rows;
    var header = -1;
    final width = sheet.columnCount;
    // The heading row: the first of the top 20 rows where most cells are filled with text.
    for (var r = 0; r < all.length && r < 20; r++) {
      final filled = all[r].where((x) => x.isNotEmpty).toList();
      if (filled.length >= 2 && filled.length >= (width * 0.5).ceil() && filled.every((x) => double.tryParse(x) == null)) {
        header = r;
        break;
      }
    }
    final headers = header >= 0
        ? [for (var c = 0; c < width; c++) all[header][c].isEmpty ? 'Column ${c + 1}' : all[header][c]]
        : [for (var c = 0; c < width; c++) 'Column ${c + 1}'];
    final rows = <List<String>>[];
    final rowImages = <int, List<Uint8List>>{};
    final imageColCount = <int, int>{};
    for (var r = header + 1; r < all.length; r++) {
      final hasText = all[r].any((x) => x.isNotEmpty);
      final pics = sheet.images[r];
      if (!hasText && pics == null) continue;
      if (pics != null) {
        rowImages[rows.length] = pics;
        final col = sheet.imageCols[r] ?? 0;
        imageColCount[col] = (imageColCount[col] ?? 0) + 1;
      }
      rows.add(all[r]);
    }
    var imageColumn = -1;
    if (imageColCount.isNotEmpty) {
      imageColumn = imageColCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      if (imageColumn >= headers.length) imageColumn = headers.length - 1;
    }
    return ClashTable._(sheet, header, headers, rows, rowImages, imageColumn);
  }

  /// Index of the first column whose heading matches one of [keys] (lower case), or -1.
  int column(List<String> keys, {List<String> not = const []}) {
    for (final k in keys) {
      for (var c = 0; c < headers.length; c++) {
        final h = headers[c].toLowerCase();
        if (h.contains(k) && !not.any(h.contains)) return c;
      }
    }
    return -1;
  }

  int get statusColumn => column(['status']);
  int get nameColumn => column(['clash name', 'name'], not: ['test', 'item', 'file', 'layer']);
  int get testColumn => column(['test']);
  int get idColumn => column(['clash id', 'guid', 'id'], not: ['grid', 'element', 'item']);
  int get gridColumn => column(['grid']);
  int get levelColumn => column(['level']);
  int get descriptionColumn => column(['description', 'comment', 'note']);
  int get viewpointColumn => column(['viewpoint', 'view']);
  int get dateColumn => column(['date found', 'found', 'date']);

  /// True when this sheet is a list of clashes (one clash per row), not a summary page.
  bool get isClashList => headerRow >= 0 && rows.length >= 2 && (statusColumn >= 0 || rowImages.length >= 2 || (nameColumn >= 0 && idColumn >= 0));

  String cell(int row, int col) => col < 0 || col >= rows[row].length ? '' : rows[row][col];

  /// {status: count}, for the report summary.
  Map<String, int> statusCounts() {
    final c = statusColumn;
    final out = <String, int>{};
    if (c < 0) return out;
    for (final r in rows) {
      final s = c < r.length && r[c].isNotEmpty ? r[c] : '(blank)';
      out[s] = (out[s] ?? 0) + 1;
    }
    return out;
  }
}

/// The sheet that looks most like a clash list (a list with the most rows), for counting statuses.
int bestSheetIndex(XlsxBook book) {
  var best = 0;
  var bestScore = -1;
  for (var i = 0; i < book.sheets.length; i++) {
    final t = ClashTable.from(book.sheets[i]);
    final score = (t.isClashList ? 1000000 : 0) + t.rows.length;
    if (score > bestScore) {
      best = i;
      bestScore = score;
    }
  }
  return best;
}
