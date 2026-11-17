import 'dart:convert';

import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/song_sources.dart';
import 'package:flutter_test/flutter_test.dart';

// Shaped like Chordie's pages (made-up songs).
const _results = '''
<div class="rateStar"><div style="margin: 0 auto;width: 100%;font-size: 17px; color: grey; font-weight: bold;">4.5</div></div>
<a href="/chord.pere/www.example.com/morning.html"><span style="font-size: 18px; color: black;" >Morning Light</span> &nbsp;&nbsp;<span style="color: grey;font-size: 16px;">The Hill &#38;#38; Co</span></a>
<a style="color: black" href="/chord.pere/www.example.com/morning.html">Preview text...</a>
<a href="/chord.pere/www.example.com/river.html"><span style="font-size: 18px; color: black;" >River Song</span> &nbsp;&nbsp;<span style="color: grey;font-size: 16px;">Someone</span></a>
''';

const _song = '''
<h1 class="titleLeft">Morning Light&nbsp;&nbsp;<a href="/song.php/x"><span>The Hill</span></a></h1>
<div id="song" class="songChord"><div id="firstcol">
<div class="textline"> </div>
<div class="textline"> [Verse 1]</div>
<div class="chordline"> The <span class="bracket">[</span><span class="relc"><span class="absc G">G</span></span><span class="bracket">]</span>morning light is <span class="bracket">[</span><span class="relc"><span class="absc D">D</span></span><span class="bracket">]</span>on the hill</div>
<div class="textline"> </div>
<div class="textline"> </div>
<div class="textline"> Chorus:</div>
<div class="chordline"> We <span class="bracket">[</span><span class="relc"><span class="absc C">C</span></span><span class="bracket">]</span>sing tonight &amp; more</div>
<pre>
e|--3--|
</pre>
''';

