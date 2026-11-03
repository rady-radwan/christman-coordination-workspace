// Excel number formats: turns a cell value into the text Excel shows.

const _monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _daysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Built-in Excel formats by id (the ones that matter for display).
const builtInFormats = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'mm/dd/yyyy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yyyy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
};

/// A format code with quoted text, escapes and [brackets] removed (for testing what kind it is).
String _bare(String code) =>
    code.replaceAll(RegExp(r'"[^"]*"'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').replaceAll(RegExp(r'\\.'), '').replaceAll(RegExp(r'[_*].'), '');

bool isDateFormatCode(String code) {
  final c = _bare(code).toLowerCase();
  if (c.contains('general')) return false;
  return c.contains('y') || c.contains('d') || c.contains('h') || (c.contains('m') && !c.contains('0') && !c.contains('#')) || c.contains('s') && c.contains(':');
}

/// Splits "pos;neg;zero;text" outside quotes.
List<String> _sections(String code) {
  final out = <String>[];
  final b = StringBuffer();
  var q = false;
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (ch == '"') q = !q;
    if (ch == '\\' && i + 1 < code.length) {
      b.write(ch);
      b.write(code[++i]);
      continue;
    }
    if (ch == ';' && !q) {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(ch);
    }
  }
  out.add(b.toString());
  return out;
}

/// The text Excel shows for [v] (a number, text, true/false or error) in format [code].
String formatValue(Object? v, String code) {
  if (v == null) return '';
  if (v is bool) return v ? 'TRUE' : 'FALSE';
  if (v is String) {
    final secs = _sections(code);
    if (secs.length >= 4 && secs[3].contains('@')) return _literal(secs[3]).replaceAll('@', v);
    return v;
  }
  if (v is! num) return v.toString();
  final n = v.toDouble();
  if (code.isEmpty || code.toLowerCase() == 'general') return generalNumber(n);
  final secs = _sections(code);
  var sec = secs[0];
  var value = n;
  var sign = '';
  if (n < 0) {
    if (secs.length >= 2 && secs[1].trim().isNotEmpty) {
      sec = secs[1];
      value = -n;
    } else {
      sign = '-';
      value = -n;
    }
  } else if (n == 0 && secs.length >= 3 && secs[2].trim().isNotEmpty) {
    sec = secs[2];
  }
  if (sec.toLowerCase().trim() == 'general') return sign + generalNumber(value);
  if (sec.trim() == '@') return generalNumber(n);
  if (isDateFormatCode(sec)) return formatDate(n, sec);
  return sign + _formatNumber(value, sec);
}

/// Excel's "General" display of a number.
String generalNumber(double n) {
  if (n.isNaN || n.isInfinite) return '#NUM!';
  if (n == n.truncateToDouble() && n.abs() < 1e11) return n.toInt().toString();
  if (n.abs() >= 1e11 || (n.abs() < 1e-9 && n != 0)) return n.toStringAsExponential(5).replaceFirst(RegExp(r'\.?0+e'), 'E').replaceFirst('E+', 'E+');
  final digitsBefore = n.abs() < 1 ? 1 : n.abs().toInt().toString().length;
  var s = n.toStringAsFixed((10 - digitsBefore).clamp(0, 10));
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Removes quotes, escapes, [colors], spacing (_x) and fill (*x) marks.
String _literal(String s) {
  final b = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '"') {
      final end = s.indexOf('"', i + 1);
      if (end < 0) break;
      b.write(s.substring(i + 1, end));
      i = end + 1;
    } else if (ch == '\\' && i + 1 < s.length) {
      b.write(s[i + 1]);
      i += 2;
    } else if (ch == '_' && i + 1 < s.length) {
      b.write(' ');
      i += 2;
    } else if (ch == '*' && i + 1 < s.length) {
      i += 2;
    } else if (ch == '[') {
      final end = s.indexOf(']', i);
      i = end < 0 ? s.length : end + 1;
    } else {
      b.write(ch);
      i++;
    }
  }
  return b.toString();
}

