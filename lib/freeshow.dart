// FreeShow `.show` files: JSON `[id, show]`, where a show has `meta`
// (title, artist, CCLI…), `slides` (each with a `group` such as "Verse 1",
// text `items` made of `lines` with chord positions, and continuation
// `children`), and `layouts` listing the slides in play order.
//
// Sections map to slide groups, the song structure to the layout, chords to
// line chords, and translated sections ("Verse 1 (FR)", linked to their
// original) to a second text item tagged with its `language` — how FreeShow
// stores its own translations. Both ways.

import 'dart:convert';
import 'dart:math';

import 'chordpro.dart';
import 'export.dart';
import 'music.dart';
import 'state.dart';
import 'translation.dart';

final _rand = Random();
String _id() => [
  for (var i = 0; i < 12; i++)
    'abcdefghijklmnopqrstuvwxyz0123456789'[_rand.nextInt(36)],
].join();

final _chord = RegExp(r'\[([^\]\n]*)\]');
final _directive = RegExp(r'^\s*\{[^}]*\}\s*$');

/// FreeShow's own group names (they get its colours).
const _globalGroups = {
  'verse': 'verse',
  'chorus': 'chorus',
  'pre-chorus': 'pre_chorus',
  'prechorus': 'pre_chorus',
  'pre chorus': 'pre_chorus',
  'bridge': 'bridge',
  'intro': 'intro',
  'outro': 'outro',
  'tag': 'tag',
  'break': 'break',
  'interlude': 'break',
  'ending': 'outro',
};

String? _globalGroup(String name) {
  final base = name.toLowerCase().replaceAll(RegExp(r'[\d\s]+$'), '').trim();
  return _globalGroups[base];
}

/// One ChordPro line as a FreeShow line: the lyric, and chords at their
/// character positions.
Map<String, dynamic> _line(String chordPro, String Function(String) chord) {
  final text = StringBuffer();
  final chords = <Map<String, dynamic>>[];
  var last = 0;
  for (final m in _chord.allMatches(chordPro)) {
    text.write(chordPro.substring(last, m.start));
    final c = m.group(1)!.trim();
    if (c.isNotEmpty) {
      chords.add({'id': _id(), 'pos': text.length, 'key': chord(c)});
    }
    last = m.end;
  }
  text.write(chordPro.substring(last));
  return {
    'align': '',
    'text': [
      {'value': text.toString().trimRight(), 'style': ''},
    ],
    if (chords.isNotEmpty) 'chords': chords,
  };
}

/// FreeShow's full-screen text box, or half of it when there are two.
String _boxStyle(int index, int count) => count < 2
    ? 'top:120px;left:50px;height:840px;width:1820px;'
    : 'top:${index == 0 ? 60 : 560}px;left:50px;height:460px;width:1820px;';

/// A section's slides: its lines (no label, directives or comments), split
/// where the section has blank lines / slide breaks.
List<List<String>> _slidesOf(String sectionText) {
  final body = sectionText.split('\n').skip(1).join('\n');
  return [
    for (final p in ChordPro.parts(body, tidy: false))
      if (!p.isMarker)
        [
          for (final l in p.lines)
            if (l.trim().isNotEmpty &&
                !_directive.hasMatch(l) &&
                !l.trim().startsWith('#') &&
                ChordPro.sectionName(l) == null)
              l,
        ],
  ].where((s) => s.isNotEmpty).toList();
}

