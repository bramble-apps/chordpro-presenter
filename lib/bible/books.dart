// Book names, numbers and references. Copied from the Bible XML Viewer
// (~/CascadeProjects/bible_xml_viewer/lib/bible/books.dart).
// Book names, abbreviations and reference parsing (ported from ContentView.swift).

const List<String> canonicalBooks = [
  'Genesis',
  'Exodus',
  'Leviticus',
  'Numbers',
  'Deuteronomy',
  'Joshua',
  'Judges',
  'Ruth',
  '1 Samuel',
  '2 Samuel',
  '1 Kings',
  '2 Kings',
  '1 Chronicles',
  '2 Chronicles',
  'Ezra',
  'Nehemiah',
  'Esther',
  'Job',
  'Psalms',
  'Proverbs',
  'Ecclesiastes',
  'Song of Solomon',
  'Isaiah',
  'Jeremiah',
  'Lamentations',
  'Ezekiel',
  'Daniel',
  'Hosea',
  'Joel',
  'Amos',
  'Obadiah',
  'Jonah',
  'Micah',
  'Nahum',
  'Habakkuk',
  'Zephaniah',
  'Haggai',
  'Zechariah',
  'Malachi',
  'Matthew',
  'Mark',
  'Luke',
  'John',
  'Acts',
  'Romans',
  '1 Corinthians',
  '2 Corinthians',
  'Galatians',
  'Ephesians',
  'Philippians',
  'Colossians',
  '1 Thessalonians',
  '2 Thessalonians',
  '1 Timothy',
  '2 Timothy',
  'Titus',
  'Philemon',
  'Hebrews',
  'James',
  '1 Peter',
  '2 Peter',
  '1 John',
  '2 John',
  '3 John',
  'Jude',
  'Revelation',
];

String? defaultBookNameForNumber(String number) {
  final n = int.tryParse(number);
  if (n == null || n < 1 || n > canonicalBooks.length) return null;
  return canonicalBooks[n - 1];
}

const Map<String, String> _shortIds = {
  'GEN': 'Genesis',
  'EXO': 'Exodus',
  'LEV': 'Leviticus',
  'NUM': 'Numbers',
  'DEU': 'Deuteronomy',
  'JOS': 'Joshua',
  'JDG': 'Judges',
  'RUT': 'Ruth',
  '1SA': '1 Samuel',
  '2SA': '2 Samuel',
  '1KI': '1 Kings',
  '2KI': '2 Kings',
  '1CH': '1 Chronicles',
  '2CH': '2 Chronicles',
  'EZR': 'Ezra',
  'NEH': 'Nehemiah',
  'EST': 'Esther',
  'JOB': 'Job',
  'PSA': 'Psalms',
  'PRO': 'Proverbs',
  'ECC': 'Ecclesiastes',
  'SNG': 'Song of Solomon',
  'ISA': 'Isaiah',
  'JER': 'Jeremiah',
  'LAM': 'Lamentations',
  'EZE': 'Ezekiel',
  'EZK': 'Ezekiel',
  'DAN': 'Daniel',
  'HOS': 'Hosea',
  'JOL': 'Joel',
  'JOE': 'Joel',
  'AMO': 'Amos',
  'OBA': 'Obadiah',
  'JON': 'Jonah',
  'MIC': 'Micah',
  'NAM': 'Nahum',
  'NAH': 'Nahum',
  'HAB': 'Habakkuk',
  'ZEP': 'Zephaniah',
  'HAG': 'Haggai',
  'ZEC': 'Zechariah',
  'MAL': 'Malachi',
  'MAT': 'Matthew',
  'MRK': 'Mark',
  'MAR': 'Mark',
  'LUK': 'Luke',
  'JHN': 'John',
  'JOH': 'John',
  'ACT': 'Acts',
  'ROM': 'Romans',
  '1CO': '1 Corinthians',
  '2CO': '2 Corinthians',
  'GAL': 'Galatians',
  'EPH': 'Ephesians',
  'PHP': 'Philippians',
  'PHI': 'Philippians',
  'COL': 'Colossians',
  '1TH': '1 Thessalonians',
  '2TH': '2 Thessalonians',
  '1TI': '1 Timothy',
  '2TI': '2 Timothy',
  'TIT': 'Titus',
  'PHM': 'Philemon',
  'HEB': 'Hebrews',
  'JAS': 'James',
  'JAM': 'James',
  '1PE': '1 Peter',
  '2PE': '2 Peter',
  '1JO': '1 John',
  '1JN': '1 John',
  '2JO': '2 John',
  '2JN': '2 John',
  '3JO': '3 John',
  '3JN': '3 John',
  'JUD': 'Jude',
  'JDE': 'Jude',
  'REV': 'Revelation',
  'TOB': 'Tobit',
  'JDT': 'Judith',
  'ESG': 'Esther (Greek)',
  'WIS': 'Wisdom of Solomon',
  'SIR': 'Sirach',
  'BAR': 'Baruch',
  '1MA': '1 Maccabees',
  '2MA': '2 Maccabees',
  'MAN': 'Prayer of Manasseh',
  'PS2': 'Psalm 151',
  '3MA': '3 Maccabees',
  '4ES': '4 Ezra',
  '1ES': '1 Ezra',
  '2ES': '2 Ezra',
  'ODA': 'Odes',
  'PSS': 'Psalms of Solomon',
  'LBA': 'Letter of Baruch',
  'EPI': 'Epistle of Jeremiah',
};

