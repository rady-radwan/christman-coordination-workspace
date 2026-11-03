import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Longest side of a saved photo, in pixels. Keeps uploads small but readable.
const maxPhotoSide = 2000;

enum MarkTool {
  select('Select', Icons.near_me_outlined),
  arrow('Arrow', Icons.north_east),
  box('Box', Icons.crop_square),
  circle('Circle', Icons.circle_outlined),
  cloud('Cloud', Icons.cloud_outlined),
  text('Text', Icons.title),
  pen('Pen', Icons.edit_outlined);

  const MarkTool(this.label, this.icon);
  final String label;
  final IconData icon;

  bool get isShape => this == MarkTool.box || this == MarkTool.circle || this == MarkTool.cloud;
}

/// How a text label is drawn.
enum TextLook {
  filled('Label'),
  outline('Outlined'),
  plain('Plain');

  const TextLook(this.label);
  final String label;
}

const markColors = <(String, Color)>[
  ('Red', Color(0xFFE4252B)),
  ('Yellow', Color(0xFFF5C400)),
  ('Blue', Color(0xFF2F8BFF)),
  ('Green', Color(0xFF2DB55D)),
  ('Orange', Color(0xFFFF7A1A)),
  ('Black', Color(0xFF000000)),
  ('White', Color(0xFFFFFFFF)),
];

/// One markup, stored in image pixel coordinates.
/// [width] scales the line thickness and [size] scales text; both default to 1.
class Mark {
  Mark({
    required this.tool,
    required this.color,
    required this.points,
    this.text,
    this.width = 1,
    this.size = 1,
    this.fill = false,
    this.look = TextLook.filled,
  });

  final MarkTool tool;
  Color color;
  List<Offset> points;
  String? text;
  double width;
  double size;
  bool fill;
  TextLook look;

  Mark copy() => Mark(
        tool: tool,
        color: color,
        points: List.of(points),
        text: text,
        width: width,
        size: size,
        fill: fill,
        look: look,
      );
}

// ------------------------------------------------------------------ geometry

double baseStroke(double imageWidth) => math.max(3.0, imageWidth / 250);
double baseFont(double imageWidth) => math.max(16.0, imageWidth / 28);

TextPainter _textPainter(Mark m, double imageWidth) {
  final lightBg = m.color.computeLuminance() > 0.5;
  final fg = switch (m.look) {
    TextLook.filled => lightBg ? const Color(0xFF1A1A1A) : Colors.white,
    _ => m.color,
  };
  return TextPainter(
    text: TextSpan(
      text: m.text ?? '',
      style: TextStyle(color: fg, fontSize: baseFont(imageWidth) * m.size, fontWeight: FontWeight.w700, fontFamily: 'Barlow'),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: imageWidth * 0.9);
}

Rect _labelRect(Mark m, double imageWidth) {
  final tp = _textPainter(m, imageWidth);
  final pad = baseFont(imageWidth) * m.size * 0.35;
  final at = m.points.first;
  return Rect.fromLTWH(at.dx, at.dy, tp.width + pad * 2, tp.height + pad * 1.4);
}

/// Bounding box of a mark in image coordinates.
Rect markBounds(Mark m, double imageWidth) {
  switch (m.tool) {
    case MarkTool.text:
      return _labelRect(m, imageWidth);
    case MarkTool.pen:
      var r = Rect.fromPoints(m.points.first, m.points.first);
      for (final p in m.points) {
        r = r.expandToInclude(Rect.fromPoints(p, p));
      }
      return r;
    default:
      return Rect.fromPoints(m.points[0], m.points[1]);
  }
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// [interior]: whether clicking inside an unfilled box/circle/cloud counts, or only near its outline.
bool hitsMark(Mark m, Offset p, double tolerance, double imageWidth, {bool interior = true}) {
  final reach = tolerance + baseStroke(imageWidth) * m.width;
  if (m.tool.isShape && !interior && !m.fill) {
    final r = markBounds(m, imageWidth);
    return r.inflate(reach).contains(p) && !r.deflate(reach).contains(p);
  }
  switch (m.tool) {
    case MarkTool.arrow:
      return _distToSegment(p, m.points[0], m.points[1]) <= reach;
    case MarkTool.pen:
      for (var i = 1; i < m.points.length; i++) {
        if (_distToSegment(p, m.points[i - 1], m.points[i]) <= reach) return true;
      }
      return false;
    default:
      return markBounds(m, imageWidth).inflate(reach).contains(p);
  }
}

/// Drag handles of a selected mark, in image coordinates.
List<Offset> markHandles(Mark m, double imageWidth) {
  switch (m.tool) {
    case MarkTool.arrow:
      return [m.points[0], m.points[1]];
    case MarkTool.text:
      return [_labelRect(m, imageWidth).bottomRight];
    case MarkTool.pen:
    case MarkTool.select:
      return const [];
    default:
      final r = Rect.fromPoints(m.points[0], m.points[1]);
      return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }
}

// ------------------------------------------------------------------ public entry

/// Opens [bytes] in the editor. Returns the marked-up photo as JPEG, or null if cancelled.
Future<Uint8List?> openMarkupEditor(BuildContext context, Uint8List bytes, {String title = 'Mark up photo'}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => MarkupEditorScreen(bytes: bytes, title: title)),
  );
}

