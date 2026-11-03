import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One worksheet of an Excel file: cell text by row and column, plus the
/// pictures placed on it (e.g. clash viewpoint images), by row.
class XlsxSheet {
  XlsxSheet(this.name, this.rows, this.images, this.imageCols);
  final String name;

  /// rows[r][c] — every row has the same number of columns.
  final List<List<String>> rows;

  /// Pictures anchored on each row (0-based row index).
  final Map<int, List<Uint8List>> images;

  /// The column each picture sits in, per row.
  final Map<int, int> imageCols;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;
}

class XlsxBook {
  XlsxBook(this.sheets);
  final List<XlsxSheet> sheets;
}

class XlsxException implements Exception {
  XlsxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads an .xlsx file (text, numbers, dates and pictures). Formulas show their last value.
XlsxBook readXlsx(Uint8List bytes) {
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
    return XmlDocument.parse(utf8.decode(b, allowMalformed: true));
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

  // Which cell styles are dates
  final dateStyles = <int>{};
  final styles = doc('xl/styles.xml');
  if (styles != null) {
    final custom = <int, String>{};
    for (final f in _els(styles, 'numFmt')) {
      final id = int.tryParse(_attr(f, 'numFmtId') ?? '');
      if (id != null) custom[id] = _attr(f, 'formatCode') ?? '';
    }
    final xfs = _els(styles, 'cellXfs').firstOrNull;
    if (xfs != null) {
      var i = 0;
      for (final xf in xfs.childElements.where((e) => e.name.local == 'xf')) {
        final id = int.tryParse(_attr(xf, 'numFmtId') ?? '0') ?? 0;
        if (_isDateFormat(id, custom[id])) dateStyles.add(i);
        i++;
      }
    }
  }

  final wbRels = _rels(doc('xl/_rels/workbook.xml.rels'));
  final sheets = <XlsxSheet>[];
  for (final sh in _els(wb, 'sheet')) {
    final name = _attr(sh, 'name') ?? 'Sheet${sheets.length + 1}';
    final target = wbRels[_attr(sh, 'id') ?? ''];
    if (target == null) continue;
    final path = _resolve('xl', target);
    final sheetDoc = doc(path);
    if (sheetDoc == null) continue;

    // Cells
    final cells = <int, Map<int, String>>{};
    var maxRow = -1, maxCol = -1;
    var rowGuess = -1;
    for (final row in _els(sheetDoc, 'row')) {
      final rAttr = int.tryParse(_attr(row, 'r') ?? '');
      final r = rAttr != null ? rAttr - 1 : rowGuess + 1;
      rowGuess = r;
      var colGuess = -1;
      for (final c in row.childElements.where((e) => e.name.local == 'c')) {
        final ref = _attr(c, 'r');
        final col = ref != null ? _colIndex(ref) : colGuess + 1;
        colGuess = col;
        final text = _cellText(c, shared, dateStyles);
        if (text.isEmpty) continue;
        (cells[r] ??= {})[col] = text;
        if (r > maxRow) maxRow = r;
        if (col > maxCol) maxCol = col;
      }
    }

    // Pictures
    final images = <int, List<Uint8List>>{};
    final imageCols = <int, int>{};
    final sheetRels = _rels(doc(_relsPathFor(path)));
    final sheetDir = path.substring(0, path.lastIndexOf('/'));
    for (final t in sheetRels.values.where((t) => t.contains('drawings/'))) {
      final drawingPath = _resolve(sheetDir, t);
      final drawing = doc(drawingPath);
      if (drawing == null) continue;
      final drawingRels = _rels(doc(_relsPathFor(drawingPath)));
      final drawingDir = drawingPath.substring(0, drawingPath.lastIndexOf('/'));
      for (final anchor in drawing.rootElement.childElements) {
        final from = _els(anchor, 'from').firstOrNull;
        final blip = _els(anchor, 'blip').firstOrNull;
        if (from == null || blip == null) continue;
        final r = int.tryParse(_els(from, 'row').firstOrNull?.innerText ?? '');
        final col = int.tryParse(_els(from, 'col').firstOrNull?.innerText ?? '');
        final media = drawingRels[_attr(blip, 'embed') ?? ''];
        if (r == null || media == null) continue;
        final bytes = raw(_resolve(drawingDir, media));
        if (bytes == null) continue;
        (images[r] ??= []).add(bytes);
        imageCols[r] = col ?? 0;
        if (r > maxRow) maxRow = r;
        if ((col ?? 0) > maxCol) maxCol = col ?? 0;
      }
    }

    final rows = <List<String>>[
      for (var r = 0; r <= maxRow; r++) [for (var c = 0; c <= maxCol; c++) cells[r]?[c] ?? ''],
    ];
    sheets.add(XlsxSheet(name, rows, images, imageCols));
  }
  if (sheets.isEmpty) throw XlsxException('No worksheets could be read from this file.');
  return XlsxBook(sheets);
}

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

String _cellText(XmlElement c, List<String> shared, Set<int> dateStyles) {
  final t = _attr(c, 't');
  final v = c.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText;
  switch (t) {
    case 's':
      final i = int.tryParse(v ?? '');
      return i != null && i >= 0 && i < shared.length ? shared[i].trim() : '';
    case 'inlineStr':
      return _els(c, 't').map((e) => e.innerText).join().trim();
    case 'b':
      return v == '1' ? 'TRUE' : 'FALSE';
    case 'str':
    case 'e':
      return (v ?? '').trim();
  }
  if (v == null || v.isEmpty) return '';
  final n = double.tryParse(v);
  if (n == null) return v.trim();
  final s = int.tryParse(_attr(c, 's') ?? '');
  if (s != null && dateStyles.contains(s)) return excelDateText(n);
  if (n == n.truncateToDouble() && n.abs() < 1e15) return n.toInt().toString();
  var out = n.toStringAsFixed(4);
  out = out.replaceFirst(RegExp(r'0+$'), '');
  return out.endsWith('.') ? out.substring(0, out.length - 1) : out;
}

bool _isDateFormat(int id, String? code) {
  if ((id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47) || (id >= 50 && id <= 58)) return true;
  if (code == null) return false;
  final c = code.replaceAll(RegExp(r'"[^"]*"'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').replaceAll(RegExp(r'\\.'), '').toLowerCase();
  return c.contains('y') || c.contains('d') || (c.contains('m') && (c.contains('h') || c.contains('s')));
}

/// Excel day number → "11/03/2026" or "11/03/2026 2:20 PM".
String excelDateText(double serial) {
  final d = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (serial * 86400000).round()));
  final date = '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  if (serial == serial.truncateToDouble()) return date;
  if (serial < 1) {
    // time only
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$date $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

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

/// The sheet that looks most like a clash list (most rows), for the first view.
int bestSheetIndex(XlsxBook book) {
  var best = 0;
  for (var i = 1; i < book.sheets.length; i++) {
    if (book.sheets[i].rows.length > book.sheets[best].rows.length) best = i;
  }
  return best;
}
