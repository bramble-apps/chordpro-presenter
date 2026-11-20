import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/export.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> model() async {
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final m = PresenterModel();
  await m.load();
  m.addOrUpdate(
    Song(
      title: 'Test',
      artist: 'Someone',
      raw: 'Verse 1:\n[G]Hello [D]world\n\nChorus:\n[C]Sing [G]out',
      ccli: '123',
      tempo: '90',
    ),
  );
  return m;
}

void main() {
  test('ChordPro export: metadata, current key, structure', () async {
    final m = await model();
    m.setTranspose(2); // G -> A
    m.setStructure(const [
      StructureItem.section('Chorus'),
      StructureItem.keyChange(4),
      StructureItem.section('Verse 1'),
    ]);
    final out = exportChordPro(ExportSource.from(m), includeChords: true);
    expect(out, contains('{title: Test}'));
    expect(out, contains('{artist: Someone}'));
    expect(out, contains('{key: A}'));
    expect(out, contains('{ccli: 123}'));
    expect(out, contains('[D]Sing [A]out'));
    expect(out, contains('{comment: Key change → Db}'), reason: 'A + 4');
    expect(out, contains('[Db]Hello [Ab]world'), reason: 'G +2 +4');
    expect(out.indexOf('Sing'), lessThan(out.indexOf('Hello')));

    final noChords = exportChordPro(ExportSource.from(m), includeChords: false);
    expect(noChords, contains('Sing out'));
    expect(noChords, isNot(contains('[')));
  });

  test('Text export lines chords up over the lyrics', () async {
    final m = await model();
    final out = exportText(ExportSource.from(m), includeChords: true);
    final lines = out.split('\n');
    final i = lines.indexOf('Hello world');
    expect(i, greaterThan(0));
    expect(lines[i - 1], 'G     D');
    expect(lines.first, 'Test');
    expect(out, contains('CCLI Song # 123'));
    expect(
      exportText(ExportSource.from(m), includeChords: false),
      isNot(contains('G     D')),
    );
  });

  testWidgets('PDF export produces a PDF at any size', (tester) async {
    // Loading the bundled fonts is real I/O.
    await tester.runAsync(() async {
      final m = await model();
      for (final scale in [0.5, 1.0, 1.5]) {
        final bytes = await exportPdf(
          ExportSource.from(m),
          includeChords: true,
          scale: scale,
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(1000));
      }
    });
  });

  test('styled Unicode letters become plain letters with real styles', () {
    // "𝘛𝘰" is sans-serif italic, "𝐁𝐨𝐥𝐝" bold, "𝟐" bold digit.
    expect(foldStyledLetters('𝘛𝘰 Ending'), [
      ('To', false, true),
      (' Ending', false, false),
    ]);
    expect(foldStyledLetters('𝐁𝐨𝐥𝐝𝟐'), [('Bold2', true, false)]);
    expect(foldStyledLetters('Plain'), [('Plain', false, false)]);
  });

  testWidgets('PDF handles styled letters and chords over spaces', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final m = await model();
      m.addOrUpdate(
        Song(
          title: 'Styled',
          raw:
              'Chorus:\n[G]Bless my soul [A/C#]  O my soul\n'
              '[D] {c: 𝘛𝘰 𝘐𝘯𝘴𝘵𝘳𝘶𝘮𝘦𝘯𝘵𝘢𝘭}',
        ),
      );
      final bytes = await exportPdf(ExportSource.from(m), includeChords: true);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  testWidgets('PDF in columns: fewer pages, parts kept together', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final m = await model();
      final raw = [
        for (var v = 1; v <= 24; v++)
          'Verse $v:\n'
              '[G]Line one of verse $v [D]goes here\n'
              '[Em]Line two of verse $v [C]goes here\n'
              '[G]Line three of verse $v [D]goes here\n',
      ].join('\n');
      m.addOrUpdate(Song(title: 'Long', raw: raw));
      int pages(List<int> pdf) =>
          RegExp(r'/Type\s*/Page[^s]')
              .allMatches(String.fromCharCodes(pdf))
              .length;
      final counts = <int>[];
      for (final columns in [1, 2, 3]) {
        final bytes = await exportPdf(
          ExportSource.from(m),
          includeChords: true,
          columns: columns,
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        counts.add(pages(bytes));
      }
      expect(counts[0], greaterThan(1), reason: 'long enough to need pages');
      expect(counts[1], lessThan(counts[0]));
      // Three narrow columns can wrap long lines; short lines fit.
      expect(counts[2], lessThan(counts[0]));
    });
  });

  testWidgets('PDF with linked sections styled or hidden', (tester) async {
    await tester.runAsync(() async {
      final m = await model();
      m.addOrUpdate(
        Song(
          title: 'Grâce',
          raw: 'Verse 1:\nAmazing grace\n\nCouplet 1:\nGrâce infinie',
          structure: const [
            StructureItem.section('Verse 1', linked: true),
            StructureItem.section('Couplet 1'),
          ],
        ),
      );
      m.updateFormat((f) {
        f.linked.italic = true;
        f.linked.dim = true;
        f.linked.size = 80;
      });
      final styled = await exportPdf(ExportSource.from(m), includeChords: true);
      expect(String.fromCharCodes(styled.take(4)), '%PDF');
      m.updateFormat((f) => f.linked.show = false);
      final hidden = await exportPdf(ExportSource.from(m), includeChords: true);
      expect(String.fromCharCodes(hidden.take(4)), '%PDF');
      expect(hidden.length, lessThan(styled.length));
    });
  });

  testWidgets('PDF export with labels in either margin, any columns', (t) async {
    await t.runAsync(() async {
      final m = await model();
      for (final side in ['left', 'right']) {
        for (final columns in [1, 2]) {
          final bytes = await exportPdf(
            ExportSource.from(m),
            includeChords: true,
            columns: columns,
            marginLabels: side,
          );
          expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        }
      }
    });
  });
}
