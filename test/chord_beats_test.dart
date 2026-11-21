import 'package:bilingual_projector/chord_beats.dart';
import 'package:bilingual_projector/widgets/song_marks.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/chord_beats_editor.dart';
import 'package:bilingual_projector/widgets/chord_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beats per bar from the time signature', () {
    expect(beatsPerBar('4/4'), 4);
    expect(beatsPerBar('6/8'), 6);
    expect(beatsPerBar(' 3 / 4 '), 3);
    expect(beatsPerBar(''), 4);
  });

  test('a song can have its own chord beats', () {
    final f = SheetFormat()
      ..chordBeats = true
      ..beatStyle = ChordBeatStyle.pills;
    final all = BeatSettings.of(f, const {});
    expect((all.show, all.style, all.own), (true, ChordBeatStyle.pills, false));
    final own = BeatSettings.of(f, {
      'beats': {'show': false, 'style': 'stacks', 'barsPerLine': 3},
    });
    expect(
      (own.show, own.style, own.barsPerLine, own.own),
      (false, ChordBeatStyle.stacks, 3, true),
    );
    // Old saves without the settings keep working.
    expect(SheetFormat().chordBeats, false);
  });

  for (final style in [
    ChordBeatStyle.stacks,
    ChordBeatStyle.pills,
    ChordBeatStyle.timeline,
  ]) {
    testWidgets('${style.label}: a box per bar, chord over its words', (
      tester,
    ) async {
      const raw =
          "Verse 1:\n[G]'Tis so sweet to [C]trust in [C/G]Je - [G]sus\n"
          '[G]Just to [C]know, [G/D]saith [D]the [G]Lord';
      final song = Song(title: 'T', raw: raw, timeSignature: '4/4');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChordSheet(
              song: song,
              raw: raw,
              format: SheetFormat(),
              transpose: 0,
              displayKey: null,
              parts: ChordPro.parts(raw),
              beats: BeatSettings(show: true, style: style, barsPerLine: 4),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text("'Tis so sweet to"), findsOneWidget);
      expect(find.text('C/G'), findsOneWidget);
      expect(find.text('Lord'), findsOneWidget);
      // 9 bars, each with its beat ticks.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_BeatTicks',
        ),
        findsNWidgets(9),
      );
    });
  }

  test('chords are known by section and place', () {
    final keys = ChordKeys();
    final out = <String>[];
    for (final l in ['[C]Intro', 'Verse 1:', '[G]a [D]b', 'Chorus:', '[C]c']) {
      keys.line(l);
      for (final s in ChordPro.segments(l)) {
        if (s.chord?.isNotEmpty ?? false) out.add(keys.next());
      }
    }
    expect(out, ['#0', 'verse 1#0', 'verse 1#1', 'chorus#0']);
    expect(beatDots(4, 4), '••••');
    expect(beatDots(4, 4, hideFull: true), '');
    expect(beatDots(2, 4, hideFull: true), '••');
    expect(beatDots(0, 4), '');
    expect(beatDots(12, 4), '·12');
  });

  testWidgets('Chord Beats editor: drawn like the sheet, tap to edit', (
    tester,
  ) async {
    final beats = <String, int>{};
    Map<String, dynamic>? own;
    final song = Song(
      title: 'T',
      raw: 'Verse 1:\n[G]Light [D]shine\nChorus:\n[C]Sing',
      timeSignature: '4/4',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ChordBeatsEditor(
              song: () => song.copy()..extra['chordBeats'] = beats,
              model: null,
              ownSettings: own,
              onOwnSettings: (v) => setState(() => own = v),
              beats: beats,
            ),
          ),
        ),
      ),
    );
    // Beats off: plain chords; turned on here, dots appear. (The key
    // beside the title is a G too.)
    expect(
      find
          .text('G')
          .evaluate()
          .where((e) => e.findAncestorWidgetOfExactType<SongMarks>() == null),
      hasLength(1),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('G••••'), findsOneWidget);

    await tester.tap(find.text('D••••'));
    await tester.pump();
    await tester.tap(find.byTooltip('Fewer beats (Ctrl+↓)'));
    await tester.tap(find.byTooltip('Fewer beats (Ctrl+↓)'));
    await tester.pump();
    expect(beats, {'verse 1#1': 2});
    expect(find.text('D••'), findsOneWidget);
    expect(find.text('2 beats'), findsOneWidget);
    // Keyboard: next chord, one more beat.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(beats, {'verse 1#1': 2, 'chorus#0': 5});
    // Back to a bar: no number kept.
    await tester.tap(find.byTooltip('Fewer beats (Ctrl+↓)'));
    await tester.pump();
    expect(beats, {'verse 1#1': 2});

    // Another style, for this song only: shown as boxes, still tappable.
    await tester.tap(find.text('Only this song'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<ChordBeatStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stacks').last);
    await tester.pumpAndSettle();
    expect(own, {'show': true, 'style': 'stacks', 'barsPerLine': 4});
    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.text('Sing'));
    await tester.pump();
    expect(find.text('4 beats (a bar)'), findsOneWidget);
  });

  testWidgets('custom beats: two half-bar chords share a bar', (tester) async {
    const raw = 'Verse 1:\n[G]one [C]two [D]three';
    final song = Song(
      title: 'T',
      raw: raw,
      timeSignature: '4/4',
      extra: {
        'chordBeats': {'verse 1#0': 2, 'verse 1#1': 2},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChordSheet(
            song: song,
            raw: raw,
            format: SheetFormat(),
            transpose: 0,
            displayKey: null,
            parts: ChordPro.parts(raw),
            beats: const BeatSettings(
              show: true,
              style: ChordBeatStyle.stacks,
              barsPerLine: 1,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // G and C (2 beats each) fill the first row; D wraps to the next.
    final g = tester.getRect(find.text('G'));
    final c = tester.getRect(find.text('C'));
    final d = tester.getRect(find.text('D'));
    expect(c.top, g.top);
    expect(d.top, greaterThan(g.top));
  });
}
