import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Duplicate setlist: same songs, keys and notes; its own ids; no OpenChords link', () async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final m = PresenterModel();
    await m.load();
    final a = Song(title: 'A', raw: '[G]a');
    final b = Song(title: 'B', raw: '[C]b');
    m.addOrUpdate(a);
    m.addOrUpdate(b);
    final gig = m.createSetlist('Gig');
    final other = m.createSetlist('Other');
    m.addSongsToSetlist(gig, [a.id, b.id]);
    gig.entries.first.transpose = 2;
    gig.notes = 'Bring capo';
    gig.extra['openchords'] = {'id': 'x'};
    gig.extra['mine'] = 1;

    final copy = m.duplicateSetlist(gig);
    expect(copy.name, 'Gig copy');
    expect(copy.id, isNot(gig.id));
    expect(m.setlists.indexOf(copy), m.setlists.indexOf(gig) + 1);
    expect(m.setlists.last, other);
    expect([for (final e in copy.entries) e.songId], [a.id, b.id]);
    expect(copy.entries.first.transpose, 2);
    expect(copy.notes, 'Bring capo');
    expect(copy.extra, {'mine': 1});
    // entries are its own: changing one leaves the original as it was
    expect(copy.entries.first.id, isNot(gig.entries.first.id));
    copy.entries.first.transpose = 5;
    expect(gig.entries.first.transpose, 2);
    expect(gig.extra['openchords'], {'id': 'x'});
  });
}
