import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bible/bible_xml.dart';
import 'bible/books.dart';
import 'browser.dart';
import 'chordpro.dart';

export 'bible/bible_xml.dart' show Bible, BibleBook, Chapter, Verse;

/// Bible passages for the presentation mode's Bible tool: versions (two
/// bundled, more imported from Bible XML files), the passage queue, and
/// passages as slides (each slide a few verses, a second version beside
/// it like a song's translation).

/// A Bible version the app can show.
class BibleVersionInfo {
  /// Short name ("WEB", "KJV", "LSG"); also the tag on its slides.
  final String id;
  final String name;

  /// Bundled versions: the asset holding the XML.
  final String? asset;

  const BibleVersionInfo(this.id, this.name, {this.asset});

  bool get bundled => asset != null;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// A run of verses in one chapter, in one version (and maybe a second
/// version beside it).
class BiblePassage {
  final String version;
  final String? second;

  /// Book number ("43" for John), as [Bible.book] takes it.
  final String book;
  final int chapter;
  final int from;
  final int to;

  /// Verses on each slide.
  final int perSlide;

  const BiblePassage({
    required this.version,
    this.second,
    required this.book,
    required this.chapter,
    required this.from,
    required this.to,
    this.perSlide = 2,
  });

  BiblePassage copyWith({
    String? version,
    String? second,
    bool noSecond = false,
    int? perSlide,
  }) => BiblePassage(
    version: version ?? this.version,
    second: noSecond ? null : (second ?? this.second),
    book: book,
    chapter: chapter,
    from: from,
    to: to,
    perSlide: perSlide ?? this.perSlide,
  );

  /// The book's English name (the version's own comes from [referenceIn]).
  String get bookName =>
      defaultBookNameForNumber(book) ?? canonicalBookName(book) ?? book;

  String get verses => from == to ? '$from' : '$from–$to';

  /// "John 3:16–18".
  String get reference => '$bookName $chapter:$verses';

  /// "Jean 3:16–18" in [bible]'s own book names.
  String referenceIn(Bible? bible) =>
      '${bible?.book(book)?.name ?? bookName} $chapter:$verses';

  /// "WEB" or "WEB + KJV".
  String get versions => second == null ? version : '$version + $second';

  /// Same verses and versions (an id for its slides).
  String get key =>
      '$version|${second ?? ''}|$book|$chapter|$from|$to|$perSlide';

  Map<String, dynamic> toJson() => {
    'version': version,
    if (second != null) 'second': second,
    'book': book,
    'chapter': chapter,
    'from': from,
    'to': to,
    'perSlide': perSlide,
  };

  static BiblePassage? fromJson(Object? j) {
    if (j is! Map) return null;
    final version = j['version'], book = j['book'];
    if (version is! String || book is! String) return null;
    int n(Object? v, int fallback) => (v as num?)?.toInt() ?? fallback;
    final from = n(j['from'], 1);
    return BiblePassage(
      version: version,
      second: j['second'] as String?,
      book: book,
      chapter: n(j['chapter'], 1),
      from: from,
      to: n(j['to'], from),
      perSlide: n(j['perSlide'], 2).clamp(1, 10),
    );
  }

