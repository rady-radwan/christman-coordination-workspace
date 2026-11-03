import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Clashes" sheetId="1" r:id="rId1"/></sheets></workbook>'))
    ..addFile(_f('xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'))
    ..addFile(_f('xl/sharedStrings.xml',
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>NMC Clash Report</t></si><si><t>Clash Name</t></si><si><t>Status</t></si><si><t>Grid Location</t></si><si><t>Date Found</t></si><si><t>Clash1</t></si><si><t>New</t></si><si><t>C-4 : Level 2</t></si><si><t>Clash2</t></si><si><r><t>Act</t></r><r><t>ive</t></r></si><si><t>Image</t></si></sst>'))
    ..addFile(_f('xl/styles.xml',
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>'))
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
    expect(book.sheets.single.name, 'Clashes');
    final t = ClashTable.from(book.sheets.single);
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

  test('rejects files that are not xlsx', () {
    expect(() => readXlsx(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<XlsxException>()));
  });
}
