// Finding songs online: search sites and import a song as ChordPro.
//
// Each request is made because the user asked (a search, or opening one
// song), names this app honestly, and goes through the local server, which
// only talks to the sites listed in tools/serve.py, at most once a second
// each. A site that refuses the app (Cifra Club's song pages, SongSelect's
// login) opens in the browser instead: copy the song there and paste it,
// and [pastedToChordPro] turns it into ChordPro.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'browser.dart';
import 'chordpro.dart';
import 'music.dart';
import 'tabs.dart' show isTabLine;

/// One search result.
class SongHit {
  final String title;
  final String artist;
  final String source; // site name shown, e.g. "chordie.com"
  final String url;

  /// 0–5 stars and how many voted, if the site rates songs.
  final double? rating;
  final int? votes;

  /// The site won't hand the song to the app: it opens in the browser.
  final bool opensInBrowser;

  /// Worship Leader: the song's database language and id.
  final String? lang;
  final int? id;

  const SongHit({
    required this.title,
    required this.artist,
    required this.source,
    required this.url,
    this.rating,
    this.votes,
    this.opensInBrowser = false,
    this.lang,
    this.id,
  });
}

/// A song fetched from a site, ready to add to the library.
class FoundSong {
  final String title;
  final String artist;
  final String raw; // ChordPro
  final String url;
  final int capo;
  final String key;
  final String copyright;
  final String ccli;

  /// Song structure (play order), when the site gives one.
  final List<StructureItem> structure;
  const FoundSong({
    required this.title,
    required this.artist,
    required this.raw,
    required this.url,
    this.capo = 0,
    this.key = '',
    this.copyright = '',
    this.ccli = '',
    this.structure = const [],
  });
}

class SongSourceError implements Exception {
  final String message;
  SongSourceError(this.message);
  @override
  String toString() => message;
}

/// Gets a page. In the browser it goes through the local server (sites
/// don't let web pages read them directly); installed apps fetch it
/// themselves. Swapped in tests.
Future<String> Function(String url) fetchPage = _fetch;

const _userAgent = 'ChordProPresenter/1.0 (song import; personal use)';

Future<String> _fetch(String url) async {
  if (kIsWeb) {
    final bytes = await fetchBytes('fetch?url=${Uri.encodeComponent(url)}');
    if (bytes == null) {
      throw SongSourceError(
        "Couldn't reach the site. Online search works when the app is "
        'opened from its local server.',
      );
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
  final r = await http.get(Uri.parse(url), headers: {'User-Agent': _userAgent});
  if (r.statusCode != 200) {
    throw SongSourceError('The site answered ${r.statusCode}.');
  }
  return utf8.decode(r.bodyBytes, allowMalformed: true);
}

const _entities = {
  'nbsp': ' ',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'sbquo': '‚',
  'bdquo': '„',
  'prime': '′',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'middot': '·',
  'bull': '•',
  'laquo': '«',
  'raquo': '»',
  'iexcl': '¡',
  'iquest': '¿',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'deg': '°',
  'sharp': '♯',
  'flat': '♭',
};

const _letters = {
  'AElig': 'Æ',
  'Aacute': 'Á',
  'Acirc': 'Â',
  'Agrave': 'À',
  'Aring': 'Å',
  'Atilde': 'Ã',
  'Auml': 'Ä',
  'Cacute': 'Ć',
  'Ccedil': 'Ç',
  'Ccirc': 'Ĉ',
  'Eacute': 'É',
  'Ecedil': 'Ȩ',
  'Ecirc': 'Ê',
  'Egrave': 'È',
  'Etilde': 'Ẽ',
  'Euml': 'Ë',
  'Iacute': 'Í',
  'Icirc': 'Î',
  'Igrave': 'Ì',
  'Itilde': 'Ĩ',
  'Iuml': 'Ï',
  'Nacute': 'Ń',
  'Ncedil': 'Ņ',
  'Ngrave': 'Ǹ',
  'Ntilde': 'Ñ',
  'OElig': 'Œ',
  'Oacute': 'Ó',
  'Ocirc': 'Ô',
  'Ograve': 'Ò',
  'Oslash': 'Ø',
  'Otilde': 'Õ',
  'Ouml': 'Ö',
  'Sacute': 'Ś',
  'Scedil': 'Ş',
  'Scirc': 'Ŝ',
  'Uacute': 'Ú',
  'Ucirc': 'Û',
  'Ugrave': 'Ù',
  'Uring': 'Ů',
  'Utilde': 'Ũ',
  'Uuml': 'Ü',
  'Yacute': 'Ý',
  'Ycirc': 'Ŷ',
  'Ygrave': 'Ỳ',
  'Ytilde': 'Ỹ',
  'Yuml': 'Ÿ',
  'Zacute': 'Ź',
  'Zcirc': 'Ẑ',
  'aacute': 'á',
  'acirc': 'â',
  'aelig': 'æ',
  'agrave': 'à',
  'aring': 'å',
  'atilde': 'ã',
  'auml': 'ä',
  'cacute': 'ć',
  'ccedil': 'ç',
  'ccirc': 'ĉ',
  'eacute': 'é',
  'ecedil': 'ȩ',
  'ecirc': 'ê',
  'egrave': 'è',
  'etilde': 'ẽ',
  'euml': 'ë',
  'iacute': 'í',
  'icirc': 'î',
  'igrave': 'ì',
  'itilde': 'ĩ',
  'iuml': 'ï',
  'nacute': 'ń',
  'ncedil': 'ņ',
  'ngrave': 'ǹ',
  'ntilde': 'ñ',
  'oacute': 'ó',
  'ocirc': 'ô',
  'oelig': 'œ',
  'ograve': 'ò',
  'oslash': 'ø',
  'otilde': 'õ',
  'ouml': 'ö',
  'sacute': 'ś',
  'scedil': 'ş',
  'scirc': 'ŝ',
  'szlig': 'ß',
  'uacute': 'ú',
  'ucirc': 'û',
  'ugrave': 'ù',
  'uring': 'ů',
  'utilde': 'ũ',
  'uuml': 'ü',
  'yacute': 'ý',
  'ycirc': 'ŷ',
  'ygrave': 'ỳ',
  'yring': 'ẙ',
  'ytilde': 'ỹ',
  'yuml': 'ÿ',
  'zacute': 'ź',
  'zcirc': 'ẑ',
};

/// HTML character references (`&rsquo;`, `&#39;`, `&#x2019;`, accented
/// letters…) as the characters they stand for.
String _unescape(String s) =>
    s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+\d?);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x')) {
        return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      }
      if (e.startsWith('#')) {
        return String.fromCharCode(int.parse(e.substring(1)));
      }
      final named = _entities[e];
      if (named != null) return named;
      // Accented letters: &eacute; &Agrave; &ccedil; &ntilde; &uuml; …
      final letter = _letters[e];
      if (letter != null) return letter;
      return m.group(0)!;
    });