  @override
  bool operator ==(Object other) => other is BiblePassage && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

String? canonicalBookName(String number) {
  final n = int.tryParse(number);
  return n != null && n >= 1 && n <= canonicalBooks.length
      ? canonicalBooks[n - 1]
      : null;
}

/// A passage typed as text: "John 3:16-18", "Jn 3", "1 Cor 13:4–7",
/// "Ps 23.1-3". [bible] also knows its own book names ("Jean 3:16").
/// Null when the book or chapter isn't there. A missing end verse is the
/// start verse; a chapter alone is the whole chapter.
({String book, int chapter, int from, int to})? parsePassage(
  String input,
  Bible bible,
) {
  final text = input.trim().replaceAll(RegExp(r'[–—]'), '-');
  // Split off the range end: "3:16-18" → "3:16" and 18.
  final range = RegExp(r'^(.*?\d)\s*-\s*(\d+)\s*$').firstMatch(text);
  final head = range?.group(1) ?? text;
  int? end = range == null ? null : int.parse(range.group(2)!);
  final ref = parseDirectReference(head);
  BibleBook? book;
  int? chapter, verse;
  if (ref != null) {
    book = bible.book('${ref.bookNumber}');
    chapter = ref.chapter;
    verse = ref.verse;
  }
  if (book == null) {
    // The version's own book name: "Jean 3:16", "1 Jean 4".
    final m = RegExp(r'^(\d?\s*\D+?)\s*(\d+)(?:\s*[:.,]\s*(\d+))?$')
        .firstMatch(head);
    if (m != null) {
      book = bible.bookNamed(m.group(1)!.trim());
      chapter = int.parse(m.group(2)!);
      verse = m.group(3) == null ? null : int.parse(m.group(3)!);
    }
  }
  if (book == null || chapter == null) return null;
  final ch = book.chapter(chapter);
  if (ch == null || ch.verses.isEmpty) return null;
  final last = ch.verses.last.numberValue;
  // "John 3-4" (chapters) isn't a verse range: the whole chapter.
  if (verse == null) end = null;
  final from = (verse ?? ch.verses.first.numberValue).clamp(1, last);
  final to = (end ?? (verse ?? last)).clamp(from, last);
  return (book: book.number, chapter: chapter, from: from, to: to);
}

/// Text that is safe as song lines: no chords, directives, or a colon at
/// the end (which would make the line a section label).
String _safeLine(String s) {
  var t = s
      .replaceAll('[', '(')
      .replaceAll(']', ')')
      .replaceAll('{', '(')
      .replaceAll('}', ')')
      .trim();
  if (t.endsWith(':')) t = '$t​';
  return t;
}

const _superscript = ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'];

/// "16" → "¹⁶".
String superscriptNumber(int n) =>
    '$n'.split('').map((d) => _superscript[int.parse(d)]).join();

/// The verses of [p] in [bible] (those it has).
List<Verse> passageVerses(BiblePassage p, Bible bible) {
  final ch = bible.book(p.book)?.chapter(p.chapter);
  if (ch == null) return const [];
  return [
    for (final v in ch.verses)
      if (v.numberValue >= p.from && v.numberValue <= p.to) v,
  ];
}

/// [p] as song text: a section per slide ([BiblePassage.perSlide] verses),
/// named by its verses; with a second version, its section follows,
/// linked so the two show together (like a song's translation).
({String title, String raw, List<StructureItem> structure}) passageText(
  BiblePassage p,
  Bible bible, {
  Bible? second,
  bool numbers = true,
  bool reference = true,
}) {
  final verses = passageVerses(p, bible);
  final other = second == null ? const <Verse>[] : passageVerses(p, second);
  final lines = <String>[];
  final structure = <StructureItem>[];
  final step = p.perSlide.clamp(1, 10);

  void section(String name, String tag, List<Verse> group, String ref) {
    lines.add('$name ($tag):');
    for (final v in group) {
      final text = _safeLine(v.text);
      lines.add(numbers ? '${superscriptNumber(v.numberValue)} $text' : text);
    }
    if (reference) lines.add(_safeLine('$ref $tag'));
    lines.add('');
  }

  for (var i = 0; i < verses.length; i += step) {
    final group = verses.sublist(i, (i + step).clamp(0, verses.length));
    final a = group.first.numberValue, b = group.last.numberValue;
    final span = a == b ? '$a' : '$a–$b';
    final name = '${p.bookName} ${p.chapter}:$span';
    section(
      name,
      p.version,
      group,
      '${bible.book(p.book)?.name ?? p.bookName} ${p.chapter}:$span',
    );
    final match = [
      for (final v in other)
        if (v.numberValue >= a && v.numberValue <= b) v,
    ];
    if (second != null && match.isNotEmpty) {
      structure.add(
        StructureItem.section('$name (${p.version})', linked: true),
      );
      section(
        name,
        p.second!,
        match,
        '${second.book(p.book)?.name ?? p.bookName} ${p.chapter}:$span',
      );
      structure.add(StructureItem.section('$name (${p.second})'));
    } else {
      structure.add(StructureItem.section('$name (${p.version})'));
    }
  }
  return (
    title: p.referenceIn(bible),
    raw: lines.join('\n').trimRight(),
    structure: structure,
  );
}

/// The versions, the queue and the tool's choices (remembered here, not
/// in the song library).
class BibleLibrary extends ChangeNotifier {
  BibleLibrary._();
  static final BibleLibrary instance = BibleLibrary._();

  static const bundledVersions = [
    BibleVersionInfo(
      'WEB',
      'World English Bible',
      asset: 'assets/bibles/WEB.xml',
    ),
    BibleVersionInfo(
      'KJV',
      'King James Version',
      asset: 'assets/bibles/KJV.xml',
    ),
  ];

  final List<BibleVersionInfo> _imported = [];
  final Map<String, Future<Bible>> _loading = {};
  final KeyValueStore _store = KeyValueStore();
  bool _ready = false;
  Future<void>? _starting;

  List<BibleVersionInfo> get versions => [...bundledVersions, ..._imported];

  BibleVersionInfo? versionById(String? id) =>
      versions.where((v) => v.id == id).firstOrNull;

  /// Passages lined up to show one after another.
  final List<BiblePassage> queue = [];

  /// The tool's last choices.
  String version = 'WEB';
  String? second;
  int perSlide = 2;
  bool numbers = true;
  bool reference = true;
  BiblePassage? last;