/// The song as a FreeShow `.show` file (as it's arranged and keyed in
/// [src]).
String exportFreeShow(ExportSource src, {DateTime? now}) {
  String chord(String c) => src.chord(c, 0, standard: true);
  final raw = src.raw;

  // Play order from the arranged text: section names, and which are
  // linked to the next ({link}).
  final order = <(String, bool)>[];
  for (final line in raw.split('\n')) {
    final name = ChordPro.sectionName(line);
    if (name != null) {
      order.add((name, false));
    } else if (line.trim() == linkMarker && order.isNotEmpty) {
      order[order.length - 1] = (order.last.$1, true);
    }
  }
  final noLabels = order.isEmpty;
  final lyricsName = 'Lyrics';
  String? textOf(String name) =>
      noLabels ? '$lyricsName:\n$raw' : ChordPro.sectionText(raw, name);
  if (noLabels) order.add((lyricsName, false));

  final slides = <String, Map<String, dynamic>>{};
  final groupIds = <String, String>{}; // section key → parent slide id
  final layout = <Map<String, dynamic>>[];

  for (var i = 0; i < order.length; i++) {
    final (name, _) = order[i];
    if (translationOf(name) != null) continue; // goes on its original
    final key = name.toLowerCase();
    if (!groupIds.containsKey(key)) {
      final main = _slidesOf(textOf(name) ?? '$name:');
      if (main.isEmpty) main.add(const []);
      // Translations linked right after it (in this or any later copy).
      final translations = <(String, List<List<String>>)>[];
      for (var j = i; j < order.length - 1 && order[j].$2; j++) {
        final t = translationOf(order[j + 1].$1);
        if (t == null || t.$1.toLowerCase() != key) break;
        final text = ChordPro.sectionText(raw, order[j + 1].$1);
        if (text != null) translations.add((t.$2, _slidesOf(text)));
      }
      final ids = [for (final _ in main) _id()];
      for (var s = 0; s < main.length; s++) {
        final count = 1 + translations.length;
        slides[ids[s]] = {
          'group': s == 0 ? name : null,
          'color': null,
          if (s == 0 && _globalGroup(name) != null)
            'globalGroup': _globalGroup(name),
          'settings': {},
          'notes': '',
          'items': [
            {
              'style': _boxStyle(0, count),
              'lines': [for (final l in main[s]) _line(l, chord)],
            },
            for (var t = 0; t < translations.length; t++)
              {
                'style': _boxStyle(t + 1, count),
                'language': translations[t].$1.toLowerCase(),
                'lines': [
                  if (s < translations[t].$2.length)
                    for (final l in translations[t].$2[s]) _line(l, chord),
                ],
              },
          ],
          if (s == 0 && ids.length > 1) 'children': ids.sublist(1),
        };
      }
      groupIds[key] = ids.first;
    }
    layout.add({'id': groupIds[key]});
  }

  final song = src.song;
  final created = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final layoutId = _id();
  final show = {
    'name': song.displayTitle,
    'category': 'song',
    'settings': {'activeLayout': layoutId, 'template': 'default'},
    'timestamps': {'created': created, 'modified': created, 'used': null},
    'quickAccess': {},
    'meta': {
      'title': song.displayTitle,
      if (src.artistLine.isNotEmpty) 'artist': src.artistLine,
      if (song.lyricist.isNotEmpty) 'author': song.lyricist,
      if (song.composer.isNotEmpty) 'composer': song.composer,
      if (song.copyright.isNotEmpty) 'copyright': song.copyright,
      if (song.ccli.isNotEmpty) 'CCLI': song.ccli,
      if (src.soundingKey != null) 'key': src.soundingKey!.name,
    },
    'slides': slides,
    'layouts': {
      layoutId: {'name': 'Default', 'notes': '', 'slides': layout},
    },
    'media': {},
  };
  return jsonEncode([_id(), show]);
}

/// The show inside a decoded `.show` file, or null if it isn't one.
Map<String, dynamic>? freeShowData(Object? decoded) {
  Object? show = decoded;
  if (decoded is List && decoded.length == 2 && decoded[1] is Map) {
    show = decoded[1];
  }
  if (show is Map<String, dynamic> &&
      show['slides'] is Map &&
      show['layouts'] is Map) {
    return show;
  }
  return null;
}

String _s(Object? v) => v is String ? v.trim() : (v is num ? '$v' : '');