/// Unescapes until stable (some sites escape twice: "&#38;#38;").
String _clean(String s) {
  var out = s;
  for (var i = 0; i < 3; i++) {
    final next = _unescape(out);
    if (next == out) break;
    out = next;
  }
  return out
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ---- Chordie ----

const chordieSite = 'chordie.com';

/// Songs on Chordie matching [query] (up to [count]).
Future<List<SongHit>> searchChordie(String query, {int count = 25}) async {
  final q = Uri.encodeQueryComponent(query.trim());
  final html = await fetchPage(
    'https://www.chordie.com/results.php?q=$q&from=0&size=$count&mode=song',
  );
  return parseChordieResults(html);
}

List<SongHit> parseChordieResults(String html) {
  final hits = <SongHit>[];
  final seen = <String>{};
  final row = RegExp(
    r'<a href="(/chord\.pere/[^"]+)"><span[^>]*font-size: 18px[^>]*>(.*?)</span>\s*(?:&nbsp;)*\s*<span[^>]*>(.*?)</span>',
    dotAll: true,
  );
  for (final m in row.allMatches(html)) {
    final url = 'https://www.chordie.com${m.group(1)}';
    if (!seen.add(url)) continue;
    // The star rating shown just before this result, if any.
    final before = html.substring(0, m.start);
    final stars = RegExp(
      r'font-size: 17px; color: grey; font-weight: bold;">([\d.]+)<',
    ).allMatches(before);
    hits.add(
      SongHit(
        title: _clean(m.group(2)!),
        artist: _clean(m.group(3)!),
        source: chordieSite,
        url: url,
        rating: stars.isEmpty ? null : double.tryParse(stars.last.group(1)!),
      ),
    );
  }
  return hits;
}

/// A Chordie song page as ChordPro (its lines already carry [chords]).
FoundSong parseChordieSong(String html, String url) {
  final heading = RegExp(
    r'<h1 class="titleLeft">(.*?)</h1>',
    dotAll: true,
  ).firstMatch(html);
  var title = '', artist = '';
  if (heading != null) {
    final h = heading.group(1)!;
    final a = RegExp(r'<a[^>]*>(.*?)</a>', dotAll: true).firstMatch(h);
    artist = a == null ? '' : _clean(a.group(1)!);
    title = _clean(a == null ? h : h.substring(0, a.start));
  }
  final start = html.indexOf('id="song"');
  final body = start < 0 ? html : html.substring(start);
  final lines = <String>[];
  final line = RegExp(
    r'<div class="(?:textline|chordline)">(.*?)</div>|<pre>(.*?)</pre>',
    dotAll: true,
  );
  for (final m in line.allMatches(body)) {
    if (m.group(2) != null) {
      // Tab: kept as comments so it doesn't show on slides.
      for (final t in _unescape(m.group(2)!).split('\n')) {
        if (t.trim().isNotEmpty) lines.add('# ${t.trimRight()}');
      }
      continue;
    }
    var t = m.group(1)!;
    t = _unescape(t.replaceAll(RegExp(r'<[^>]+>'), ''));
    lines.add(t.trimRight().replaceFirst(RegExp(r'^ '), ''));
  }
  // Tidy: no blank runs, none at the ends.
  final out = <String>[];
  for (final l in lines) {
    if (l.trim().isEmpty && (out.isEmpty || out.last.trim().isEmpty)) continue;
    out.add(l);
  }
  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  final raw = _labelSections(out.join('\n'));
  return FoundSong(title: title, artist: artist, raw: raw, url: url);
}

Future<FoundSong> fetchChordieSong(SongHit hit) async =>
    parseChordieSong(await fetchPage(hit.url), hit.url);

// ---- Sites to browse ----

/// A site opened in the browser: [searchUrl] has `{q}` for the song name
/// (without it, the site's home page opens).
class BrowseSite {
  final String name;
  final String searchUrl;
  const BrowseSite(this.name, this.searchUrl);

  String urlFor(String query) => searchUrl.contains('{q}')
      ? searchUrl.replaceAll('{q}', Uri.encodeQueryComponent(query.trim()))
      : searchUrl;

  Map<String, dynamic> toJson() => {'name': name, 'url': searchUrl};
  static BrowseSite? fromJson(Object? j) =>
      j is Map && j['name'] is String && j['url'] is String
      ? BrowseSite(j['name'] as String, j['url'] as String)
      : null;
}

const browseSites = [
  BrowseSite(
    'songselect.ccli.com',
    'https://songselect.ccli.com/search/results?search={q}',
  ),
  BrowseSite(
    'ultimate-guitar.com',
    'https://www.ultimate-guitar.com/search.php?search_type=title&value={q}',
  ),
  BrowseSite('worshipleaderapp.com', 'https://worshipleaderapp.com/'),
  BrowseSite(
    'chords-and-tabs.net',
    'https://www.chords-and-tabs.net/search?q={q}',
  ),
  BrowseSite('cifraclub.com', 'https://www.cifraclub.com/?q={q}'),
];

// ---- Pasted songs ----

final _chordToken = RegExp(
  r'^\(?[A-G][#b♯♭]?(?:maj|min|m|M|dim|aug|sus|add|°|ø|\+|-)?\d*'
  r'(?:(?:maj|sus|add|b|#|\+|-)\d+)*(?:/[A-G][#b♯♭]?)?\)?$',
);

bool _isChord(String token) =>
    _chordToken.hasMatch(token) &&
    Chord.parse(token.replaceAll(RegExp(r'[()]'), '')) != null;

/// A line of only chords (and bar marks / repeat counts).
bool _isChordLine(String line) {
  final tokens = line
      .trim()
      .split(RegExp(r'[\s|]+'))
      .where(
        (t) =>
            t.isNotEmpty &&
            !RegExp(
              r'^(\||/|:|-+|x\d+|\(x\d+\)|N\.?C\.?)$',
              caseSensitive: false,
            ).hasMatch(t),
      )
      .toList();
  return tokens.isNotEmpty && tokens.every(_isChord);
}

/// A line of guitar tab ("e|--3--|", "B|-1-0-|", "e|--3--| x2"): the
/// tab view's own test, so what goes in a tab block draws as tab.
bool _isTabLine(String line) => isTabLine(line);

/// "[Verse 1]" / "Chorus:" / "VERSE 2" style headings → "Verse 1:".
String? _heading(String line) {
  final t = line.trim();
  final bracket = RegExp(r'^\[([^\]]+)\]$').firstMatch(t);
  // "(intro)", "(refrão)": only section names (not "(x2)", "(oh oh)").
  final paren = RegExp(r'^\(([^)]+)\)$').firstMatch(t);
  final name = bracket?.group(1) ?? paren?.group(1) ?? t;
  if (bracket != null && !_isChord(name)) return _sectionName(name);
  if (_sectionWord.hasMatch(name) && name.split(' ').length <= 4) {
    return _sectionName(name.replaceAll(RegExp(r':$'), ''));
  }
  return null;
}

/// Section names, in English and as Cifra Club and other sites write them
/// in Portuguese, Spanish and French.
final _sectionWord = RegExp(
  r'^(intro|introdução|introducao|introducción|verse|verso|estrofe|estrofa|'
  r'couplet|pre[- ]?chorus|pr[ée][- ]?refr[ãa]o|pre[- ]?coro|chorus|refrain|'
  r'refr[ãa]o|coro|estribillo|bridge|ponte|puente|pont|tag|outro|ending|'
  r'final|fim|interlude|interl[úu]dio|instrumental|solo|hook|coda|break|'
  r'vamp|turnaround|post[- ]?chorus|primeira parte|segunda parte|'
  r'terceira parte|parte \d+)\b[^:]*:?$',
  caseSensitive: false,
);

/// "intro" → "Intro", "refrão" → "Refrão" (as written otherwise).
String _sectionName(String name) {
  final n = name.trim();
  return n.isEmpty ? n : n[0].toUpperCase() + n.substring(1);
}

/// Labels written as "[Verse 1]" become "Verse 1:".
String _labelSections(String raw) => [
  for (final l in raw.split('\n'))
    if (RegExp(r'^\s*\[([^\]]+)\]\s*$').firstMatch(l) case final m?
        when !_isChord(m.group(1)!.trim()))
      '${m.group(1)!.trim()}:'
    else
      l,
].join('\n');

/// A chord sheet copied from a website (chords on their own lines above
/// the lyrics, or Ultimate Guitar's `[ch]G[/ch]` markup) as ChordPro:
/// each chord goes into the lyric under it, at its column; headings become
/// section labels. Text that's already ChordPro is left as it is.
String pastedToChordPro(String text) {
  // Characters first (UG's "I&rsquo;m"): chords line up with the words as
  // shown, so columns must be counted on the real characters.
  var s = _unescape(text.replaceAll('\r\n', '\n').replaceAll('\t', '    '))
      // Invisible characters (Cifra Club starts every line with a
      // zero-width space): they'd hide a chord line and shift columns.
      .replaceAll(RegExp('[\u200b\u200c\u200d\u2060\ufeff]'), '');
  // Ultimate Guitar's own markup.
  s = s
      .replaceAll(RegExp(r'\[/?tab\]'), '')
      .replaceAllMapped(RegExp(r'\[ch\](.*?)\[/ch\]'), (m) => m.group(1)!);
  final lines = s.split('\n');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trimRight();
    // A heading with the chords after it ("[Intro] G  D/F#  Em", as
    // Cifra Club writes intros and solos): the heading, then the chords.
    final inline =
        RegExp(r'^\s*\[([^\]]+)\]\s+(\S.*)$').firstMatch(line) ??
        RegExp(r'^\s*\(([^)]+)\)\s+(\S.*)$').firstMatch(line);
    final named = inline?.group(1)!.trim() ?? '';
    if (inline != null &&
        !_isChord(named) &&
        (line.trimLeft().startsWith('[') || _sectionWord.hasMatch(named)) &&
        _isChordLine(inline.group(2)!)) {
      if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
      out.add('${_sectionName(named)}:');
      line = inline.group(2)!;
    }
    final heading = _heading(line);
    if (heading != null) {
      if (out.isNotEmpty && out.last.trim().isNotEmpty) out.add('');
      out.add('$heading:');
      continue;
    }
    // Tab: the run of tab lines as a tab block (drawn as strings and
    // playable), whatever site it came from.
    if (_isTabLine(line)) {
      out.add('{start_of_tab}');
      while (i < lines.length && _isTabLine(lines[i].trimRight())) {
        out.add(lines[i].trim());
        i++;
      }
      i--;
      out.add('{end_of_tab}');
      continue;
    }
    if (_isChordLine(line)) {
      final next = i + 1 < lines.length ? lines[i + 1].trimRight() : null;
      if (next != null && _isTabLine(next)) {
        out.add('# ${line.trim()}');
        continue;
      }
      // Chords and where they start; bar marks too, as [|] (they're
      // beside the chords, on the chord line).
      final chords = <(int, String)>[];
      for (final m in RegExp(r'\||[^\s|]+').allMatches(line)) {
        final t = m.group(0)!;
        if (t == '|') {
          chords.add((m.start, '|'));
        } else if (_isChord(t)) {
          // Right against a bar ("|G"): starts where the bar does.
          final col =
              chords.isNotEmpty &&
                  chords.last.$2 == '|' &&
                  chords.last.$1 + 1 == m.start
              ? chords.last.$1
              : m.start;
          chords.add((col, t.replaceAll(RegExp(r'[()]'), '')));
        }
      }
      if (next != null &&
          next.trim().isNotEmpty &&
          !_isChordLine(next) &&
          _heading(next) == null) {
        // Chords into the lyric line, right to left so columns hold.
        var lyric = next;
        for (final (col, chord) in chords.reversed) {
          if (col > lyric.length) lyric = lyric.padRight(col);
          lyric = lyric.replaceRange(col, col, '[$chord]');
        }
        out.add(lyric.trimRight());
        i++;
      } else {
        // Chords with no words under them (intro, instrumental…): each in
        // brackets, bar marks too ([|]).
        var bare = line.trim();
        bare = bare.replaceAllMapped(
          RegExp(r'\||[^\s|]+'),
          (m) => m.group(0) == '|'
              ? '[|]'
              : _isChord(m.group(0)!)
              ? '[${m.group(0)!.replaceAll(RegExp(r'[()]'), '')}]'
              : m.group(0)!,
        );
        out.add(bare.replaceAll(RegExp(r' {2,}'), ' '));
      }
      continue;
    }
    out.add(line);
  }
  // No blank runs, none at the ends.
  final tidy = <String>[];
  for (final l in out) {
    if (l.trim().isEmpty && (tidy.isEmpty || tidy.last.trim().isEmpty)) {
      continue;
    }
    tidy.add(l);
  }
  while (tidy.isNotEmpty && tidy.last.trim().isEmpty) {
    tidy.removeLast();
  }
  return tidy.join('\n');
}