/// OSIS book IDs (Gen, Exod, 1Sam, ...).
const List<String> _osisIds = [
  'Gen',
  'Exod',
  'Lev',
  'Num',
  'Deut',
  'Josh',
  'Judg',
  'Ruth',
  '1Sam',
  '2Sam',
  '1Kgs',
  '2Kgs',
  '1Chr',
  '2Chr',
  'Ezra',
  'Neh',
  'Esth',
  'Job',
  'Ps',
  'Prov',
  'Eccl',
  'Song',
  'Isa',
  'Jer',
  'Lam',
  'Ezek',
  'Dan',
  'Hos',
  'Joel',
  'Amos',
  'Obad',
  'Jonah',
  'Mic',
  'Nah',
  'Hab',
  'Zeph',
  'Hag',
  'Zech',
  'Mal',
  'Matt',
  'Mark',
  'Luke',
  'John',
  'Acts',
  'Rom',
  '1Cor',
  '2Cor',
  'Gal',
  'Eph',
  'Phil',
  'Col',
  '1Thess',
  '2Thess',
  '1Tim',
  '2Tim',
  'Titus',
  'Phlm',
  'Heb',
  'Jas',
  '1Pet',
  '2Pet',
  '1John',
  '2John',
  '3John',
  'Jude',
  'Rev',
];

String? defaultBookNameForShortId(String id) => _shortIds[id.toUpperCase()];

/// The canonical 1-66 number for a book attribute (number, short id, OSIS id
/// or name), or null when it isn't one of the 66.
int? canonicalBookNumber(String raw) {
  final s = raw.trim();
  final n = int.tryParse(s);
  if (n != null) return n >= 1 && n <= 66 ? n : null;
  final osis = _osisIds.indexWhere((o) => o.toLowerCase() == s.toLowerCase());
  if (osis >= 0) return osis + 1;
  final name = _shortIds[s.toUpperCase()] ?? resolveBookName(s);
  if (name == null) return null;
  final i = canonicalBooks.indexOf(name);
  return i >= 0 ? i + 1 : null;
}

