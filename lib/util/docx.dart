import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'bep_blocks.dart';

class DocxException implements Exception {
  DocxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What came out of a Word file.
class DocxContent {
  DocxContent(this.blocks, this.skippedPictures);
  final List<BepBlock> blocks;

  /// Pictures left out (too large or too many).
  final int skippedPictures;

  /// Splits the content into sections at the top-level headings: (title, blocks).
  List<(String, List<BepBlock>)> sections() {
    final levels = blocks.where((b) => b.type == 'h').map((b) => b.level);
    if (levels.isEmpty) return [('Imported from Word', blocks)];
    final top = levels.reduce((a, b) => a < b ? a : b);
    final out = <(String, List<BepBlock>)>[];
    var title = 'Introduction';
    var current = <BepBlock>[];
    for (final b in blocks) {
      if (b.type == 'h' && b.level == top) {
        if (current.isNotEmpty) out.add((title, current));
        title = b.text.trim().isEmpty ? 'Section ${out.length + 1}' : b.text.trim();
        current = [];
      } else {
        // Headings under the top level move up one step.
        current.add(b.type == 'h' ? (b.copy()..level = (b.level - top).clamp(1, 3)) : b);
      }
    }
    if (current.isNotEmpty || out.isEmpty) out.add((title, current));
    return out;
  }
}

const _maxPictures = 40;
const _maxPictureBytes = 8 * 1024 * 1024;

/// Reads a .docx file into BEP blocks: headings, text (bold kept), bullet and numbered
/// lists, checkboxes, tables and pictures.
DocxContent readDocx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw DocxException('This is not a Word .docx file. In Word use File > Save As > Word Document (.docx).');
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

  final main = doc('word/document.xml');
  if (main == null) throw DocxException('This file has no Word document inside. Is it a .docx file?');

  // Styles: id -> heading level (1..9) and whether a style is a list style.
  final headingOf = <String, int>{};
  final styles = doc('word/styles.xml');
  if (styles != null) {
    for (final s in _els(styles, 'style')) {
      final id = _attr(s, 'styleId');
      if (id == null) continue;
      final name = (_attr(_child(s, 'name'), 'val') ?? '').toLowerCase();
      final outline = int.tryParse(_attr(_child(_child(s, 'pPr'), 'outlineLvl'), 'val') ?? '');
      final m = RegExp(r'^heading\s*(\d)').firstMatch(name);
      if (m != null) {
        headingOf[id] = int.parse(m.group(1)!);
      } else if (name == 'title') {
        headingOf[id] = 1;
      } else if (outline != null && outline < 9) {
        headingOf[id] = outline + 1;
      }
    }
  }

  // Numbering: numId -> ilvl -> format ("bullet", "decimal", ...)
  final abstractFmt = <String, Map<int, String>>{};
  final numToAbstract = <String, String>{};
  final numbering = doc('word/numbering.xml');
  if (numbering != null) {
    for (final a in _els(numbering, 'abstractNum')) {
      final id = _attr(a, 'abstractNumId');
      if (id == null) continue;
      final levels = <int, String>{};
      for (final l in a.childElements.where((e) => e.name.local == 'lvl')) {
        final ilvl = int.tryParse(_attr(l, 'ilvl') ?? '') ?? 0;
        levels[ilvl] = _attr(_child(l, 'numFmt'), 'val') ?? 'bullet';
      }
      abstractFmt[id] = levels;
    }
    for (final n in _els(numbering, 'num')) {
      final id = _attr(n, 'numId');
      final abs = _attr(_child(n, 'abstractNumId'), 'val');
      if (id != null && abs != null) numToAbstract[id] = abs;
    }
  }

  final rels = <String, String>{};
  final relDoc = doc('word/_rels/document.xml.rels');
  if (relDoc != null) {
    for (final r in _els(relDoc, 'Relationship')) {
      final id = _attr(r, 'Id'), t = _attr(r, 'Target');
      if (id != null && t != null) rels[id] = t;
    }
  }

  final out = <BepBlock>[];
  var pictures = 0, skipped = 0;
  BepBlock? list; // the list being filled

