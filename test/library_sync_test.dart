import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/library_sync.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/library_sync_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A model with two libraries: "Church" (open) and "Band", which share one
/// song (edited since in Church) and each have songs and a setlist of
/// their own.
Future<(PresenterModel, String, String)> twoLibraries() async {
  final m = PresenterModel();
  await m.load();
  final shared = Song(
    title: 'Shared',
    raw: '[C]old words',
    date: DateTime.utc(2026, 1, 1),
  );
  // Band first: its own song, a setlist, and the shared song (old).
  final band = (await m.createLibrary('Band')).id;
  final fast = m.addTag('Fast');
  m
    ..addOrUpdate(shared.copy())
    ..addOrUpdate(Song(title: 'Band only', raw: '[E]x', tags: [fast.id]));
  final gig = m.createSetlist('Gig');
  m.addSongsToSetlist(gig, [
    m.songs.firstWhere((s) => s.title == 'Band only').id,
  ]);
  // Church: the shared song edited, its own song (same title as nothing).
  final church = (await m.createLibrary('Church')).id;
  m.addOrUpdate(shared.copy());
  final mine = m.songById(shared.id)!.copy()..raw = '[C]new words';
  m.addOrUpdate(mine);
  m.addOrUpdate(Song(title: 'Church only', raw: '[G]y'));
  return (m, church, band);
}

void main() {
  setUp(() {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
  });

  test('compares two libraries', () async {
    final (m, _, band) = await twoLibraries();
    final (diff, _, _) = await m.compareWithLibrary(band);
    final only = {
      for (final s in diff.songs) s.title: (s.here != null, s.there != null),
    };
    expect(only['Church only'], (true, false));
    expect(only['Band only'], (false, true));
    expect(only['Shared'], (true, true));
    final shared = diff.songs.firstWhere((s) => s.title == 'Shared');
    expect(shared.hereNewer, isTrue);
    // Defaults: everything new copied across, the newer edit wins.
    expect(diff.choices[shared], SyncChoice.here);
    expect(diff.setlists.single.name, 'Gig');
    expect(diff.choices[diff.setlists.single], SyncChoice.there);
  });

  test('syncs both ways, then the libraries match', () async {
    final (m, church, band) = await twoLibraries();
    final (diff, here, there) = await m.compareWithLibrary(band);
    final r = await m.syncWithLibrary(band, diff, here, there);
    expect(r.describe('Church', 'Band'), contains('to Band: 2 songs'));
    // Here: Band's song, its tag (by name) and setlist came over.
    expect(m.songs.map((s) => s.title), containsAll(['Band only', 'Shared']));
    final fast = m.tags.singleWhere((t) => t.name == 'Fast');
    expect(m.songs.firstWhere((s) => s.title == 'Band only').tags, [fast.id]);
    final gig = m.setlists.singleWhere((s) => s.name == 'Gig');
    expect(m.songById(gig.entries.single.songId)!.title, 'Band only');
    // There: saved, with the newer "Shared" and Church's own song.
    await m.switchLibrary(band);
    expect(m.songs.map((s) => s.title), containsAll(['Church only', 'Shared']));
    expect(m.songs.firstWhere((s) => s.title == 'Shared').raw, '[C]new words');
    await m.switchLibrary(church);
    final (again, _, _) = await m.compareWithLibrary(band);
    expect(again.isEmpty, isTrue);
  });

  test('send only, keep both, and songs matched by title', () async {
    final (m, _, band) = await twoLibraries();
    // The same song added to each library separately.
    m.addOrUpdate(Song(title: 'Amazing Grace!', raw: '[G]a', artist: 'Newton'));
    await m.switchLibrary(band);
    m.addOrUpdate(Song(title: 'amazing grace', raw: '[G]b', artist: 'newton'));
    final church = m.libraries.firstWhere((l) => l.name == 'Church').id;
    await m.switchLibrary(church);

    final (diff, here, there) = await m.compareWithLibrary(band);
    final grace = diff.songs.firstWhere((s) => s.title == 'Amazing Grace!');
    expect(grace.changed, isTrue);
    diff.choose(SyncChoice.here);
    expect(
      diff.choices[diff.songs.firstWhere((s) => s.title == 'Band only')],
      SyncChoice.skip,
    );
    diff.choices[grace] = SyncChoice.both;
    await m.syncWithLibrary(band, diff, here, there);
    // Nothing came here but the other version of Grace, as a copy.
    expect(m.songs.map((s) => s.title), isNot(contains('Band only')));
    expect(m.songs.map((s) => s.title), contains('amazing grace (Band)'));
    await m.switchLibrary(band);
    expect(m.songs.map((s) => s.title), contains('Amazing Grace! (Church)'));
    expect(m.songs.map((s) => s.title), contains('amazing grace'));
  });

  testWidgets('the dialog syncs with the choices made', (tester) async {
    final (m, _, band) = (await tester.runAsync(twoLibraries))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showLibrarySync(c, m, band),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Church ⇄ Band'), findsOneWidget);
    expect(find.text('Church only'), findsOneWidget);
    expect(find.text('Band only'), findsOneWidget);
    await tester.tap(find.text('Send to Band'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    // Sent only: Band's song didn't come here.
    expect(m.songs.map((s) => s.title), isNot(contains('Band only')));
    final there = await tester.runAsync(() => m.librarySide(band));
    expect(there!.songs.map((s) => s.title), contains('Church only'));
  });
}