const Map<String, String> bookAbbreviations = {
  'g': 'Genesis',
  'ge': 'Genesis',
  'gen': 'Genesis',
  'gn': 'Genesis',
  'ex': 'Exodus',
  'exo': 'Exodus',
  'exod': 'Exodus',
  'lv': 'Leviticus',
  'le': 'Leviticus',
  'lev': 'Leviticus',
  'nu': 'Numbers',
  'nm': 'Numbers',
  'num': 'Numbers',
  'nb': 'Numbers',
  'dt': 'Deuteronomy',
  'de': 'Deuteronomy',
  'deu': 'Deuteronomy',
  'deut': 'Deuteronomy',
  'jos': 'Joshua',
  'josh': 'Joshua',
  'jsh': 'Joshua',
  'jdg': 'Judges',
  'jg': 'Judges',
  'judg': 'Judges',
  'ru': 'Ruth',
  'rut': 'Ruth',
  'rth': 'Ruth',
  '1sa': '1 Samuel',
  '1sam': '1 Samuel',
  '1sm': '1 Samuel',
  '1s': '1 Samuel',
  '2sa': '2 Samuel',
  '2sam': '2 Samuel',
  '2sm': '2 Samuel',
  '2s': '2 Samuel',
  '1ki': '1 Kings',
  '1kgs': '1 Kings',
  '1k': '1 Kings',
  '2ki': '2 Kings',
  '2kgs': '2 Kings',
  '2k': '2 Kings',
  '1ch': '1 Chronicles',
  '1chr': '1 Chronicles',
  '1chron': '1 Chronicles',
  '2ch': '2 Chronicles',
  '2chr': '2 Chronicles',
  '2chron': '2 Chronicles',
  'ezr': 'Ezra',
  'ez': 'Ezra',
  'ne': 'Nehemiah',
  'neh': 'Nehemiah',
  'es': 'Esther',
  'est': 'Esther',
  'esth': 'Esther',
  'jb': 'Job',
  'job': 'Job',
  'ps': 'Psalms',
  'psa': 'Psalms',
  'psm': 'Psalms',
  'pss': 'Psalms',
  'psalm': 'Psalms',
  'pr': 'Proverbs',
  'pro': 'Proverbs',
  'prv': 'Proverbs',
  'prov': 'Proverbs',
  'ec': 'Ecclesiastes',
  'ecc': 'Ecclesiastes',
  'eccl': 'Ecclesiastes',
  'eccle': 'Ecclesiastes',
  'qoh': 'Ecclesiastes',
  'so': 'Song of Solomon',
  'sos': 'Song of Solomon',
  'song': 'Song of Solomon',
  'sng': 'Song of Solomon',
  'ss': 'Song of Solomon',
  'is': 'Isaiah',
  'isa': 'Isaiah',
  'je': 'Jeremiah',
  'jer': 'Jeremiah',
  'jr': 'Jeremiah',
  'la': 'Lamentations',
  'lam': 'Lamentations',
  'eze': 'Ezekiel',
  'ezek': 'Ezekiel',
  'ezk': 'Ezekiel',
  'da': 'Daniel',
  'dan': 'Daniel',
  'dn': 'Daniel',
  'ho': 'Hosea',
  'hos': 'Hosea',
  'joe': 'Joel',
  'jl': 'Joel',
  'am': 'Amos',
  'amo': 'Amos',
  'ob': 'Obadiah',
  'oba': 'Obadiah',
  'obad': 'Obadiah',
  'jon': 'Jonah',
  'jnh': 'Jonah',
  'mi': 'Micah',
  'mic': 'Micah',
  'na': 'Nahum',
  'nah': 'Nahum',
  'hab': 'Habakkuk',
  'hb': 'Habakkuk',
  'zep': 'Zephaniah',
  'zph': 'Zephaniah',
  'zp': 'Zephaniah',
  'hag': 'Haggai',
  'hg': 'Haggai',
  'zec': 'Zechariah',
  'zch': 'Zechariah',
  'zc': 'Zechariah',
  'mal': 'Malachi',
  'ml': 'Malachi',
  'mt': 'Matthew',
  'mat': 'Matthew',
  'matt': 'Matthew',
  'mk': 'Mark',
  'mr': 'Mark',
  'mrk': 'Mark',
  'mar': 'Mark',
  'lk': 'Luke',
  'lu': 'Luke',
  'luk': 'Luke',
  'jn': 'John',
  'joh': 'John',
  'jhn': 'John',
  'ac': 'Acts',
  'act': 'Acts',
  'ro': 'Romans',
  'rom': 'Romans',
  'rm': 'Romans',
  '1co': '1 Corinthians',
  '1cor': '1 Corinthians',
  '1c': '1 Corinthians',
  '2co': '2 Corinthians',
  '2cor': '2 Corinthians',
  '2c': '2 Corinthians',
  'ga': 'Galatians',
  'gal': 'Galatians',
  'ep': 'Ephesians',
  'eph': 'Ephesians',
  'ph': 'Philippians',
  'php': 'Philippians',
  'phil': 'Philippians',
  'pp': 'Philippians',
  'co': 'Colossians',
  'col': 'Colossians',
  '1th': '1 Thessalonians',
  '1thes': '1 Thessalonians',
  '1thess': '1 Thessalonians',
  '1ts': '1 Thessalonians',
  '2th': '2 Thessalonians',
  '2thes': '2 Thessalonians',
  '2thess': '2 Thessalonians',
  '2ts': '2 Thessalonians',
  '1ti': '1 Timothy',
  '1tim': '1 Timothy',
  '1tm': '1 Timothy',
  '2ti': '2 Timothy',
  '2tim': '2 Timothy',
  '2tm': '2 Timothy',
  'ti': 'Titus',
  'tit': 'Titus',
  'tt': 'Titus',
  'phm': 'Philemon',
  'pm': 'Philemon',
  'philem': 'Philemon',
  'he': 'Hebrews',
  'heb': 'Hebrews',
  'ja': 'James',
  'jam': 'James',
  'jas': 'James',
  'jm': 'James',
  '1pe': '1 Peter',
  '1pet': '1 Peter',
  '1pt': '1 Peter',
  '1p': '1 Peter',
  '2pe': '2 Peter',
  '2pet': '2 Peter',
  '2pt': '2 Peter',
  '2p': '2 Peter',
  '1jn': '1 John',
  '1jo': '1 John',
  '1joh': '1 John',
  '1j': '1 John',
  '2jn': '2 John',
  '2jo': '2 John',
  '2joh': '2 John',
  '2j': '2 John',
  '3jn': '3 John',
  '3jo': '3 John',
  '3joh': '3 John',
  '3j': '3 John',
  'jud': 'Jude',
  'jude': 'Jude',
  'jd': 'Jude',
  're': 'Revelation',
  'rev': 'Revelation',
  'rv': 'Revelation',
  'apoc': 'Revelation',
};

