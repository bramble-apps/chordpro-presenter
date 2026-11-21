import 'package:bilingual_projector/themes.dart';
import 'package:bilingual_projector/widgets/dialog_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every dialog's ✓ is the theme's accent, its ✕ the neutral tint: the
  // same in every style and colour theme, light and dark.
  for (final style in UiStyle.values) {
    testWidgets('✓ accent, ✕ neutral (${style.name})', (tester) async {
      for (final t in appThemes) {
        for (final b in Brightness.values) {
          final theme = buildTheme(t, b, style: style);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Row(
                  children: [
                    DialogCancelButton(onPressed: () {}),
                    DialogDoneButton(onPressed: () {}),
                  ],
                ),
              ),
            ),
          );
          // (past the theme change's fade)
          await tester.pumpAndSettle();
          Color fillOf(Type t) => tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(t),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color!;
          final scheme = theme.colorScheme;
          final why = '${t.id} ${b.name}';
          expect(fillOf(DialogDoneButton), scheme.primary, reason: why);
          expect(
            fillOf(DialogCancelButton),
            scheme.surfaceContainerHighest,
            reason: why,
          );
        }
      }
    });
  }
}
