import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:christman_coordination/util/formula.dart';
import 'package:christman_coordination/util/numfmt.dart';
import 'package:christman_coordination/util/xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile _f(String name, String text) {
  final b = utf8.encode(text);
  return ArchiveFile(name, b.length, b);
}

/// A small clash report: title row, header row, 2 clashes (one with a picture), a date cell.
Uint8List _workbook() {
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
  final a = Archive()
    ..addFile(_f('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'))
    ..addFile(_f('xl/workbook.xml',
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Summary" sheetId="2" r:id="rId2"/><sheet name="Clashes" sheetId="1" r:id="rId1"/></sheets></workbook>'))
    ..addFile(_f('xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>'))
    ..addFile(_f('xl/worksheets/sheet2.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="30" customWidth="1"/></cols><sheetData>'
        '<row r="1" ht="24" customHeight="1"><c r="A1" t="inlineStr" s="2"><is><t>Total clashes</t></is></c><c r="B1" t="inlineStr"><is><t>Open</t></is></c></row>'
        '<row r="2"><c r="A2"><f>COUNTA(Clashes!A4:A100)</f></c><c r="B2"><f>COUNTIFS(Clashes!B:B,"&lt;&gt;Resolved",Clashes!A:A,"Clash?")</f></c><c r="C2"><f>A2*2</f><v>99</v></c><c r="D2"><f>IFERROR(1/0,"none")</f></c><c r="E2"><f>SUMPRODUCT((Clashes!B4:B5="New")*1)</f></c></row>'
        '</sheetData><mergeCells count="1"><mergeCell ref="A1:A1"/></mergeCells></worksheet>'))
    ..addFile(_f('xl/sharedStrings.xml',
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>NMC Clash Report</t></si><si><t>Clash Name</t></si><si><t>Status</t></si><si><t>Grid Location</t></si><si><t>Date Found</t></si><si><t>Clash1</t></si><si><t>New</t></si><si><t>C-4 : Level 2</t></si><si><t>Clash2</t></si><si><r><t>Act</t></r><r><t>ive</t></r></si><si><t>Image</t></si></sst>'))
    ..addFile(_f('xl/styles.xml',
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/></font><font><b/><sz val="14"/><color rgb="FFFFFFFF"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor theme="4" tint="0.5"/></patternFill></fill></fills>'
        '<borders count="2"><border/><border><left style="thin"><color auto="1"/></left><bottom style="medium"><color rgb="FFFF0000"/></bottom></border></borders>'
        '<cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf></cellXfs></styleSheet>'))
    ..addFile(_f('xl/worksheets/sheet1.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
        '<row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3" t="s"><v>2</v></c><c r="C3" t="s"><v>3</v></c><c r="D3" t="s"><v>4</v></c><c r="E3" t="s"><v>10</v></c></row>'
        '<row r="4"><c r="A4" t="s"><v>5</v></c><c r="B4" t="s"><v>6</v></c><c r="C4" t="s"><v>7</v></c><c r="D4" s="1"><v>46329</v></c></row>'
        '<row r="5"><c r="A5" t="s"><v>8</v></c><c r="B5" t="s"><v>9</v></c><c r="C5" t="inlineStr"><is><t>D-6</t></is></c><c r="D5"><v>12.5</v></c></row>'
        '</sheetData><drawing r:id="rId1"/></worksheet>'))
    ..addFile(_f('xl/worksheets/_rels/sheet1.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>'))
    ..addFile(_f('xl/drawings/drawing1.xml',
        '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<xdr:twoCellAnchor><xdr:from><xdr:col>4</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>3</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>5</xdr:col><xdr:row>4</xdr:row></xdr:to>'
        '<xdr:pic><xdr:blipFill><a:blip r:embed="rId1"/></xdr:blipFill></xdr:pic><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>'))
    ..addFile(_f('xl/drawings/_rels/drawing1.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>'))
    ..addFile(ArchiveFile('xl/media/image1.png', png.length, png));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test('reads cells, dates, rich text and pictures', () {
    final book = readXlsx(_workbook());
    expect(book.sheets.map((s) => s.name).toList(), ['Summary', 'Clashes']);
    expect(bestSheetIndex(book), 1);
    final t = ClashTable.from(book.sheets[1]);
    expect(t.isClashList, isTrue);
    expect(t.headerRow, 2);
    expect(t.headers.take(5).toList(), ['Clash Name', 'Status', 'Grid Location', 'Date Found', 'Image']);
    expect(t.rows.length, 2);
    expect(t.cell(0, 0), 'Clash1');
    expect(t.cell(0, 3), '11/03/2026');
    expect(t.cell(1, 1), 'Active');
    expect(t.cell(1, 2), 'D-6');
    expect(t.cell(1, 3), '12.5');
    expect(t.rowImages[0]?.length, 1);
    expect(t.imageColumn, 4);
    expect(t.statusColumn, 1);
    expect(t.nameColumn, 0);
    expect(t.gridColumn, 2);
    expect(t.statusCounts(), {'New': 1, 'Active': 1});
  });

  test('summary formulas saved without results are calculated; looks are read', () {
    final book = readXlsx(_workbook());
    final sum = book.sheets[0];
    expect(ClashTable.from(sum).isClashList, isFalse);
    String text(int r, int c) => sum.cells[r]![c]!.text;
    expect(text(1, 0), '2'); // COUNTA
    expect(text(1, 1), '2'); // COUNTIFS with <> and wildcard
    expect(text(1, 2), '99'); // saved result is kept
    expect(text(1, 3), 'none'); // IFERROR
    expect(text(1, 4), '1'); // SUMPRODUCT
    final st = book.style(sum.cells[0]![0]!.style);
    expect(st.bold, isTrue);
    expect(st.fontSize, 14);
    expect(st.fontColor, 0xFFFFFFFF);
    expect(st.fill, isNotNull);
    expect(st.hAlign, 'center');
    expect(st.wrap, isTrue);
    expect(st.left?.style, 'thin');
    expect(st.bottom?.color, 0xFFFF0000);
    expect(sum.colPx(0), 210);
    expect(sum.rowPx(0), 32);
    expect(sum.merges.length, 1);
  });

  test('formula calculator', () {
    final h = _Grid({
      'A1': 5.0, 'A2': 10.0, 'A3': 'x', 'B1': 'New', 'B2': 'Active', 'B3': 'New',
    });
    Object? f(String s) => evaluateFormula(s, h, now: DateTime(2026, 11, 3));
    expect(f('SUM(A1:A3)'), 15.0);
    expect(f('A1+A2*2'), 25.0);
    expect(f('COUNTIF(B1:B3,"New")'), 2.0);
    expect(f('COUNTIFS(B:B,"New",A:A,">4")'), 1.0);
    expect(f('SUMIFS(A1:A3,B1:B3,"<>Active")'), 5.0);
    expect(f('IF(A1>3,"big","small")'), 'big');
    expect(f('A1/0'), const XlError('#DIV/0!'));
    expect(f('IFERROR(A1/0,0)'), 0.0);
    expect(f('"Total: "&A2'), 'Total: 10');
    expect(f('ROUND(2.345,2)'), 2.35);
    expect(f('TODAY()'), 46329.0);
    expect(f('TEXT(TODAY(),"mmm d, yyyy")'), 'Nov 3, 2026');
    expect(f('MAX(A1:A3)-MIN(A1:A3)'), 5.0);
    expect(f('VLOOKUP("Active",B1:B3,1,FALSE)'), 'Active');
    expect(f('INDEX(B1:B3,MATCH(10,A1:A3,0))'), 'Active');
    expect(f('UNKNOWNFN(1)'), const XlError('#NAME?'));
    expect(shiftFormula(r'SUM(A1:B2)+$C$3+Sheet1!D4', 1, 2), r'SUM(C2:D3)+$C$3+Sheet1!F5');
  });

  test('number formats', () {
    expect(formatValue(1234.5, '#,##0.00'), '1,234.50');
    expect(formatValue(0.256, '0.0%'), '25.6%');
    expect(formatValue(46329.0, 'mmm d, yyyy'), 'Nov 3, 2026');
    expect(formatValue(46329.5, 'm/d/yyyy h:mm AM/PM'), '11/3/2026 12:00 PM');
    expect(formatValue(-12.0, '#,##0;(#,##0)'), '(12)');
    expect(formatValue(3.0, '0 "days"'), '3 days');
    expect(formatValue(12.5, 'General'), '12.5');
    expect(formatValue(0.0, '#,##0'), '0');
  });

  test('rejects files that are not xlsx', () {
    expect(() => readXlsx(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<XlsxException>()));
  });
}

/// A tiny one-sheet host for testing formulas.
class _Grid implements FormulaHost {
  _Grid(Map<String, Object?> cells) {
    cells.forEach((k, v) {
      final rc = parseCellRef(k)!;
      _cells[(rc.$1, rc.$2)] = v;
    });
  }
  final _cells = <(int, int), Object?>{};

  @override
  Object? cellValue(String? sheet, int row, int col) => _cells[(row, col)];

  @override
  int lastRow(String? sheet) => _cells.keys.map((k) => k.$1).reduce((a, b) => a > b ? a : b);

  @override
  int lastCol(String? sheet) => _cells.keys.map((k) => k.$2).reduce((a, b) => a > b ? a : b);

  @override
  String? definedName(String name) => null;
}
