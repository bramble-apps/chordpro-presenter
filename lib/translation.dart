import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chordpro.dart';

/// Slide translation (the idea from FreeShow's "Translate"): each section
/// gets a machine-translated copy right after it — "Verse 1 (FR)" — linked
/// to it in the song structure, so the two show together as one slide
/// (top / bottom or side by side, see the linked-section formatting).
/// Translate again to update a language; remove it to drop its sections.

/// Turns text into [language] (a Google Translate code like `fr`).
typedef Translator = Future<String> Function(String text, String language);

/// Google Translate's free endpoint (what FreeShow uses). Lines stay lines.
Future<String> googleTranslate(String text, String language) async {
  final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
    'client': 'gtx',
    'sl': 'auto',
    'tl': language,
    'dt': 't',
    'q': text,
  });
  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw TranslationError('Google Translate answered ${res.statusCode}');
  }
  final json = jsonDecode(utf8.decode(res.bodyBytes));
  // [[["translated", "original", …], …], …]: one entry per sentence.
  final segments = json is List && json.isNotEmpty && json[0] is List
      ? json[0] as List
      : const [];
  return [
    for (final s in segments)
      if (s is List && s.isNotEmpty && s[0] is String) s[0] as String,
  ].join();
}

class TranslationError implements Exception {
  final String message;
  TranslationError(this.message);
  @override
  String toString() => message;
}

/// A language to translate into.
class Language {
  final String code;
  final String name;
  final String nativeName;
  const Language(this.code, this.name, this.nativeName);

  /// The tag in section names: "Verse 1 (FR)".
  String get tag => code.toUpperCase();

  String get label => name == nativeName ? name : '$name · $nativeName';
}