/// Title and artist from a pasted song's first lines ("Title" /
/// "Title - Artist" / "Title by Artist"), if they look like one.
(String, String)? guessTitle(String text) {
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (_isChordLine(t) || _heading(t) != null || ChordPro.isSectionLabel(t)) {
      return null;
    }
    final m = RegExp(r'^(.+?)\s+(?:-|–|—|by)\s+(.+)$').firstMatch(t);
    return m == null ? (t, '') : (m.group(1)!.trim(), m.group(2)!.trim());
  }
  return null;
}

// ---- Ultimate Guitar ----

const ugSite = 'ultimate-guitar.com';

/// The page's data (a JSON blob in `<div class="js-store" data-content>`).
Map<String, dynamic>? _ugStore(String html) {
  final m = RegExp(r'class="js-store" data-content="([^"]*)"').firstMatch(html);
  if (m == null) return null;
  final data = jsonDecode(_unescape(m.group(1)!));
  return data is Map<String, dynamic> ? data : null;
}

Map<String, dynamic>? _ugPage(String html) {
  final store = _ugStore(html)?['store'];
  final page = store is Map ? store['page'] : null;
  final data = page is Map ? page['data'] : null;
  return data is Map<String, dynamic> ? data : null;
}

Future<List<SongHit>> searchUltimateGuitar(String query) async {
  final q = Uri.encodeQueryComponent(query.trim());
  return parseUltimateGuitarResults(
    await fetchPage(
      'https://www.ultimate-guitar.com/search.php?search_type=title&value=$q',
    ),
  );
}

