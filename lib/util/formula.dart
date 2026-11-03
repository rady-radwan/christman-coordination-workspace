// A small Excel formula calculator, used when a workbook was saved without the
// results of its formulas (some export tools do that). Covers the functions a
// clash report summary normally uses: COUNTIFS, SUMIFS, IF, IFERROR, TODAY, ...

import 'dart:math' as math;

import 'numfmt.dart';

/// An Excel error value like #N/A or #DIV/0!.
class XlError implements Exception {
  const XlError(this.code);
  final String code;
  @override
  String toString() => code;
  @override
  bool operator ==(Object other) => other is XlError && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

const _na = XlError('#N/A');
const _value = XlError('#VALUE!');
const _div0 = XlError('#DIV/0!');
const _ref = XlError('#REF!');
const _name = XlError('#NAME?');
const _num = XlError('#NUM!');

/// What the calculator needs from the workbook.
abstract class FormulaHost {
  /// The value of a cell: double, String, bool, XlError or null (blank).
  /// [sheet] is null for the formula's own sheet. Throws [XlError] '#REF!' for an unknown sheet.
  Object? cellValue(String? sheet, int row, int col);

  /// Last used row / column (0-based) of a sheet, for whole-column references like A:A.
  int lastRow(String? sheet);
  int lastCol(String? sheet);