enum _Drag { none, draw, move, resize }

class MarkupEditorScreen extends StatefulWidget {
  const MarkupEditorScreen({super.key, required this.bytes, this.title = 'Mark up photo'});
  final Uint8List bytes;
  final String title;

  @override
  State<MarkupEditorScreen> createState() => _MarkupEditorScreenState();
}

class _MarkupEditorScreenState extends State<MarkupEditorScreen> {
  static const _bg = Color(0xFF111417);
  static const _panelColor = Color(0xFF1B2024);
  static const _border = Color(0xFF3B4248);
  static const _copper = Color(0xFFB98052);
  static const _copperLight = Color(0xFFD19A6C);
  static const _muted = Color(0xFFA9B0B6);

  ui.Image? _image;
  String? _error;
  final List<Mark> _marks = [];
  final List<List<Mark>> _undo = [];
  final List<List<Mark>> _redo = [];
  Mark? _drawing;
  Mark? _selected;
  double _scale = 1;
  bool _saving = false;
  final _focus = FocusNode();

  // Settings for new markups.
  MarkTool _tool = MarkTool.arrow;
  Color _color = markColors.first.$2;
  double _width = 1;
  double _textSize = 1;
  bool _fill = false;
  TextLook _look = TextLook.filled;

  // Current drag.
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  List<Offset> _origPoints = const [];
  Offset _resizeAnchor = Offset.zero;
  int _handle = -1;
  Rect _origLabel = Rect.zero;
  double _origSize = 1;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double get _imageWidth => _image?.width.toDouble() ?? 1000;

