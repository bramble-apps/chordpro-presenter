import 'package:bilingual_projector/widgets/detent_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone sheet: the full width, nearly the full height, '
      'dragged down shut', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? result = 'not closed';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDetentSheet<String>(
              context,
              builder: (_) => const Center(child: Text('Page')),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    expect(useDetentSheet(tester.element(find.text('Open'))), isTrue);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(
      find
          .ancestor(of: find.text('Page'), matching: find.byType(Material))
          .first,
    );
    // Edge to edge: no room lost at the sides.
    expect(sheet.left, 0);
    expect(sheet.width, 400);
    expect(sheet.top, lessThan(20));
    // Dragged down (by its grabber): shut, nothing chosen.
    await tester.dragFrom(Offset(200, sheet.top + 8), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
    expect(result, isNull);
  });
}
