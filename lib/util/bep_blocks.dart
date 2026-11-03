import 'dart:typed_data';

/// One piece of a BEP section: a heading, text, a list, a table, a note box, a line or a picture.
class BepBlock {
  BepBlock(
    this.type, {
    this.text = '',
    this.level = 2,
    List<String>? items,
    List<bool>? checks,
    List<List<String>>? rows,
    this.header = true,
    this.tone = 'info',
    this.path = '',
    this.caption = '',
    this.bytes,
  })  : items = items ?? [],
        checks = checks ?? [],
        rows = rows ?? [];

  /// h (heading), p (text), ul (bullets), ol (numbered), check (checklist),
  /// table, note (colored box), hr (line), img (picture).
  String type;
  String text;

  /// Heading size: 1 (big), 2, 3 (small caps).
  int level;
  List<String> items;
  List<bool> checks;
  List<List<String>> rows;

  /// The first table row is a heading row.
  bool header;

  /// Note box color: info, warning, tip, important.
  String tone;

  /// Stored picture path ('files' bucket), and its caption.
  String path;
  String caption;

  /// A picture not uploaded yet (just added or imported from Word).
  Uint8List? bytes;

  static const types = ['h', 'p', 'ul', 'ol', 'check', 'table', 'note', 'hr', 'img'];
  static const tones = ['info', 'warning', 'tip', 'important'];

  static String label(String type) => switch (type) {
        'h' => 'Heading',
        'p' => 'Text',
        'ul' => 'Bullets',
        'ol' => 'Numbered list',
        'check' => 'Checklist',
        'table' => 'Table',
        'note' => 'Note box',
        'hr' => 'Line',
        'img' => 'Picture',
        _ => type,
      };

  BepBlock copy() => BepBlock(type,
      text: text,
      level: level,
      items: [...items],
      checks: [...checks],
      rows: [for (final r in rows) [...r]],
      header: header,
      tone: tone,
      path: path,
      caption: caption,
      bytes: bytes);

  Map<String, dynamic> toJson() => switch (type) {
        'h' => {'t': 'h', 'text': text, 'level': level},
        'p' => {'t': 'p', 'text': text},
        'ul' || 'ol' => {'t': type, 'items': items},
        'check' => {'t': 'check', 'items': items, 'checks': [for (var i = 0; i < items.length; i++) i < checks.length && checks[i]]},
        'table' => {'t': 'table', 'rows': rows, 'header': header},
        'note' => {'t': 'note', 'text': text, 'tone': tone},
        'img' => {'t': 'img', 'path': path, 'caption': caption},
        _ => {'t': type},
      };

  factory BepBlock.fromJson(Map<String, dynamic> j) {
    final t = (j['t'] ?? 'p') as String;
    List<String> strs(Object? v) => v is List ? [for (final x in v) '${x ?? ''}'] : <String>[];
    return BepBlock(
      types.contains(t) ? t : 'p',
      text: (j['text'] ?? '') as String,
      level: (j['level'] as num?)?.toInt() ?? 2,
      items: strs(j['items']),
      checks: j['checks'] is List ? [for (final x in j['checks'] as List) x == true] : null,
      rows: j['rows'] is List ? [for (final r in j['rows'] as List) strs(r)] : null,
      header: j['header'] != false,
      tone: (j['tone'] ?? 'info') as String,
      path: (j['path'] ?? '') as String,
      caption: (j['caption'] ?? '') as String,
    );
  }

  /// True when the block holds nothing worth keeping.
  bool get isEmpty => switch (type) {
        'h' || 'p' || 'note' => text.trim().isEmpty,
        'ul' || 'ol' || 'check' => items.every((x) => x.trim().isEmpty),
        'table' => rows.every((r) => r.every((x) => x.trim().isEmpty)),
        'img' => path.isEmpty && bytes == null,
        _ => false,
      };
}

List<BepBlock> blocksFromJson(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) BepBlock.fromJson(Map<String, dynamic>.from(x))] : <BepBlock>[];

List<Map<String, dynamic>> blocksToJson(List<BepBlock> blocks) => [for (final b in blocks) if (!b.isEmpty || b.type == 'hr') b.toJson()];

/// Plain text of the blocks (kept in "body" for search and older app versions).
String blocksPlainText(List<BepBlock> blocks) {
  final out = <String>[];
  for (final b in blocks) {
    switch (b.type) {
      case 'h':
        out.add('# ${b.text}');
      case 'p':
        out.add(b.text.replaceAll('**', ''));
      case 'note':
        out.add('Note: ${b.text.replaceAll('**', '')}');
      case 'ul':
        out.addAll(b.items.map((x) => '- ${x.trim()}'));
      case 'ol':
        for (var i = 0; i < b.items.length; i++) {
          out.add('- ${i + 1}. ${b.items[i].trim()}');
        }
      case 'check':
        for (var i = 0; i < b.items.length; i++) {
          out.add('- [${i < b.checks.length && b.checks[i] ? 'x' : ' '}] ${b.items[i]}');
        }
      case 'table':
        out.addAll(b.rows.map((r) => r.map((x) => x.replaceAll('\n', ' ')).join(' | ')));
      case 'hr':
        out.add('');
      case 'img':
        out.add(b.caption.isEmpty ? '(picture)' : '(picture) ${b.caption}');
    }
    out.add('');
  }
  return out.join('\n').trim();
}