/// Chord sheets only (not tabs, Pro, video or official-app versions), best
/// rated first.
List<SongHit> parseUltimateGuitarResults(String html) {
  final results = _ugPage(html)?['results'];
  if (results is! List) return const [];
  final hits = <SongHit>[];
  for (final r in results.whereType<Map>()) {
    if (r['type'] != 'Chords') continue;
    final url = r['tab_url'];
    if (url is! String || !url.contains('tabs.ultimate-guitar.com/tab/')) {
      continue;
    }
    final version = r['version'];
    final name = '${r['song_name'] ?? ''}'.trim();
    hits.add(
      SongHit(
        title: version is num && version > 1 ? '$name (ver $version)' : name,
        artist: '${r['artist_name'] ?? ''}'.trim(),
        source: ugSite,
        url: url,
        rating: (r['rating'] as num?)?.toDouble(),
        votes: (r['votes'] as num?)?.toInt(),
      ),
    );
  }
  hits.sort((a, b) => (b.votes ?? 0).compareTo(a.votes ?? 0));
  return hits;
}

FoundSong parseUltimateGuitarSong(String html, String url) {
  final data = _ugPage(html);
  final tab = data?['tab'];
  final view = data?['tab_view'];
  final wiki = view is Map ? view['wiki_tab'] : null;
  final content = wiki is Map ? wiki['content'] : null;
  if (tab is! Map || content is! String) {
    throw SongSourceError("Couldn't read that song.");
  }
  final meta = view is Map && view['meta'] is Map ? view['meta'] as Map : {};
  return FoundSong(
    title: '${tab['song_name'] ?? ''}'.trim(),
    artist: '${tab['artist_name'] ?? ''}'.trim(),
    raw: pastedToChordPro(content),
    url: url,
    capo: (meta['capo'] as num?)?.toInt() ?? 0,
    key: '${meta['tonality'] ?? ''}',
  );
}

