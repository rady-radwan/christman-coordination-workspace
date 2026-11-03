import 'package:christman_coordination/editor/markup_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const iw = 1000.0; // image width in pixels

  Mark box({bool fill = false}) =>
      Mark(tool: MarkTool.box, color: Colors.red, points: [const Offset(100, 100), const Offset(300, 200)], fill: fill);

  test('arrow is hit near its line, not far away', () {
    final a = Mark(tool: MarkTool.arrow, color: Colors.red, points: [const Offset(0, 0), const Offset(100, 0)]);
    expect(hitsMark(a, const Offset(50, 3), 5, iw), isTrue);
    expect(hitsMark(a, const Offset(50, 60), 5, iw), isFalse);
  });

  test('unfilled box: inside counts for Select, only the edge while drawing', () {
    final b = box();
    expect(hitsMark(b, const Offset(200, 150), 5, iw), isTrue);
    expect(hitsMark(b, const Offset(200, 150), 5, iw, interior: false), isFalse);
    expect(hitsMark(b, const Offset(101, 150), 5, iw, interior: false), isTrue);
  });

  test('filled box is hit anywhere inside', () {
    expect(hitsMark(box(fill: true), const Offset(200, 150), 5, iw, interior: false), isTrue);
  });

  test('shapes have four corner handles, arrows two, pen none', () {
    expect(markHandles(box(), iw).length, 4);
    expect(markHandles(Mark(tool: MarkTool.arrow, color: Colors.red, points: [Offset.zero, const Offset(1, 1)]), iw).length, 2);
    expect(markHandles(Mark(tool: MarkTool.pen, color: Colors.red, points: [Offset.zero, const Offset(1, 1)]), iw), isEmpty);
  });

  test('copy is independent of the original', () {
    final b = box();
    final c = b.copy()..points = [Offset.zero, const Offset(1, 1)];
    expect(b.points.first, const Offset(100, 100));
    expect(c.points.first, Offset.zero);
  });

  test('bigger line width and text size scale the drawing', () {
    final thin = box()..width = 1;
    final thick = box()..width = 3;
    // A point just outside the thin reach is inside the thick reach.
    expect(hitsMark(thin, const Offset(200, 90), 2, iw), isFalse);
    expect(hitsMark(thick, const Offset(200, 90), 2, iw), isTrue);
  });

  test('cloud path closes around the rectangle', () {
    final p = cloudPath(const Rect.fromLTWH(0, 0, 200, 100), 20);
    final b = p.getBounds();
    expect(b.width, greaterThanOrEqualTo(200));
    expect(b.height, greaterThanOrEqualTo(100));
  });
}
