// Padding check for UI tests: measures what's actually seen (a field's
// outline, a button's filled circle, not their tap targets) against the
// edges of the surface they sit on, so the gaps can be compared.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The part of [finder]'s widget that is seen: a button's own shape
/// (inside the larger tap target touch layouts add), a text field's border
/// box; anything else, its whole box.
Rect visibleRect(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  if (widget is IconButton || widget is ButtonStyleButton) {
    final shape = find.descendant(of: finder, matching: find.byType(Material));
    return tester.getRect(shape.first);
  }
  if (widget is TextField) {
    return tester.getRect(
      find.descendant(of: finder, matching: find.byType(InputDecorator)),
    );
  }
  return tester.getRect(finder);
}

/// The gaps from [frame]'s edges to what's seen of [left] (its left edge),
/// [top] (its top edge) and [right] (its right edge).
({double left, double top, double right}) paddingGaps(
  WidgetTester tester, {
  required Finder frame,
  required Finder left,
  required Finder top,
  required Finder right,
}) {
  final f = tester.getRect(frame);
  return (
    left: visibleRect(tester, left).left - f.left,
    top: visibleRect(tester, top).top - f.top,
    right: f.right - visibleRect(tester, right).right,
  );
}

/// Checks that what's seen at the top, left and right of [frame] is the
/// same distance from each of its edges (within [tolerance] pixels).
void expectEvenPadding(
  WidgetTester tester, {
  required Finder frame,
  required Finder left,
  required Finder top,
  required Finder right,
  double tolerance = 0.5,
  String? reason,
}) {
  final g = paddingGaps(
    tester,
    frame: frame,
    left: left,
    top: top,
    right: right,
  );
  final why =
      '${reason ?? 'padding'}: left ${g.left}, top ${g.top}, right ${g.right}';
  expect(g.top, closeTo(g.left, tolerance), reason: why);
  expect(g.right, closeTo(g.left, tolerance), reason: why);
}