// ---- chords-and-tabs.net ----

const catSite = 'chords-and-tabs.net';

Future<List<SongHit>> searchChordsAndTabs(String query) async {
  final q = Uri.encodeComponent(query.trim().toLowerCase());
  return parseChordsAndTabsResults(
    await fetchPage('https://www.chords-and-tabs.net/songs/search/$q'),
  );
}

List<SongHit> parseChordsAndTabsResults(String html) {
  final hits = <SongHit>[];
  final item = RegExp(
    r'<a href="(/song/name/[^"]+)">\s*<span class="songtype typechords">chords</span>\s*<b>(.*?)</b>(?:<span class="version">(.*?)</span>)?.*?<div class="rating">\s*<span>(\d+)</span>',
    dotAll: true,
  );
  for (final m in item.allMatches(html)) {
    final full = _clean(m.group(2)!);
    final dash = full.indexOf(' - ');
    final version = _clean(m.group(3) ?? '');
    final n = int.tryParse(version.replaceAll(RegExp(r'\D'), '')) ?? 1;
    final title = dash < 0 ? full : full.substring(dash + 3);
    hits.add(
      SongHit(
        title: n > 1 ? '$title (ver $n)' : title,
        artist: dash < 0 ? '' : full.substring(0, dash),
        source: catSite,
        url: 'https://www.chords-and-tabs.net${m.group(1)}',
        votes: int.tryParse(m.group(4)!),
      ),
    );
    if (hits.length == 25) break;
  }
  return hits;
}

FoundSong parseChordsAndTabsSong(String html, String url) {
  final view = RegExp(
    r'<div id="snippet--snippetXteView"[^>]*>(.*?)</div>',
    dotAll: true,
  ).firstMatch(html);
  if (view == null) throw SongSourceError("Couldn't read that song.");
  final text = _unescape(view.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ''));
  final h1 = RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true).firstMatch(html);
  final heading = h1 == null ? '' : _clean(h1.group(1)!);
  final dash = heading.indexOf(' - ');
  return FoundSong(
    title: dash < 0 ? heading : heading.substring(dash + 3).trim(),
    artist: dash < 0 ? '' : heading.substring(0, dash).trim(),
    raw: pastedToChordPro(text),
    url: url,
  );
}

// ---- Cifra Club (search only: its song pages refuse apps) ----

const cifraSite = 'cifraclub.com';

Future<List<SongHit>> searchCifraClub(String query) async {
  final q = Uri.encodeQueryComponent(query.trim());
  return parseCifraClubResults(
    await fetchPage('https://solr.sscdn.co/cc/c7/?q=$q'),
  );
}

