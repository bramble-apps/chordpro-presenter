import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('libraries keep their own songs, tags and setlists', () async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final m = PresenterModel();
    await m.load();
    expect(m.libraries.map((l) => l.name), ['My Library']);
    final first = m.songs.single.title;
    m.addTag('English');

    final french = await m.createLibrary('French');
    expect(m.libraryId, french.id);
    expect(m.songs, isEmpty);
    expect(m.tags, isEmpty);
    m.addOrUpdate(Song(title: 'Bénis Dieu', raw: '[G]Bénis'));
    m.createSetlist('Dimanche');

    await m.switchLibrary('main');
    expect(m.songs.map((s) => s.title), [first]);
    expect(m.tags.map((t) => t.name), ['English']);
    expect(m.setlists, isEmpty);

    // After a restart: the open library, and the other one intact.
    await m.switchLibrary(french.id);
    await m.flush();
    final again = PresenterModel();
    await again.load();
    expect(again.libraries.map((l) => l.name), ['My Library', 'French']);
    expect(again.currentLibrary.name, 'French');
    expect(again.songs.map((s) => s.title), ['Bénis Dieu']);
    expect(again.setlists.map((s) => s.name), ['Dimanche']);
    await again.switchLibrary('main');
    expect(again.songs.map((s) => s.title), [first]);

    // The open library can't be deleted; another one can.
    await again.deleteLibrary('main');
    expect(again.libraries.length, 2);
    await again.deleteLibrary(french.id);
    expect(again.libraries.map((l) => l.name), ['My Library']);
  });
}