/// Turns the old "# heading / - bullet" text into blocks.
List<BepBlock> blocksFromText(String body) => textToBlocks(body, markdown: true);

final _bulletRe = RegExp(r'^(\s*)([-*•·▪◦‣])\s+');
final _bulletTabRe = RegExp(r'^(\s*)([-*•·▪◦‣o§])\t');
final _numRe = RegExp(r'^(\s*)(\d{1,3}|[a-zA-Z])[.)]\s+');
final _checkRe = RegExp(r'^\s*([☐☑☒□■✓✔]|\[[ xX]\])\s*');

/// Turns pasted (or old) text into blocks: tab-separated lines become a table,
/// "- " / "•" lines bullets, "1." lines a numbered list, ☐/☒ lines a checklist.
List<BepBlock> textToBlocks(String text, {bool markdown = false}) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <BepBlock>[];
  BepBlock? open;

  void close() {
    if (open != null && !open!.isEmpty) out.add(open!);
    open = null;
  }

  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    final line = raw.trimRight();

    // Table: two or more lines in a row with tabs.
    if (line.contains('\t') && !_bulletTabRe.hasMatch(line) && i + 1 < lines.length && lines[i + 1].contains('\t')) {
      close();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].contains('\t')) {
        rows.add(lines[i].trimRight().split('\t').map((x) => x.trim()).toList());
        i++;
      }
      final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      for (final r in rows) {
        while (r.length < width) {
          r.add('');
        }
      }
      out.add(BepBlock('table', rows: rows, header: true));
      continue;
    }
    i++;

    if (line.trim().isEmpty) {
      close();
      continue;
    }
    if (markdown && line.startsWith('#')) {
      close();
      final hashes = RegExp(r'^#+').stringMatch(line)!.length;
      out.add(BepBlock('h', text: line.substring(hashes).trim(), level: 3)); // old "# " lines were small headings
      continue;
    }
    final check = _checkRe.firstMatch(line);
    if (check != null && line.trim().length > check.group(0)!.length) {
      final mark = check.group(1)!;
      final done = mark == '☑' || mark == '☒' || mark == '■' || mark == '✓' || mark == '✔' || mark.toLowerCase() == '[x]';
      if (open?.type != 'check') {
        close();
        open = BepBlock('check');
      }
      open!.items.add(line.substring(check.end).trim());
      open!.checks.add(done);
      continue;
    }
    final bullet = _bulletRe.firstMatch(line) ?? _bulletTabRe.firstMatch(line);
    if (bullet != null && line.length > bullet.end) {
      if (open?.type != 'ul') {
        close();
        open = BepBlock('ul');
      }
      open!.items.add('${'  ' * (bullet.group(1)!.length ~/ 2)}${line.substring(bullet.end).trim()}');
      continue;
    }
    final num = _numRe.firstMatch(line);
    if (num != null && line.length > num.end && (open?.type == 'ol' || RegExp(r'^\s*(1|a|A)[.)]').hasMatch(line))) {
      if (open?.type != 'ol') {
        close();
        open = BepBlock('ol');
      }
      open!.items.add('${'  ' * (num.group(1)!.length ~/ 2)}${line.substring(num.end).trim()}');
      continue;
    }
    if (open?.type != 'p') {
      close();
      open = BepBlock('p');
      open!.text = line.trim();
    } else {
      open!.text = '${open!.text}\n${line.trim()}';
    }
  }
  close();
  return out;
}

/// A rough line count, to decide when a section is long enough to fold.
double blocksHeightEstimate(List<BepBlock> blocks) {
  var lines = 0.0;
  for (final b in blocks) {
    switch (b.type) {
      case 'h':
        lines += 1.6;
      case 'p':
      case 'note':
        for (final l in b.text.split('\n')) {
          lines += 1 + l.length ~/ 110;
        }
        if (b.type == 'note') lines += 1;
      case 'ul':
      case 'ol':
      case 'check':
        for (final l in b.items) {
          lines += 1 + l.length ~/ 110;
        }
      case 'table':
        lines += b.rows.length * 1.8;
      case 'img':
        lines += 14;
      default:
        lines += 1;
    }
    lines += 0.5;
  }
  return lines;
}
