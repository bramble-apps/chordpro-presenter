// Bible text model and a schema-tolerant Bible XML parser, ported from the
// Bible XML Viewer (~/CascadeProjects/bible_xml_viewer/lib/bible/). Reads
// Zefania (XMLBIBLE/BIBLEBOOK/CHAPTER/VERS), Beblia (bible/book/chapter/
// verse), OSIS (div type=book, chapter, verse) and similar. Uses its own
// small XML tokenizer, so the app needs no XML package.
import 'dart:convert';
import 'dart:typed_data';

import 'books.dart';

class Verse {
  Verse(this.number, this.text)
    : numberValue =
          int.tryParse(number) ??
          int.tryParse(_digits.stringMatch(number) ?? '') ??
          0;

  final String number;
  final String text;
  final int numberValue;
}

class Chapter {
  Chapter(this.number, this.verses);

  final String number;
  final List<Verse> verses;

  int get numberValue => int.tryParse(number) ?? 0;
}

class BibleBook {
  BibleBook(this.number, this.name, List<Chapter> chapters)
    : _load = (() => chapters);

  /// A book whose chapters are read when first asked for.
  BibleBook.lazy(this.number, this.name, this._load);

  final List<Chapter> Function() _load;

  /// Canonical 1-66 number as a string when known, otherwise the file's id.
  final String number;

  /// The book's name, in the Bible's own language.
  final String name;
  late final List<Chapter> chapters = _load();

  Chapter? chapter(int n) {
    for (final c in chapters) {
      if (c.numberValue == n) return c;
    }
    return null;
  }
}

class Bible {
  Bible(this.books, {this.title, this.language});

  final List<BibleBook> books;
  final String? title;

  /// Language code ("en", "fr"…) when the file or its name says.
  final String? language;

  BibleBook? book(String number) {
    for (final b in books) {
      if (b.number == number) return b;
    }
    return null;
  }

  /// A book by its number, English name, abbreviation or its own name (or
  /// the start of it).
  BibleBook? bookNamed(String name) {
    final n = canonicalBookNumber(name);
    if (n != null && book('$n') != null) return book('$n');
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return null;
    for (final b in books) {
      if (b.name.toLowerCase() == lower) return b;
    }
    final starts = [
      for (final b in books)
        if (b.name.toLowerCase().startsWith(lower)) b,
    ];
    return starts.length == 1 ? starts.first : null;
  }

  int get verseCount => books.fold(
    0,
    (n, b) => n + b.chapters.fold(0, (m, c) => m + c.verses.length),
  );
}

/// Decodes XML bytes, honouring UTF-8/UTF-16 byte order marks and the
/// encoding in the XML declaration.
String decodeXmlBytes(Uint8List bytes) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes, 2, little: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes, 2, little: false);
    }
    // No BOM, but "<\0" / "\0<" means UTF-16.
    if (bytes[0] == 0x3C && bytes[1] == 0x00) {
      return _utf16(bytes, 0, little: true);
    }
    if (bytes[0] == 0x00 && bytes[1] == 0x3C) {
      return _utf16(bytes, 0, little: false);
    }
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final head = latin1.decode(
    bytes.sublist(start, bytes.length < 200 ? bytes.length : 200),
  );
  final enc = RegExp(r'''encoding=["']([^"']+)''')
      .firstMatch(head)
      ?.group(1)
      ?.toLowerCase();
  if (enc != null &&
      (enc.contains('8859-1') || enc == 'latin1' || enc.contains('1252'))) {
    return latin1.decode(bytes.sublist(start));
  }
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

String _utf16(Uint8List b, int start, {required bool little}) {
  final codes = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    codes.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(codes);
}

// ---- A small XML tokenizer (enough for Bible files) ----

sealed class _XmlEvent {}

class _Start extends _XmlEvent {
  _Start(this.name, this.attrs, this.selfClosing);

  /// Local name (no namespace prefix), upper case.
  final String name;