List<SongHit> parseCifraClubResults(String json) {
  final data = jsonDecode(json);
  final docs = data is Map && data['response'] is Map
      ? (data['response'] as Map)['docs']
      : null;
  if (docs is! List) return const [];
  return [
    for (final d in docs.whereType<Map>())
      if ('${d['tipo']}' == '2' && d['dns'] is String && d['url'] is String)
        SongHit(
          title: '${d['txt'] ?? ''}',
          artist: '${d['art'] ?? ''}',
          source: cifraSite,
          url: 'https://www.cifraclub.com/${d['dns']}/${d['url']}/',
          opensInBrowser: true,
        ),
  ].take(15).toList();
}

/// Reads the song off a Cifra Club page open in the in-app browser, when
/// the person looking at it taps Import (the site turns away apps that
/// fetch its pages themselves): the chord sheet's text (chords over the
/// words), title, artist and key, as JSON. (desktop/electron/main.js keeps
/// a copy for the Linux app.)
const cifraPageScript = r'''(() => {
  const pre = document.querySelector('pre');
  // "Song (chords) - Artist - Cifra Club"
  const parts = document.title.split(' - ');
  const h1 = document.querySelector('h1');
  const title = parts.length >= 3
      ? parts.slice(0, -2).join(' - ').replace(/\s*\([^)]*\)\s*$/, '')
      : (h1 ? h1.textContent.trim() : '');
  const artist = parts.length >= 3 ? parts[parts.length - 2] : '';
  const keyLabel = [...document.querySelectorAll('span, b, a, div, p')]
      .map((e) => e.textContent.trim())
      .find((t) => t.length < 24 &&
          /^(key|tom|tono|tonalidad)\s*:\s*[A-G]/i.test(t));
  return JSON.stringify({
    pre: pre ? (pre.innerText || pre.textContent) : '',
    title: title.trim(),
    artist: artist.trim(),
    key: keyLabel || '',
    url: location.href,
  });
})()''';

/// A Cifra Club page's song, as [cifraPageScript] read it, as ChordPro.
FoundSong cifraClubFromPage(Map<String, dynamic> page, String url) {
  final pre = '${page['pre'] ?? ''}';
  if (pre.trim().isEmpty) {
    throw SongSourceError('No chords on that page.');
  }
  // "Key: G" / "Tom: G" / "G" → "G".
  final key = '${page['key'] ?? ''}'
      .replaceFirst(RegExp(r'^\s*[a-z]+\s*:\s*', caseSensitive: false), '')
      .trim();
  return FoundSong(
    title: '${page['title'] ?? ''}'.trim(),
    artist: '${page['artist'] ?? ''}'.trim(),
    raw: pastedToChordPro(pre),
    url: '${page['url'] ?? url}',
    key: key,
  );
}

// ---- Worship Leader (its free song database, searched offline) ----

const worshipLeaderSite = 'worshipleaderapp.com';

/// Languages offered for the Worship Leader database (its own codes).
const worshipLeaderLanguages = {
  'en': 'English',
  'fr': 'French',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'de': 'German',
  'it': 'Italian',
  'sw': 'Swahili',
  'ko': 'Korean',
  'zh': 'Chinese',
  'ru': 'Russian',
  'uk': 'Ukrainian',
  'pl': 'Polish',
  'ro': 'Romanian',
  'ar': 'Arabic',
  'tr': 'Turkish',
};

/// Gets JSON from the local server. Swapped in tests.
Future<Object?> Function(String path) fetchServerJson = _serverJson;

Future<Object?> _serverJson(String path) async {
  if (!kIsWeb) {
    throw SongSourceError('Needs the app\'s local server.');
  }
  final bytes = await fetchBytes(path);
  if (bytes == null) {
    throw SongSourceError(
      "Couldn't reach the song database. It works when the app is opened "
      'from its local server.',
    );
  }
  final data = jsonDecode(utf8.decode(bytes));
  if (data is Map && data['error'] != null) {
    throw SongSourceError('${data['error']}');
  }
  return data;
}

Future<List<SongHit>> searchWorshipLeader(
  String query,
  List<String> langs,
) async {
  final data = await fetchServerJson(
    'songdb/search?q=${Uri.encodeQueryComponent(query.trim())}'
    '&langs=${langs.join(',')}',
  );
  if (data is! List) return const [];
  return [
    for (final r in data.whereType<Map>())
      SongHit(
        title: '${r['title'] ?? ''}',
        artist: '${r['author'] ?? ''}',
        source: worshipLeaderSite,
        url: 'https://worshipleaderapp.com/',
        lang: '${r['lang']}',
        id: (r['id'] as num?)?.toInt(),
      ),
  ];
}

Future<FoundSong> fetchWorshipLeaderSong(SongHit hit) async {
  final data = await fetchServerJson(
    'songdb/song?lang=${hit.lang}&id=${hit.id}',
  );
  if (data is! Map) throw SongSourceError("Couldn't read that song.");
  return worshipLeaderSong(data.cast<String, dynamic>(), hit.url);
}

const _verseTypes = {
  'v': 'Verse',
  'c': 'Chorus',
  'b': 'Bridge',
  'p': 'Pre-Chorus',
  'i': 'Intro',
  'e': 'Ending',
  'o': 'Other',
  't': 'Tag',
};