/// Resolves an abbreviation, full name or unique prefix to a canonical name.
String? resolveBookName(String input) {
  final lower = input.toLowerCase().trim();
  if (lower.isEmpty) return null;
  final abbr =
      bookAbbreviations[lower] ?? bookAbbreviations[lower.replaceAll(' ', '')];
  if (abbr != null) return abbr;
  for (final b in canonicalBooks) {
    if (b.toLowerCase() == lower ||
        b.toLowerCase().replaceAll(' ', '') == lower) {
      return b;
    }
  }
  final matches = canonicalBooks
      .where(
        (b) =>
            b.toLowerCase().startsWith(lower) ||
            b.toLowerCase().replaceAll(' ', '').startsWith(lower),
      )
      .toList();
  return matches.length == 1 ? matches.first : null;
}

class ParsedReference {
  const ParsedReference(this.bookName, this.chapter, [this.verse]);
  final String bookName;
  final int chapter;
  final int? verse;

  int get bookNumber => canonicalBooks.indexOf(bookName) + 1;

  @override
  String toString() =>
      verse == null ? '$bookName $chapter' : '$bookName $chapter:$verse';
}

/// Parses "Jn 3:16", "G 2 1", "John 3", "1Jn 3:16", "1 John 3 16".
ParsedReference? parseDirectReference(String input) {
  var working = input.trim();
  if (working.isEmpty) return null;
  var prefix = '';
  final lead = RegExp(r'^(\d+)\s*').firstMatch(working);
  if (lead != null &&
      working.length > lead.end &&
      RegExp(r'[A-Za-z]').hasMatch(working[lead.end])) {
    prefix = lead.group(1)!;
    working = working.substring(lead.end).trim();
  }
  final parts = working
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  // The book name may be several words ("Song of Solomon").
  var bookWords = 1;
  while (bookWords < parts.length &&
      !RegExp(r'^\d').hasMatch(parts[bookWords])) {
    bookWords++;
  }
  var bookPart = parts.take(bookWords).join(' ');
  var numbers = parts.skip(bookWords).toList();
  if (numbers.isEmpty) {
    final m = RegExp(r'^(\D+?)(\d.*)$').firstMatch(bookPart);
    if (m != null) {
      bookPart = m.group(1)!;
      numbers = [m.group(2)!];
    }
  }
  final book =
      resolveBookName(prefix.isEmpty ? bookPart : '$prefix$bookPart') ??
      (prefix.isEmpty ? null : resolveBookName('$prefix $bookPart'));
  if (book == null || numbers.isEmpty) return null;

  final nums = numbers.join(' ');
  if (nums.contains(':') || nums.contains('.')) {
    final cv = nums.split(RegExp(r'[:.]'));
    final chapter = int.tryParse(cv[0].trim());
    if (chapter != null && chapter > 0) {
      final verse = cv.length > 1
          ? int.tryParse(RegExp(r'\d+').stringMatch(cv[1]) ?? '')
          : null;
      return ParsedReference(book, chapter, verse);
    }
  }
  final ints = RegExp(r'\d+')
      .allMatches(nums)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  if (ints.length >= 2) return ParsedReference(book, ints[0], ints[1]);
  if (ints.length == 1) return ParsedReference(book, ints[0]);
  return null;
}