  /// Reads the imported versions and the queue (once).
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      final j = jsonDecode(await _store.read('bible.state') ?? '{}');
      if (j is Map) {
        for (final v in (j['imported'] as List?) ?? const []) {
          if (v is Map && v['id'] is String) {
            _imported.add(
              BibleVersionInfo(v['id'] as String, '${v['name'] ?? v['id']}'),
            );
          }
        }
        queue.addAll(
          ((j['queue'] as List?) ?? const [])
              .map(BiblePassage.fromJson)
              .nonNulls,
        );
        version = (j['version'] as String?) ?? version;
        second = j['second'] as String?;
        perSlide = ((j['perSlide'] as num?)?.toInt() ?? 2).clamp(1, 10);
        numbers = j['numbers'] != false;
        reference = j['reference'] != false;
        last = BiblePassage.fromJson(j['last']);
      }
    } catch (_) {}
    if (versionById(version) == null) version = 'WEB';
    if (versionById(second) == null || second == version) second = null;
    _ready = true;
    notifyListeners();
  }

  bool get ready => _ready;

  void save() {
    notifyListeners();
    if (!_ready) return;
    unawaited(
      _store.write(
        'bible.state',
        jsonEncode({
          'imported': [for (final v in _imported) v.toJson()],
          'queue': [for (final p in queue) p.toJson()],
          'version': version,
          'second': ?second,
          'perSlide': perSlide,
          'numbers': numbers,
          'reference': reference,
          'last': ?last?.toJson(),
        }),
      ),
    );
  }

  /// The version's text (read once, then kept).
  Future<Bible> load(String id) {
    final info = versionById(id);
    if (info == null) return Future.error(StateError('No Bible "$id"'));
    return _loading[id] ??=
        () async {
          final Uint8List bytes;
          if (info.asset != null) {
            final data = await rootBundle.load(info.asset!);
            bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          } else {
            final stored = await _store.readBytes('bible.xml.$id');
            if (stored == null) throw StateError('The $id file is missing');
            bytes = stored;
          }
          return openBibleXml(decodeXmlBytes(bytes), languageHint: info.name);
        }()..catchError((Object _) {
          _loading.remove(id);
          return Bible(const []);
        });
  }

  /// Adds the Bible in [bytes] (an XML file called [fileName]). Returns
  /// its version; throws [FormatException] when it isn't a Bible.
  Future<BibleVersionInfo> importXml(String fileName, Uint8List bytes) async {
    final bible = openBibleXml(decodeXmlBytes(bytes), languageHint: fileName);
    if (bible.books.first.chapters.isEmpty) {
      throw const FormatException('No verses found in this XML file.');
    }
    final stem = fileName
        .split('/')
        .last
        .replaceAll(RegExp(r'\.(xml|zef|osis)$', caseSensitive: false), '');
    final id = uniqueVersionId(versionIdFor(bible.title, stem));
    final info = BibleVersionInfo(
      id,
      (bible.title?.trim().isNotEmpty ?? false) ? bible.title!.trim() : stem,
    );
    await _store.writeBytes('bible.xml.$id', bytes);
    _imported.add(info);
    _loading[id] = Future.value(bible);
    save();
    return info;
  }

  /// Removes an imported version (and the passages in the queue using it).
  Future<void> remove(String id) async {
    final i = _imported.indexWhere((v) => v.id == id);
    if (i < 0) return;
    _imported.removeAt(i);
    _loading.remove(id);
    queue.removeWhere((p) => p.version == id || p.second == id);
    if (version == id) version = 'WEB';
    if (second == id) second = null;
    await _store.delete('bible.xml.$id');
    save();
  }

  String uniqueVersionId(String base) {
    var id = base;
    for (var n = 2; versionById(id) != null; n++) {
      id = '$base$n';
    }
    return id;
  }

  // ---- Queue ----

  void enqueue(BiblePassage p) {
    queue.add(p);
    save();
  }

  void dequeue(int i) {
    if (i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    save();
  }

  /// Moves the passage at [from] to [to] (its index afterwards).
  void reorder(int from, int to) {
    if (from < 0 || from >= queue.length) return;
    final p = queue.removeAt(from);
    queue.insert(to.clamp(0, queue.length), p);
    save();
  }

  void clearQueue() {
    queue.clear();
    save();
  }

  @visibleForTesting
  void resetForTest() {
    _imported.clear();
    _loading.clear();
    queue.clear();
    version = 'WEB';
    second = null;
    perSlide = 2;
    last = null;
    _starting = null;
    _ready = false;
  }

  @visibleForTesting
  void putForTest(String id, Bible bible, {String? name}) {
    if (versionById(id) == null) {
      _imported.add(BibleVersionInfo(id, name ?? id));
    }
    _loading[id] = Future.value(bible);
  }
}

/// A short tag for a version: the letters of a short title ("LSG",
/// "NEG79"), else the file name's.
String versionIdFor(String? title, String fileName) {
  String tag(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final t = title == null ? '' : tag(title);
  if (t.isNotEmpty && t.length <= 8) return t;
  final f = tag(fileName);
  if (f.isNotEmpty && f.length <= 8) return f;
  final words = (title?.trim().isNotEmpty ?? false ? title! : fileName)
      .split(RegExp(r'[\s_\-.]+'))
      .where((w) => w.isNotEmpty);
  final initials = tag(words.map((w) => w[0]).join());
  return initials.isEmpty
      ? 'BIBLE'
      : initials.substring(0, initials.length.clamp(0, 6));
}
