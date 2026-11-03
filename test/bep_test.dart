import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:christman_coordination/util/bep_blocks.dart';
import 'package:christman_coordination/util/docx.dart';
import 'package:christman_coordination/util/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile _f(String name, String text) {
  final b = utf8.encode(text);
  return ArchiveFile(name, b.length, b);
}

const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

Uint8List _docx() {
  final body = '<w:body>'
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Project Information</w:t></w:r></w:p>'
      '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Owner:</w:t></w:r><w:r><w:t xml:space="preserve"> Newcastle</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Revit 2025</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Navisworks 2025</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Naming</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Trade codes</w:t></w:r></w:p>'
      '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Code</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Trade</w:t></w:r></w:p></w:tc></w:tr>'
      '<w:tr><w:tc><w:p><w:r><w:t>MECH</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Mechanical</w:t></w:r></w:p></w:tc></w:tr>'
      '<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>All trades</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
      '<w:p><w:r><w:t>☒ Budget</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>☐ Laser scan</w:t></w:r></w:p>'
      '</w:body>';
  final a = Archive()
    ..addFile(_f('word/document.xml', '<w:document $_w>$body</w:document>'))
    ..addFile(_f('word/styles.xml',
        '<w:styles $_w><w:style w:styleId="Heading1"><w:name w:val="heading 1"/></w:style><w:style w:styleId="Heading2"><w:name w:val="heading 2"/></w:style></w:styles>'))
    ..addFile(_f('word/numbering.xml',
        '<w:numbering $_w><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test('pasted text becomes tables, lists and checklists', () {
    final b = textToBlocks('Intro line\nsecond line\n\nLevel\tElevation\nL1\t0\'-0"\nL2\t14\'-0"\n\n• Revit\n• Navisworks\n\n1. First\n2. Second\n☐ Not yet\n☒ Done');
    expect(b.map((x) => x.type).toList(), ['p', 'table', 'ul', 'ol', 'check']);
    expect(b[0].text, 'Intro line\nsecond line');
    expect(b[1].rows.length, 3);
    expect(b[1].rows[2], ['L2', '14\'-0"']);
    expect(b[2].items, ['Revit', 'Navisworks']);
    expect(b[3].items, ['First', 'Second']);
    expect(b[4].checks, [false, true]);
  });

  test('blocks survive saving and give plain text', () {
    final blocks = [
      BepBlock('h', text: 'Levels', level: 1),
      BepBlock('table', rows: [
        ['A', 'B'],
        ['1', '2']
      ]),
      BepBlock('note', text: 'Use **TOS**', tone: 'warning'),
    ];
    final back = blocksFromJson(jsonDecode(jsonEncode(blocksToJson(blocks))));
    expect(back.length, 3);
    expect(back[1].rows[1], ['1', '2']);
    expect(back[2].tone, 'warning');
    expect(blocksPlainText(back), contains('A | B'));
    // Old "# heading / - bullet" text
    final old = blocksFromText('# Rules\n- No spaces\n- Use dashes\nFormat: X');
    expect(old.map((x) => x.type).toList(), ['h', 'ul', 'p']);
  });

  test('Word file becomes sections with tables, lists and checkboxes', () {
    final d = readDocx(_docx());
    final types = d.blocks.map((b) => b.type).toList();
    expect(types, ['h', 'p', 'ul', 'h', 'h', 'table', 'check']);
    expect(d.blocks[1].text, '**Owner:** Newcastle');
    expect(d.blocks[2].items, ['Revit 2025', 'Navisworks 2025']);
    expect(d.blocks[5].rows[2], ['All trades', '']);
    expect(d.blocks[6].checks, [true, false]);
    final parts = d.sections();
    expect(parts.map((p) => p.$1).toList(), ['Project Information', 'Naming']);
    expect(parts[1].$2.first.type, 'h');
    expect(parts[1].$2.first.level, 1);
    expect(() => readDocx(Uint8List.fromList([1, 2, 3])), throwsA(isA<DocxException>()));
  });

  test('version compare', () {
    expect(compareVersions('0.5.0', '0.4.0'), 1);
    expect(compareVersions('0.10.0', '0.9.3'), 1);
    expect(compareVersions('0.4.0', '0.4.0+4'), 0);
    expect(compareVersions('0.3.9', '0.4'), -1);
  });
}