String _formatNumber(double value, String sec) {
  // Find the digit placeholders outside quotes.
  var first = -1, last = -1;
  var q = false;
  for (var i = 0; i < sec.length; i++) {
    final ch = sec[i];
    if (ch == '"') q = !q;
    if (q) continue;
    if (ch == '\\') {
      i++;
      continue;
    }
    if ('0#?'.contains(ch)) {
      if (first < 0) first = i;
      last = i;
    }
  }
  final percents = RegExp('%').allMatches(_bare(sec)).length;
  for (var p = 0; p < percents; p++) {
    value *= 100;
  }
  if (first < 0) return _literal(sec);
  // Extend over a decimal point / commas right after the last digit (e.g. "0.").
  var end = last + 1;
  while (end < sec.length && (sec[end] == ',' || sec[end] == '.')) {
    end++;
  }
  final pattern = sec.substring(first, end);
  if (pattern.toUpperCase().contains('E')) return value.toStringAsExponential(2).toUpperCase();
  final dot = pattern.indexOf('.');
  final decimals = dot < 0 ? 0 : RegExp('[0#?]').allMatches(pattern.substring(dot + 1)).length;
  final intPart = dot < 0 ? pattern : pattern.substring(0, dot);
  final grouping = RegExp(r'[0#?],[0#?]').hasMatch(intPart);
  // Trailing commas scale by 1000.
  var scale = 0;
  for (var i = intPart.length - 1; i >= 0 && intPart[i] == ','; i--) {
    scale++;
  }
  for (var s = 0; s < scale; s++) {
    value /= 1000;
  }
  var digits = value.toStringAsFixed(decimals);
  var whole = digits.contains('.') ? digits.substring(0, digits.indexOf('.')) : digits;
  var frac = digits.contains('.') ? digits.substring(digits.indexOf('.') + 1) : '';
  // Optional decimals (#) drop trailing zeros.
  if (dot >= 0) {
    final decPattern = pattern.substring(dot + 1).replaceAll(RegExp('[^0#?]'), '');
    final required = decPattern.lastIndexOf('0') + 1;
    while (frac.length > required && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
  }
  if (!intPart.contains('0') && whole == '0') whole = '';
  if (grouping) whole = _group(whole);
  final number = frac.isEmpty ? (dot >= 0 && pattern.substring(dot + 1).contains('0') ? '$whole.' : whole) : '$whole.$frac';
  return _literal(sec.substring(0, first)) + number + _literal(sec.substring(end));
}

String _group(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// Excel day number shown with a date/time format like "mmm d, yyyy" or "h:mm AM/PM".
String formatDate(double serial, String code) {
  final d = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (serial * 86400000).round()));
  final c = code;
  final ampm = RegExp(r'am/pm|a/p', caseSensitive: false).hasMatch(c);
  final b = StringBuffer();
  var i = 0;
  var lastWasHour = false;
  String two(int n) => n.toString().padLeft(2, '0');
  while (i < c.length) {
    final rest = c.substring(i);
    final lower = rest.toLowerCase();
    final ch = lower[0];
    if (rest.startsWith('"')) {
      final end = c.indexOf('"', i + 1);
      b.write(c.substring(i + 1, end < 0 ? c.length : end));
      i = end < 0 ? c.length : end + 1;
      continue;
    }
    if (ch == '\\' && rest.length > 1) {
      b.write(rest[1]);
      i += 2;
      continue;
    }
    if (ch == '[') {
      final end = c.indexOf(']', i);
      i = end < 0 ? c.length : end + 1;
      continue;
    }
    if (ch == '_' || ch == '*') {
      if (ch == '_') b.write(' ');
      i += 2;
      continue;
    }
    if (lower.startsWith('am/pm')) {
      b.write(d.hour < 12 ? 'AM' : 'PM');
      i += 5;
      continue;
    }
    if (lower.startsWith('a/p')) {
      b.write(d.hour < 12 ? 'A' : 'P');
      i += 3;
      continue;
    }
    final run = RegExp('^${RegExp.escape(ch)}+').stringMatch(lower)!.length;
    switch (ch) {
      case 'y':
        b.write(run <= 2 ? two(d.year % 100) : d.year.toString());
        break;
      case 'm':
        // Minutes when right after hours or right before seconds.
        final after = lower.substring(run).replaceFirst(RegExp(r'^[^a-z]*'), '');
        if ((lastWasHour || after.startsWith('s')) && run <= 2) {
          b.write(run == 1 ? d.minute.toString() : two(d.minute));
        } else if (run == 1) {
          b.write(d.month.toString());
        } else if (run == 2) {
          b.write(two(d.month));
        } else if (run == 3) {
          b.write(_monthsLong[d.month - 1].substring(0, 3));
        } else if (run == 5) {
          b.write(_monthsLong[d.month - 1][0]);
        } else {
          b.write(_monthsLong[d.month - 1]);
        }
        break;
      case 'd':
        if (run == 1) {
          b.write(d.day.toString());
        } else if (run == 2) {
          b.write(two(d.day));
        } else if (run == 3) {
          b.write(_daysLong[d.weekday - 1].substring(0, 3));
        } else {
          b.write(_daysLong[d.weekday - 1]);
        }
        break;
      case 'h':
        var h = d.hour;
        if (ampm) h = h % 12 == 0 ? 12 : h % 12;
        b.write(run == 1 ? h.toString() : two(h));
        break;
      case 's':
        b.write(run == 1 ? d.second.toString() : two(d.second));
        break;
      default:
        b.write(rest.substring(0, run));
    }
    if (ch != ':' && ch != ' ') lastWasHour = ch == 'h';
    i += run;
  }
  return b.toString();
}