  void endList() {
    if (list != null && list!.items.isNotEmpty) out.add(list!);
    list = null;
  }

  void addPicture(String rid) {
    final target = rels[rid];
    if (target == null) return;
    final path = target.startsWith('/') ? target.substring(1) : 'word/${target.replaceFirst(RegExp(r'^\./'), '')}';
    final b = raw(path);
    final lower = path.toLowerCase();
    final isImage = lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.bmp');
    if (b == null || !isImage) return;
    if (pictures >= _maxPictures || b.length > _maxPictureBytes) {
      skipped++;
      return;
    }
    pictures++;
    out.add(BepBlock('img', bytes: b));
  }

  /// Text of a paragraph with **bold** marks, plus picture ids found in it.
  (String, List<String>) paragraphText(XmlElement p, {bool marks = true}) {
    final b = StringBuffer();
    final pics = <String>[];
    void walk(XmlElement e) {
      for (final c in e.childElements) {
        switch (c.name.local) {
          case 'r':
            {
              final rPr = _child(c, 'rPr');
              final bold = marks && _on(_child(rPr, 'b'));
              final text = StringBuffer();
              for (final x in c.childElements) {
                switch (x.name.local) {
                  case 't':
                    text.write(x.innerText);
                  case 'tab':
                    text.write('\t');
                  case 'br':
                  case 'cr':
                    text.write('\n');
                  case 'noBreakHyphen':
                    text.write('-');
                  case 'sym':
                    {
                      final ch = (_attr(x, 'char') ?? '').toUpperCase();
                      text.write(const ['F0FE', 'F078', '2612', '2611', 'F0FD', 'F0FC'].contains(ch) ? '☒' : '☐');
                    }
                  case 'drawing':
                  case 'pict':
                  case 'object':
                    for (final blip in _els(x, 'blip')) {
                      final id = _attr(blip, 'embed');
                      if (id != null) pics.add(id);
                    }
                    for (final im in _els(x, 'imagedata')) {
                      final id = _attr(im, 'id');
                      if (id != null) pics.add(id);
                    }
                }
              }
              final s = text.toString();
              if (s.isEmpty) break;
              if (bold && s.trim().isNotEmpty) {
                final lead = RegExp(r'^\s*').stringMatch(s)!;
                final tail = RegExp(r'\s*$').stringMatch(s)!;
                b.write('$lead**${s.trim()}**$tail');
              } else {
                b.write(s);
              }
            }
          case 'hyperlink':
          case 'smartTag':
          case 'ins':
          case 'sdt':
          case 'sdtContent':
          case 'fldSimple':
          case 'customXml':
          case 'moveTo':
            walk(c);
          default:
            break;
        }
      }
    }

    walk(p);
    return (b.toString().replaceAll('****', ''), pics);
  }

  String cellText(XmlElement tc) {
    final parts = <String>[];
    for (final p in _els(tc, 'p')) {
      final t = paragraphText(p, marks: false).$1.replaceAll('\t', ' ').trim();
      if (t.isNotEmpty) parts.add(t);
    }
    return parts.join('\n');
  }

