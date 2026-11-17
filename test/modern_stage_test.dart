import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/projection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modern stage view: this part, up next, parts, details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final m = PresenterModel();
    await m.load();
    m.projection.view = ProjectionView.stage;
    m.projection.stageLayout = StageLayout.modern;
    expect(m.slides.length, greaterThanOrEqualTo(2));

    Future<void> show({bool picture = false}) => tester.pumpWidget(
      MaterialApp(
        home: ProjectorDisplay(data: m.projectionData, picture: picture),
      ),
    );

    await show();
    // The next part is named under its box, the title is shown, and the
    // clock and time elapsed are running.
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text(m.currentSong!.displayTitle), findsOneWidget);
    expect(find.textContaining('Elapsed'), findsOneWidget);
    expect(find.text('End'), findsNothing);
    // Fades between parts by default (two copies while fading).
    expect(m.projection.stageFade, isTrue);
    m.selection.value = 1;
    await tester.pump();
    // Old and new cross-fade.
    List<double> fades() => [
      for (final e
          in find
              .descendant(
                of: find.byType(AnimatedSwitcher).first,
                matching: find.byType(FadeTransition),
              )
              .evaluate())
        (e.widget as FadeTransition).opacity.value,
    ];
    await tester.pump(const Duration(milliseconds: 60));
    final mid = fades();
    expect(mid, hasLength(2));
    expect(mid.every((o) => o > 0 && o < 1), isTrue, reason: '$mid');
    await tester.pumpAndSettle();
    expect(fades(), [1.0]);

    // On the last part, the next window shows the next song (or the end).
    m.selection.value = m.slides.length - 1;
    await tester.pumpAndSettle();
    expect(find.text('End'), findsOneWidget);

    // Pictures drawn ahead of time (casting from the phone) leave out the
    // clock and time elapsed, which would be stuck.
    await show(picture: true);
    expect(find.textContaining('Elapsed'), findsNothing);

    // Classic is still the whole sheet.
    m.projection.stageLayout = StageLayout.classic;
    await show();
    expect(find.text('Up next'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('modern stage view never overlaps, on any screen shape', (
    tester,
  ) async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final m = PresenterModel();
    await m.load();
    m.projection.view = ProjectionView.stage;
    m.projection.stageLayout = StageLayout.modern;
    const areas = [
      'modern-parts',
      'modern-now',
      'modern-head',
      'modern-upnext',
      'modern-next',
    ];
    final widths = <(Size, int), double>{};
    for (final screen in const [
      Size(1920, 1080), // 16:9
      Size(1900, 1140), // a browser window (the overlap that was reported)
      Size(1600, 1200), // 4:3
      Size(2560, 1080), // ultrawide
      Size(1366, 768),
    ]) {
      for (final listWidth in const [100, 50, 0, 200]) {
        m.projection.stagePartsWidth = listWidth;
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(home: ProjectorDisplay(data: m.projectionData)),
        );
        await tester.pump(const Duration(seconds: 1));
        final shown = [
          for (final a in areas)
            if (find.byKey(ValueKey(a)).evaluate().isNotEmpty) a,
        ];
        // Width 0 hides the list.
        expect(shown.contains('modern-parts'), listWidth > 0);
        final rects = {
          for (final a in shown) a: tester.getRect(find.byKey(ValueKey(a))),
        };
        widths[(screen, listWidth)] = rects['modern-now']!.width;
        final whole = Offset.zero & screen;
        // Both windows reach the bottom margin (no empty band below), the
        // same distance from the bottom as the top.
        final now = rects['modern-now']!, next = rects['modern-next']!;
        expect(
          screen.height - now.bottom,
          closeTo(now.top, 1),
          reason: 'bottom margin at $screen',
        );
        expect(
          next.bottom,
          closeTo(now.bottom, 1),
          reason: 'windows line up at the bottom at $screen',
        );
        for (final a in shown) {
          expect(
            whole.contains(rects[a]!.topLeft) &&
                whole.contains(rects[a]!.bottomRight - const Offset(1, 1)),
            isTrue,
            reason: '$a is on the screen at $screen',
          );
          for (final b in shown) {
            if (a.compareTo(b) >= 0) continue;
            final o = rects[a]!.intersect(rects[b]!);
            expect(
              o.width <= 0.5 || o.height <= 0.5,
              isTrue,
              reason: '$a and $b overlap at $screen',
            );
          }
        }
      }
    }
    // A narrower list gives the song's window more room.
    for (final screen in const [Size(1920, 1080), Size(1900, 1140)]) {
      expect(widths[(screen, 50)]!, greaterThan(widths[(screen, 100)]!));
      expect(widths[(screen, 0)]!, greaterThan(widths[(screen, 50)]!));
    }
    tester.view.reset();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