/// A song from the database (OpenLP's lyrics XML, chords inline) as
/// ChordPro, with its play order as the song structure.
FoundSong worshipLeaderSong(Map<String, dynamic> d, String url) {
  final lyrics = '${d['lyrics'] ?? ''}';
  final names = <String, String>{}; // "v1" → "Verse 1"
  final blocks = <String>[];
  final verse = RegExp(
    r'<verse([^>]*)>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</verse>',
    dotAll: true,
  );
  final counts = <String, int>{};
  final totals = <String, int>{};
  // A verse's code: type="v" label="1", or (newer OpenLP) name="v1".
  (String, String) codeOf(String attrs) {
    final name = RegExp(
      r'name="([a-z]+)(\d*)[a-z]?"',
      caseSensitive: false,
    ).firstMatch(attrs);
    final type =
        RegExp(r'type="([^"]*)"').firstMatch(attrs)?.group(1)?.toLowerCase() ??
        name?.group(1)!.toLowerCase() ??
        'v';
    final label =
        RegExp(r'label="([^"]*)"').firstMatch(attrs)?.group(1) ??
        name?.group(2) ??
        '';
    return (type, label);
  }

  for (final m in verse.allMatches(lyrics)) {
    final (t, _) = codeOf(m.group(1)!);
    totals[t] = (totals[t] ?? 0) + 1;
  }
  for (final m in verse.allMatches(lyrics)) {
    final (type, label) = codeOf(m.group(1)!);
    counts[type] = (counts[type] ?? 0) + 1;
    final base = _verseTypes[type] ?? 'Verse';
    // A lone chorus / bridge isn't numbered; verses always are.
    final name = type != 'v' && totals[type] == 1
        ? base
        : '$base ${label.isEmpty ? counts[type] : label}';
    names['$type$label'] = name;
    final text = _unescape(m.group(2)!)
        .replaceAll('[---]', '')
        .replaceAll(RegExp(r'\{/?[a-z]+\}'), '')
        .split('\n')
        .map((l) => l.trimRight())
        .join('\n')
        .trim();
    blocks.add('$name:\n$text');
  }
  // The play order, only if every part of it is known: one left out
  // would leave the song playing only the parts that are (e.g. only its
  // chorus). Otherwise it plays as written.
  final codes = [
    for (final code in '${d['verseOrder'] ?? ''}'.toLowerCase().split(
      RegExp(r'\s+'),
    ))
      if (code.isNotEmpty) code,
  ];
  // ("c" for "c1" and the other way round: a lone chorus has no number.)
  String? named(String c) =>
      names[c] ?? names['${c}1'] ?? names[c.replaceFirst(RegExp(r'1$'), '')];
  final order = !codes.every((c) => named(c) != null)
      ? <StructureItem>[]
      : [for (final code in codes) StructureItem.section(named(code)!)];
  return FoundSong(
    title: '${d['title'] ?? ''}',
    artist: '${d['author'] ?? ''}',
    raw: blocks.join('\n\n'),
    url: url,
    copyright: '${d['copyright'] ?? ''}',
    ccli: '${d['ccli'] ?? ''}',
    structure: order,
  );
}

// ---- Worship Together ----

const worshipTogetherSite = 'worshiptogether.com';

/// Song addresses from Worship Together's sitemap (kept for a day).
List<String>? _wtSlugs;
DateTime? _wtLoaded;
Map<String, int> _wtSuffixes = const {};

Future<List<String>> _worshipTogetherSlugs() async {
  final fresh =
      _wtLoaded != null &&
      DateTime.now().difference(_wtLoaded!) < const Duration(days: 1);
  if (_wtSlugs != null && fresh) return _wtSlugs!;
  final xml = await fetchPage('https://www.worshiptogether.com/sitemap-en.xml');
  _wtSlugs = worshipTogetherSlugs(xml);
  _wtSuffixes = _suffixCounts(_wtSlugs!);
  _wtLoaded = DateTime.now();
  return _wtSlugs!;
}

/// The songs in a sitemap ("in-the-end-chris-tomlin").
List<String> worshipTogetherSlugs(String sitemap) => {
  for (final m in RegExp(
    r'<loc>https://www\.worshiptogether\.com/songs/([a-z0-9-]+)/</loc>',
  ).allMatches(sitemap))
    m.group(1)!,
}.toList();

/// How many songs end with each 1–4 word ending (artists repeat).
Map<String, int> _suffixCounts(List<String> slugs) {
  final counts = <String, int>{};
  for (final slug in slugs) {
    final parts = slug.split('-');
    for (var k = 1; k <= 4 && k < parts.length; k++) {
      final end = parts.sublist(parts.length - k).join('-');
      counts[end] = (counts[end] ?? 0) + 1;
    }
  }
  return counts;
}

String _titleCase(String words) => words
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// "psalm-100-chris-tomlin" → ("Psalm 100", "Chris Tomlin"), using the
/// longest ending that several songs share as the artist.
(String, String) worshipTogetherName(String slug, Map<String, int> suffixes) {
  final parts = slug.split('-');
  for (var k = 4; k >= 1; k--) {
    if (k >= parts.length) continue;
    final end = parts.sublist(parts.length - k).join('-');
    if ((suffixes[end] ?? 0) >= 3) {
      return (
        _titleCase(parts.sublist(0, parts.length - k).join(' ')),
        _titleCase(end.replaceAll('-', ' ')),
      );
    }
  }
  return (_titleCase(parts.join(' ')), '');
}

Future<List<SongHit>> searchWorshipTogether(String query) async {
  final slugs = await _worshipTogetherSlugs();
  return matchWorshipTogether(slugs, _wtSuffixes, query);
}

