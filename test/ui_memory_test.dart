import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone: the side pane comes back as it was left', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    await model.load();
    for (var i = 0; i < 60; i++) {
      model.addOrUpdate(
        Song(title: 'Song ${i.toString().padLeft(2, '0')}', raw: 'x'),
      );
    }
    model.createSetlist('Sunday');
    await tester.pumpWidget(
      BilingualProjectorApp(
        model: model,
        home: OperatorScreen(model: model),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openPane() async {
      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pumpAndSettle();
    }

    Future<void> closePane() async {
      Navigator.of(tester.element(find.byType(Sidebar))).pop();
      await tester.pumpAndSettle();
    }

    // Scrolled down the songs, closed, opened: the same place.
    await openPane();
    final list = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.drag(list.first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Sidebar), matching: find.text('Song 00')),
      findsNothing,
    );
    final shown = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .firstWhere((t) => t.startsWith('Song '));
    await closePane();
    await openPane();
    expect(
      find.descendant(of: find.byType(Sidebar), matching: find.text(shown)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Sidebar), matching: find.text('Song 00')),
      findsNothing,
    );

    // On the setlists, closed, opened: still the setlists.
    await tester.tap(find.text('Setlists'));
    await tester.pumpAndSettle();
    expect(find.text('Sunday'), findsOneWidget);
    await closePane();
    await openPane();
    expect(find.text('Sunday'), findsOneWidget);
  });
}