  Future<void> _decode() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final longest = math.max(desc.width, desc.height);
      final f = longest > maxPhotoSide ? maxPhotoSide / longest : 1.0;
      final codec = await desc.instantiateCodec(
        targetWidth: (desc.width * f).round(),
        targetHeight: (desc.height * f).round(),
      );
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = 'This file could not be opened as a photo.');
    }
  }

  // ------------------------------------------------------------------ history

  /// Saves the current state so the next change can be undone.
  void _commit() {
    _undo.add(_marks.map((m) => m.copy()).toList());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoOne() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_marks.map((m) => m.copy()).toList());
      _marks
        ..clear()
        ..addAll(_undo.removeLast());
      _selected = null;
    });
  }

  void _redoOne() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_marks.map((m) => m.copy()).toList());
      _marks
        ..clear()
        ..addAll(_redo.removeLast());
      _selected = null;
    });
  }

  // ------------------------------------------------------------------ hit testing

  Offset _toImage(Offset local) => local / _scale;
  double get _tolerance => 10 / _scale;
  double get _handleRadius => 16 / _scale;

  Mark? _topMarkAt(Offset p) {
    for (final m in _marks.reversed) {
      if (hitsMark(m, p, _tolerance, _imageWidth)) return m;
    }
    return null;
  }

  int _handleAt(Mark m, Offset p) {
    final hs = markHandles(m, _imageWidth);
    for (var i = 0; i < hs.length; i++) {
      if ((hs[i] - p).distance <= _handleRadius) return i;
    }
    return -1;
  }

  // ------------------------------------------------------------------ gestures

  void _panStart(Offset local) {
    final p = _toImage(local);
    _dragStart = p;
    final sel = _selected;

    // 1. Grab a handle of the selected markup to resize it.
    if (sel != null) {
      final h = _handleAt(sel, p);
      if (h >= 0) {
        _commit();
        _drag = _Drag.resize;
        _handle = h;
        _origPoints = List.of(sel.points);
        if (sel.tool.isShape) {
          final r = Rect.fromPoints(sel.points[0], sel.points[1]);
          final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
          _resizeAnchor = corners[(h + 2) % 4];
        } else if (sel.tool == MarkTool.text) {
          _origLabel = _labelRect(sel, _imageWidth);
          _origSize = sel.size;
        }
        return;
      }
    }

    // 2. Grab a markup to move it (the selected one first, then any in Select mode).
    final hit = (sel != null && hitsMark(sel, p, _tolerance, _imageWidth, interior: _tool == MarkTool.select))
        ? sel
        : (_tool == MarkTool.select ? _topMarkAt(p) : null);
    if (hit != null) {
      _commit();
      setState(() => _selected = hit);
      _drag = _Drag.move;
      _origPoints = List.of(hit.points);
      return;
    }

    // 3. Draw a new markup.
    if (_tool == MarkTool.select || _tool == MarkTool.text) {
      setState(() => _selected = null);
      _drag = _Drag.none;
      return;
    }
    setState(() {
      _selected = null;
      _drawing = Mark(tool: _tool, color: _color, points: [p, p], width: _width, fill: _fill);
    });
    _drag = _Drag.draw;
  }

  void _panUpdate(Offset local) {
    final p = _toImage(local);
    final sel = _selected;
    switch (_drag) {
      case _Drag.draw:
        final d = _drawing;
        if (d == null) return;
        setState(() {
          if (d.tool == MarkTool.pen) {
            d.points.add(p);
          } else {
            d.points[1] = p;
          }
        });
      case _Drag.move:
        if (sel == null) return;
        final delta = p - _dragStart;
        setState(() => sel.points = [for (final o in _origPoints) o + delta]);
      case _Drag.resize:
        if (sel == null) return;
        setState(() {
          if (sel.tool.isShape) {
            final r = Rect.fromPoints(_resizeAnchor, p);
            sel.points = [r.topLeft, r.bottomRight];
          } else if (sel.tool == MarkTool.arrow) {
            sel.points = List.of(_origPoints)..[_handle] = p;
          } else if (sel.tool == MarkTool.text) {
            final newWidth = math.max(10.0, p.dx - _origLabel.left);
            sel.size = (_origSize * newWidth / _origLabel.width).clamp(0.3, 6.0);
          }
        });
      case _Drag.none:
        break;
    }
  }

  void _panEnd() {
    if (_drag == _Drag.draw) {
      final d = _drawing;
      if (d != null) {
        final big = d.tool == MarkTool.pen ? d.points.length > 2 : (d.points[0] - d.points[1]).distance > 6 / _scale;
        setState(() {
          if (big) {
            _commit();
            _marks.add(d);
            _selected = d; // ready to move or resize right away
          }
          _drawing = null;
        });
      }
    }
    _drag = _Drag.none;
  }

  Future<void> _tap(Offset local) async {
    final p = _toImage(local);
    final hit = _topMarkAt(p);
    if (hit != null) {
      setState(() => _selected = hit);
      return;
    }
    if (_tool == MarkTool.text) {
      final text = await _askText();
      if (text == null || text.trim().isEmpty) return;
      setState(() {
        _commit();
        final m = Mark(tool: MarkTool.text, color: _color, points: [p], text: text.trim(), size: _textSize, look: _look);
        _marks.add(m);
        _selected = m;
      });
      return;
    }
    setState(() => _selected = null);
  }

  Future<String?> _askText({String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial.isEmpty ? 'Add text' : 'Edit text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'e.g. LEAK HERE'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(initial.isEmpty ? 'Add' : 'Save')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ actions on the selection

  void _changeSelected(void Function(Mark m) change) {
    final m = _selected;
    if (m == null) return;
    setState(() {
      _commit();
      change(m);
    });
  }

  void _deleteSelected() {
    final m = _selected;
    if (m == null) return;
    setState(() {
      _commit();
      _marks.remove(m);
      _selected = null;
    });
  }

  void _duplicateSelected() {
    final m = _selected;
    if (m == null) return;
    setState(() {
      _commit();
      final shift = Offset(24 / _scale, 24 / _scale);
      final c = m.copy()..points = [for (final p in m.points) p + shift];
      _marks.add(c);
      _selected = c;
    });
  }

  Future<void> _editSelectedText() async {
    final m = _selected;
    if (m == null || m.tool != MarkTool.text) return;
    final t = await _askText(initial: m.text ?? '');
    if (t == null || t.trim().isEmpty) return;
    _changeSelected((m) => m.text = t.trim());
  }

  void _bringToFront() {
    final m = _selected;
    if (m == null) return;
    setState(() {
      _commit();
      _marks
        ..remove(m)
        ..add(m);
    });
  }

  // ------------------------------------------------------------------ save

  Future<void> _done() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _saving = true;
      _selected = null;
    });
    try {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.high);
      paintMarks(canvas, _marks, image.width.toDouble());
      final out = await rec.endRecording().toImage(image.width, image.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      final jpg = await compute(encodeJpgJob, EncodeJob(image.width, image.height, data!.buffer.asUint8List()));
      if (mounted) Navigator.pop(context, jpg);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the photo. Try again.')));
      }
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _selected = null),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoOne,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoOne,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redoOne,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): _duplicateSelected,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Column(children: [
              _topBar(),
              Expanded(child: _canvas()),
              _panel(sel),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        child: Row(children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(64, 44)),
            child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'BarlowCondensed', fontWeight: FontWeight.w700, fontSize: 19, color: Colors.white),
            ),
          ),
          FilledButton(
            onPressed: _image == null || _saving ? null : _done,
            style: FilledButton.styleFrom(
              backgroundColor: _copper,
              foregroundColor: const Color(0xFF141414),
              minimumSize: const Size(80, 40),
              shape: const StadiumBorder(),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Done'),
          ),
        ]),
      );

  Widget _canvas() => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white))
            : _image == null
                ? const CircularProgressIndicator()
                : LayoutBuilder(builder: (context, box) {
                    final im = _image!;
                    _scale = math.min(box.maxWidth / im.width, box.maxHeight / im.height);
                    final w = im.width * _scale, h = im.height * _scale;
                    return SizedBox(
                      width: w,
                      height: h,
                      child: MouseRegion(
                        cursor: _tool == MarkTool.select
                            ? SystemMouseCursors.move
                            : _tool == MarkTool.text
                                ? SystemMouseCursors.text
                                : SystemMouseCursors.precise,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => _panStart(d.localPosition),
                          onPanUpdate: (d) => _panUpdate(d.localPosition),
                          onPanEnd: (_) => _panEnd(),
                          onTapUp: (d) => _tap(d.localPosition),
                          child: CustomPaint(
                            size: Size(w, h),
                            painter: _EditorPainter(
                              image: im,
                              marks: [..._marks, if (_drawing != null) _drawing!],
                              selected: _selected,
                              scale: _scale,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
      );

  Widget _panel(Mark? sel) {
    // What the size controls apply to: the selected markup, or new ones.
    final target = sel?.tool ?? _tool;
    final isText = target == MarkTool.text;
    final isShape = target.isShape;
    final showLine = !isText && target != MarkTool.select;
    final currentColor = sel?.color ?? _color;

    final hint = sel != null
        ? 'Selected ${sel.tool.label.toLowerCase()}: drag to move, drag the white dots to resize. Delete key removes it.'
        : _tool == MarkTool.select
            ? 'Tap a markup to select it.'
            : _tool == MarkTool.text
                ? 'Tap the photo where the text should go.'
                : 'Drag on the photo to draw. Tap any markup to select it.';

    return Container(
      color: _panelColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final t in MarkTool.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _ToolButton(
                  tool: t,
                  selected: t == _tool,
                  onTap: () => setState(() {
                    _tool = t;
                    if (t != MarkTool.select) _selected = null;
                  }),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(hint, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final (name, color) in markColors)
            Semantics(
              button: true,
              selected: color == currentColor,
              label: name,
              child: Tooltip(
                message: name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    if (sel != null) {
                      _changeSelected((m) => m.color = color);
                    } else {
                      setState(() => _color = color);
                    }
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: color == currentColor ? _copperLight : _border, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.undo, label: 'Undo (Ctrl+Z)', onTap: _undo.isEmpty ? null : _undoOne),
          _RoundIcon(icon: Icons.redo, label: 'Redo (Ctrl+Y)', onTap: _redo.isEmpty ? null : _redoOne),
        ]),
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
          if (showLine)
            _SliderRow(
              label: 'Line',
              value: sel?.width ?? _width,
              min: 0.4,
              max: 4,
              onStart: sel != null ? _commit : null,
              onChanged: (v) => setState(() {
                if (sel != null) {
                  sel.width = v;
                } else {
                  _width = v;
                }
              }),
            ),
          if (isText)
            _SliderRow(
              label: 'Text size',
              value: sel?.size ?? _textSize,
              min: 0.4,
              max: 4,
              onStart: sel != null ? _commit : null,
              onChanged: (v) => setState(() {
                if (sel != null) {
                  sel.size = v;
                } else {
                  _textSize = v;
                }
              }),
            ),
          if (isShape)
            _Chip(
              label: 'Fill',
              icon: Icons.format_color_fill,
              on: sel?.fill ?? _fill,
              onTap: () {
                if (sel != null) {
                  _changeSelected((m) => m.fill = !m.fill);
                } else {
                  setState(() => _fill = !_fill);
                }
              },
            ),
          if (isText)
            for (final look in TextLook.values)
              _Chip(
                label: look.label,
                on: (sel?.look ?? _look) == look,
                onTap: () {
                  if (sel != null) {
                    _changeSelected((m) => m.look = look);
                  } else {
                    setState(() => _look = look);
                  }
                },
              ),
          if (sel != null && sel.tool == MarkTool.text)
            _Chip(label: 'Edit text', icon: Icons.edit, on: false, onTap: _editSelectedText),
          if (sel != null) ...[
            _Chip(label: 'Bring to front', icon: Icons.flip_to_front, on: false, onTap: _bringToFront),
            _Chip(label: 'Duplicate', icon: Icons.copy, on: false, onTap: _duplicateSelected),
            _Chip(label: 'Delete', icon: Icons.delete_outline, on: false, danger: true, onTap: _deleteSelected),
          ],
        ]),
      ]),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.selected, required this.onTap});
  final MarkTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFF3A2B1F) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? const Color(0xFFB98052) : const Color(0xFF3B4248)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(tool.icon, color: Colors.white, size: 21),
              const SizedBox(height: 3),
              Text(tool.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onStart,
  });
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: Row(children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFFB98052),
                inactiveTrackColor: const Color(0xFF3B4248),
                thumbColor: const Color(0xFFD19A6C),
                overlayColor: const Color(0x33B98052),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChangeStart: onStart == null ? null : (_) => onStart!(),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${(value * 100).round()}%', style: const TextStyle(color: Color(0xFFA9B0B6), fontSize: 12)),
          ),
        ]),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap, this.icon, this.danger = false});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFF2867E) : Colors.white;
    return Material(
      color: on ? const Color(0xFF3A2B1F) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: on ? const Color(0xFFB98052) : const Color(0xFF3B4248))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon),
        color: Colors.white,
        disabledColor: const Color(0xFF5A6168),
        style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFF3B4248)), minimumSize: const Size(40, 40)),
      );
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({required this.image, required this.marks, required this.selected, required this.scale});
  final ui.Image image;
  final List<Mark> marks;
  final Mark? selected;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble();
    canvas.save();
    canvas.scale(scale);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    paintMarks(canvas, marks, iw);

    final sel = selected;
    if (sel != null) {
      // Selection frame and handles, kept the same size on screen whatever the photo size.
      final px = 1 / scale;
      final frame = markBounds(sel, iw).inflate(8 * px);
      canvas.drawRect(frame, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * px
        ..color = const Color(0x99000000));
      canvas.drawRect(frame, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * px
        ..color = Colors.white);
      for (final h in markHandles(sel, iw)) {
        canvas.drawCircle(h, 8 * px, Paint()..color = Colors.white);
        canvas.drawCircle(h, 8 * px, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = const Color(0xFFB98052));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) => true;
}