/// Enduring Word commentary page for a chapter.
Uri? enduringWordChapterUrl(String bookName, String chapter) {
  var n = bookName.toLowerCase();
  if (n == 'psalms') n = 'psalm';
  if (n == 'song of songs') n = 'song of solomon';
  n = n.replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), '-');
  n = n.replaceAll(RegExp(r'^-+|-+$'), '');
  if (n.isEmpty) return null;
  return Uri.parse('https://enduringword.com/bible-commentary/$n-$chapter/');
}

/// Default abbreviation for a Bible's display name (first letters / first 3).
String defaultAbbreviation(String displayName) {
  final words = displayName
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'BIB';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 3 ? w.substring(0, 3) : w).toUpperCase();
  }
  return words.map((w) => w[0]).join().toUpperCase();
}

// MARK: - Deuterocanonical books (Apocrypha)

/// The deuterocanonical books / Apocrypha, in the usual order, with the
/// spellings and short ids files use for them and Zefania's book number.
/// They get book numbers 67 and up, in this order.
const List<(String, List<String>, int?)> deuterocanonicalBooks = [
  ('Tobit', ['tob', 'tobit', 'tobias', 'tb', 'tobt'], 69),
  ('Judith', ['jdt', 'judith', 'judit', 'jdth', 'jth'], 67),
  (
    'Additions to Esther',
    [
      'addesth',
      'addest',
      'esg',
      'esthgr',
      'esther (greek)',
      'greek esther',
      'additions to esther',
      'rest of esther',
      'adde',
    ],
    75,
  ),
  (
    'Wisdom of Solomon',
    ['wis', 'wisdom', 'wisdom of solomon', 'wisd', 'ws', 'sap', 'sapientia'],
    68,
  ),
  (
    'Sirach',
    [
      'sir',
      'sirach',
      'ecclesiasticus',
      'ecclus',
      'sirach (ecclesiasticus)',
      'jesus sirach',
      'sirak',
    ],
    70,
  ),
  ('Baruch', ['bar', 'baruch'], 71),
  (
    'Letter of Jeremiah',
    [
      'epjer',
      'letjer',
      'ljer',
      'lje',
      'epi',
      'letter of jeremiah',
      'epistle of jeremiah',
      'epistle of jeremy',
    ],
    79,
  ),
  (
    'Additions to Daniel',
    [
      'adddan',
      'addan',
      'dag',
      'dangr',
      'additions to daniel',
      'prayer of azariah',
      'praz',
      'song of the three',
      'sgthree',
      's3y',
      'song of three youths',
    ],
    74,
  ),
  ('Susanna', ['sus', 'susanna', 'susannah'], null),
  (
    'Bel and the Dragon',
    ['bel', 'bel and the dragon', 'bel & the dragon'],
    null,
  ),
  (
    '1 Maccabees',
    ['1macc', '1mac', '1ma', '1 maccabees', '1 macc', 'i maccabees'],
    72,
  ),
  (
    '2 Maccabees',
    ['2macc', '2mac', '2ma', '2 maccabees', '2 macc', 'ii maccabees'],
    73,
  ),
  (
    '3 Maccabees',
    ['3macc', '3mac', '3ma', '3 maccabees', '3 macc', 'iii maccabees'],
    77,
  ),
  (
    '4 Maccabees',
    ['4macc', '4mac', '4ma', '4 maccabees', '4 macc', 'iv maccabees'],
    78,
  ),
  ('1 Esdras', ['1esd', '1es', '1 esdras', 'i esdras', '3 ezra'], 80),
  ('2 Esdras', ['2esd', '2es', '2 esdras', 'ii esdras', '4es', '4 ezra'], 81),
  (
    'Prayer of Manasseh',
    [
      'prman',
      'man',
      'orman',
      'manasseh',
      'manasses',
      'manasse',
      'manassse',
      'prayer of manasseh',
      'prayer of manasses',
    ],
    76,
  ),
  ('Psalm 151', ['ps151', 'psa151', 'ps2', 'psalm 151', 'psalms 151'], null),
  ('Odes', ['odes', 'oda', 'odae'], 82),
  ('Psalms of Solomon', ['pssol', 'pss', 'psalms of solomon'], 83),
  (
    'Laodiceans',
    ['eplao', 'lao', 'laodiceans', 'epistle to the laodiceans'],
    84,
  ),
];