/// Languages offered (Google Translate codes), by English name.
const languages = <Language>[
  Language('af', 'Afrikaans', 'Afrikaans'),
  Language('sq', 'Albanian', 'Shqip'),
  Language('am', 'Amharic', 'አማርኛ'),
  Language('ar', 'Arabic', 'العربية'),
  Language('hy', 'Armenian', 'Հայերեն'),
  Language('bn', 'Bengali', 'বাংলা'),
  Language('bg', 'Bulgarian', 'Български'),
  Language('ca', 'Catalan', 'Català'),
  Language('zh-CN', 'Chinese (Simplified)', '简体中文'),
  Language('zh-TW', 'Chinese (Traditional)', '繁體中文'),
  Language('hr', 'Croatian', 'Hrvatski'),
  Language('cs', 'Czech', 'Čeština'),
  Language('da', 'Danish', 'Dansk'),
  Language('nl', 'Dutch', 'Nederlands'),
  Language('en', 'English', 'English'),
  Language('et', 'Estonian', 'Eesti'),
  Language('fa', 'Persian', 'فارسی'),
  Language('tl', 'Filipino', 'Filipino'),
  Language('fi', 'Finnish', 'Suomi'),
  Language('fr', 'French', 'Français'),
  Language('de', 'German', 'Deutsch'),
  Language('el', 'Greek', 'Ελληνικά'),
  Language('gu', 'Gujarati', 'ગુજરાતી'),
  Language('ht', 'Haitian Creole', 'Kreyòl ayisyen'),
  Language('ha', 'Hausa', 'Hausa'),
  Language('iw', 'Hebrew', 'עברית'),
  Language('hi', 'Hindi', 'हिन्दी'),
  Language('hu', 'Hungarian', 'Magyar'),
  Language('ig', 'Igbo', 'Igbo'),
  Language('id', 'Indonesian', 'Bahasa Indonesia'),
  Language('it', 'Italian', 'Italiano'),
  Language('ja', 'Japanese', '日本語'),
  Language('rw', 'Kinyarwanda', 'Ikinyarwanda'),
  Language('ko', 'Korean', '한국어'),
  Language('ln', 'Lingala', 'Lingála'),
  Language('lt', 'Lithuanian', 'Lietuvių'),
  Language('mg', 'Malagasy', 'Malagasy'),
  Language('ms', 'Malay', 'Bahasa Melayu'),
  Language('ml', 'Malayalam', 'മലയാളം'),
  Language('mr', 'Marathi', 'मराठी'),
  Language('ne', 'Nepali', 'नेपाली'),
  Language('no', 'Norwegian', 'Norsk'),
  Language('pl', 'Polish', 'Polski'),
  Language('pt', 'Portuguese', 'Português'),
  Language('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
  Language('ro', 'Romanian', 'Română'),
  Language('ru', 'Russian', 'Русский'),
  Language('sr', 'Serbian', 'Српски'),
  Language('sk', 'Slovak', 'Slovenčina'),
  Language('so', 'Somali', 'Soomaali'),
  Language('es', 'Spanish', 'Español'),
  Language('sw', 'Swahili', 'Kiswahili'),
  Language('sv', 'Swedish', 'Svenska'),
  Language('ta', 'Tamil', 'தமிழ்'),
  Language('te', 'Telugu', 'తెలుగు'),
  Language('th', 'Thai', 'ไทย'),
  Language('ti', 'Tigrinya', 'ትግርኛ'),
  Language('tr', 'Turkish', 'Türkçe'),
  Language('uk', 'Ukrainian', 'Українська'),
  Language('ur', 'Urdu', 'اردو'),
  Language('vi', 'Vietnamese', 'Tiếng Việt'),
  Language('xh', 'Xhosa', 'isiXhosa'),
  Language('yo', 'Yoruba', 'Yorùbá'),
  Language('zu', 'Zulu', 'isiZulu'),
];

Language? languageFor(String code) {
  final c = code.toLowerCase();
  for (final l in languages) {
    if (l.code.toLowerCase() == c) return l;
  }
  return null;
}

final _tagged = RegExp(r'^(.*\S)\s+\(([A-Z]{2,3}(?:-[A-Z]{2})?)\)$');

/// "Verse 1 (FR)" → ("Verse 1", "FR"); null for an original section.
(String, String)? translationOf(String sectionName) {
  final m = _tagged.firstMatch(sectionName.trim());
  if (m == null || languageFor(m.group(2)!) == null) return null;
  return (m.group(1)!, m.group(2)!);
}

/// Language tags translated in this song, in the order they first appear.
List<String> translatedLanguages(String raw) {
  final out = <String>[];
  for (final name in ChordPro.sectionNames(raw)) {
    final t = translationOf(name);
    if (t != null && !out.contains(t.$2)) out.add(t.$2);
  }
  return out;
}

class TranslatedSong {
  final String raw;
  final List<StructureItem> structure;
  const TranslatedSong(this.raw, this.structure);
}

String _key(String name) => name.trim().toLowerCase();

/// The structure in use, or the sections in written order when there's
/// none yet (links need a structure).
List<StructureItem> _structureOf(String raw, List<StructureItem> structure) {
  if (structure.isNotEmpty) return List.of(structure);
  return [for (final n in ChordPro.sectionNames(raw)) StructureItem.section(n)];
}

/// The lyrics of a section, without its label, chords, directives or
/// credit lines, with sung syllables joined ("sea - ring" → "searing") so
/// the translator sees whole words.
String _lyrics(String sectionText) {
  final lines = sectionText.split('\n');
  final body = lines.skip(1).join('\n');
  return [
    for (final slide in ChordPro.parseToSlides(body, tidy: false))
      slide
          .split('\n')
          .map(
            (l) => ChordPro.joinSyllables(l).replaceAll(RegExp(r' {2,}'), ' '),
          )
          .join('\n'),
  ].join('\n\n').trim();
}

/// The copy of section [name] with the most words (a label can appear
/// again later with no words, meaning "repeat it").
String? _fullest(String raw, String name) {
  final lines = raw.split('\n');
  String? best;
  var most = -1;
  for (var i = 0; i < lines.length; i++) {
    final n = ChordPro.sectionName(lines[i]);
    if (n == null || _key(n) != _key(name)) continue;
    var e = i + 1;
    while (e < lines.length &&
        ChordPro.sectionName(lines[e]) == null &&
        !ChordPro.isDivider(lines[e])) {
      e++;
    }
    final text = lines.sublist(i, e).join('\n').trimRight();
    final words = _lyrics(text).length;
    if (words > most) {
      most = words;
      best = text;
    }
  }
  return best;
}

/// [structure] without translation items; each removed item's link goes
/// to the one before it (so links run on past it).
List<StructureItem> _withoutTranslations(
  List<StructureItem> structure,
  bool Function(String name) drop,
) {
  final items = <StructureItem>[];
  for (final item in structure) {
    if (!item.isModulation && drop(item.name)) {
      if (items.isNotEmpty && !items.last.isModulation && items.last.linked) {
        items[items.length - 1] = items.last.withLinked(item.linked);
      }
      continue;
    }
    items.add(item);
  }
  return items;
}

/// [structure] (or the sections as written) with each section followed by
/// its translations in [raw], all linked to it. Earlier translation items
/// are replaced, so this keeps any arrangement in step with the text.
List<StructureItem> withTranslations(
  String raw,
  List<StructureItem> structure,
) {
  final base = _withoutTranslations(
    _structureOf(raw, structure),
    (n) => translationOf(n) != null,
  );
  final tags = translatedLanguages(raw);
  final present = {for (final n in ChordPro.sectionNames(raw)) _key(n)};
  final out = <StructureItem>[];
  for (final item in base) {
    out.add(item);
    if (item.isModulation) continue;
    final names = [
      for (final tag in tags)
        if (present.contains(_key('${item.name} ($tag)')))
          '${item.name} ($tag)',
    ];
    if (names.isEmpty) continue;
    // The original links to its translations; the last takes its link on.
    final link = item.linked;
    out[out.length - 1] = item.withLinked(true);
    for (var k = 0; k < names.length; k++) {
      out.add(
        StructureItem.section(names[k], linked: k < names.length - 1 || link),
      );
    }
  }
  return out;
}

/// Removes every section of language [tag] (or all translations) from the
/// text and the structure.
TranslatedSong removeTranslation(
  String raw,
  List<StructureItem> structure, {
  String? tag,
}) {
  bool drop(String name) {
    final t = translationOf(name);
    return t != null && (tag == null || t.$2 == tag);
  }

  // The text: drop the sections' blocks (label to next label).
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var skipping = false;
  for (final line in lines) {
    final name = ChordPro.sectionName(line);
    if (name != null) skipping = drop(name);
    if (!skipping) out.add(line);
  }
  final text = out.join('\n');
  return TranslatedSong(
    text,
    withTranslations(text, _withoutTranslations(structure, drop)),
  );
}

/// Translates every section into [language] and puts each translation
/// right after its original, linked to it (replacing an earlier one in
/// that language). [onProgress] gets (done, total).
Future<TranslatedSong> translateSong({
  required String raw,
  required List<StructureItem> structure,
  required Language language,
  Translator translate = googleTranslate,
  void Function(int done, int total)? onProgress,
  String? title,
}) async {
  final tag = language.tag;
  // Unlabelled lyrics get labels first (so they're translated too), and
  // join the structure where they used to show.
  final (text, labelled) = ChordPro.relabel(
    removeTranslation(raw, const [], tag: tag).raw,
    structure,
    title: title,
  );

  // Originals that have lyrics, once each (a label used again with no
  // words is a repeat: the copy with the words is translated).
  final originals = <String>[];
  final bodies = <String, String>{};
  for (final name in ChordPro.sectionNames(text)) {
    if (translationOf(name) != null) continue;
    final body = _fullest(text, name);
    if (body == null || _lyrics(body).isEmpty) continue;
    if (originals.any((o) => _key(o) == _key(name))) continue;
    originals.add(name);
    bodies[name] = body;
  }
  if (originals.isEmpty) {
    throw TranslationError('No sections with lyrics to translate.');
  }

  // Translate them all (a few at a time).
  final translated = <String, String>{};
  var done = 0;
  onProgress?.call(0, originals.length);
  for (var i = 0; i < originals.length; i += 4) {
    final batch = originals.skip(i).take(4).toList();
    final results = await Future.wait([
      for (final name in batch)
        translate(_lyrics(bodies[name]!), language.code),
    ]);
    for (var b = 0; b < batch.length; b++) {
      translated[batch[b]] = results[b].trim();
      onProgress?.call(++done, originals.length);
    }
  }

  // Each translation goes in the text after the original's block and its
  // other translations.
  final lines = text.split('\n');
  for (final name in originals) {
    final t = translated[name]!;
    if (t.isEmpty) continue;
    // After the copy with the words.
    var start = -1, most = -1;
    for (var i = 0; i < lines.length; i++) {
      final n = ChordPro.sectionName(lines[i]);
      if (n == null || _key(n) != _key(name)) continue;
      var e = i + 1;
      while (e < lines.length &&
          ChordPro.sectionName(lines[e]) == null &&
          !ChordPro.isDivider(lines[e])) {
        e++;
      }
      final words = _lyrics(lines.sublist(i, e).join('\n')).length;
      if (words > most) {
        most = words;
        start = i;
      }
    }
    if (start < 0) continue;
    var end = start + 1;
    while (true) {
      while (end < lines.length &&
          ChordPro.sectionName(lines[end]) == null &&
          !ChordPro.isDivider(lines[end])) {
        end++;
      }
      final next = end < lines.length ? ChordPro.sectionName(lines[end]) : null;
      final tr = next == null ? null : translationOf(next);
      if (tr == null || _key(tr.$1) != _key(name)) break;
      end++;
    }
    while (end > start + 1 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    lines.insertAll(end, ['', '$name ($tag):', ...t.split('\n')]);
  }
  final out = lines.join('\n');
  return TranslatedSong(out, withTranslations(out, labelled));
}
