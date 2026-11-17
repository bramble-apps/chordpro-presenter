import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Song song(String title, String lyrics, {String artist = ''}) =>
      Song(title: title, raw: lyrics, artist: artist);

  test('the exact title comes first, then the title, then lyrics', () {
    final songs = [
      song('Jesus Is Lord', '[G]Jesus is Lord of all'),
      song('Crown Him', 'Crown Him, for He is Lord of lords'),
      song('He Is Lord', '[C]He is Lord, He is Lord'),
      song('He Is Lord Of All The Earth', 'Sing'),
      song('Holy', 'He sits in glory; lord of all is He'),
      song('Other', 'Nothing here at all'),
    ];
    final ranked = [
      for (final s in songs)
        if (s.searchRank('He Is Lord') case final r?) (s.title, r),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    expect(ranked.first, ('He Is Lord', 0));
    expect(ranked[1], ('He Is Lord Of All The Earth', 1));
    expect([for (final r in ranked) r.$1], contains('Crown Him'));
    expect([for (final r in ranked) r.$1], isNot(contains('Other')));
  });

  test('words must be whole words, the last one may be unfinished', () {
    final s = song('Amazing Grace', 'This is the time that saved a wretch');
    // "is" as a word is there; "hi" alone isn't a word start ("this").
    expect(s.searchRank('wretch sav'), isNotNull);
    expect(s.searchRank('hi wre'), isNull);
    // Accents and punctuation still don't matter in titles.
    expect(song('Alléluia', '').searchRank('alleluia'), 0);
  });

  test('lyric matches show the line they were found in', () {
    final s = song(
      'Crown Him',
      '{title: Crown Him}\n{c: Verse}\n[G]Crown Him, for [D]He is Lord of all\n'
          'Sing to the King\nHe reigns forever and ever',
    );
    expect(s.searchSnippet('He is Lord'), 'Crown Him, for He is Lord of all');
    // Words on different lines: each line, joined.
    expect(
      s.searchSnippet('crown forever'),
      'Crown Him, for He is Lord of all … He reigns forever and ever',
    );
    // A long line keeps just the matches and a little around them.
    final long = song(
      'Long',
      'He is the one who came to us and who will reign as Lord forever more',
    );
    expect(
      long.searchSnippet('he lord'),
      'He is the … reign as Lord forever more',
    );
    // Title and artist matches have no snippet.
    expect(s.searchSnippet('Crown Him'), isNull);
  });
}
