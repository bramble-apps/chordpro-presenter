import 'package:bilingual_projector/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets('tooltips are readable in every style, light and dark', (
    tester,
  ) async {
    for (final style in UiStyle.values) {
      for (final brightness in Brightness.values) {
        final theme = buildTheme(
          themeById(defaultThemeId),
          brightness,
          style: style,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Center(
                child: Tooltip(message: 'Tip', child: Text('hover me')),
              ),
            ),
          ),
        );
        final state = tester.state<TooltipState>(find.byType(Tooltip));
        state.ensureTooltipVisible();
        await tester.pumpAndSettle();
        final tipText = tester.widget<Text>(find.text('Tip'));
        final text = DefaultTextStyle.of(tester.element(find.text('Tip'))).style
            .merge(tipText.style);
        final box = tester
            .widgetList<Container>(
              find.ancestor(
                of: find.text('Tip'),
                matching: find.byType(Container),
              ),
            )
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.color != null);
        // Tooltip backgrounds are see-through: judge against the page.
        final bg = Color.alphaBlend(box.color!, theme.colorScheme.surface);
        expect(
          _contrast(text.color!, bg),
          greaterThan(4.5),
          reason: '$style $brightness',
        );
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
      }
    }
  });
}