String _norm(String s) =>
    s.toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The index into [deuterocanonicalBooks] for a book, by its name or short
/// id (preferred), else Zefania's number; null for other books.
int? deuterocanonicalIndex({String? name, String? short, String? number}) {
  for (final raw in [name, short]) {
    if (raw == null || raw.isEmpty) continue;
    final n = _norm(raw);
    final squashed = n.replaceAll(' ', '');
    for (var i = 0; i < deuterocanonicalBooks.length; i++) {
      final aliases = deuterocanonicalBooks[i].$2;
      if (aliases.contains(n) ||
          aliases.contains(squashed) ||
          _norm(deuterocanonicalBooks[i].$1) == n) {
        return i;
      }
    }
  }
  final z = int.tryParse(number ?? '');
  if (z != null && z > 66) {
    final i = deuterocanonicalBooks.indexWhere((b) => b.$3 == z);
    if (i >= 0) return i;
  }
  return null;
}

/// The book number used for a deuterocanonical book.
String deuterocanonicalNumber(int index) => '${67 + index}';

// MARK: - Book names by language

/// The 66 book names in other languages, for Bibles that don't name their
/// books (Beblia files, numbered books).
const Map<String, List<String>> localizedBookNames = {
  'fr': [
    'Genèse',
    'Exode',
    'Lévitique',
    'Nombres',
    'Deutéronome',
    'Josué',
    'Juges',
    'Ruth',
    '1 Samuel',
    '2 Samuel',
    '1 Rois',
    '2 Rois',
    '1 Chroniques',
    '2 Chroniques',
    'Esdras',
    'Néhémie',
    'Esther',
    'Job',
    'Psaumes',
    'Proverbes',
    'Ecclésiaste',
    'Cantique des cantiques',
    'Ésaïe',
    'Jérémie',
    'Lamentations',
    'Ézéchiel',
    'Daniel',
    'Osée',
    'Joël',
    'Amos',
    'Abdias',
    'Jonas',
    'Michée',
    'Nahum',
    'Habacuc',
    'Sophonie',
    'Aggée',
    'Zacharie',
    'Malachie',
    'Matthieu',
    'Marc',
    'Luc',
    'Jean',
    'Actes',
    'Romains',
    '1 Corinthiens',
    '2 Corinthiens',
    'Galates',
    'Éphésiens',
    'Philippiens',
    'Colossiens',
    '1 Thessaloniciens',
    '2 Thessaloniciens',
    '1 Timothée',
    '2 Timothée',
    'Tite',
    'Philémon',
    'Hébreux',
    'Jacques',
    '1 Pierre',
    '2 Pierre',
    '1 Jean',
    '2 Jean',
    '3 Jean',
    'Jude',
    'Apocalypse',
  ],
  'de': [
    '1. Mose',
    '2. Mose',
    '3. Mose',
    '4. Mose',
    '5. Mose',
    'Josua',
    'Richter',
    'Rut',
    '1. Samuel',
    '2. Samuel',
    '1. Könige',
    '2. Könige',
    '1. Chronik',
    '2. Chronik',
    'Esra',
    'Nehemia',
    'Ester',
    'Hiob',
    'Psalmen',
    'Sprüche',
    'Prediger',
    'Hoheslied',
    'Jesaja',
    'Jeremia',
    'Klagelieder',
    'Hesekiel',
    'Daniel',
    'Hosea',
    'Joel',
    'Amos',
    'Obadja',
    'Jona',
    'Micha',
    'Nahum',
    'Habakuk',
    'Zefanja',
    'Haggai',
    'Sacharja',
    'Maleachi',
    'Matthäus',
    'Markus',
    'Lukas',
    'Johannes',
    'Apostelgeschichte',
    'Römer',
    '1. Korinther',
    '2. Korinther',
    'Galater',
    'Epheser',
    'Philipper',
    'Kolosser',
    '1. Thessalonicher',
    '2. Thessalonicher',
    '1. Timotheus',
    '2. Timotheus',
    'Titus',
    'Philemon',
    'Hebräer',
    'Jakobus',
    '1. Petrus',
    '2. Petrus',
    '1. Johannes',
    '2. Johannes',
    '3. Johannes',
    'Judas',
    'Offenbarung',
  ],
  'es': [
    'Génesis',
    'Éxodo',
    'Levítico',
    'Números',
    'Deuteronomio',
    'Josué',
    'Jueces',
    'Rut',
    '1 Samuel',
    '2 Samuel',
    '1 Reyes',
    '2 Reyes',
    '1 Crónicas',
    '2 Crónicas',
    'Esdras',
    'Nehemías',
    'Ester',
    'Job',
    'Salmos',
    'Proverbios',
    'Eclesiastés',
    'Cantares',
    'Isaías',
    'Jeremías',
    'Lamentaciones',
    'Ezequiel',
    'Daniel',
    'Oseas',
    'Joel',
    'Amós',
    'Abdías',
    'Jonás',
    'Miqueas',
    'Nahúm',
    'Habacuc',
    'Sofonías',
    'Hageo',
    'Zacarías',
    'Malaquías',
    'Mateo',
    'Marcos',
    'Lucas',
    'Juan',
    'Hechos',
    'Romanos',
    '1 Corintios',
    '2 Corintios',
    'Gálatas',
    'Efesios',
    'Filipenses',
    'Colosenses',
    '1 Tesalonicenses',
    '2 Tesalonicenses',
    '1 Timoteo',
    '2 Timoteo',
    'Tito',
    'Filemón',
    'Hebreos',
    'Santiago',
    '1 Pedro',
    '2 Pedro',
    '1 Juan',
    '2 Juan',
    '3 Juan',
    'Judas',
    'Apocalipsis',
  ],
  'pt': [
    'Gênesis',
    'Êxodo',
    'Levítico',
    'Números',
    'Deuteronômio',
    'Josué',
    'Juízes',
    'Rute',
    '1 Samuel',
    '2 Samuel',
    '1 Reis',
    '2 Reis',
    '1 Crônicas',
    '2 Crônicas',
    'Esdras',
    'Neemias',
    'Ester',
    'Jó',
    'Salmos',
    'Provérbios',
    'Eclesiastes',
    'Cânticos',
    'Isaías',
    'Jeremias',
    'Lamentações',
    'Ezequiel',
    'Daniel',
    'Oseias',
    'Joel',
    'Amós',
    'Obadias',
    'Jonas',
    'Miqueias',
    'Naum',
    'Habacuque',
    'Sofonias',
    'Ageu',
    'Zacarias',
    'Malaquias',
    'Mateus',
    'Marcos',
    'Lucas',
    'João',
    'Atos',
    'Romanos',
    '1 Coríntios',
    '2 Coríntios',
    'Gálatas',
    'Efésios',
    'Filipenses',
    'Colossenses',
    '1 Tessalonicenses',
    '2 Tessalonicenses',
    '1 Timóteo',
    '2 Timóteo',
    'Tito',
    'Filemom',
    'Hebreus',
    'Tiago',
    '1 Pedro',
    '2 Pedro',
    '1 João',
    '2 João',
    '3 João',
    'Judas',
    'Apocalipse',
  ],
  'it': [
    'Genesi',
    'Esodo',
    'Levitico',
    'Numeri',
    'Deuteronomio',
    'Giosuè',
    'Giudici',
    'Rut',
    '1 Samuele',
    '2 Samuele',
    '1 Re',
    '2 Re',
    '1 Cronache',
    '2 Cronache',
    'Esdra',
    'Neemia',
    'Ester',
    'Giobbe',
    'Salmi',
    'Proverbi',
    'Ecclesiaste',
    'Cantico dei Cantici',
    'Isaia',
    'Geremia',
    'Lamentazioni',
    'Ezechiele',
    'Daniele',
    'Osea',
    'Gioele',
    'Amos',
    'Abdia',
    'Giona',
    'Michea',
    'Naum',
    'Abacuc',
    'Sofonia',
    'Aggeo',
    'Zaccaria',
    'Malachia',
    'Matteo',
    'Marco',
    'Luca',
    'Giovanni',
    'Atti',
    'Romani',
    '1 Corinzi',
    '2 Corinzi',
    'Galati',
    'Efesini',
    'Filippesi',
    'Colossesi',
    '1 Tessalonicesi',
    '2 Tessalonicesi',
    '1 Timoteo',
    '2 Timoteo',
    'Tito',
    'Filemone',
    'Ebrei',
    'Giacomo',
    '1 Pietro',
    '2 Pietro',
    '1 Giovanni',
    '2 Giovanni',
    '3 Giovanni',
    'Giuda',
    'Apocalisse',
  ],
  'nl': [
    'Genesis',
    'Exodus',
    'Leviticus',
    'Numeri',
    'Deuteronomium',
    'Jozua',
    'Richteren',
    'Ruth',
    '1 Samuël',
    '2 Samuël',
    '1 Koningen',
    '2 Koningen',
    '1 Kronieken',
    '2 Kronieken',
    'Ezra',
    'Nehemia',
    'Ester',
    'Job',
    'Psalmen',
    'Spreuken',
    'Prediker',
    'Hooglied',
    'Jesaja',
    'Jeremia',
    'Klaagliederen',
    'Ezechiël',
    'Daniël',
    'Hosea',
    'Joël',
    'Amos',
    'Obadja',
    'Jona',
    'Micha',
    'Nahum',
    'Habakuk',
    'Sefanja',
    'Haggai',
    'Zacharia',
    'Maleachi',
    'Matteüs',
    'Marcus',
    'Lucas',
    'Johannes',
    'Handelingen',
    'Romeinen',
    '1 Korintiërs',
    '2 Korintiërs',
    'Galaten',
    'Efeziërs',
    'Filippenzen',
    'Kolossenzen',
    '1 Tessalonicenzen',
    '2 Tessalonicenzen',
    '1 Timoteüs',
    '2 Timoteüs',
    'Titus',
    'Filemon',
    'Hebreeën',
    'Jakobus',
    '1 Petrus',
    '2 Petrus',
    '1 Johannes',
    '2 Johannes',
    '3 Johannes',
    'Judas',
    'Openbaring',
  ],
};