  /// Attributes by local name, lower case.
  final Map<String, String> attrs;
  final bool selfClosing;
}

class _End extends _XmlEvent {
  _End(this.name);
  final String name;
}

class _Text extends _XmlEvent {
  _Text(this.text);
  final String text;
}

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[A-Za-z]+);');
const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _unescape(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    if (e.startsWith('#x')) {
      return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 32);
    }
    if (e.startsWith('#')) {
      return String.fromCharCode(int.tryParse(e.substring(1)) ?? 32);
    }
    return _named[e] ?? m.group(0)!;
  });
}

String _local(String name) {
  final i = name.indexOf(':');
  return i < 0 ? name : name.substring(i + 1);
}

/// Whether the quotes in xml[from, to) are all closed.
bool _quotesClosed(String xml, int from, int to) {
  int? quote;
  for (var i = from; i < to; i++) {
    final c = xml.codeUnitAt(i);
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == 0x22 || c == 0x27) {
      quote = c;
    }
  }
  return quote == null;
}

final _attr = RegExp(r'''([^\s=/]+)\s*=\s*("([^"]*)"|'([^']*)')''');

Iterable<_XmlEvent> _events(String xml) sync* {
  var i = 0;
  final n = xml.length;
  while (i < n) {
    final lt = xml.indexOf('<', i);
    if (lt < 0) {
      yield _Text(_unescape(xml.substring(i)));
      return;
    }
    if (lt > i) yield _Text(_unescape(xml.substring(i, lt)));
    if (xml.startsWith('<!--', lt)) {
      final e = xml.indexOf('-->', lt + 4);
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      final e = xml.indexOf(']]>', lt + 9);
      yield _Text(xml.substring(lt + 9, e < 0 ? n : e));
      i = e < 0 ? n : e + 3;
      continue;
    }
    if (xml.startsWith('<?', lt) || xml.startsWith('<!', lt)) {
      final e = xml.indexOf('>', lt + 2);
      i = e < 0 ? n : e + 1;
      continue;
    }
    // A tag: its end (past any '>' inside a quoted attribute value).
    var j = xml.indexOf('>', lt + 1);
    if (j < 0) j = n;
    while (j < n && !_quotesClosed(xml, lt + 1, j)) {
      final next = xml.indexOf('>', j + 1);
      j = next < 0 ? n : next;
    }
    final body = xml.substring(lt + 1, j);
    i = j + 1;
    if (body.startsWith('/')) {
      yield _End(_local(body.substring(1).trim()).toUpperCase());
      continue;
    }
    final selfClosing = body.endsWith('/');
    final inner = selfClosing ? body.substring(0, body.length - 1) : body;
    var sp = 0;
    while (sp < inner.length && inner.codeUnitAt(sp) > 32) {
      sp++;
    }
    if (sp == inner.length) sp = -1;
    final name = sp < 0 ? inner : inner.substring(0, sp);
    final attrs = <String, String>{};
    if (sp >= 0) {
      for (final m in _attr.allMatches(inner.substring(sp))) {
        attrs[_local(m.group(1)!).toLowerCase()] = _unescape(
          m.group(3) ?? m.group(4) ?? '',
        );
      }
    }
    yield _Start(_local(name).toUpperCase(), attrs, selfClosing);
  }
}

// ---- The parser ----

// (Made once: building a RegExp per verse is slow on the web.)
final _digits = RegExp(r'\d+');
final _onlyDigits = RegExp(r'^\d+$');
final _spaces = RegExp(r'\s+');
final _nonDigitStart = RegExp(r'^\D');

bool _digitsOnly(String s) => s.isNotEmpty && _onlyDigits.hasMatch(s);

