import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models.dart';
import 'dates.dart';

const _copper = PdfColor.fromInt(0xFF8C5A32);
const _copperLight = PdfColor.fromInt(0xFFF6ECE3);
const _ink = PdfColor.fromInt(0xFF1A1A1A);
const _muted = PdfColor.fromInt(0xFF5C5A56);
const _line = PdfColor.fromInt(0xFFDEDAD3);
const _rowAlt = PdfColor.fromInt(0xFFF8F7F4);

/// Builds the meeting minutes as an organized PDF with the Christman header.
Future<Uint8List> buildMinutesPdf({
  required Meeting meeting,
  required Project project,
  required String recordedBy,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Barlow-Regular.ttf'));
  final semi = pw.Font.ttf(await rootBundle.load('assets/fonts/Barlow-SemiBold.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Barlow-Bold.ttf'));
  final cond = pw.Font.ttf(await rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
  final logo = pw.MemoryImage((await rootBundle.load('assets/logo/christman-full-light.png')).buffer.asUint8List());

  final theme = pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
    defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10, color: _ink, lineSpacing: 1.5),
  );
  final generated = DateTime.now();
  final m = meeting;

  pw.Widget heading(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 16, bottom: 6),
        padding: const pw.EdgeInsets.only(bottom: 3),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _copper, width: 1.2))),
        child: pw.Text(text.toUpperCase(), style: pw.TextStyle(font: cond, fontSize: 13, color: _copper, letterSpacing: 1.2)),
      );

  pw.Widget cell(String text, {pw.Font? font, PdfColor? color, double size = 9.5, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(text, textAlign: align, style: pw.TextStyle(font: font ?? regular, fontSize: size, color: color ?? _ink)),
      );

  pw.Widget headCell(String text) => pw.Container(
        color: _copperLight,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(text.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 8.5, color: _copper, letterSpacing: 0.6)),
      );

  pw.Widget table(List<String> headers, List<List<pw.Widget>> rows, Map<int, pw.TableColumnWidth> widths) => pw.Table(
        columnWidths: widths,
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _line, width: 0.6),
          bottom: pw.BorderSide(color: _line, width: 0.6),
        ),
        children: [
          pw.TableRow(children: headers.map(headCell).toList(), repeat: true),
          for (var i = 0; i < rows.length; i++)
            pw.TableRow(
              decoration: i.isOdd ? const pw.BoxDecoration(color: _rowAlt) : null,
              children: rows[i],
            ),
        ],
      );

  pw.Widget detail(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 86, child: pw.Text(k, style: pw.TextStyle(font: semi, fontSize: 9.5, color: _muted))),
          pw.Expanded(child: pw.Text(v, style: pw.TextStyle(font: regular, fontSize: 10))),
        ]),
      );

  final present = m.attendees.where((a) => a.present).length;

  final doc = pw.Document(
    title: 'Meeting ${m.number} minutes - ${project.name}',
    author: 'The Christman Company',
    creator: 'Christman Coordination Workspace',
  );
  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.letter.copyWith(marginLeft: 46, marginRight: 46, marginTop: 40, marginBottom: 40),
    header: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.5))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Image(logo, height: 26),
        pw.Spacer(),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('COORDINATION MEETING MINUTES', style: pw.TextStyle(font: cond, fontSize: 14, color: _copper, letterSpacing: 1.4)),
          pw.Text('${project.name}  ·  ${project.code}', style: pw.TextStyle(font: semi, fontSize: 9.5, color: _muted)),
        ]),
      ]),
    ),
    footer: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
      child: pw.Row(children: [
        pw.Text('Meeting ${m.number} · ${m.title}', style: pw.TextStyle(fontSize: 8, color: _muted)),
        pw.Spacer(),
        pw.Text('Generated ${raisedText(generated)} · Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    ),
    build: (ctx) => [
      pw.Text('Meeting ${m.number}', style: pw.TextStyle(font: semi, fontSize: 11, color: _copper)),
      pw.Text(m.title, style: pw.TextStyle(font: cond, fontSize: 24, color: _ink)),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: _rowAlt, border: pw.Border.all(color: _line, width: 0.8), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              detail('Date', weekdayDate(m.startsAt)),
              detail('Time', '${timeText(m.startsAt)} – ${timeText(m.endsAt)} (${m.durationMin} min)'),
              detail('Location', m.location.isEmpty ? '—' : m.location),
            ]),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              detail('Attendance', '$present present of ${m.attendees.length}'),
              detail('Next meeting', m.nextMeeting == null ? 'To be set' : '${weekdayDate(m.nextMeeting!)} · ${timeText(m.nextMeeting!)}'),
              detail('Recorded by', recordedBy),
            ]),
          ),
        ]),
      ),

      if (m.attendees.isNotEmpty) ...[
        heading('Attendees'),
        table(
          ['Name', 'Company', 'Trade / role', 'Present'],
          [
            for (final a in m.attendees)
              [
                cell(a.name, font: semi),
                cell(a.company),
                cell(a.role),
                cell(a.present ? 'Yes' : 'No', color: a.present ? _ink : _muted, align: pw.TextAlign.center),
              ],
          ],
          const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(2.6), 3: pw.FixedColumnWidth(54)},
        ),
      ],

      heading('Summary'),
      pw.Text(m.summary.trim().isEmpty ? 'No summary recorded.' : m.summary.trim(),
          style: pw.TextStyle(fontSize: 10.5, color: m.summary.trim().isEmpty ? _muted : _ink)),

      if (m.items.isNotEmpty) ...[
        heading('Items discussed (${m.items.length})'),
        table(
          ['Item', 'Status / ball in court', 'Discussion'],
          [
            for (final it in m.items)
              [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(it.number, style: pw.TextStyle(font: bold, fontSize: 9.5, color: _copper)),
                    pw.Text(it.title, style: pw.TextStyle(font: semi, fontSize: 9.5)),
                    if (it.priority.isNotEmpty)
                      pw.Text(Priority.fromDb(it.priority).label, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ]),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(it.status.isEmpty ? '' : ItemStatus.fromDb(it.status).label, style: const pw.TextStyle(fontSize: 9.5)),
                    if (it.ball.isNotEmpty) pw.Text(it.ball, style: pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ]),
                ),
                cell(it.note.trim().isEmpty ? '—' : it.note.trim()),
              ],
          ],
          const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2.2), 2: pw.FlexColumnWidth(4.6)},
        ),
      ],

      if (m.actions.isNotEmpty) ...[
        heading('Action items (${m.actions.length})'),
        table(
          ['#', 'Action', 'Owner', 'Due', 'Done'],
          [
            for (var i = 0; i < m.actions.length; i++)
              [
                cell('${i + 1}', color: _muted, align: pw.TextAlign.center),
                cell(m.actions[i].text),
                cell(m.actions[i].owner, font: semi),
                cell(m.actions[i].due == null ? '—' : shortDate(m.actions[i].due!)),
                cell(m.actions[i].done ? 'Done' : 'Open', color: m.actions[i].done ? _muted : _ink, align: pw.TextAlign.center),
              ],
          ],
          const {
            0: pw.FixedColumnWidth(24),
            1: pw.FlexColumnWidth(5.4),
            2: pw.FlexColumnWidth(2.4),
            3: pw.FixedColumnWidth(62),
            4: pw.FixedColumnWidth(44),
          },
        ),
      ],
    ],
  ));
  return doc.save();
}