  /// Formula text of a workbook name (e.g. "Clashes!$A$2:$A$200"), or null.
  String? definedName(String name);
}

/// A block of cells.
class _Area {
  _Area(this.sheet, this.r1, this.c1, this.r2, this.c2);
  final String? sheet;
  final int r1, c1, r2, c2;
  int get rows => r2 - r1 + 1;
  int get cols => c2 - c1 + 1;
}

/// A calculated array (rows of values).
class _Arr {
  _Arr(this.v);
  final List<List<Object?>> v;
  int get rows => v.length;
  int get cols => v.isEmpty ? 0 : v.first.length;
}

/// Calculates [formula] (without the leading "="). Returns double, String, bool, XlError or null.
Object? evaluateFormula(String formula, FormulaHost host, {DateTime? now}) {
  try {
    final p = _Parser(_tokenize(formula), host);
    final node = p.parse();
    final ev = _Eval(host, now ?? DateTime.now());
    final v = ev.scalar(ev.eval(node));
    if (v is double && (v.isNaN || v.isInfinite)) return _num;
    return v;
  } on XlError catch (e) {
    return e;
  } on _Unsupported {
    return _name;
  } catch (_) {
    return _value;
  }
}

class _Unsupported implements Exception {}

// =====================================================================
// Tokens
// =====================================================================

enum _T { num, str, bool, err, ref, area, name, func, op, lparen, rparen, comma, end }

class _Tok {
  _Tok(this.t, [this.s = '', this.n = 0, this.area]);
  final _T t;
  final String s;
  final double n;
  final _Area? area;
  @override
  String toString() => '$t:$s';
}

final _cellRe = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$');
final _colRe = RegExp(r'^\$?([A-Za-z]{1,3})$');
final _rowRe = RegExp(r'^\$?(\d+)$');

int colNumber(String letters) {
  var n = 0;
  for (final ch in letters.toUpperCase().codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

String colLetters(int col) {
  var n = col + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// "A1", "$B$3" -> (row, col), or null.
(int, int)? parseCellRef(String s) {
  final m = _cellRe.firstMatch(s);
  if (m == null) return null;
  final c = colNumber(m.group(1)!);
  final r = int.parse(m.group(2)!) - 1;
  if (c > 16383 || r < 0) return null;
  return (r, c);
}

/// "A1:C5", "A:A", "2:4" -> area, or null. Whole columns/rows use -1 for the open end.
_Area? _parseArea(String? sheet, String a, String b) {
  final ca = parseCellRef(a), cb = parseCellRef(b);
  if (ca != null && cb != null) {
    return _Area(sheet, math.min(ca.$1, cb.$1), math.min(ca.$2, cb.$2), math.max(ca.$1, cb.$1), math.max(ca.$2, cb.$2));
  }
  final xa = _colRe.firstMatch(a), xb = _colRe.firstMatch(b);
  if (xa != null && xb != null) {
    final c1 = colNumber(xa.group(1)!), c2 = colNumber(xb.group(1)!);
    return _Area(sheet, 0, math.min(c1, c2), -1, math.max(c1, c2));
  }
  final ya = _rowRe.firstMatch(a), yb = _rowRe.firstMatch(b);
  if (ya != null && yb != null) {
    final r1 = int.parse(ya.group(1)!) - 1, r2 = int.parse(yb.group(1)!) - 1;
    return _Area(sheet, math.min(r1, r2), 0, math.max(r1, r2), -1);
  }
  return null;
}

List<_Tok> _tokenize(String f) {
  final out = <_Tok>[];
  var i = 0;
  bool isWordChar(String ch) => RegExp(r'[A-Za-z0-9_.$\\]').hasMatch(ch);

  // Reads a reference (and an optional ":ref") after an optional sheet name.
  void readRef(String? sheet) {
    final start = i;
    while (i < f.length && isWordChar(f[i])) {
      i++;
    }
    final a = f.substring(start, i);
    if (i < f.length && f[i] == ':') {
      final save = i;
      i++;
      // Second part may repeat the sheet name: Sheet1!A1:Sheet1!B2
      var j = i;
      while (j < f.length && isWordChar(f[j])) {
        j++;
      }
      if (j < f.length && f[j] == '!') i = j + 1;
      final s2 = i;
      while (i < f.length && isWordChar(f[i])) {
        i++;
      }
      final area = _parseArea(sheet, a, f.substring(s2, i));
      if (area != null) {
        out.add(_Tok(_T.area, '', 0, area));
        return;
      }
      i = save;
    }
    final c = parseCellRef(a);
    if (c != null) {
      out.add(_Tok(_T.area, '', 0, _Area(sheet, c.$1, c.$2, c.$1, c.$2)));
      return;
    }
    throw _ref;
  }

  while (i < f.length) {
    final ch = f[i];
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
      i++;
      continue;
    }
    if (ch == '"') {
      final b = StringBuffer();
      i++;
      while (i < f.length) {
        if (f[i] == '"') {
          if (i + 1 < f.length && f[i + 1] == '"') {
            b.write('"');
            i += 2;
            continue;
          }
          break;
        }
        b.write(f[i]);
        i++;
      }
      i++;
      out.add(_Tok(_T.str, b.toString()));
      continue;
    }
    if (ch == "'") {
      // 'Sheet name'!A1
      final end = f.indexOf("'!", i + 1);
      if (end < 0) throw _ref;
      final sheet = f.substring(i + 1, end).replaceAll("''", "'");
      i = end + 2;
      readRef(sheet);
      continue;
    }
    if (ch == '#') {
      final m = RegExp(r'^#(N/A|DIV/0!|VALUE!|REF!|NAME\?|NUM!|NULL!|SPILL!|CALC!)').firstMatch(f.substring(i));
      if (m == null) throw _value;
      out.add(_Tok(_T.err, m.group(0)!));
      i += m.group(0)!.length;
      continue;
    }
    if (RegExp(r'[0-9.]').hasMatch(ch)) {
      final m = RegExp(r'^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?').firstMatch(f.substring(i));
      if (m != null) {
        // "1:3" (whole rows) is a range, not a number.
        final after = i + m.group(0)!.length;
        if (after < f.length && f[after] == ':' && !m.group(0)!.contains('.')) {
          readRef(null);
          continue;
        }
        out.add(_Tok(_T.num, '', double.parse(m.group(0)!)));
        i = after;
        continue;
      }
    }
    if (RegExp(r'[A-Za-z_$\\]').hasMatch(ch)) {
      final start = i;
      var j = i;
      while (j < f.length && isWordChar(f[j])) {
        j++;
      }
      final word = f.substring(start, j);
      if (j < f.length && f[j] == '!') {
        i = j + 1;
        readRef(word);
        continue;
      }
      if (j < f.length && f[j] == '(') {
        out.add(_Tok(_T.func, word.toUpperCase().replaceFirst(RegExp(r'^_XLFN\.(_XLWS\.)?'), '').replaceFirst('_XLWS.', '')));
        i = j;
        continue;
      }
      final upper = word.toUpperCase();
      if (upper == 'TRUE' || upper == 'FALSE') {
        out.add(_Tok(_T.bool, upper));
        i = j;
        continue;
      }
      if (parseCellRef(word) != null || (j < f.length && f[j] == ':')) {
        i = start;
        readRef(null);
        continue;
      }
      out.add(_Tok(_T.name, word));
      i = j;
      continue;
    }
    if (ch == '(') {
      out.add(_Tok(_T.lparen));
      i++;
      continue;
    }
    if (ch == ')') {
      out.add(_Tok(_T.rparen));
      i++;
      continue;
    }
    if (ch == ',' || ch == ';') {
      out.add(_Tok(_T.comma));
      i++;
      continue;
    }
    final two = i + 1 < f.length ? f.substring(i, i + 2) : '';
    if (two == '<=' || two == '>=' || two == '<>') {
      out.add(_Tok(_T.op, two));
      i += 2;
      continue;
    }
    if ('+-*/^&=<>%'.contains(ch)) {
      out.add(_Tok(_T.op, ch));
      i++;
      continue;
    }
    if (ch == '@') {
      i++; // implicit intersection marker
      continue;
    }
    throw _Unsupported();
  }
  out.add(_Tok(_T.end));
  return out;
}

/// Moves the relative references of a shared formula by ([dRow], [dCol]).
String shiftFormula(String f, int dRow, int dCol) {
  if (dRow == 0 && dCol == 0) return f;
  final b = StringBuffer();
  var i = 0;
  final re = RegExp(r'(\$?)([A-Za-z]{1,3})(\$?)(\d+)');
  while (i < f.length) {
    final ch = f[i];
    if (ch == '"' || ch == "'") {
      final end = f.indexOf(ch, i + 1);
      final stop = end < 0 ? f.length : end + 1;
      b.write(f.substring(i, stop));
      i = stop;
      continue;
    }
    final m = re.matchAsPrefix(f, i);
    final prevOk = i == 0 || !RegExp(r'[A-Za-z0-9_.]').hasMatch(f[i - 1]);
    if (m != null && prevOk) {
      final end = m.end;
      final nextOk = end >= f.length || !RegExp(r'[A-Za-z0-9_(!]').hasMatch(f[end]);
      if (nextOk) {
        var col = colNumber(m.group(2)!);
        var row = int.parse(m.group(4)!) - 1;
        if (m.group(1)!.isEmpty) col += dCol;
        if (m.group(3)!.isEmpty) row += dRow;
        b.write('${m.group(1)}${colLetters(math.max(0, col))}${m.group(3)}${math.max(0, row) + 1}');
        i = end;
        continue;
      }
    }
    b.write(ch);
    i++;
  }
  return b.toString();
}

// =====================================================================
// Parser
// =====================================================================

abstract class _Node {}

class _Lit extends _Node {
  _Lit(this.v);
  final Object? v;
}

class _RefN extends _Node {
  _RefN(this.area);
  final _Area area;
}

class _NameN extends _Node {
  _NameN(this.name);
  final String name;
}

class _Fn extends _Node {
  _Fn(this.name, this.args);
  final String name;
  final List<_Node> args;
}

class _Un extends _Node {
  _Un(this.op, this.a);
  final String op;
  final _Node a;
}

class _Bin extends _Node {
  _Bin(this.op, this.a, this.b);
  final String op;
  final _Node a, b;
}

class _Parser {
  _Parser(this.toks, this.host);
  final List<_Tok> toks;
  final FormulaHost host;
  var p = 0;

  _Tok get cur => toks[p];

  _Node parse() {
    final n = _compare();
    if (cur.t != _T.end) throw _value;
    return n;
  }

  bool _isOp(List<String> ops) => cur.t == _T.op && ops.contains(cur.s);

  _Node _compare() {
    var a = _concat();
    while (_isOp(['=', '<>', '<', '>', '<=', '>='])) {
      final op = toks[p++].s;
      a = _Bin(op, a, _concat());
    }
    return a;
  }

  _Node _concat() {
    var a = _add();
    while (_isOp(['&'])) {
      p++;
      a = _Bin('&', a, _add());
    }
    return a;
  }

  _Node _add() {
    var a = _mul();
    while (_isOp(['+', '-'])) {
      final op = toks[p++].s;
      a = _Bin(op, a, _mul());
    }
    return a;
  }

  _Node _mul() {
    var a = _pow();
    while (_isOp(['*', '/'])) {
      final op = toks[p++].s;
      a = _Bin(op, a, _pow());
    }
    return a;
  }

  _Node _pow() {
    var a = _unary();
    while (_isOp(['^'])) {
      p++;
      a = _Bin('^', a, _unary());
    }
    return a;
  }

  _Node _unary() {
    if (_isOp(['-', '+'])) {
      final op = toks[p++].s;
      return _Un(op, _unary());
    }
    var a = _primary();
    while (_isOp(['%'])) {
      p++;
      a = _Un('%', a);
    }
    return a;
  }

  _Node _primary() {
    final t = toks[p++];
    switch (t.t) {
      case _T.num:
        return _Lit(t.n);
      case _T.str:
        return _Lit(t.s);
      case _T.bool:
        return _Lit(t.s == 'TRUE');
      case _T.err:
        return _Lit(XlError(t.s));
      case _T.area:
        return _RefN(t.area!);
      case _T.name:
        return _NameN(t.s);
      case _T.lparen:
        {
          final n = _compare();
          if (cur.t != _T.rparen) throw _value;
          p++;
          return n;
        }
      case _T.func:
        return _func(t.s);
      default:
        throw _value;
    }
  }

  _Fn _func(String name) {
        if (cur.t != _T.lparen) throw _value;
        p++;
        final args = <_Node>[];
        if (cur.t == _T.rparen) {
          p++;
          return _Fn(name, args);
        }
        while (true) {
          if (cur.t == _T.comma || cur.t == _T.rparen) {
            args.add(_Lit(null)); // empty argument
          } else {
            args.add(_compare());
          }
          if (cur.t == _T.comma) {
            p++;
            continue;
          }
          if (cur.t == _T.rparen) {
            p++;
            break;
          }
          throw _value;
        }
        return _Fn(name, args);
  }
}

// =====================================================================
// Evaluation
// =====================================================================

double excelSerial(DateTime d) {
  final base = DateTime.utc(1899, 12, 30);
  final utc = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  return utc.difference(base).inSeconds / 86400.0;
}

DateTime serialDate(double s) => DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (s * 86400000).round()));

class _Eval {
  _Eval(this.host, this.now);
  final FormulaHost host;
  final DateTime now;
  int _depth = 0;