String? _first(Map<String, String> attrs, List<String> keys) {
  for (final k in keys) {
    final v = attrs[k];
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

String? _numberFromOsisId(String? id) {
  if (id == null) return null;
  final last = id.split('.').last;
  return RegExp(r'\d+').stringMatch(last);
}

/// Elements whose text is not part of the verse (footnotes, cross references).
const _skippedElements = {'NOTE', 'RF', 'FOOTNOTE', 'XREF', 'REMARK', 'F', 'X'};

/// A book as read, before its number and name are settled.
class _RawBook {
  _RawBook(this.number, this.name, this.short, this.chapters);
  final String number;
  final String? name, short;
  final List<Chapter> chapters;
}

/// Whether a book name from a file is a real name, not a number or a short
/// id ("Gen", "1SA", "AddEsth").
bool _realName(String? name, String? short, String number) {
  if (name == null) return false;
  final n = name.trim();
  if (n.length < 3 || _digitsOnly(n) || n == number || n == short) return false;
  if (!RegExp(r'[a-zà-ÿ]').hasMatch(n)) return n.contains(' ');
  return !RegExp(r'^[0-9]?[A-Z][a-z]+[A-Z][a-z]*$').hasMatch(n); // AddEsth
}

bool _isVerse(String name) => name == 'VERSE' || name == 'VERS' || name == 'V';

/// Parses a whole Bible. Throws [FormatException] if no verses are found.
/// [languageHint] (a file or version name) helps name the books when the
/// file doesn't.
Bible parseBibleXml(String xml, {String? languageHint}) {
  final raw = <_RawBook>[];
  String? title;
  String? language; // from the file: Zefania <language>, OSIS xml:lang
  var inLanguage = false;

  String? bookNumber;
  String? bookName;
  String? bookShort;
  List<Chapter>? chapters;
  String? chapterNumber;
  List<Verse>? verses;
  String? verseNumber;
  StringBuffer? verseText;
  var verseDepth = 0;
  var skipDepth = 0;
  var bookElement = '';
  var chapterless = <Verse>[]; // verses directly in a book (OSIS milestones)

  void finishVerse() {
    if (verseNumber != null && verseText != null) {
      final text = verseText.toString().replaceAll(_spaces, ' ').trim();
      (verses ?? chapterless).add(Verse(verseNumber!, text));
    }
    verseNumber = null;
    verseText = null;
    verseDepth = 0;
  }

  void finishChapter() {
    finishVerse();
    if (chapters != null && verses != null) {
      final number = chapterNumber ?? '${chapters!.length + 1}';
      // A chapter that appears twice (split, or repeated, in the file): one
      // chapter, with each verse once.
      final same = chapters!.where((c) => c.number == number).firstOrNull;
      if (same != null) {
        final have = {for (final v in same.verses) v.number};
        same.verses.addAll(verses!.where((v) => !have.contains(v.number)));
      } else if (verses!.isNotEmpty) {
        chapters!.add(Chapter(number, verses!));
      }
    }
    verses = null;
    chapterNumber = null;
  }

  void finishBook() {
    finishChapter();
    if (chapters != null && bookNumber != null) {
      if (chapters!.isEmpty && chapterless.isNotEmpty) {
        chapters!.add(Chapter('1', chapterless));
      }
      if (chapters!.isNotEmpty) {
        raw.add(_RawBook(bookNumber!, bookName, bookShort, chapters!));
      }
    }
    bookNumber = null;
    bookName = null;
    bookShort = null;
    chapters = null;
    chapterless = <Verse>[];
    bookElement = '';
  }

  for (final event in _events(xml)) {
    switch (event) {
      case _Start(:final name, :final attrs, :final selfClosing):
        if (verseDepth > 0) {
          if (skipDepth > 0 || _skippedElements.contains(name)) {
            if (!selfClosing) skipDepth++;
            continue;
          }
          // OSIS milestone: <verse sID=.../> starts, <verse eID=.../> ends.
          if (_isVerse(name) && attrs.containsKey('eid')) {
            finishVerse();
            continue;
          }
          if (!_isVerse(name)) {
            if (!selfClosing) verseDepth++;
            continue;
          }
        }

        if (name == 'XMLBIBLE' || name == 'BIBLE') {
          title ??= _first(attrs, ['biblename', 'translation', 'name']);
        }
        language ??= _first(attrs, ['lang', 'language']);
        if (name == 'LANGUAGE' && bookNumber == null) {
          inLanguage = !selfClosing;
          continue;
        }

        if (bookNumber == null &&
            (name == 'BIBLEBOOK' ||
                name == 'BOOK' ||
                (name == 'DIV' && attrs['type']?.toLowerCase() == 'book'))) {
          final rawNumber = _first(attrs, [
            'bnumber',
            'bnum',
            'booknumber',
            'book',
            'number',
            'id',
            'code',
          ]);
          bookName =
              _first(attrs, ['bname', 'bookname', 'name', 'title']) ??
              _first(attrs, ['osisid']);
          bookShort = _first(attrs, [
            'bsname',
            'short',
            'abbr',
            'abbreviation',
            'osisid',
          ]);
          bookNumber =
              rawNumber ??
              _first(attrs, ['osisid']) ??
              bookName ??
              '${raw.length + 1}';
          chapters = [];
          bookElement = name;
          continue;
        }

        if (name == 'CHAPTER' || name == 'C') {
          finishChapter();
          if (attrs.containsKey('eid')) continue;
          chapters ??= [];
          bookNumber ??= '${raw.length + 1}';
          chapterNumber =
              _first(attrs, [
                'cnumber',
                'cnum',
                'chapternumber',
                'chapter',
                'number',
                'n',
                'id',
              ]) ??
              _numberFromOsisId(_first(attrs, ['osisid', 'sid']));
          if (chapterNumber != null && !_digitsOnly(chapterNumber!)) {
            chapterNumber =
                RegExp(r'\d+')
                    .allMatches(chapterNumber!)
                    .lastOrNull
                    ?.group(0) ??
                chapterNumber;
          }
          verses = [];
          continue;
        }

        if (_isVerse(name)) {
          finishVerse();
          var n =
              _first(attrs, [
                'vnumber',
                'vnum',
                'versenumber',
                'verse',
                'number',
                'n',
                'id',
              ]) ??
              _numberFromOsisId(_first(attrs, ['osisid', 'sid']));
          n ??= _first(attrs, ['bcv'])?.split('.').last;
          if (n != null && !_digitsOnly(n) && _nonDigitStart.hasMatch(n)) {
            n = _digits.allMatches(n).lastOrNull?.group(0) ?? n;
          }
          if (selfClosing && !attrs.containsKey('sid')) continue;
          verseNumber = n ?? '${(verses ?? chapterless).length + 1}';
          verseText = StringBuffer();
          verseDepth = 1;
          continue;
        }
      case _End(:final name):
        if (name == 'LANGUAGE') inLanguage = false;
        if (skipDepth > 0) {
          skipDepth--;
          continue;
        }
        if (verseDepth > 1) {
          verseDepth--;
          continue;
        }
        if (_isVerse(name)) {
          finishVerse();
        } else if (name == 'CHAPTER' || name == 'C') {
          finishChapter();
        } else if (name == bookElement && bookNumber != null) {
          finishBook();
        }
      case _Text(:final text):
        if (inLanguage && text.trim().isNotEmpty) {
          language ??= text.trim();
        }
        if (verseDepth > 0 && skipDepth == 0) verseText?.write(text);
    }
  }
  finishBook();

  if (raw.isEmpty) {
    throw const FormatException('No books or verses found in this XML file.');
  }
  final lang =
      bibleLanguage(language) ??
      bibleLanguage(title) ??
      bibleLanguage(languageHint);
  final localized = localizedBookNames[lang];

  // Numbers and names, once the language is known. The 66 books get 1-66,
  // the Apocrypha 67 and up, anything else keeps its own id.
  final books = <BibleBook>[];
  final used = <String>{};
  for (final r in raw) {
    final deutero =
        (int.tryParse(r.number) ?? 0) > 66 || int.tryParse(r.number) == null
        ? deuterocanonicalIndex(name: r.name, short: r.short, number: r.number)
        : null;
    final canon = deutero != null
        ? null
        : canonicalBookNumber(r.number) ??
              (r.short != null ? canonicalBookNumber(r.short!) : null) ??
              (r.name != null ? canonicalBookNumber(r.name!) : null);
    var id = canon != null
        ? '$canon'
        : deutero != null
        ? deuterocanonicalNumber(deutero)
        : r.number;
    final english = canon != null
        ? canonicalBooks[canon - 1]
        : deutero != null
        ? deuterocanonicalBooks[deutero].$1
        : null;
    final real = _realName(r.name, r.short, r.number);
    final String name;
    if (lang == null || lang == 'en') {
      name =
          english ??
          (real
              ? r.name!.trim()
              : (defaultBookNameForShortId(r.number) ?? r.name ?? r.number));
    } else {
      name = real
          ? r.name!.trim()
          : (canon != null && localized != null
                    ? localized[canon - 1]
                    : null) ??
                english ??
                r.name ??
                r.number;
    }
    // Two books with the same number: keep both.
    if (used.contains(id)) {
      final base = id;
      for (var i = 2; used.contains(id); i++) {
        id = '$base-$i';
      }
    }
    used.add(id);
    final chapters = [...r.chapters];
    if (chapters.every((c) => int.tryParse(c.number) != null)) {
      chapters.sort(
        (a, b) => int.parse(a.number).compareTo(int.parse(b.number)),
      );
    }
    books.add(BibleBook(id, name, chapters));
  }
  return Bible(books, title: title, language: lang);
}

final _bookStart = RegExp(
  r'''<(?:BIBLEBOOK|BOOK)(?=[\s>])|<div\s[^>]*type\s*=\s*["']book["']''',
  caseSensitive: false,
);
final _tagName = RegExp(r'^<([^\s>]+)');

/// [parseBibleXml], but quick to open: the books are found first and each
/// one's text is read only when it is opened (a whole Bible takes seconds
/// to read in a browser). Files it can't split are read whole.
Bible openBibleXml(String xml, {String? languageHint}) {
  final starts = [for (final m in _bookStart.allMatches(xml)) m.start];
  if (starts.length < 2) return parseBibleXml(xml, languageHint: languageHint);
  // The file with one stand-in verse per book: its books' numbers and
  // names, settled as for the whole file.
  final skeleton = StringBuffer(xml.substring(0, starts.first));
  final slices = <String>[];
  for (var i = 0; i < starts.length; i++) {
    final slice = xml.substring(
      starts[i],
      i + 1 < starts.length ? starts[i + 1] : xml.length,
    );
    final gt = slice.indexOf('>');
    final tag = _tagName.firstMatch(slice)?.group(1);
    if (gt < 0 || tag == null || slice[gt - 1] == '/') {
      return parseBibleXml(xml, languageHint: languageHint);
    }
    skeleton.write(
      '${slice.substring(0, gt + 1)}'
      '<CHAPTER cnumber="1"><VERS vnumber="1">x</VERS></CHAPTER></$tag>',
    );
    slices.add(slice);
  }
  final Bible head;
  try {
    head = parseBibleXml(skeleton.toString(), languageHint: languageHint);
  } on FormatException {
    return parseBibleXml(xml, languageHint: languageHint);
  }
  if (head.books.length != slices.length) {
    return parseBibleXml(xml, languageHint: languageHint);
  }
  return Bible(
    [
      for (final (i, b) in head.books.indexed)
        BibleBook.lazy(b.number, b.name, () {
          try {
            return parseBibleXml(slices[i]).books.first.chapters;
          } on FormatException {
            return [];
          }
        }),
    ],
    title: head.title,
    language: head.language,
  );
}