/// Draws [marks] onto [canvas] in image pixel coordinates.
void paintMarks(Canvas canvas, List<Mark> marks, double imageWidth) {
  for (final m in marks) {
    final stroke = baseStroke(imageWidth) * m.width;
    final paint = Paint()
      ..color = m.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()..color = m.color.withValues(alpha: 0.25);
    switch (m.tool) {
      case MarkTool.box:
        final r = Rect.fromPoints(m.points[0], m.points[1]);
        if (m.fill) canvas.drawRect(r, fillPaint);
        canvas.drawRect(r, paint);
      case MarkTool.circle:
        final r = Rect.fromPoints(m.points[0], m.points[1]);
        if (m.fill) canvas.drawOval(r, fillPaint);
        canvas.drawOval(r, paint);
      case MarkTool.cloud:
        final path = cloudPath(Rect.fromPoints(m.points[0], m.points[1]), baseStroke(imageWidth) * 7);
        if (m.fill) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, paint);
      case MarkTool.arrow:
        _arrow(canvas, m.points[0], m.points[1], paint, stroke);
      case MarkTool.pen:
        final path = Path()..moveTo(m.points.first.dx, m.points.first.dy);
        for (final p in m.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      case MarkTool.text:
        _label(canvas, m, imageWidth);
      case MarkTool.select:
        break;
    }
  }
}