  void paragraph(XmlElement p) {
    final pPr = _child(p, 'pPr');
    final styleId = _attr(_child(pPr, 'pStyle'), 'val');
    final outline = int.tryParse(_attr(_child(pPr, 'outlineLvl'), 'val') ?? '');
    final numPr = _child(pPr, 'numPr');
    final (text, pics) = paragraphText(p);
    final plain = text.replaceAll('**', '').trim();

    var heading = styleId == null ? null : headingOf[styleId];
    if (heading == null && outline != null && outline < 9) heading = outline + 1;

    if (heading != null && plain.isNotEmpty) {
      endList();
      out.add(BepBlock('h', text: plain, level: heading));
    } else if (numPr != null && plain.isNotEmpty) {
      final numId = _attr(_child(numPr, 'numId'), 'val') ?? '';
      final ilvl = int.tryParse(_attr(_child(numPr, 'ilvl'), 'val') ?? '') ?? 0;
      final fmt = abstractFmt[numToAbstract[numId]]?[ilvl] ?? 'bullet';
      final checkbox = RegExp(r'^[☐☑☒]').hasMatch(plain);
      final type = checkbox ? 'check' : (fmt == 'bullet' || fmt == 'none' ? 'ul' : 'ol');
      if (list?.type != type) {
        endList();
        list = BepBlock(type);
      }
      if (type == 'check') {
        list!.items.add(plain.substring(1).trim());
        list!.checks.add(!plain.startsWith('☐'));
      } else {
        list!.items.add('${'  ' * ilvl}${text.trim()}');
      }
    } else if (plain.isNotEmpty) {
      endList();
      // Plain text: the usual bullet / checkbox characters still become lists.
      final blocks = textToBlocks(text);
      if (blocks.length == 1 && blocks.first.type == 'p' && out.isNotEmpty && out.last.type == 'p' && !out.last.text.endsWith('\n\n')) {
        out.last.text = '${out.last.text}\n${blocks.first.text}';
      } else {
        for (final b in blocks) {
          if (b.type == 'check' && out.isNotEmpty && out.last.type == 'check') {
            out.last.items.addAll(b.items);
            out.last.checks.addAll(b.checks);
          } else {
            out.add(b);
          }
        }
      }
    } else {
      endList();
      // An empty paragraph ends the current text block.
      if (out.isNotEmpty && out.last.type == 'p' && !out.last.text.endsWith('\n\n')) out.last.text = '${out.last.text}\n\n';
    }
    for (final id in pics) {
      endList();
      addPicture(id);
    }
  }

  void table(XmlElement tbl) {
    endList();
    final rows = <List<String>>[];
    for (final tr in tbl.childElements.where((e) => e.name.local == 'tr')) {
      final row = <String>[];
      for (final tc in tr.childElements.where((e) => e.name.local == 'tc' || e.name.local == 'sdt')) {
        final cell = tc.name.local == 'sdt' ? _els(tc, 'tc').firstOrNull : tc;
        if (cell == null) continue;
        final tcPr = _child(cell, 'tcPr');
        final span = int.tryParse(_attr(_child(tcPr, 'gridSpan'), 'val') ?? '') ?? 1;
        final vMerge = _child(tcPr, 'vMerge');
        final continued = vMerge != null && _attr(vMerge, 'val') != 'restart';
        row.add(continued ? '' : cellText(cell));
        for (var i = 1; i < span; i++) {
          row.add('');
        }
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isEmpty) return;
    final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    for (final r in rows) {
      while (r.length < width) {
        r.add('');
      }
    }
    // A one-cell table is a box of text.
    if (width == 1 && rows.length == 1) {
      out.add(BepBlock('note', text: rows.first.first, tone: 'info'));
      return;
    }
    out.add(BepBlock('table', rows: rows, header: true));
    for (final p in _els(tbl, 'blip')) {
      final id = _attr(p, 'embed');
      if (id != null) addPicture(id);
    }
  }

  void body(XmlElement e) {
    for (final c in e.childElements) {
      switch (c.name.local) {
        case 'p':
          paragraph(c);
        case 'tbl':
          table(c);
        case 'sdt':
          {
            final content = _child(c, 'sdtContent');
            if (content != null) body(content);
          }
        case 'customXml':
          body(c);
      }
    }
  }

  final bodyEl = _els(main, 'body').firstOrNull;
  if (bodyEl != null) body(bodyEl);
  endList();
  for (final b in out) {
    if (b.type == 'p') b.text = b.text.trim();
  }
  return DocxContent(out.where((b) => !b.isEmpty).toList(), skipped);
}

bool _on(XmlElement? e) {
  if (e == null) return false;
  final v = _attr(e, 'val');
  return v == null || (v != '0' && v != 'false' && v != 'none');
}

XmlElement? _child(XmlElement? e, String local) => e?.childElements.where((x) => x.name.local == local).firstOrNull;

Iterable<XmlElement> _els(XmlNode n, String local) => n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String? _attr(XmlElement? e, String local) {
  if (e == null) return null;
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