/// Songs whose address has every word of [query], best matches first.
List<SongHit> matchWorshipTogether(
  List<String> slugs,
  Map<String, int> suffixes,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final scored = <(int, SongHit)>[];
  for (final slug in slugs) {
    final parts = slug.split('-');
    if (!words.every((w) => parts.any((p) => p.startsWith(w)))) continue;
    final (title, artist) = worshipTogetherName(slug, suffixes);
    final t = title.toLowerCase();
    final q = words.join(' ');
    final score = t == q
        ? 0
        : t.startsWith(q)
        ? 1
        : t.contains(q)
        ? 2
        : 3;
    scored.add((
      score * 1000 + title.length,
      SongHit(
        title: title,
        artist: artist,
        source: worshipTogetherSite,
        url: 'https://www.worshiptogether.com/songs/$slug/',
      ),
    ));
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in scored.take(25)) s.$2];
}

/// A Worship Together song page (its chord chart: lines of chord + lyric
/// pieces) as ChordPro.
FoundSong parseWorshipTogetherSong(String html, String url) {
  final lines = <String>[];
  // The chart's lines: the text from one "chord-pro-line" to the next.
  final chart = html.split('<div class="chord-pro-line">').skip(1).toList();
  if (chart.isNotEmpty) {
    // The last line runs until the chart ends.
    final last = chart.last;
    final end = last.indexOf(RegExp(r'</div>\s*</div>\s*</div>'));
    chart[chart.length - 1] = end < 0 ? last : last.substring(0, end + 12);
  }
  final segment = RegExp(
    r'<div class="chord-pro-note">(.*?)</div>\s*(?:<div class="chord-pro-lyric">(.*?)</div>)?',
    dotAll: true,
  );
  for (final l in chart) {
    final out = StringBuffer();
    var onlyChords = true;
    for (final s in segment.allMatches(l)) {
      final note = _clean(s.group(1)!);
      final lyric = _unescape(
        (s.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
      );
      if (lyric.trim().isNotEmpty) onlyChords = false;
      if (note.isNotEmpty) {
        // "C///" → [C] (rhythm slashes dropped).
        final chords = [
          for (final c in note.split(RegExp(r'\s+')))
            if (c.replaceAll(RegExp(r'/+$'), '').isNotEmpty)
              '[${c.replaceAll(RegExp(r'/+$'), '')}]',
        ];
        out.write(
          lyric.trim().isEmpty ? '${chords.join(' ')} ' : chords.join(),
        );
      }
      out.write(lyric);
    }
    var text = out.toString().replaceAll(' ', ' ').trimRight();
    final heading = _heading(text);
    if (onlyChords || heading == null) {
      lines.add(text);
    } else {
      if (lines.isNotEmpty && lines.last.trim().isNotEmpty) lines.add('');
      lines.add('$heading:');
    }
  }
  final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html);
  final name = _clean(title?.group(1) ?? '')
      .replaceAll(RegExp(r'\s*\|\s*Worship Together\s*$'), '');
  final dash = name.indexOf(RegExp(r' [–—-] '));
  final key = RegExp(r'data-original-key="([^"]*)"').firstMatch(html)?.group(1);
  return FoundSong(
    title: dash < 0 ? name : name.substring(0, dash).trim(),
    artist: dash < 0 ? '' : name.substring(dash + 3).trim(),
    raw: lines.join('\n').trim(),
    url: url,
    key: key ?? '',
  );
}

// ---- Every source ----

/// The sites searched, in the order results are shown.
const searchSites = [
  ugSite,
  worshipTogetherSite,
  worshipLeaderSite,
  catSite,
  chordieSite,
  cifraSite,
];

Future<List<SongHit>> searchSite(
  String site,
  String query, {
  List<String> langs = const ['en'],
}) => switch (site) {
  ugSite => searchUltimateGuitar(query),
  worshipTogetherSite => searchWorshipTogether(query),
  worshipLeaderSite => searchWorshipLeader(query, langs),
  catSite => searchChordsAndTabs(query),
  chordieSite => searchChordie(query),
  cifraSite => searchCifraClub(query),
  _ => Future.value(const []),
};

/// The song at [url] when it's on a site the app can read (a link shared
/// from the browser or a site's app), else null.
Future<FoundSong?> songFromLink(String url) async {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  final site = [
    ugSite,
    worshipTogetherSite,
    catSite,
    chordieSite,
  ].where((s) => host == s || host.endsWith('.$s')).firstOrNull;
  if (site == null) return null;
  return fetchSong(SongHit(title: '', artist: '', source: site, url: url));
}

/// The song behind a result (not for [SongHit.opensInBrowser] ones).
Future<FoundSong> fetchSong(SongHit hit) async => switch (hit.source) {
  ugSite => parseUltimateGuitarSong(await fetchPage(hit.url), hit.url),
  worshipTogetherSite => parseWorshipTogetherSong(
    await fetchPage(hit.url),
    hit.url,
  ),
  worshipLeaderSite => fetchWorshipLeaderSong(hit),
  catSite => parseChordsAndTabsSong(await fetchPage(hit.url), hit.url),
  chordieSite => fetchChordieSong(hit),
  _ => throw SongSourceError('Open this one in your browser.'),
};