/// A FreeShow line back to ChordPro (chords put back at their positions).
String _chordPro(Object? line) {
  if (line is! Map) return '';
  final text = [
    for (final t in (line['text'] as List?) ?? const [])
      if (t is Map) _s(t['value']).isEmpty ? '' : '${t['value']}',
  ].join();
  final chords = [
    for (final c in (line['chords'] as List?) ?? const [])
      if (c is Map && c['pos'] is num && _s(c['key']).isNotEmpty)
        ((c['pos'] as num).toInt().clamp(0, text.length), _s(c['key'])),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  var out = text;
  for (final (pos, key) in chords) {
    out = out.replaceRange(pos, pos, '[$key]');
  }
  return out.trimRight();
}

List<String> _itemLines(Map item) =>
    [for (final l in (item['lines'] as List?) ?? const []) _chordPro(l)]
      ..removeWhere((l) => l.trim().isEmpty);

String _titleCase(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// A song from a FreeShow show: its groups as sections, its layout as the
/// structure, translated items as linked "(XX)" sections.
Song importFreeShow(Map<String, dynamic> show, {String fileName = ''}) {
  final slides = (show['slides'] as Map).cast<String, dynamic>();
  final layouts = (show['layouts'] as Map).cast<String, dynamic>();
  final settings = show['settings'] is Map ? show['settings'] as Map : {};
  final layoutId = layouts.containsKey(settings['activeLayout'])
      ? settings['activeLayout'] as String
      : (layouts.keys.isEmpty ? null : layouts.keys.first);
  final refs = layoutId == null
      ? const []
      : ((layouts[layoutId] as Map)['slides'] as List?) ?? const [];

  final names = <String, String>{}; // slide id → section name
  final used = <String, int>{};
  final blocks = <String>[];
  final order = <String>[];
  for (final ref in refs) {
    if (ref is! Map || ref['disabled'] == true) continue;
    final id = _s(ref['id']);
    final slide = slides[id];
    if (slide is! Map) continue;
    var name = names[id];
    if (name == null) {
      var base = _s(slide['group']);
      if (base.isEmpty) base = _titleCase(_s(slide['globalGroup']));
      if (base.isEmpty) base = 'Slide';
      base = base.replaceAll(':', '');
      // Another group with the same name: number it.
      final n = (used[base.toLowerCase()] ?? 0) + 1;
      used[base.toLowerCase()] = n;
      name = n == 1 ? base : '$base $n';
      names[id] = name;

      // The slide and its continuation slides.
      final pages = [
        slide,
        for (final c in (slide['children'] as List?) ?? const [])
          if (slides[c] is Map) slides[c] as Map,
      ];
      final main = <String>[];
      final translated = <String, List<String>>{};
      for (final page in pages) {
        final items = ((page['items'] as List?) ?? const [])
            .whereType<Map>()
            .where((i) => i['lines'] is List);
        final mainLines = <String>[];
        for (final item in items) {
          final lang = _s(item['language']);
          final lines = _itemLines(item);
          if (lang.isEmpty) {
            mainLines.addAll(lines);
          } else if (lines.isNotEmpty) {
            final t = translated.putIfAbsent(lang, () => []);
            if (t.isNotEmpty) t.add('');
            t.addAll(lines);
          }
        }
        if (mainLines.isEmpty) continue;
        if (main.isNotEmpty) main.add('');
        main.addAll(mainLines);
      }
      blocks.add(['$name:', ...main].join('\n'));
      for (final e in translated.entries) {
        final tag = (languageFor(e.key)?.tag ?? e.key.toUpperCase());
        blocks.add(['$name ($tag):', ...e.value].join('\n'));
      }
    }
    order.add(name);
  }

  final raw = blocks.join('\n\n');
  final meta = show['meta'] is Map ? show['meta'] as Map : const {};
  final title = [
    _s(show['name']),
    _s(meta['title']),
    fileName.replaceAll(RegExp(r'\.show$', caseSensitive: false), ''),
  ].firstWhere((t) => t.isNotEmpty, orElse: () => 'Untitled');
  final structure = withTranslations(raw, [
    for (final n in order) StructureItem.section(n),
  ]);
  return Song(
    title: title,
    raw: raw,
    key: MusicKey.parse(_s(meta['key'])),
    artist: _s(meta['artist']).isNotEmpty
        ? _s(meta['artist'])
        : _s(meta['author']),
    composer: _s(meta['composer']),
    lyricist: _s(meta['author']),
    copyright: _s(meta['copyright']),
    ccli: _s(meta['CCLI']),
    structure: structure,
    date: DateTime.now(),
  );
}