void _arrow(Canvas canvas, Offset a, Offset b, Paint paint, double stroke) {
  canvas.drawLine(a, b, paint);
  final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final head = math.max(stroke * 5, 14.0);
  for (final side in [-1, 1]) {
    final t = angle + math.pi + side * math.pi / 7;
    canvas.drawLine(b, b + Offset(math.cos(t), math.sin(t)) * head, paint);
  }
}

/// Revision cloud: half-circle bumps around the rectangle, bulging outward.
Path cloudPath(Rect r, double bump) {
  final path = Path()..moveTo(r.left, r.top);
  void edge(Offset from, Offset to) {
    final len = (to - from).distance;
    final n = math.max(2, (len / bump).round());
    for (var i = 1; i <= n; i++) {
      final p = Offset.lerp(from, to, i / n)!;
      path.arcToPoint(p, radius: Radius.circular(len / n / 2), clockwise: true);
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
  return path..close();
}

void _label(Canvas canvas, Mark m, double imageWidth) {
  final rect = _labelRect(m, imageWidth);
  final pad = baseFont(imageWidth) * m.size * 0.35;
  final origin = Offset(rect.left + pad, rect.top + pad * 0.7);
  switch (m.look) {
    case TextLook.filled:
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(baseFont(imageWidth) * m.size * 0.2)),
          Paint()..color = m.color);
      _textPainter(m, imageWidth).paint(canvas, origin);
    case TextLook.outline:
      // Dark or light outline behind colored text so it reads on any background.
      final lightText = m.color.computeLuminance() > 0.5;
      final outline = TextPainter(
        text: TextSpan(
          text: m.text ?? '',
          style: TextStyle(
            fontSize: baseFont(imageWidth) * m.size,
            fontWeight: FontWeight.w700,
            fontFamily: 'Barlow',
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = baseFont(imageWidth) * m.size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = lightText ? const Color(0xFF111111) : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: imageWidth * 0.9);
      outline.paint(canvas, origin);
      _textPainter(m, imageWidth).paint(canvas, origin);
    case TextLook.plain:
      _textPainter(m, imageWidth).paint(canvas, origin);
  }
}

/// Data passed to the background JPEG encoder.
class EncodeJob {
  EncodeJob(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

Uint8List encodeJpgJob(EncodeJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 85);
}