  Object? eval(_Node n) {
    if (n is _Lit) return n.v;
    if (n is _RefN) return n.area;
    if (n is _NameN) {
      final text = host.definedName(n.name);
      if (text == null) throw _name;
      if (++_depth > 20) throw _ref;
      try {
        return eval(_Parser(_tokenize(text), host).parse());
      } finally {
        _depth--;
      }
    }
    if (n is _Un) {
      final v = eval(n.a);
      return _map1(v, (x) {
        final d = _num1(x);
        return switch (n.op) { '-' => -d, '%' => d / 100, _ => d };
      });
    }
    if (n is _Bin) {
      final a = eval(n.a), b = eval(n.b);
      return _map2(a, b, (x, y) => _binary(n.op, x, y));
    }
    if (n is _Fn) return _call(n.name, n.args);
    throw _value;
  }

  // ---------------------------------------------------------- values

  int _r2(_Area a) => a.r2 < 0 ? host.lastRow(a.sheet) : a.r2;
  int _c2(_Area a) => a.c2 < 0 ? host.lastCol(a.sheet) : a.c2;

  List<List<Object?>> _matrix(_Area a) {
    final r2 = _r2(a), c2 = _c2(a);
    return [
      for (var r = a.r1; r <= r2; r++) [for (var c = a.c1; c <= c2; c++) host.cellValue(a.sheet, r, c)],
    ];
  }