/// A language code ('en', 'fr', ...) from a hint: an ISO code, a Zefania
/// code (ENG, GER, FRE, ...), a language name in English or in itself, or
/// a title or file name containing one ("French S21", "FrenchS21Bible").
String? bibleLanguage(String? hint) {
  if (hint == null || hint.trim().isEmpty) return null;
  final h = hint.trim().toLowerCase();
  const codes = {
    'en': ['en', 'eng', 'english'],
    'fr': ['fr', 'fre', 'fra', 'french', 'français', 'francais'],
    'de': ['de', 'ger', 'deu', 'german', 'deutsch'],
    'es': ['es', 'spa', 'esp', 'spanish', 'español', 'espanol'],
    'pt': ['pt', 'por', 'portuguese', 'português', 'portugues'],
    'it': ['it', 'ita', 'italian', 'italiano'],
    'nl': ['nl', 'dut', 'nld', 'dutch', 'nederlands'],
  };
  final code = h.split(RegExp(r'[-_]')).first;
  for (final e in codes.entries) {
    if (e.value.contains(code) || e.value.contains(h)) return e.key;
  }
  // Inside a title or file name: whole language names only.
  for (final e in codes.entries) {
    for (final name in e.value.where((v) => v.length > 3)) {
      if (h.contains(name)) return e.key;
    }
  }
  return null;
}