void main() {
  test('chordie: results', () {
    final hits = parseChordieResults(_results);
    expect(hits, hasLength(2));
    expect(hits.first.title, 'Morning Light');
    expect(hits.first.artist, 'The Hill & Co');
    expect(
      hits.first.url,
      'https://www.chordie.com/chord.pere/www.example.com/morning.html',
    );
    expect(hits.first.rating, 4.5);
    expect(hits.first.source, 'chordie.com');
  });

  test('chordie: a song page as ChordPro', () {
    final song = parseChordieSong(_song, 'https://www.chordie.com/x');
    expect(song.title, 'Morning Light');
    expect(song.artist, 'The Hill');
    expect(song.raw, '''Verse 1:
The [G]morning light is [D]on the hill

Chorus:
We [C]sing tonight & more
# e|--3--|''');
    expect(ChordPro.sectionNames(song.raw), ['Verse 1', 'Chorus']);
  });

  test('search goes through fetchPage', () async {
    final asked = <String>[];
    final old = fetchPage;
    fetchPage = (url) async {
      asked.add(url);
      return _results;
    };
    addTearDown(() => fetchPage = old);
    final hits = await searchChordie('morning light');
    expect(hits, hasLength(2));
    expect(asked.single, contains('q=morning+light'));
    expect(asked.single, contains('mode=song'));
  });

  test('pasted chords-over-lyrics become ChordPro', () {
    const pasted = '''
Morning Light - The Hill

[Verse 1]
G            D
The morning light is on the hill
Em        C
And all is calm

[Chorus]
C    G  D
We sing tonight

[Instrumental]
G  D  Em  C
''';
    expect(pastedToChordPro(pasted), '''Morning Light - The Hill

Verse 1:
[G]The morning l[D]ight is on the hill
[Em]And all is[C] calm

Chorus:
[C]We si[G]ng [D]tonight

Instrumental:
[G] [D] [Em] [C]''');
    expect(guessTitle(pasted), ('Morning Light', 'The Hill'));
  });

  test('Ultimate Guitar markup and chords past the end of a lyric', () {
    const ug = '[Chorus]\n[tab][ch]C[/ch]       [ch]G/B[/ch]\nHi there[/tab]';
    expect(pastedToChordPro(ug), 'Chorus:\n[C]Hi there[G/B]');
    // Already ChordPro: unchanged.
    const cho = 'Verse:\n[G]Already [D]inline';
    expect(pastedToChordPro(cho), cho);
    // HTML characters are decoded before chords are placed (UG stores
    // "I&rsquo;m"), and chord lines with bar marks are chords.
    expect(
      pastedToChordPro(
        '[Intro]\n|G D Em D|C  Cm |G\n\n'
        '[Verse 1]\n[tab]       [ch]B[/ch]          [ch]Em[/ch]\n'
        'When I&rsquo;m overwhelmed within[/tab]',
      ),
      'Intro:\n[|][G] [D] [Em] [D][|][C] [Cm] [|][G]\n\nVerse 1:\n'
      'When I\u2019[B]m overwhelm[Em]ed within',
    );
    expect(pastedToChordPro('Caf&eacute; &amp; Cr&egrave;me'), 'Café & Crème');
    // Tab becomes a tab block (start / end of tab); chords above it
    // aren't merged into it.
    expect(
      pastedToChordPro('   G7\ne|--1---|\nB|--0---| x2\nG\nHello'),
      '# G7\n{start_of_tab}\ne|--1---|\nB|--0---| x2\n{end_of_tab}\n'
      '[G]Hello',
    );
    // Bar marks beside chords over a lyric go in as [|], in place.
    expect(
      pastedToChordPro('|G       |D\nLord I lift your name'),
      '[|][G]Lord I li[|][D]ft your name',
    );
    // Words that look like chords in a lyric aren't a chord line.
    expect(pastedToChordPro('A Day to Remember'), 'A Day to Remember');
  });

  test('browse links', () {
    final ug = browseSites.firstWhere((s) => s.name == 'ultimate-guitar.com');
    expect(ug.urlFor('amazing grace'), contains('value=amazing+grace'));
    const home = BrowseSite('x', 'https://example.com/');
    expect(home.urlFor('q'), 'https://example.com/');
  });
  test('ultimate guitar: chord sheets from the page data, then a song', () {
    String store(Map<String, dynamic> data) =>
        '<div class="js-store" data-content="${const HtmlEscape().convert(jsonEncode({
          'store': {
            'page': {'data': data},
          },
        }))}"></div>';
    final results = store({
      'results': [
        {
          'type': 'Chords',
          'song_name': 'Morning Light',
          'artist_name': 'The Hill',
          'tab_url':
              'https://tabs.ultimate-guitar.com/tab/the-hill/morning-chords-1',
          'rating': 4.8,
          'votes': 12,
          'version': 1,
        },
        {
          'type': 'Chords',
          'song_name': 'Morning Light',
          'artist_name': 'The Hill',
          'tab_url':
              'https://tabs.ultimate-guitar.com/tab/the-hill/morning-chords-2',
          'rating': 4.9,
          'votes': 300,
          'version': 2,
        },
        {
          'type': 'Tabs',
          'song_name': 'X',
          'tab_url': 'https://tabs.ultimate-guitar.com/tab/x',
        },
        {
          'type': 'Chords',
          'song_name': 'Pro',
          'tab_url': 'https://www.ultimate-guitar.com/pro/?x',
        },
      ],
    });
    final hits = parseUltimateGuitarResults(results);
    expect(hits.map((h) => h.title), [
      'Morning Light (ver 2)',
      'Morning Light',
    ]);
    expect(hits.first.votes, 300);

    final song = parseUltimateGuitarSong(
      store({
        'tab': {'song_name': 'Morning Light', 'artist_name': 'The Hill'},
        'tab_view': {
          'meta': {'capo': 2, 'tonality': 'G'},
          'wiki_tab': {
            'content': '[Verse 1]\r\n[tab][ch]G[/ch]       [ch]D[/ch]\r\nThe morning light[/tab]',
          },
        },
      }),
      'u',
    );
    expect(song.raw, 'Verse 1:\n[G]The morn[D]ing light');
    expect(song.capo, 2);
    expect(song.key, 'G');
  });

  test('chords-and-tabs.net: chord results and a song', () {
    const results =
        '<ul class="main-list"><li><a href="/song/name/the-hill-morning">\n'
        '<span class="songtype typechords">chords</span>\n'
        '<b>The Hill - Morning Light</b><span class="version">ver. 2</span>\n'
        '<div class="rating"><span>8</span></div></a></li>\n'
        '<li><a href="/song/name/the-hill-tab"><span class="songtype typetabs">tabs</span>\n'
        '<b>The Hill - Tab</b><div class="rating"><span>1</span></div></a></li></ul>';
    final hits = parseChordsAndTabsResults(results);
    expect(hits, hasLength(1));
    expect(hits.single.title, 'Morning Light (ver 2)');
    expect(hits.single.artist, 'The Hill');
    expect(
      hits.single.url,
      'https://www.chords-and-tabs.net/song/name/the-hill-morning',
    );
    final song = parseChordsAndTabsSong(
      '<h1><a href="/x">The Hill</a> - <span>Morning Light</span></h1>'
          '<div id="snippet--snippetXteView" class="xte-view"><b>G</b>      <b>D</b>\nThe morning light &amp; more</div>',
      'u',
    );
    expect(song.title, 'Morning Light');
    expect(song.artist, 'The Hill');
    expect(song.raw, '[G]The mor[D]ning light & more');
  });

  test('cifra club: songs only, opened in the browser', () {
    final hits = parseCifraClubResults(
      jsonEncode({
        'response': {
          'docs': [
            {'tipo': '2', 'txt': 'Luz', 'art': 'A', 'dns': 'a', 'url': 'luz'},
            {'tipo': '1', 'txt': 'Artist page', 'dns': 'a', 'url': ''},
          ],
        },
      }),
    );
    expect(hits, hasLength(1));
    expect(hits.single.url, 'https://www.cifraclub.com/a/luz/');
    expect(hits.single.opensInBrowser, isTrue);
  });

  test('worship leader: OpenLP lyrics to ChordPro with its play order', () {
    final song = worshipLeaderSong({
      'title': 'Morning Light',
      'author': 'The Hill',
      'verseOrder': 'v1 c1 v2 c1 b1',
      'lyrics':
          "<?xml version='1.0'?><song version=\"1.0\"><lyrics>"
          '<verse label="1" type="v"><![CDATA[The [G]morning [---]light]]></verse>'
          '<verse label="1" type="c"><![CDATA[{r}We [C]sing{/r}]]></verse>'
          '<verse label="2" type="v"><![CDATA[The [D]river]]></verse>'
          '<verse label="1" type="b"><![CDATA[Ho[Em]ld on]]></verse>'
          '</lyrics></song>',
    }, 'u');
    expect(
      song.raw,
      'Verse 1:\nThe [G]morning light\n\nChorus:\nWe [C]sing\n\n'
      'Verse 2:\nThe [D]river\n\nBridge:\nHo[Em]ld on',
    );
    expect(song.structure.map((s) => s.name), [
      'Verse 1',
      'Chorus',
      'Verse 2',
      'Chorus',
      'Bridge',
    ]);
  });
  test('worship together: songs from the sitemap, then a chart', () {
    const sitemap =
        '<loc>https://www.worshiptogether.com/songs/</loc>'
        '<loc>https://www.worshiptogether.com/songs/morning-light-the-hill/</loc>'
        '<loc>https://www.worshiptogether.com/songs/river-song-the-hill/</loc>'
        '<loc>https://www.worshiptogether.com/songs/new-day-the-hill/</loc>'
        '<loc>https://www.worshiptogether.com/songs/light-of-morning-someone/</loc>'
        '<loc>https://www.worshiptogether.com/es/canciones/luz-x/</loc>';
    final slugs = worshipTogetherSlugs(sitemap);
    expect(slugs, hasLength(4));
    final hits = matchWorshipTogether(slugs, {
      'the-hill': 3,
      'hill': 3,
    }, 'morning light');
    expect(hits.map((h) => '${h.title} / ${h.artist}'), [
      'Morning Light / The Hill',
      'Light Of Morning Someone / ',
    ]);
    expect(
      hits.first.url,
      'https://www.worshiptogether.com/songs/morning-light-the-hill/',
    );

    String seg(String note, [String? lyric]) =>
        '<div class="chord-pro-segment"><div class="chord-pro-note">$note</div>'
        '${lyric == null ? '' : '<div class="chord-pro-lyric">$lyric</div>'}</div>';
    String line(List<String> segs) =>
        '<div class="chord-pro-line">${segs.join()}</div>';
    final html =
        '<title>Morning Light &#x2013; The Hill | Worship Together</title>'
        '<div id="chordPro" data-original-key="G"><div class="x">'
        '${line([seg('&nbsp;', 'Intro')])}'
        '${line([seg('G// D//&nbsp;')])}'
        '${line([seg('&nbsp;', 'Verse 1')])}'
        '${line([seg('&nbsp;', 'The '), seg('G', 'morning '), seg('D', 'light')])}'
        '</div></div></div>';
    final song = parseWorshipTogetherSong(html, 'u');
    expect(song.title, 'Morning Light');
    expect(song.artist, 'The Hill');
    expect(song.key, 'G');
    expect(song.raw, 'Intro:\n[G] [D]\n\nVerse 1:\nThe [G]morning [D]light');
  });

  test('worship leader: every part of the play order, or none', () {
    // Newer OpenLP: name="v1"; a lone chorus with no number.
    const lyrics =
        '<verse name="v1"><![CDATA[One]]></verse>'
        '<verse name="c"><![CDATA[Chorus words]]></verse>'
        '<verse name="v2"><![CDATA[Two]]></verse>';
    final song = worshipLeaderSong({
      'title': 'T',
      'lyrics': lyrics,
      'verseOrder': 'v1 c1 v2 c1',
    }, 'u');
    expect([
      for (final s in song.structure) s.toJson()['name'] ?? s.toJson(),
    ], hasLength(4));
    // A part it doesn't know: no play order (all of it, as written),
    // never just the parts it knows.
    final odd = worshipLeaderSong({
      'title': 'T',
      'lyrics': lyrics,
      'verseOrder': 'v1 x9 c1',
    }, 'u');
    expect(odd.structure, isEmpty);
    expect(odd.raw, contains('Two'));
  });

  test('cifra club: the song read off its page (in-app browser)', () {
    final song = cifraClubFromPage({
      'pre':
          '[Intro] G  D\n\n[Primeira Parte]\n'
          'G          D\nLuz do mundo\n',
      'title': 'Luz',
      'artist': 'Artista',
      'key': 'Tom: G',
      'url': 'https://www.cifraclub.com/a/luz/',
    }, 'u');
    expect(song.title, 'Luz');
    expect(song.artist, 'Artista');
    expect(song.key, 'G');
    expect(song.raw, startsWith('Intro:\n[G] [D]\n'));
    expect(song.raw, contains('[G]Luz do mund[D]o'));
    // As the real page has it: each line led by a zero-width space.
    final real = cifraClubFromPage({
      'pre':
          '\u200b           C          G\n'
          '\u200bBless the Lord, O my soul\n',
      'title': 'T',
      'key': 'Key:  G',
    }, 'u');
    expect(real.raw, 'Bless the L[C]ord, O my s[G]oul');
    expect(real.key, 'G');
    // Nothing on the page: said plainly.
    expect(
      () => cifraClubFromPage({'pre': ''}, 'u'),
      throwsA(isA<SongSourceError>()),
    );
  });

  test('Cifra Club headings: in brackets, in Portuguese, chords after', () {
    const pre =
        '(intro) C G Am C11\n\n'
        'C                      G\n'
        'Though the Earth Cried out for blood\n\n'
        '(refrão)\n'
        '   C        G\n'
        'On Friday a thief (x2)\n';
    expect(
      pastedToChordPro(pre),
      'Intro:\n[C] [G] [Am] [C11]\n\n'
      '[C]Though the Earth Cried [G]out for blood\n\n'
      'Refrão:\n'
      'On [C]Friday a [G]thief (x2)',
    );
    // Words in brackets that aren't a section stay lyrics.
    expect(pastedToChordPro('(oh oh oh)'), '(oh oh oh)');
  });
}