  /// Ranges become arrays (single cells become their value).
  Object? deref(Object? v) {
    if (v is _Area) {
      if (v.r1 == _r2(v) && v.c1 == _c2(v)) return host.cellValue(v.sheet, v.r1, v.c1);
      return _Arr(_matrix(v));
    }
    return v;
  }

  /// One value (the first, for a range).
  Object? scalar(Object? v) {
    v = deref(v);
    if (v is _Arr) return v.rows == 0 || v.cols == 0 ? null : v.v[0][0];
    return v;
  }

  Object? _map1(Object? v, Object? Function(Object?) f) {
    v = deref(v);
    if (v is _Arr) return _Arr([for (final row in v.v) [for (final x in row) _safe(() => f(x))]]);
    return f(v);
  }

  Object? _map2(Object? a, Object? b, Object? Function(Object?, Object?) f) {
    a = deref(a);
    b = deref(b);
    if (a is! _Arr && b is! _Arr) return f(a, b);
    final aa = a is _Arr ? a : null, bb = b is _Arr ? b : null;
    final rows = math.max(aa?.rows ?? 1, bb?.rows ?? 1);
    final cols = math.max(aa?.cols ?? 1, bb?.cols ?? 1);
    Object? at(Object? v, _Arr? arr, int r, int c) {
      if (arr == null) return v;
      final rr = arr.rows == 1 ? 0 : r, cc = arr.cols == 1 ? 0 : c;
      if (rr >= arr.rows || cc >= arr.cols) return _na;
      return arr.v[rr][cc];
    }

    return _Arr([
      for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) _safe(() => f(at(a, aa, r, c), at(b, bb, r, c)))],
    ]);
  }

  Object? _safe(Object? Function() f) {
    try {
      return f();
    } on XlError catch (e) {
      return e;
    }
  }

  double _num1(Object? v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    if (v is XlError) throw v;
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return 0;
      final d = double.tryParse(t.replaceAll(',', ''));
      if (d != null) return d;
      if (t.endsWith('%')) {
        final p = double.tryParse(t.substring(0, t.length - 1));
        if (p != null) return p / 100;
      }
      throw _value;
    }
    throw _value;
  }

  String _str(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    if (v is XlError) throw v;
    if (v is num) return generalNumber(v.toDouble());
    return v.toString();
  }

  bool _bool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is XlError) throw v;
    if (v is String) {
      final u = v.toUpperCase();
      if (u == 'TRUE') return true;
      if (u == 'FALSE') return false;
      throw _value;
    }
    throw _value;
  }

  /// Excel ordering: numbers < text < booleans; text ignores case.
  int _cmp(Object? a, Object? b) {
    if (a is XlError) throw a;
    if (b is XlError) throw b;
    a ??= b is String ? '' : (b is bool ? false : 0.0);
    b ??= a is String ? '' : (a is bool ? false : 0.0);
    int rank(Object v) => v is num ? 0 : (v is String ? 1 : 2);
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.toLowerCase().compareTo(b.toLowerCase());
    if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
    return 0;
  }

  Object? _binary(String op, Object? a, Object? b) {
    switch (op) {
      case '+':
        return _num1(a) + _num1(b);
      case '-':
        return _num1(a) - _num1(b);
      case '*':
        return _num1(a) * _num1(b);
      case '/':
        final d = _num1(b);
        if (d == 0) throw _div0;
        return _num1(a) / d;
      case '^':
        return math.pow(_num1(a), _num1(b)).toDouble();
      case '&':
        return _str(a) + _str(b);
      case '=':
        return _cmp(a, b) == 0;
      case '<>':
        return _cmp(a, b) != 0;
      case '<':
        return _cmp(a, b) < 0;
      case '>':
        return _cmp(a, b) > 0;
      case '<=':
        return _cmp(a, b) <= 0;
      case '>=':
        return _cmp(a, b) >= 0;
    }
    throw _value;
  }

  // ---------------------------------------------------------- helpers for functions

  /// Every value from the arguments, with where it came from (a range or typed directly).
  Iterable<(Object?, bool)> _values(List<_Node> args) sync* {
    for (final a in args) {
      final v = eval(a);
      if (v is _Area) {
        for (final row in _matrix(v)) {
          for (final x in row) {
            yield (x, true);
          }
        }
      } else if (v is _Arr) {
        for (final row in v.v) {
          for (final x in row) {
            yield (x, true);
          }
        }
      } else {
        yield (v, false);
      }
    }
  }

  /// Numbers for SUM/AVERAGE/MIN/MAX: in ranges only real numbers count.
  List<double> _numbers(List<_Node> args) {
    final out = <double>[];
    for (final (v, fromRange) in _values(args)) {
      if (v is XlError) throw v;
      if (fromRange) {
        if (v is num) out.add(v.toDouble());
      } else if (v != null) {
        out.add(_num1(v));
      }
    }
    return out;
  }

  List<List<Object?>> _grid(_Node n) {
    final v = eval(n);
    if (v is _Area) return _matrix(v);
    if (v is _Arr) return v.v;
    return [
      [v]
    ];
  }

  List<Object?> _flat(_Node n) => [for (final row in _grid(n)) ...row];

  /// A COUNTIF-style test like ">5", "<>Resolved", "Clash*" or 3.
  bool Function(Object?) _criterion(Object? crit) {
    crit = scalar(crit);
    if (crit is num || crit is bool) return (v) => v != null && v is! XlError && _safeCmp(v, crit) == 0;
    var s = _str(crit);
    var op = '=';
    for (final o in ['<=', '>=', '<>', '<', '>', '=']) {
      if (s.startsWith(o)) {
        op = o;
        s = s.substring(o.length);
        break;
      }
    }
    final n = double.tryParse(s.trim());
    final upper = s.toUpperCase();
    final Object? target = n ?? (upper == 'TRUE' ? true : (upper == 'FALSE' ? false : s));
    final wild = target is String && (s.contains('*') || s.contains('?'));
    final re = wild ? _wildcard(s) : null;
    return (v) => _test(v, op, target, re);
  }

  RegExp _wildcard(String s) {
    {
      final b = StringBuffer('^');
      for (var i = 0; i < s.length; i++) {
        final ch = s[i];
        if (ch == '~' && i + 1 < s.length) {
          b.write(RegExp.escape(s[++i]));
        } else if (ch == '*') {
          b.write('.*');
        } else if (ch == '?') {
          b.write('.');
        } else {
          b.write(RegExp.escape(ch));
        }
      }
      b.write(r'$');
      return RegExp(b.toString(), caseSensitive: false, dotAll: true);
    }
  }

  bool _test(Object? v, String op, Object? target, RegExp? re) {
    {
      if (v is XlError) return false;
      if (op == '=' || op == '<>') {
        bool eq;
        if (target is String && target.isEmpty) {
          eq = v == null || (v is String && v.isEmpty);
        } else if (re != null) {
          eq = v is String && re.hasMatch(v);
        } else if (target is num) {
          eq = (v is num && v == target) || (v is String && double.tryParse(v.trim()) == target);
        } else {
          eq = v != null && _safeCmp(v, target) == 0;
        }
        return op == '=' ? eq : !eq;
      }
      if (v == null) return false;
      if (target is num && v is! num) return false;
      if (target is String && v is! String) return false;
      final c = _safeCmp(v, target);
      return switch (op) { '<' => c < 0, '>' => c > 0, '<=' => c <= 0, _ => c >= 0 };
    }
  }

  int _safeCmp(Object? a, Object? b) {
    try {
      return _cmp(a, b);
    } on XlError {
      return 2;
    }
  }

  /// Rows (flattened positions) that pass every (range, criterion) pair.
  List<int> _matches(List<_Node> args, int start) {
    Set<int>? keep;
    for (var i = start; i + 1 < args.length; i += 2) {
      final cells = _flat(args[i]);
      final test = _criterion(eval(args[i + 1]));
      final ok = <int>{};
      final before = keep;
      for (var k = 0; k < cells.length; k++) {
        if ((before == null || before.contains(k)) && test(cells[k])) ok.add(k);
      }
      keep = ok;
    }
    return (keep ?? <int>{}).toList()..sort();
  }

  Object? _arg(List<_Node> args, int i, [Object? fallback]) => i < args.length ? scalar(eval(args[i])) : fallback;

  // ---------------------------------------------------------- functions

  Object? _call(String name, List<_Node> a) {
    switch (name) {
      case 'SUM':
        return _numbers(a).fold<double>(0, (s, x) => s + x);
      case 'AVERAGE':
        {
          final n = _numbers(a);
          if (n.isEmpty) throw _div0;
          return n.reduce((x, y) => x + y) / n.length;
        }
      case 'MIN':
        {
          final n = _numbers(a);
          return n.isEmpty ? 0.0 : n.reduce(math.min);
        }
      case 'MAX':
        {
          final n = _numbers(a);
          return n.isEmpty ? 0.0 : n.reduce(math.max);
        }
      case 'COUNT':
        return _values(a).where((e) => e.$1 is num || (!e.$2 && e.$1 is String && double.tryParse(e.$1 as String) != null)).length.toDouble();
      case 'COUNTA':
        return _values(a).where((e) => e.$1 != null && !(e.$2 && e.$1 == '')).length.toDouble();
      case 'COUNTBLANK':
        return _values(a).where((e) => e.$1 == null || e.$1 == '').length.toDouble();
      case 'COUNTIF':
      case 'COUNTIFS':
        return _matches(a, 0).length.toDouble();
      case 'SUMIF':
        {
          final keep = _matches(a.sublist(0, 2), 0);
          final vals = _flat(a.length > 2 ? a[2] : a[0]);
          return keep.fold<double>(0, (s, k) => s + (k < vals.length && vals[k] is num ? (vals[k] as num).toDouble() : 0));
        }
      case 'SUMIFS':
      case 'AVERAGEIFS':
      case 'MINIFS':
      case 'MAXIFS':
        {
          final vals = _flat(a[0]);
          final keep = _matches(a, 1);
          final nums = [for (final k in keep) if (k < vals.length && vals[k] is num) (vals[k] as num).toDouble()];
          if (name == 'SUMIFS') return nums.fold<double>(0, (s, x) => s + x);
          if (name == 'AVERAGEIFS') {
            if (nums.isEmpty) throw _div0;
            return nums.reduce((x, y) => x + y) / nums.length;
          }
          if (nums.isEmpty) return 0.0;
          return name == 'MINIFS' ? nums.reduce(math.min) : nums.reduce(math.max);
        }
      case 'AVERAGEIF':
        {
          final keep = _matches(a.sublist(0, 2), 0);
          final vals = _flat(a.length > 2 ? a[2] : a[0]);
          final nums = [for (final k in keep) if (k < vals.length && vals[k] is num) (vals[k] as num).toDouble()];
          if (nums.isEmpty) throw _div0;
          return nums.reduce((x, y) => x + y) / nums.length;
        }
      case 'SUMPRODUCT':
        {
          final grids = [for (final n in a) _flatValues(eval(n))];
          if (grids.isEmpty) return 0.0;
          final len = grids.first.length;
          var total = 0.0;
          for (var k = 0; k < len; k++) {
            var prod = 1.0;
            for (final g in grids) {
              final v = k < g.length ? g[k] : null;
              if (v is XlError) throw v;
              prod *= v is num ? v.toDouble() : (v is bool ? (v ? 1 : 0) : 0);
            }
            total += prod;
          }
          return total;
        }
      case 'IF':
        {
          final c = _bool(_arg(a, 0));
          if (c) return a.length > 1 ? _blankZero(eval(a[1])) : true;
          return a.length > 2 ? _blankZero(eval(a[2])) : false;
        }
      case 'IFS':
        for (var i = 0; i + 1 < a.length; i += 2) {
          if (_bool(_arg(a, i))) return _blankZero(eval(a[i + 1]));
        }
        throw _na;
      case 'IFERROR':
      case 'IFNA':
        try {
          final v = scalar(eval(a[0]));
          if (v is XlError && (name == 'IFERROR' || v == _na)) return _blankZero(eval(a[1]));
          return v;
        } on XlError catch (e) {
          if (name == 'IFNA' && e != _na) rethrow;
          return _blankZero(eval(a[1]));
        }
      case 'ISERROR':
        try {
          return scalar(eval(a[0])) is XlError;
        } on XlError {
          return true;
        }
      case 'ISNA':
        try {
          return scalar(eval(a[0])) == _na;
        } on XlError catch (e) {
          return e == _na;
        }
      case 'ISBLANK':
        return scalar(eval(a[0])) == null;
      case 'ISNUMBER':
        return scalar(eval(a[0])) is num;
      case 'ISTEXT':
        return scalar(eval(a[0])) is String;
      case 'AND':
        return _values(a).where((e) => e.$1 != null && !(e.$2 && e.$1 is String)).every((e) => _bool(e.$1));
      case 'OR':
        return _values(a).where((e) => e.$1 != null && !(e.$2 && e.$1 is String)).any((e) => _bool(e.$1));
      case 'NOT':
        return !_bool(_arg(a, 0));
      case 'TRUE':
        return true;
      case 'FALSE':
        return false;
      case 'NA':
        throw _na;
      case 'ROUND':
      case 'ROUNDUP':
      case 'ROUNDDOWN':
        {
          final x = _num1(_arg(a, 0));
          final d = _num1(_arg(a, 1, 0.0)).toInt();
          final f = math.pow(10, d).toDouble();
          final y = x * f;
          final r = name == 'ROUND'
              ? (y.abs() + 0.5 + 1e-9).floorToDouble() * y.sign
              : name == 'ROUNDUP'
                  ? (y.abs() - 1e-9).ceilToDouble() * y.sign
                  : (y.abs() + 1e-9).floorToDouble() * y.sign;
          return r / f;
        }
      case 'INT':
        return _num1(_arg(a, 0)).floorToDouble();
      case 'ABS':
        return _num1(_arg(a, 0)).abs();
      case 'MOD':
        {
          final x = _num1(_arg(a, 0)), y = _num1(_arg(a, 1));
          if (y == 0) throw _div0;
          return x - y * (x / y).floorToDouble();
        }
      case 'TODAY':
        return excelSerial(DateTime(now.year, now.month, now.day)).floorToDouble();
      case 'NOW':
        return excelSerial(now);
      case 'DATE':
        return excelSerial(DateTime(_num1(_arg(a, 0)).toInt(), _num1(_arg(a, 1)).toInt(), _num1(_arg(a, 2)).toInt())).floorToDouble();
      case 'YEAR':
        return serialDate(_num1(_arg(a, 0))).year.toDouble();
      case 'MONTH':
        return serialDate(_num1(_arg(a, 0))).month.toDouble();
      case 'DAY':
        return serialDate(_num1(_arg(a, 0))).day.toDouble();
      case 'WEEKDAY':
        return (serialDate(_num1(_arg(a, 0))).weekday % 7 + 1).toDouble();
      case 'DAYS':
        return (_num1(_arg(a, 0)).floorToDouble() - _num1(_arg(a, 1)).floorToDouble());
      case 'DATEDIF':
        {
          final s = serialDate(_num1(_arg(a, 0))), e = serialDate(_num1(_arg(a, 1)));
          final unit = _str(_arg(a, 2, 'D')).toUpperCase();
          if (e.isBefore(s)) throw _num;
          if (unit == 'D') return e.difference(s).inDays.toDouble();
          var months = (e.year - s.year) * 12 + e.month - s.month;
          if (e.day < s.day) months--;
          if (unit == 'M') return months.toDouble();
          if (unit == 'Y') return (months ~/ 12).toDouble();
          throw _num;
        }
      case 'TEXT':
        return formatValue(_arg(a, 0), _str(_arg(a, 1, 'General')));
      case 'VALUE':
        return _num1(_arg(a, 0));
      case 'N':
        {
          final v = _arg(a, 0);
          return v is num ? v.toDouble() : (v is bool ? (v ? 1.0 : 0.0) : 0.0);
        }
      case 'CONCAT':
      case 'CONCATENATE':
        return _values(a).map((e) => _str(e.$1)).join();
      case 'TEXTJOIN':
        {
          final sep = _str(_arg(a, 0));
          final skip = _bool(_arg(a, 1, true));
          final parts = _values(a.sublist(2)).map((e) => _str(e.$1)).where((s) => !skip || s.isNotEmpty);
          return parts.join(sep);
        }
      case 'LEN':
        return _str(_arg(a, 0)).length.toDouble();
      case 'LEFT':
        {
          final s = _str(_arg(a, 0));
          final n = _num1(_arg(a, 1, 1.0)).toInt();
          return s.substring(0, n.clamp(0, s.length));
        }
      case 'RIGHT':
        {
          final s = _str(_arg(a, 0));
          final n = _num1(_arg(a, 1, 1.0)).toInt();
          return s.substring(s.length - n.clamp(0, s.length));
        }
      case 'MID':
        {
          final s = _str(_arg(a, 0));
          final start = _num1(_arg(a, 1)).toInt() - 1;
          final n = _num1(_arg(a, 2)).toInt();
          if (start < 0 || n < 0) throw _value;
          if (start >= s.length) return '';
          return s.substring(start, math.min(s.length, start + n));
        }
      case 'UPPER':
        return _str(_arg(a, 0)).toUpperCase();
      case 'LOWER':
        return _str(_arg(a, 0)).toLowerCase();
      case 'PROPER':
        return _str(_arg(a, 0)).toLowerCase().replaceAllMapped(RegExp(r"(^|[^a-z'])([a-z])"), (m) => '${m[1]}${m[2]!.toUpperCase()}');
      case 'TRIM':
        return _str(_arg(a, 0)).trim().replaceAll(RegExp(r' +'), ' ');
      case 'SUBSTITUTE':
        return _str(_arg(a, 0)).replaceAll(_str(_arg(a, 1)), _str(_arg(a, 2)));
      case 'REPT':
        return _str(_arg(a, 0)) * _num1(_arg(a, 1)).toInt().clamp(0, 1000);
      case 'HYPERLINK':
        return a.length > 1 ? _arg(a, 1) : _arg(a, 0);
      case 'ROWS':
        return _grid(a[0]).length.toDouble();
      case 'COLUMNS':
        {
          final g = _grid(a[0]);
          return (g.isEmpty ? 0 : g.first.length).toDouble();
        }
      case 'INDEX':
        {
          final g = _grid(a[0]);
          var r = _num1(_arg(a, 1, 1.0)).toInt();
          var c = _num1(_arg(a, 2, 1.0)).toInt();
          if (g.length == 1 && a.length == 2) {
            c = r;
            r = 1;
          }
          if (r < 1 || c < 1 || r > g.length || c > g[r - 1].length) throw _ref;
          return g[r - 1][c - 1];
        }
      case 'MATCH':
        {
          final x = _arg(a, 0);
          final list = _flat(a[1]);
          final type = _num1(_arg(a, 2, 1.0)).toInt();
          if (type == 0) {
            final test = _criterion(x is String ? x : x);
            for (var k = 0; k < list.length; k++) {
              if (test(list[k])) return (k + 1).toDouble();
            }
            throw _na;
          }
          var best = -1;
          for (var k = 0; k < list.length; k++) {
            if (list[k] == null) continue;
            final c = _safeCmp(list[k], x);
            if (type > 0 ? c <= 0 : c >= 0) best = k;
          }
          if (best < 0) throw _na;
          return (best + 1).toDouble();
        }
      case 'VLOOKUP':
      case 'HLOOKUP':
        {
          final x = _arg(a, 0);
          var g = _grid(a[1]);
          if (name == 'HLOOKUP') {
            g = [
              for (var c = 0; c < (g.isEmpty ? 0 : g.first.length); c++) [for (final row in g) row[c]]
            ];
          }
          final col = _num1(_arg(a, 2)).toInt();
          final exact = a.length > 3 && !_bool(_arg(a, 3, true));
          if (col < 1 || g.isEmpty || col > g.first.length) throw _ref;
          if (exact) {
            final test = _criterion(x);
            for (final row in g) {
              if (test(row[0])) return row[col - 1];
            }
            throw _na;
          }
          List<Object?>? found;
          for (final row in g) {
            if (row[0] != null && _safeCmp(row[0], x) <= 0) found = row;
          }
          if (found == null) throw _na;
          return found[col - 1];
        }
      case 'XLOOKUP':
        {
          final x = _arg(a, 0);
          final keys = _flat(a[1]);
          final vals = _flat(a[2]);
          final test = _criterion(x);
          for (var k = 0; k < keys.length; k++) {
            if (test(keys[k])) return k < vals.length ? vals[k] : _na;
          }
          if (a.length > 3) return _arg(a, 3);
          throw _na;
        }
      case 'UNIQUE':
      case 'FILTER':
      case 'SORT':
        throw _Unsupported();
    }
    throw _Unsupported();
  }

  List<Object?> _flatValues(Object? v) {
    v = deref(v);
    if (v is _Arr) return [for (final row in v.v) ...row];
    return [v];
  }

  /// A blank cell returned by IF/IFERROR shows as 0 in Excel.
  Object? _blankZero(Object? v) {
    final s = deref(v);
    if (s is _Arr) return s;
    return s ?? 0.0;
  }
}
