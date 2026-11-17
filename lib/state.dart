import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Offset, Size;

import 'band_sync/band_sync.dart';
import 'bible.dart';
import 'chords/chord_db.dart';
import 'chords/chord_sound.dart';
import 'browser.dart';
import 'chordpro.dart';
import 'fonts.dart';
import 'gospelizer.dart';
import 'format.dart';
import 'ink.dart';
import 'library_import.dart';
import 'media.dart';
import 'media_library.dart';
import 'autoscroll.dart';
import 'freeshow.dart';
import 'translation.dart';
import 'widgets/live_media.dart' show LiveControl;
import 'metronome.dart';
import 'pads/pad_controller.dart';
import 'music.dart';
import 'projection.dart';
import 'widgets/projection_view.dart';
import 'themes.dart';

/// Random UUID v4 (uppercase, like Swift's UUID).
String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
          '${h.substring(16, 20)}-${h.substring(20)}'
      .toUpperCase();
}

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');
List<String> _strList(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Tag {
  final String id;
  String name;
  String? color;

  /// Songs with a hidden tag stay out of the song list unless you filter by
  /// that tag or turn on "Show hidden songs" (e.g. seasonal Christmas songs).
  bool hidden;

  Tag({String? id, required this.name, this.color, this.hidden = false})
    : id = id ?? newId();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'hidden': hidden,
  };

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
    id: j['id'] as String?,
    name: _str(j['name']),
    color: j['color'] as String?,
    hidden: j['hidden'] as bool? ?? false,
  );
}

class Song {
  final String id;
  String title;
  String raw;

  /// Semitones from the written key to the key it is played in (-6..+5).
  int transpose;
  int capo;

  /// Key the chords are written in. Null = guess from `{key:}` or chords.
  MusicKey? key;

  String artist;
  String subtitle;
  String tempo;
  String timeSignature;
  String duration;
  String composer;
  String lyricist;
  String copyright;
  String ccli;
  String ccliLicense;
  String footer;
  String notes;
  String audioUrl;
  String sortTitle;
  List<String> tags;

  /// Order to play: sections and key changes (empty = as written).
  List<StructureItem> structure;
  DateTime? date;

  /// Fields from imported libraries this app doesn't use (kept on export).
  Map<String, dynamic> extra;

  /// The person's own fields (OnSong's custom metadata): name → value, in
  /// the order added, e.g. "Theme" → "Grace", "Season" → "Easter".
  Map<String, String> custom;

  Song({
    String? id,
    required this.title,
    required this.raw,
    this.transpose = 0,
    this.capo = 0,
    this.key,
    this.artist = '',
    this.subtitle = '',
    this.tempo = '',
    this.timeSignature = '',
    this.duration = '',
    this.composer = '',
    this.lyricist = '',
    this.copyright = '',
    this.ccli = '',
    this.ccliLicense = '',
    this.footer = '',
    this.notes = '',
    this.audioUrl = '',
    this.sortTitle = '',
    List<String>? tags,
    List<StructureItem>? structure,
    this.date,
    Map<String, dynamic>? extra,
    Map<String, String>? custom,
  }) : id = id ?? newId(),
       tags = tags ?? [],
       structure = structure ?? [],
       extra = extra ?? {},
       custom = custom ?? {};

  Song copy() => Song.fromJson(jsonDecode(jsonEncode(toJson())));

  /// Title, or the first `{title:}` in the ChordPro text, or "Untitled".
  String get displayTitle {
    if (title.trim().isNotEmpty) return title;
    final titles = ChordProHeader.parse(raw).titles;
    if (titles.isNotEmpty && titles.first.isNotEmpty) return titles.first;
    return 'Untitled';
  }

  /// Artist, or the `{artist:}` in the ChordPro text, or "".
  String get displayArtist {
    if (artist.trim().isNotEmpty) return artist;
    return ChordProHeader.parse(raw).artist?.trim() ?? '';
  }

  /// Title for sorting (accents folded, leading punctuation dropped);
  /// remembered until the title changes (sorting asks for it a lot).
  String get sortKey {
    final source = sortTitle.isNotEmpty ? sortTitle : displayTitle;
    if (!identical(source, _sortSource)) {
      _sortSource = source;
      _sortKey = foldAccents(source).replaceAll(_leadingPunctuation, '');
    }
    return _sortKey;
  }

  String? _sortSource;
  String _sortKey = '';
  static final _leadingPunctuation = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);

  /// Title, artist, subtitle and lyrics as a [searchKey] (letters and
  /// digits only, accents folded, chords dropped); remembered until any of
  /// them changes. Match it with [searchMatches].
  String get searchText {
    final customNow = custom.isEmpty ? '' : jsonEncode(custom);
    if (customNow != _searchCustom) {
      _searchCustom = customNow;
      _searchRaw = null;
    }
    if (!identical(raw, _searchRaw) ||
        !identical(title, _searchTitle) ||
        !identical(artist, _searchArtist) ||
        !identical(subtitle, _searchSubtitle)) {
      _searchRaw = raw;
      _searchTitle = title;
      _searchArtist = artist;
      _searchSubtitle = subtitle;
      final more = custom.values.join('\n');
      _searchText = searchKey('$displayTitle\n$artist\n$subtitle\n$raw\n$more');
      _searchWords = searchWords(
        '$displayTitle\n$artist\n$subtitle\n$raw\n$more',
      );
      _searchTitleKey = searchKey(displayTitle);
      _searchTitleWords = searchWords(displayTitle);
      _searchArtistKey = searchKey('$artist $subtitle');
    }
    return _searchText;
  }

  String? _searchRaw, _searchTitle, _searchArtist, _searchSubtitle;
  String _searchCustom = '';
  String _searchText = '';
  Set<String> _searchWords = const {};
  String _searchTitleKey = '';
  Set<String> _searchTitleWords = const {};
  String _searchArtistKey = '';

  /// How well [query] matches this song (lower is better), or null for
  /// no match:
  /// 0 the title exactly, 1 the title's start, 2 within the title, 3 every
  /// word in the title, 4 the artist, 5 the words together in the lyrics,
  /// 6 every word somewhere (as whole words, the last maybe unfinished).
  int? searchRank(String query) {
    searchText; // fills the caches
    final key = searchKey(query);
    if (key.isEmpty) return 0;
    if (_searchTitleKey == key) return 0;
    if (_searchTitleKey.startsWith(key)) return 1;
    if (_searchTitleKey.contains(key)) return 2;
    final words = searchWords(query).toList();
    bool allIn(Set<String> pool) => words.every(
      (w) =>
          w == words.last ? pool.any((p) => p.startsWith(w)) : pool.contains(w),
    );
    if (words.length > 1 && allIn(_searchTitleWords)) return 3;
    if (_searchArtistKey.contains(key)) return 4;
    // Lyrics: the phrase itself (short ones only as whole words).
    if (key.length >= 4 && _searchText.contains(key)) return 5;
    if (allIn(_searchWords)) return 6;
    return null;
  }

  /// The bit of the lyrics [query] was found in, for showing under the
  /// title ("He is Lord of all", "He is … Lord … forever"), or null when
  /// the title or artist matched (or nothing did).
  String? searchSnippet(String query) {
    final rank = searchRank(query);
    if (rank == null || rank < 5) return null;
    final lines = [
      for (final l in raw.split('\n'))
        if (!l.trimLeft().startsWith('{') && !l.trimLeft().startsWith('#'))
          if (l.replaceAll(_chordsForSearch, '').trim() case final t
              when t.isNotEmpty)
            t.replaceAll(RegExp(r'\s+'), ' '),
    ];
    final key = searchKey(query);
    final words = searchWords(query).toList();
    if (rank == 5) {
      // The phrase: in one line, or running over into the next.
      for (var i = 0; i < lines.length; i++) {
        if (searchKey(lines[i]).contains(key)) {
          return _cropLine(lines[i], words);
        }
        if (i + 1 < lines.length &&
            searchKey('${lines[i]} ${lines[i + 1]}').contains(key)) {
          return '${lines[i]} / ${lines[i + 1]}';
        }
      }
    }
    // The words wherever they are: the line with most of them, then the
    // lines with the rest (at most three lines).
    bool hit(String w, String q) => q == words.last ? w.startsWith(q) : w == q;
    Set<String> found(String line) => {
      for (final q in words)
        if (searchWords(line).any((w) => hit(w, q))) q,
    };
    final missing = words.toSet();
    final picked = <int>[];
    while (missing.isNotEmpty && picked.length < 3) {
      var best = -1, bestCount = 0;
      for (var i = 0; i < lines.length; i++) {
        final n = found(lines[i]).intersection(missing).length;
        if (n > bestCount) (best, bestCount) = (i, n);
      }
      if (best < 0) break;
      picked.add(best);
      missing.removeAll(found(lines[best]));
    }
    if (picked.isEmpty) return null;
    picked.sort();
    return [for (final i in picked) _cropLine(lines[i], words)].join(' … ');
  }

  /// [line] shortened around the [words] it has: long lines keep only the
  /// matching words and a couple either side.
  static String _cropLine(String line, List<String> words) {
    final tokens = line.split(' ');
    if (tokens.length <= 9) return line;
    final keep = List.filled(tokens.length, false);
    for (var i = 0; i < tokens.length; i++) {
      final ws = searchWords(tokens[i]);
      final match = words.any(
        (q) => ws.any((w) => q == words.last ? w.startsWith(q) : w == q),
      );
      if (!match) continue;
      for (var j = max(0, i - 2); j <= min(tokens.length - 1, i + 2); j++) {
        keep[j] = true;
      }
    }
    if (!keep.contains(true)) return tokens.take(9).join(' ');
    final out = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (keep[i]) {
        out.add(tokens[i]);
      } else if (out.isEmpty || out.last != '…') {
        out.add('…');
      }
    }
    return out.join(' ');
  }

  String? _keyCacheRaw;
  MusicKey? _keyCache;

  /// The key the song is written in.
  MusicKey? get writtenKey {
    if (key != null) return key;
    if (_keyCacheRaw != raw) {
      _keyCacheRaw = raw;
      _keyCache = detectKey(raw, ChordProHeader.parse(raw).key);
    }
    return _keyCache;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'raw': raw,
    if (transpose != 0) 'transpose': transpose,
    if (capo != 0) 'capo': capo,
    if (key != null) 'key': key!.name,
    if (artist.isNotEmpty) 'artist': artist,
    if (subtitle.isNotEmpty) 'subtitle': subtitle,
    if (tempo.isNotEmpty) 'tempo': tempo,
    if (timeSignature.isNotEmpty) 'timeSignature': timeSignature,
    if (duration.isNotEmpty) 'duration': duration,
    if (composer.isNotEmpty) 'composer': composer,
    if (lyricist.isNotEmpty) 'lyricist': lyricist,
    if (copyright.isNotEmpty) 'copyright': copyright,
    if (ccli.isNotEmpty) 'ccli': ccli,
    if (ccliLicense.isNotEmpty) 'ccliLicense': ccliLicense,
    if (footer.isNotEmpty) 'footer': footer,
    if (notes.isNotEmpty) 'notes': notes,
    if (audioUrl.isNotEmpty) 'audioUrl': audioUrl,
    if (sortTitle.isNotEmpty) 'sortTitle': sortTitle,
    if (tags.isNotEmpty) 'tags': tags,
    if (structure.isNotEmpty)
      'structure': structure.map((i) => i.toJson()).toList(),
    if (date != null) 'date': date!.toIso8601String(),
    if (extra.isNotEmpty) 'extra': extra,
    if (custom.isNotEmpty) 'custom': custom,
  };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
    id: j['id'] as String?,
    title: _str(j['title']),
    raw: _str(j['raw']),
    transpose: (j['transpose'] as num?)?.toInt() ?? 0,
    capo: (j['capo'] as num?)?.toInt() ?? 0,
    key: j['key'] is String ? MusicKey.parse(j['key'] as String) : null,
    artist: _str(j['artist']),
    subtitle: _str(j['subtitle']),
    tempo: _str(j['tempo']),
    timeSignature: _str(j['timeSignature']),
    duration: _str(j['duration']),
    composer: _str(j['composer']),
    lyricist: _str(j['lyricist']),
    copyright: _str(j['copyright']),
    ccli: _str(j['ccli']),
    ccliLicense: _str(j['ccliLicense']),
    footer: _str(j['footer']),
    notes: _str(j['notes']),
    audioUrl: _str(j['audioUrl']),
    sortTitle: _str(j['sortTitle']),
    tags: _strList(j['tags']),
    structure: StructureItem.listFromJson(j['structure']),
    date: _date(j['date']),
    extra: (j['extra'] as Map<String, dynamic>?) ?? {},
    custom: {
      if (j['custom'] is Map)
        for (final e in (j['custom'] as Map).entries) '${e.key}': '${e.value}',
    },
  );
}

enum EntryType { song, divider, label, event, media, bible }

/// One item in a setlist: a song, a divider / label / event marker, a
/// media item (in [SetEntry.media], played when the setlist reaches it) or
/// a Bible passage ([SetEntry.passage]; it lives only in the setlist).
/// [transpose], [capo] and [structure] are used only for songs; transpose
/// and capo apply when the setlist has set-specific edits turned on.
class SetEntry {
  final String id;
  final EntryType type;
  final String? songId;
  String title;
  String? color;
  int transpose;
  int capo;
  List<StructureItem> structure;
  Map<String, dynamic> extra;

  SetEntry({
    String? id,
    this.type = EntryType.song,
    this.songId,
    this.title = '',
    this.color,
    this.transpose = 0,
    this.capo = 0,
    List<StructureItem>? structure,
    Map<String, dynamic>? extra,
  }) : id = id ?? newId(),
       structure = structure ?? [],
       extra = extra ?? {};

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (songId != null) 'songId': songId,
    if (title.isNotEmpty) 'title': title,
    if (color != null) 'color': color,
    if (transpose != 0) 'transpose': transpose,
    if (capo != 0) 'capo': capo,
    if (structure.isNotEmpty)
      'structure': structure.map((i) => i.toJson()).toList(),
    if (extra.isNotEmpty) 'extra': extra,
  };

  /// A media entry's item (and what it does); a song entry's own
  /// background ([background]).
  MediaItem? get media => MediaItem.fromJson(extra['media']);
  LiveMode get mediaMode =>
      LiveMode.values.asNameMap()[extra['mode']] ?? LiveMode.play;
  MediaItem? get background => MediaItem.fromJson(extra['bg']);

  /// A Bible entry's passage.
  BiblePassage? get passage => BiblePassage.fromJson(extra['bible']);

  /// Songs nested under this one (ChordPro Presenter's own): played right
  /// after it as one song. Kept in [extra], so other apps reading the
  /// setlist never meet them; they get it flattened (see
  /// [Setlist.flattened]).
  List<String> get subSongIds => [
    for (final id in (extra['subSongs'] as List?) ?? const [])
      if (id is String) id,
  ];
  set subSongIds(List<String> ids) {
    if (ids.isEmpty) {
      extra.remove('subSongs');
    } else {
      extra['subSongs'] = ids;
    }
  }

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
    id: j['id'] as String?,
    type: EntryType.values.asNameMap()[j['type']] ?? EntryType.song,
    songId: j['songId'] as String?,
    title: _str(j['title']),
    color: j['color'] as String?,
    transpose: (j['transpose'] as num?)?.toInt() ?? 0,
    capo: (j['capo'] as num?)?.toInt() ?? 0,
    structure: StructureItem.listFromJson(j['structure']),
    extra: (j['extra'] as Map<String, dynamic>?) ?? {},
  );
}

/// App-wide preferences (appearance, fonts, layout).
class AppSettings {
  String themeId = 'default';
  UiStyle uiStyle = UiStyle.material;
  ThemeModeSetting mode = ThemeModeSetting.system;

  /// Pure black backgrounds in dark mode (OLED screens).
  bool oled = false;

  /// E-ink look: black and white, no animations, lists turn pages.
  bool eink = false;

  /// Colour the music sheet with the theme; off = plain light/dark.
  bool themeMusic = true;

  /// PDFs and pictures: trimmed to what's printed (no empty margins), and
  /// recoloured to the theme (paper → background, ink → text colour).
  bool sheetCrop = false;
  bool sheetThemeColors = false;

  /// Sidebar floats over the music instead of taking its own column.
  bool floatingSidebar = false;

  /// Presentation mode: slides as a grid of tiles instead of the sheet.
  bool presentationMode = false;

  /// Name shown to others in Band Sync ("" = the device's kind).
  String bandNickname = '';

  // ---- Chord diagrams (see chords/) ----

  /// A strip of the song's chords under its title.
  bool showChordDiagrams = false;
  Instrument chordInstrument = Instrument.guitar;
  bool showDiagramFingers = true;
  double diagramZoom = 1.0;

  /// The strip folded away (its chevron).
  bool diagramsCollapsed = false;

  /// Tapping a chord in the song shows its diagrams (tap one to hear it).
  bool tapChords = false;
  ChordPlaySpeed chordPlaySpeed = ChordPlaySpeed.medium;

  /// The shape chosen for a chord ("guitar|F#m" → shape id).
  Map<String, String> chordPrefs = {};

  /// Shapes the person made (Chord Editor).
  List<ChordShape> customChords = [];

  /// The top toolbar, as arranged by the person (button ids, see
  /// toolbar_items.dart): shown in the bar, and in its ⋯ menu. Null: the
  /// usual arrangement for the screen size.
  List<String>? toolbarBar;
  List<String>? toolbarMore;

  /// Quick buttons in the bottom bar.
  bool showMetronome = true;

  /// On in the phone / tablet apps (the device's own microphone).
  bool showTuner = !kIsWeb;
  bool showAutoscroll = true;

  /// Play button for a song's reference recording (YouTube…).
  bool showPlayer = true;

  /// The worship pad (a quick button): its sound ('warm', 'shimmer',
  /// 'soft' or `sf:<id>`), SoundFont presets taken in ({id, name, file}),
  /// volume, crossfade seconds, tone (0 dark – 1 bright), reverb (0–1),
  /// octave and whether it follows the song's key.
  bool showPads = true;

  /// Gospelizer (✨): its chords glow (off: added ones in brackets,
  /// "(D7)"), and whether it keeps the song's own chords as written (off:
  /// it may also recolour and substitute them).
  bool gospelGlow = true;
  bool gospelKeep = true;

  /// The Gospelizer's quick button in the bottom bar.
  bool showGospel = true;

  /// The tuner's Levels tab: how the level is measured (a [LevelMethod]
  /// name; everyday sound level unless chosen otherwise), its gain, and
  /// the sound level's calibration (dB added).
  String levelsMethod = 'soundLevel';
  double levelsScale = 1;
  int levelsCalibration = 0;
  String padSound = 'warm';
  List<Map<String, String>> padSounds = [];
  double padVolume = 0.7;
  double padFade = 3;
  double padTone = 0.6;
  double padReverb = 0.35;
  int padOctave = 0;
  bool padFollow = true;

  /// Worship Leader song database languages searched in Find songs.
  List<String> songDbLangs = ['en', 'fr'];

  /// Song sites the user added to "Search other sites" ({name, url}).
  List<Map<String, dynamic>> songSites = [];

  /// Font for editable PowerPoint slides.
  String pptxFont = 'Arial';

  /// Last language slides were translated into (Google code).
  String translateTo = 'fr';

  /// Tuner reference pitch for A4 (Hz).
  int tunerA4 = 440;

  /// Columns in the presentation grid (1–5; pinch to change).
  int presentColumns = 3;
  String sheetFont = 'default';
  String chordFont = 'default';
  String projectorFont = 'default';
  final List<CustomFont> customFonts = [];

  List<FontOption> get fontOptions => [
    ...builtInFonts,
    for (final c in customFonts) c.option,
  ];

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'uiStyle': uiStyle.name,
    'mode': mode.name,
    'oled': oled,
    'eink': eink,
    'themeMusic': themeMusic,
    'sheetCrop': sheetCrop,
    'sheetThemeColors': sheetThemeColors,
    'floatingSidebar': floatingSidebar,
    'presentationMode': presentationMode,
    if (bandNickname.isNotEmpty) 'bandNickname': bandNickname,
    'showChordDiagrams': showChordDiagrams,
    'chordInstrument': chordInstrument.name,
    'showDiagramFingers': showDiagramFingers,
    'diagramZoom': diagramZoom,
    'diagramsCollapsed': diagramsCollapsed,
    'tapChords': tapChords,
    'chordPlaySpeed': chordPlaySpeed.name,
    if (chordPrefs.isNotEmpty) 'chordPrefs': chordPrefs,
    if (customChords.isNotEmpty)
      'customChords': [for (final c in customChords) c.toJson()],
    if (toolbarBar != null)
      'toolbar': {'bar': toolbarBar, 'more': toolbarMore ?? const []},
    'showMetronome': showMetronome,
    'showPads': showPads,
    'gospelGlow': gospelGlow,
    'gospelKeep': gospelKeep,
    'showGospel': showGospel,
    // (A new key: the earlier default was the negative dBFS reading.)
    'levelMethod': levelsMethod,
    'levelsScale': levelsScale,
    'levelsCalibration': levelsCalibration,
    'padSound': padSound,
    if (padSounds.isNotEmpty) 'padSounds': padSounds,
    'padVolume': padVolume,
    'padFade': padFade,
    'padTone': padTone,
    'padReverb': padReverb,
    'padOctave': padOctave,
    'padFollow': padFollow,
    'showTuner': showTuner,
    'translateTo': translateTo,
    'pptxFont': pptxFont,
    if (songSites.isNotEmpty) 'songSites': songSites,
    'songDbLangs': songDbLangs,
    'showAutoscroll': showAutoscroll,
    'showPlayer': showPlayer,
    'tunerA4': tunerA4,
    'presentColumns': presentColumns,
    'sheetFont': sheetFont,
    'chordFont': chordFont,
    'projectorFont': projectorFont,
    'customFonts': customFonts.map((f) => f.toJson()).toList(),
  };

  void updateFrom(Map<String, dynamic> j) {
    themeId = j['themeId'] as String? ?? themeId;
    uiStyle = UiStyle.values.asNameMap()[j['uiStyle']] ?? uiStyle;
    mode = ThemeModeSetting.values.asNameMap()[j['mode']] ?? mode;
    oled = j['oled'] as bool? ?? oled;
    eink = j['eink'] as bool? ?? eink;
    themeMusic = j['themeMusic'] as bool? ?? themeMusic;
    sheetCrop = j['sheetCrop'] as bool? ?? sheetCrop;
    sheetThemeColors = j['sheetThemeColors'] as bool? ?? sheetThemeColors;
    floatingSidebar = j['floatingSidebar'] as bool? ?? floatingSidebar;
    presentationMode = j['presentationMode'] as bool? ?? presentationMode;
    bandNickname = j['bandNickname'] as String? ?? bandNickname;
    showChordDiagrams = j['showChordDiagrams'] as bool? ?? showChordDiagrams;
    chordInstrument =
        Instrument.values.asNameMap()[j['chordInstrument']] ?? chordInstrument;
    showDiagramFingers = j['showDiagramFingers'] as bool? ?? showDiagramFingers;
    diagramZoom = ((j['diagramZoom'] as num?)?.toDouble() ?? diagramZoom).clamp(
      0.6,
      2.0,
    );
    diagramsCollapsed = j['diagramsCollapsed'] as bool? ?? diagramsCollapsed;
    tapChords =
        j['tapChords'] as bool? ??
        // (Earlier: chord buttons, or tap / double tap for diagrams.)
        (j['chordButtons'] == true ||
                (j['chordTapAction'] != null &&
                    j['chordTapAction'] != 'off')) ||
            tapChords;
    chordPlaySpeed =
        ChordPlaySpeed.values.asNameMap()[j['chordPlaySpeed']] ??
        chordPlaySpeed;
    final prefs = j['chordPrefs'];
    if (prefs is Map) {
      chordPrefs = {for (final e in prefs.entries) '${e.key}': '${e.value}'};
    }
    final custom = j['customChords'];
    if (custom is List) {
      customChords = [for (final c in custom) ?ChordShape.fromJson(c)];
    }
    final tb = j['toolbar'];
    if (tb is Map) {
      toolbarBar = [for (final e in (tb['bar'] as List?) ?? const []) '$e'];
      toolbarMore = [for (final e in (tb['more'] as List?) ?? const []) '$e'];
    }
    showMetronome = j['showMetronome'] as bool? ?? showMetronome;
    showPads = j['showPads'] as bool? ?? showPads;
    gospelGlow = j['gospelGlow'] as bool? ?? gospelGlow;
    gospelKeep = j['gospelKeep'] as bool? ?? gospelKeep;
    showGospel = j['showGospel'] as bool? ?? showGospel;
    levelsMethod = j['levelMethod'] as String? ?? levelsMethod;
    levelsScale = (j['levelsScale'] as num?)?.toDouble() ?? levelsScale;
    levelsCalibration =
        (j['levelsCalibration'] as num?)?.toInt() ?? levelsCalibration;
    padSound = j['padSound'] as String? ?? padSound;
    padSounds = [
      for (final m in (j['padSounds'] as List?) ?? const [])
        if (m is Map) {for (final e in m.entries) '${e.key}': '${e.value}'},
    ];
    double num01(String k, double v) =>
        ((j[k] as num?)?.toDouble() ?? v).clamp(0.0, 1.0);
    padVolume = num01('padVolume', padVolume);
    padTone = num01('padTone', padTone);
    padReverb = num01('padReverb', padReverb);
    padFade = ((j['padFade'] as num?)?.toDouble() ?? padFade).clamp(0.0, 10.0);
    padOctave = ((j['padOctave'] as num?)?.toInt() ?? padOctave).clamp(-1, 2);
    padFollow = j['padFollow'] as bool? ?? padFollow;
    showTuner = j['showTuner'] as bool? ?? showTuner;
    translateTo = j['translateTo'] as String? ?? translateTo;
    pptxFont = j['pptxFont'] as String? ?? pptxFont;
    songDbLangs = [
      for (final e in (j['songDbLangs'] as List?) ?? songDbLangs)
        if (e is String) e,
    ];
    songSites = [
      for (final e in (j['songSites'] as List?) ?? const [])
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    showAutoscroll = j['showAutoscroll'] as bool? ?? showAutoscroll;
    showPlayer = j['showPlayer'] as bool? ?? showPlayer;
    tunerA4 = ((j['tunerA4'] as num?)?.toInt() ?? tunerA4).clamp(415, 466);
    presentColumns = ((j['presentColumns'] as num?)?.toInt() ?? presentColumns)
        .clamp(1, 5);
    sheetFont = j['sheetFont'] as String? ?? sheetFont;
    chordFont = j['chordFont'] as String? ?? chordFont;
    projectorFont = j['projectorFont'] as String? ?? projectorFont;
    customFonts
      ..clear()
      ..addAll(
        ((j['customFonts'] as List?) ?? []).cast<Map<String, dynamic>>().map(
          CustomFont.fromJson,
        ),
      );
  }
}

enum ThemeModeSetting { system, light, dark }

class Setlist {
  final String id;
  String name;

  /// When on, key and capo changes made inside this setlist stay in the
  /// setlist instead of changing the song itself.
  bool setSpecific;
  final List<SetEntry> entries;
  DateTime? eventDate;
  String notes;
  DateTime? date;
  Map<String, dynamic> extra;

  Setlist({
    String? id,
    required this.name,
    this.setSpecific = false,
    List<SetEntry>? entries,
    this.eventDate,
    this.notes = '',
    this.date,
    Map<String, dynamic>? extra,
  }) : id = id ?? newId(),
       entries = entries ?? [],
       extra = extra ?? {};

  int get songCount => entries.where((e) => e.type == EntryType.song).length;

  /// The setlist as other apps read it (JustChords, Band Sync): each
  /// nested song an entry of its own right after its song, which keeps
  /// only the parts of its arrangement that are its own. [songOf]: a
  /// song by id (for its sections and its key).
  Setlist flattened(Song? Function(String id) songOf) {
    if (!entries.any((e) => e.subSongIds.isNotEmpty)) return this;
    String key(String name) => name.toLowerCase().trim();
    return Setlist(
      id: id,
      name: name,
      setSpecific: setSpecific,
      eventDate: eventDate,
      notes: notes,
      date: date,
      extra: extra,
      entries: [
        for (final e in entries)
          if (e.subSongIds.isEmpty)
            e
          else ...[
            SetEntry(
              id: e.id,
              type: e.type,
              songId: e.songId,
              title: e.title,
              color: e.color,
              transpose: e.transpose,
              capo: e.capo,
              structure: () {
                final own = {
                  for (final n in ChordPro.sectionNames(
                    songOf(e.songId ?? '')?.raw ?? '',
                  ))
                    key(n),
                };
                return [
                  for (final item in e.structure)
                    if (item.isModulation || own.contains(key(item.name))) item,
                ];
              }(),
              extra: {...e.extra}..remove('subSongs'),
            ),
            for (final (i, sub) in e.subSongIds.indexed)
              SetEntry(
                id: '${e.id}-sub$i',
                songId: sub,
                transpose: songOf(sub)?.transpose ?? 0,
                capo: songOf(sub)?.capo ?? 0,
              ),
          ],
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'setSpecific': setSpecific,
    'entries': entries.map((e) => e.toJson()).toList(),
    if (eventDate != null) 'eventDate': eventDate!.toIso8601String(),
    if (notes.isNotEmpty) 'notes': notes,
    if (date != null) 'date': date!.toIso8601String(),
    if (extra.isNotEmpty) 'extra': extra,
  };

  factory Setlist.fromJson(Map<String, dynamic> j) => Setlist(
    id: j['id'] as String?,
    name: (j['name'] as String?) ?? 'Setlist',
    setSpecific: (j['setSpecific'] as bool?) ?? false,
    entries: ((j['entries'] as List?) ?? [])
        .map((e) => SetEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    eventDate: _date(j['eventDate']),
    notes: _str(j['notes']),
    date: _date(j['date']),
    extra: (j['extra'] as Map<String, dynamic>?) ?? {},
  );
}

/// Slide state shared by the operator screen and projector windows.
class SlideState extends ChangeNotifier {
  List<String> slides = [];
  int index = 0;
  double fontScale = 1.0;
  double transitionDuration = 0.25;
  String projectorFont = 'default';

  String get currentSlide =>
      (index >= 0 && index < slides.length) ? slides[index] : '';

  void next() => goTo(index + 1);
  void previous() => goTo(index - 1);

  /// The selected slide, as its own lightweight signal: moving between
  /// parts only repaints the selection bar, counter and preview instead of
  /// rebuilding the whole window.
  final ValueNotifier<int> selection = ValueNotifier(0);

  void goTo(int newIndex, {bool broadcast = true}) {
    if (slides.isEmpty) return;
    final clamped = newIndex.clamp(0, slides.length - 1);
    if (clamped == index) return;
    index = clamped;
    selection.value = index;
    if (broadcast) sync.send({'type': 'index', 'index': index});
    noteSongUse();
    onIndexChanged();
  }

  /// Records that the song on screen is being used. The base does
  /// nothing; the operator's model keeps the usage log.
  void noteSongUse() {}

  /// Projector windows redraw fully; the operator only uses [selection].
  @protected
  void onIndexChanged() => notifyListeners();

  final SyncChannel sync = SyncChannel();
}

class ImportSummary {
  final int songs;
  final int setlists;
  final int tags;
  final int trashed;
  const ImportSummary(this.songs, this.setlists, this.tags, this.trashed);

  bool get isEmpty => songs + setlists + tags + trashed == 0;

  @override
  String toString() {
    final parts = [
      if (songs > 0) '$songs song${songs == 1 ? '' : 's'}',
      if (setlists > 0) '$setlists setlist${setlists == 1 ? '' : 's'}',
      if (tags > 0) '$tags tag${tags == 1 ? '' : 's'}',
      if (trashed > 0) '$trashed in Trash',
    ];
    return 'Imported ${parts.join(', ')}.';
  }
}

/// One of the libraries (folders) a person keeps: its own songs, tags,
/// setlists and trash. Settings are shared by all of them.
class LibraryInfo {
  final String id;
  String name;
  LibraryInfo(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static LibraryInfo? fromJson(Object? j) => j is Map && j['id'] is String
      ? LibraryInfo(j['id'] as String, '${j['name'] ?? 'Library'}')
      : null;
}

/// The operator's full state: songs, tags, setlists, trash, formatting and
/// slides. Saved in the browser (IndexedDB).
class PresenterModel extends SlideState {
  static const _storageKey = 'bilingual_projector_state';

  /// The open song is saved on its own (a few bytes), so flipping through
  /// songs never rewrites the whole library.
  static const _selectionKey = 'bilingual_projector_selection';
  int? _restoreSlide;
  Timer? _selectionTimer;

  /// Where things were left while the app is open: the side pane (list,
  /// sort, filters, search, scroll), the panels open, the sheet's place.
  /// Closing and opening the side pane or rotating comes back to it; a
  /// fresh start of the app starts fresh (it isn't saved).
  final Map<String, Object?> ui = {};

  /// [key] from [ui], if it's a [T].
  T? uiValue<T>(String key) => ui[key] is T ? ui[key] as T : null;

  /// Remembers [value] under [key] (until the app is closed).
  void setUi(String key, Object? value) {
    final old = ui[key];
    if (old == value ||
        (old is List && value is List && listEquals(old, value))) {
      return;
    }
    if (value == null) {
      ui.remove(key);
    } else {
      ui[key] = value;
    }
  }

  void _saveSelection() {
    final data = jsonEncode({
      'song': selectedSongId,
      'setlist': activeSetlistId,
      'entry': activeEntryId,
      'slide': selection.value,
    });
    _selectionTimer?.cancel();
    if (saveDelay == Duration.zero) {
      _store.write(_selectionKey, data);
      return;
    }
    _selectionTimer = Timer(const Duration(milliseconds: 800), () {
      _store.write(_selectionKey, data);
    });
  }

  final List<Song> songs = [];
  final List<Song> trash = [];
  final List<Tag> tags = [];
  final List<Setlist> setlists = [];

  // ---- Libraries ----
  // The open library lives in the main save (as it always has); each
  // library is also kept under its own key, written when switching away.

  final List<LibraryInfo> libraries = [LibraryInfo('main', 'My Library')];
  String libraryId = 'main';

  LibraryInfo get currentLibrary => libraries.firstWhere(
    (l) => l.id == libraryId,
    orElse: () => libraries.first,
  );

  static String _libraryKey(String id) => 'bilingual_projector_library_$id';

  Map<String, dynamic> _libraryJson() => {
    'songs': songs.map((s) => s.toJson()).toList(),
    'tags': tags.map((t) => t.toJson()).toList(),
    'setlists': setlists.map((s) => s.toJson()).toList(),
    'trash': trash.map((s) => s.toJson()).toList(),
    'selectedSongID': selectedSongId,
    'backupIdentity': ?backupIdentity,
  };

  void _applyLibrary(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String k) =>
        ((json[k] as List?) ?? []).cast<Map<String, dynamic>>();
    songs
      ..clear()
      ..addAll(list('songs').map(Song.fromJson));
    trash
      ..clear()
      ..addAll(list('trash').map(Song.fromJson));
    tags
      ..clear()
      ..addAll(list('tags').map(Tag.fromJson));
    setlists
      ..clear()
      ..addAll(list('setlists').map(Setlist.fromJson));
    selectedSongId = json['selectedSongID'] as String?;
    backupIdentity = json['backupIdentity'] as String?;
  }

  /// Opens library [id]: the open one is put away first.
  Future<void> switchLibrary(String id) async {
    // Editing another computer's library: that one only.
    if (remoteEdit) return;
    if (id == libraryId || !libraries.any((l) => l.id == id)) return;
    await _store.write(_libraryKey(libraryId), jsonEncode(_libraryJson()));
    Map<String, dynamic> next = const {};
    try {
      final stored = await _store.read(_libraryKey(id));
      if (stored != null) next = jsonDecode(stored) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Failed to load library $id: $e');
    }
    _applyLibrary(next);
    libraryId = id;
    activeSetlistId = null;
    activeEntryId = null;
    if (currentSong == null) {
      selectedSongId = songs.isEmpty ? null : songs.first.id;
    }
    _rebuildSlides();
    _saveSelection();
    await flush();
    notifyListeners();
    broadcastState();
  }

  /// A new, empty library, opened straight away.
  Future<LibraryInfo> createLibrary(String name) async {
    final lib = LibraryInfo(newId(), name.trim().isEmpty ? 'Library' : name);
    libraries.add(lib);
    await _store.write(_libraryKey(lib.id), jsonEncode(<String, dynamic>{}));
    await switchLibrary(lib.id);
    return lib;
  }

  void renameLibrary(String id, String name) {
    final lib = libraries.where((l) => l.id == id).firstOrNull;
    if (lib == null || name.trim().isEmpty) return;
    lib.name = name.trim();
    _save();
    notifyListeners();
  }

  /// Deletes a library that isn't open (with its songs, setlists…).
  Future<void> deleteLibrary(String id) async {
    if (remoteEdit || id == libraryId || libraries.length < 2) return;
    libraries.removeWhere((l) => l.id == id);
    await _store.delete(_libraryKey(id));
    _save();
    notifyListeners();
  }

  final SheetFormat format = SheetFormat();
  final AppSettings settings = AppSettings();

  /// The current song split into parts (sections). Each non-marker part is
  /// one slide; [slidePartIndex] maps slide number -> part index.
  List<SongPart> parts = [];
  List<int> slidePartIndex = [];

  /// Part index of the selected slide (-1 if none).
  int get selectedPart =>
      index < slidePartIndex.length ? slidePartIndex[index] : -1;

  /// Selects (and projects) the part at [partIndex].
  void selectPart(int partIndex) {
    final slide = slidePartIndex.indexOf(partIndex);
    if (slide >= 0) goTo(slide);
  }

  void firstSlide() => goTo(0);
  void lastSlide() => goTo(slides.length - 1);
  final Metronome metronome = Metronome();

  /// The worship pad (made when first used).
  late final PadController pads = PadController(this);
  final Autoscroll autoscroll = Autoscroll();
  String? selectedSongId;

  /// Size of the projector window (logical pixels), reported by the
  /// projector, so the preview can be an exact scale model of it.
  Size projectorSize = const Size(1280, 720);

  void _projectorSizeFrom(Map<String, dynamic> msg) {
    final w = (msg['w'] as num?)?.toDouble();
    final h = (msg['h'] as num?)?.toDouble();
    if (w == null || h == null || w < 50 || h < 50) return;
    final size = Size(w, h);
    if (size == projectorSize) return;
    projectorSize = size;
    notifyListeners();
  }

  /// When a projector window last said it is open.
  DateTime? _projectorSeen;
  Timer? _projectorCheck;

  /// True while a projector window is open (it checks in every 2 s).
  bool get projectorActive =>
      _projectorSeen != null &&
      DateTime.now().difference(_projectorSeen!) < const Duration(seconds: 5);

  /// Tests: as if a projector window opened (or closed).
  @visibleForTesting
  void debugProjecting(bool on) => _projectorAlive(on);

  void _projectorAlive(bool alive) {
    final was = projectorActive;
    _projectorSeen = alive ? DateTime.now() : null;
    if (was != projectorActive) notifyListeners();
    if (!alive) {
      _projectorCheck?.cancel();
      _projectorCheck = null;
      return;
    }
    // Notice a projector that closed without saying goodbye (crash, etc.).
    _projectorCheck ??= Timer.periodic(const Duration(seconds: 2), (t) {
      if (!projectorActive) {
        t.cancel();
        _projectorCheck = null;
        _projectorSeen = null;
        notifyListeners();
      }
    });
  }

  /// Set when the current song was opened from a setlist.
  String? activeSetlistId;
  String? activeEntryId;

  final KeyValueStore _store = KeyValueStore();
  Timer? _saveTimer;

  // ---- Lookups ----

  Song? songById(String? id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return bandSongs[id] ?? bibleSongs[id];
  }

  Tag? tagById(String id) {
    for (final t in tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  Song? get currentSong => songById(selectedSongId);

  Setlist? setlistById(String? id) {
    for (final s in setlists) {
      if (s.id == id) return s;
    }
    final band = bandSetlist;
    return band != null && band.id == id ? band : null;
  }

  // ---- Band Sync (see band_sync/) ----

  /// Following a Band Sync session: the leader's setlist and songs. Shown
  /// like the others, never saved, exported or synced.
  Setlist? bandSetlist;
  final Map<String, Song> bandSongs = {};

  BandSync? _bandSync;
  BandSync get bandSync => _bandSync ??= BandSync(this);

  /// Puts the leader's setlist in place (null: the session ended). The
  /// song open from it stays open (redrawn with the leader's changes).
  void setBandSetlist(Setlist? set, List<Song> songs) {
    final wasBand = bandSongs.containsKey(selectedSongId);
    bandSetlist = set;
    bandSongs
      ..clear()
      ..addEntries([for (final s in songs) MapEntry(s.id, s)]);
    if (wasBand) {
      if (currentSong == null) {
        selectedSongId = this.songs.isEmpty ? null : this.songs.first.id;
        activeSetlistId = null;
        activeEntryId = null;
        _rebuildSlides();
      } else {
        _rebuildSlides(keepIndex: true);
      }
    }
    notifyListeners();
  }

  /// The setlist's song entry that's open (not a media entry being
  /// played: the song before it stays open behind it).
  SetEntry? get activeEntry {
    final set = setlistById(activeSetlistId);
    if (set == null) return null;
    for (final e in set.entries) {
      if (e.id == activeEntryId) return e.type == EntryType.song ? e : null;
    }
    return null;
  }

  /// True when key/capo changes should be stored on the setlist entry.
  bool get editingSetSpecific =>
      activeEntry != null && setlistById(activeSetlistId)!.setSpecific;

  int transposeFor(Song song, {SetEntry? entry, Setlist? setlist}) =>
      (entry != null && setlist != null && setlist.setSpecific)
      ? entry.transpose
      : song.transpose;

  int capoFor(Song song, {SetEntry? entry, Setlist? setlist}) =>
      (entry != null && setlist != null && setlist.setSpecific)
      ? entry.capo
      : song.capo;

  /// Sounding key offset (what the audience hears).
  int get currentTranspose {
    final song = currentSong;
    if (song == null) return 0;
    return editingSetSpecific ? activeEntry!.transpose : song.transpose;
  }

  int get currentCapo {
    final song = currentSong;
    if (song == null) return 0;
    return editingSetSpecific ? activeEntry!.capo : song.capo;
  }

  /// Offset for the chord shapes shown (sounding key minus capo).
  int get shapeTranspose => currentTranspose - currentCapo;

  /// The key the song sounds in.
  MusicKey? get currentKey =>
      currentSong?.writtenKey?.transposed(currentTranspose);

  /// The key of the chord shapes shown (differs from [currentKey] with capo).
  MusicKey? get shapeKey => currentSong?.writtenKey?.transposed(shapeTranspose);

  /// Section order in effect: the setlist entry's arrangement, else the
  /// song's own.
  List<StructureItem> get currentStructure {
    final song = playedCurrentSong;
    if (song == null) return const [];
    return structureFor(song, activeEntry);
  }

  /// The open song as it plays: with the songs nested under its setlist
  /// entry after it (see [playedSong]). Never saved: edits go to the song.
  Song? get playedCurrentSong {
    final song = currentSong;
    if (song == null) return null;
    return playedSong(song, activeEntry, set: setlistById(activeSetlistId));
  }

  /// [song] as [entry] plays it: the songs nested under the entry after it,
  /// as one song. Their sections are renamed where a name is taken
  /// ("Verse 1 (Song B)"), so an arrangement can pick from any of them;
  /// each song's chords stay in its own key. With no arrangement for any
  /// of them, they simply follow one another.
  Song playedSong(Song song, SetEntry? entry, {Setlist? set}) {
    final subs = [
      for (final id in entry?.subSongIds ?? const <String>[]) ?songById(id),
    ];
    if (subs.isEmpty) return song;
    // (Each song with its own Gospelizer chords, if on.)
    String own(Song s) => s.gospelRaw(mark: true);
    final parentShift = transposeFor(song, entry: entry, setlist: set);
    final cacheKey = [
      entry!.id,
      parentShift,
      own(song),
      jsonEncode(song.structure),
      for (final c in subs) ...[own(c), c.transpose, jsonEncode(c.structure)],
    ].join('\u0000');
    final hit = _playedCache[cacheKey];
    if (hit != null) return hit;

    String key(String name) => name.toLowerCase().trim();
    final base = ChordPro.labelSections(own(song), title: song.title);
    final taken = {for (final n in ChordPro.sectionNames(base)) key(n)};
    // Section -> whose it is: 0 the song itself, 1… the nested ones.
    final origins = {for (final k in taken) k: 0};
    final pieces = [base];
    var anyOrder = song.structure.isNotEmpty;
    final order = <StructureItem>[
      ...song.structure.isNotEmpty
          ? song.structure
          : [
              for (final n in ChordPro.sectionNames(base))
                StructureItem.section(n),
            ],
    ];
    for (final c in subs) {
      // Its own title, artist, key… lines aren't the combined song's.
      var raw = ChordPro.labelSections(
        own(c).split('\n').where((l) => !_songInfoLine.hasMatch(l)).join('\n'),
        title: c.title,
      );
      // Its chords in its own key (the sheet shows them all moved by the
      // first song's transposition).
      final shift = normalizeTranspose(c.transpose - parentShift);
      if (shift != 0) {
        raw = rewriteIntoKey(
          raw,
          shift,
          (c.writtenKey ?? song.writtenKey ?? const MusicKey(0, false))
              .transposed(shift),
        );
      }
      final renames = <String, String>{};
      for (final n in ChordPro.sectionNames(raw)) {
        final k = key(n);
        if (renames.containsKey(k)) continue;
        // (A translation's language stays last: "Verse 1 (Song B) (FR)",
        // still paired with "Verse 1 (Song B)".)
        final lang = RegExp(r'\s*\([A-Z]{2,3}(?:-[A-Z]{2})?\)$')
            .firstMatch(n)
            ?.group(0);
        final named = !taken.contains(k)
            ? n
            : lang == null
            ? '$n (${c.displayTitle})'
            : '${n.substring(0, n.length - lang.length)} '
                  '(${c.displayTitle})$lang';
        renames[k] = named;
        taken.add(key(named));
        origins[key(named)] = pieces.length;
      }
      raw = [
        for (final line in raw.split('\n'))
          if (ChordPro.sectionName(line) case final n?
              when renames[key(n)] != null && renames[key(n)] != n)
            '${renames[key(n)]}:'
          else
            line,
      ].join('\n');
      pieces.add(raw);
      anyOrder = anyOrder || c.structure.isNotEmpty;
      order.addAll(
        c.structure.isNotEmpty
            ? [
                for (final item in c.structure)
                  item.isModulation
                      ? item
                      : StructureItem.section(
                          renames[key(item.name)] ?? item.name,
                          linked: item.linked,
                        ),
              ]
            : [
                for (final n in ChordPro.sectionNames(raw))
                  StructureItem.section(n),
              ],
      );
    }
    final played = song.copy()
      ..raw = pieces.join('\n\n')
      ..structure = anyOrder ? order : [];
    // (Its pieces have their Gospelizer chords in already.)
    played.extra.remove('gospel');
    _origins[played] = origins;
    if (_playedCache.length > 16) _playedCache.remove(_playedCache.keys.first);
    return _playedCache[cacheKey] = played;
  }

  final Map<String, Song> _playedCache = {};
  final Expando<Map<String, int>> _origins = Expando();

  /// Which song part [part] of the open song comes from: 0 the song
  /// itself, 1… the songs nested under its setlist entry.
  int nestedSongOfPart(int part) {
    final origins = _origins[playedCurrentSong ?? Object()];
    if (origins == null || part < 0 || part >= parts.length) return 0;
    for (final line in parts[part].lines) {
      if (line.trim().isEmpty) continue;
      final name = ChordPro.sectionName(line);
      return name == null ? 0 : origins[name.toLowerCase().trim()] ?? 0;
    }
    return 0;
  }

  /// Song information lines ({title:}, {artist:}, {key:}…), left out when
  /// a song is nested under another.
  static final _songInfoLine = RegExp(
    r'^\s*\{\s*(title|t|subtitle|st|artist|composer|lyricist|key|capo|'
    r'tempo|time|duration|ccli|copyright|album|year|sorttitle)\s*:',
    caseSensitive: false,
  );

  /// The order [song] plays in: the setlist entry's arrangement, else the
  /// song's own, else as written — with each translation still linked to
  /// its section (so an empty order never splits them apart).
  List<StructureItem> structureFor(Song song, SetEntry? entry) {
    final own = entry != null && entry.structure.isNotEmpty
        ? entry.structure
        : song.structure;
    if (own.isNotEmpty || translatedLanguages(song.raw).isEmpty) return own;
    return withTranslations(song.raw, const []);
  }

  /// The song text with the arrangement applied (if turned on).
  String get effectiveRaw {
    final song = playedCurrentSong;
    if (song == null) return '';
    final raw = song.gospelRaw(mark: true);
    if (!format.followArrangement) return raw;
    return ChordPro.applyStructure(raw, currentStructure);
  }

  /// Gospelizer (✨) on or off for the open song: passing chords added
  /// between its own (kept apart from its text; see gospelizer.dart).
  void setGospel(bool on) {
    final song = currentSong;
    if (song == null) return;
    song.setGospel(on, keep: settings.gospelKeep);
    _playedCache.clear();
    _rebuildSlides(keepIndex: true);
    broadcastState();
    _save();
    notifyListeners();
  }

  /// Gospelizer's "keep the song's chords" changed: songs with it on are
  /// worked out again.
  void setGospelKeep(bool keep) {
    settings.gospelKeep = keep;
    for (final s in songs) {
      if (s.gospelOn) s.setGospel(true, keep: keep);
    }
    _playedCache.clear();
    _rebuildSlides(keepIndex: true);
    broadcastState();
    _save();
    notifyListeners();
  }

  void setTranspose(int semitones) {
    final song = currentSong;
    if (song == null) return;
    final value = normalizeTranspose(semitones);
    if (editingSetSpecific) {
      activeEntry!.transpose = value;
    } else {
      song.transpose = value;
    }
    broadcastState();
    _save();
    notifyListeners();
  }

  void setCapo(int capo) {
    final song = currentSong;
    if (song == null) return;
    if (editingSetSpecific) {
      activeEntry!.capo = capo;
    } else {
      song.capo = capo;
    }
    broadcastState();
    _save();
    notifyListeners();
  }

  // ---- Load / save ----

  Future<void> load() async {
    try {
      final stored = await _store.read(_mainKey);
      if (stored != null) {
        _applyJson(jsonDecode(stored) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to load saved library: $e');
    }
    if (remoteEdit) {
      await _joinRemote();
      if (await _store.read('remote_control') == '1') {
        remoteControl = true;
        sync.send({'type': 'remoteHello'});
      }
    }
    try {
      final sel = await _store.read(_selKey);
      if (sel != null) {
        final j = jsonDecode(sel) as Map<String, dynamic>;
        _restoreSlide = j['slide'] as int?;
        final id = j['song'] as String?;
        if (songById(id) != null) {
          selectedSongId = id;
          final set = setlistById(j['setlist'] as String?);
          final entryId = j['entry'] as String?;
          if (set != null && set.entries.any((e) => e.id == entryId)) {
            activeSetlistId = set.id;
            activeEntryId = entryId;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load selection: $e');
    }
    // A first start gets a sample song (an extra library starts empty).
    if (remoteEdit) {
      if (currentSong == null && songs.isNotEmpty) {
        selectedSongId = songs.first.id;
      }
    } else if (songs.isEmpty && libraries.length == 1) {
      final sample = Song(title: 'Amazing Grace', raw: sampleChordPro);
      songs.add(sample);
      selectedSongId = sample.id;
      _save();
    } else if (currentSong == null) {
      selectedSongId = songs.first.id;
    }
    _rebuildSlides();
    // The slide that was showing (if the song still has it).
    if (_restoreSlide case final i? when i >= 0 && i < slides.length) {
      selection.value = i;
    }
    _restoreSlide = null;
    selection.addListener(_saveSelection);
    _snapshotLibrary();

    // Projector windows ask for the current state when they open, and
    // may change the slide with their own keyboard.
    sync.messages.listen((msg) {
      switch (msg['type']) {
        // Editing from another device (see _sendLibraryEdits).
        case 'libraryRequest' when !remoteEdit:
          sync.send({
            'type': 'library',
            'to': msg['from'],
            'library': libraryId,
            'name': currentLibrary.name,
            'data': _libraryJson(),
          });
        case 'libraryEdit' || 'libraryFull'
            when msg['from'] != _syncId && msg['library'] == libraryId:
          _applyLibraryEdit(msg);
        case 'libraryFull' when remoteEdit && msg['from'] != _syncId:
          // The computer opened another library: edit that one now.
          _takeRemoteLibrary(msg);
        case 'hello':
          _projectorAlive(true);
          _projectorSizeFrom(msg);
          broadcastState();
        case 'alive':
          _projectorAlive(true);
          _projectorSizeFrom(msg);
        case 'liveTime' when live != null && msg['started'] == live!.started:
          liveTime.value = (
            (msg['pos'] as num?)?.toDouble() ?? 0,
            (msg['dur'] as num?)?.toDouble() ?? 0,
          );
          final playing = msg['playing'] as bool?;
          // Paused or ended on the screen itself: the button follows.
          if (playing != null && playing != live!.playing) {
            live = live!.withPlaying(playing);
            notifyListeners();
          }
        case 'bye':
          _projectorAlive(false);
          // Another operator window pressed Stop.
          notifyListeners();
        case 'mediaRequest':
          _sendMedia(msg['id'] as String);
        case 'newBuild':
          updateAvailable = true;
          notifyListeners();
        case 'castEnded':
          notifyListeners();
        // A Remote window (see "Remote" below) follows the computer…
        case 'state' when remoteEdit:
          if (remoteControl) _followComputer(msg);
        case 'index' when remoteEdit:
          if (remoteControl && _computerSlides == slides.length) {
            _following = true;
            goTo(msg['index'] as int, broadcast: false);
            _following = false;
          }
        // …and asks where it is when its remote is turned on.
        case 'remoteHello' when !remoteEdit:
          broadcastState();
        case 'index':
          goTo(msg['index'] as int, broadcast: false);
        // The Web API (the local server's /api/…: Stream Deck, Companion,
        // a phone's browser…) and Remote windows.
        case 'remote' when !remoteEdit:
          remote('${msg['action']}', msg['value']);
      }
    });
    _syncMetronome();
  }

  /// A remote control action (the Web API and `chordpropresenter://` links):
  /// next, previous, first, last, slide (number, from 1), next-song,
  /// previous-song, song (a title to find), blackout (true, false or
  /// toggle); from a Remote window also open (a song or setlist entry by
  /// id), goto (a slide by its part) and state (everything else on the
  /// screen, see [_presentationState]). Returns false for one it doesn't
  /// know.
  bool remote(String action, [Object? value]) {
    switch (action.toLowerCase()) {
      case 'next':
        next();
      case 'previous' || 'prev':
        previous();
      case 'first':
        firstSlide();
      case 'last':
        lastSlide();
      case 'slide':
        final n = value is num ? value.toInt() : int.tryParse('$value');
        if (n == null) return false;
        goTo(n - 1);
      case 'next-song':
        goSong(1);
      case 'previous-song' || 'prev-song':
        goSong(-1);
      case 'song':
        final q = '${value ?? ''}'.trim();
        if (q.isEmpty) return false;
        final key = searchKey(q);
        final match =
            songs.where((s) => searchKey(s.displayTitle) == key).firstOrNull ??
            songs
                .where((s) => searchKey(s.displayTitle).startsWith(key))
                .firstOrNull ??
            songs.where((s) => searchMatches(s.searchText, q)).firstOrNull;
        if (match == null) return false;
        selectSong(match.id);
      case 'open':
        if (value is! Map) return false;
        final set = setlistById(value['setlist'] as String?);
        final entry = set?.entries
            .where((e) => e.id == value['entry'])
            .firstOrNull;
        if (set != null && entry != null) {
          selectEntry(set, entry);
        } else if (songById(value['song'] as String?) != null) {
          selectSong(value['song'] as String);
        } else {
          return false;
        }
      case 'state':
        if (value is! Map) return false;
        _applyPresentation(Map<String, dynamic>.from(value));
      case 'goto':
        if (value is! Map) return false;
        final part = (value['part'] as num?)?.toInt() ?? -1;
        final at = (value['index'] as num?)?.toInt() ?? 0;
        if (part >= 0 && slidePartIndex.contains(part)) {
          selectPart(part);
        } else if (value['count'] == slides.length) {
          goTo(at);
        } else {
          return false;
        }
      case 'blackout':
        final want = switch ('$value'.toLowerCase()) {
          'true' || '1' || 'on' => true,
          'false' || '0' || 'off' => false,
          _ => !blackout,
        };
        if (want != blackout) toggleBlackout();
      default:
        return false;
    }
    return true;
  }

  void _syncMetronome() {
    final song = currentSong;
    autoscroll.setSong(song?.id, song?.duration ?? '');
    if (song == null) return;
    metronome.setFromSong(song.tempo, song.timeSignature);
  }

  /// Saves the structure for the current song, or for the setlist entry
  /// when the song was opened from a setlist. [raw] is the song text when
  /// sections were edited in the structure editor.
  void setStructure(List<StructureItem> structure, {String? raw}) {
    final song = currentSong;
    if (song == null) return;
    final entry = activeEntry;
    if (raw != null) {
      // Lyrics labelled in the editor join the song's other orders where
      // they used to show.
      List<StructureItem> relabelled(List<StructureItem> st) => st.isEmpty
          ? st
          : ChordPro.relabel(song.raw, st, title: song.title).$2;
      if (entry != null) song.structure = relabelled(song.structure);
      for (final set in setlists) {
        for (final e in set.entries) {
          if (e.songId == song.id && !identical(e, entry)) {
            e.structure = relabelled(e.structure);
          }
        }
      }
      // Translations added / removed in a setlist: the song's own order
      // links them too.
      final langs = translatedLanguages(raw).join(',');
      if (entry != null && langs != translatedLanguages(song.raw).join(',')) {
        song.structure = withTranslations(raw, song.structure);
      }
      song.raw = raw;
    }
    if (entry != null) {
      entry.structure = structure;
    } else {
      song.structure = structure;
    }
    _rebuildSlides();
    _save();
    notifyListeners();
  }

  /// New song text with translated sections (see translation.dart): the
  /// song and every setlist arrangement of it link them to their originals.
  void applyTranslation(String raw) {
    final song = currentSong;
    if (song == null) return;
    // Sections labelled for the translation join each arrangement where
    // their lyrics used to show.
    List<StructureItem> relabelled(List<StructureItem> st) =>
        ChordPro.relabel(song.raw, st, title: song.title).$2;
    song.structure = withTranslations(raw, relabelled(song.structure));
    for (final set in setlists) {
      for (final e in set.entries) {
        if (e.songId == song.id && e.structure.isNotEmpty) {
          e.structure = withTranslations(raw, relabelled(e.structure));
        }
      }
    }
    song.raw = raw;
    _rebuildSlides(keepIndex: true);
    _save();
    notifyListeners();
  }

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    projectorFont = settings.projectorFont;
    broadcastState();
    _save();
    notifyListeners();
  }

  // ---- Projection ----

  /// Projector settings (lyrics / stage view, background, text…).
  final ProjectionSettings projection = ProjectionSettings();

  /// Projector shows black (or the blackout media) instead of lyrics.
  bool blackout = false;

  // ---- Song usage (for reporting) ----

  static const _usageKey = 'songUsage';

  /// Every time a song's words were up on the projector: one entry per
  /// song per service (a song shown again within 3 hours counts once).
  List<SongUse> usage = [];
  bool _usageLoaded = false;

  Future<void> loadUsage() async {
    if (_usageLoaded) return;
    _usageLoaded = true;
    try {
      final raw = await _store.read(_usageKey);
      if (raw != null) {
        usage = [
          for (final j in jsonDecode(raw) as List)
            SongUse.fromJson(Map<String, dynamic>.from(j as Map)),
        ];
      }
    } catch (_) {}
  }

  Future<void> _saveUsage() =>
      _store.write(_usageKey, jsonEncode([for (final u in usage) u.toJson()]));

  @override
  void noteSongUse() {
    if (!projecting || blackout) return;
    final song = currentSong;
    if (song == null || bibleSongs.containsKey(song.id)) return;
    // The words on screen (not the title or blank slide before them).
    if (index >= slidePartIndex.length || slidePartIndex[index] < 0) return;
    final now = DateTime.now();
    final recent = usage.reversed.takeWhile(
      (u) => now.difference(u.at) < const Duration(hours: 3),
    );
    if (recent.any((u) => u.songId == song.id)) return;
    loadUsage().then((_) {
      if (usage.any(
        (u) =>
            u.songId == song.id &&
            now.difference(u.at) < const Duration(hours: 3),
      )) {
        return;
      }
      usage.add(
        SongUse(
          songId: song.id,
          title: song.displayTitle,
          artist: song.displayArtist,
          ccli: song.ccli,
          at: now,
          setlist: activeSetlistId == null
              ? null
              : setlistById(activeSetlistId)?.name,
        ),
      );
      _saveUsage();
    });
  }

  Future<void> clearUsage({DateTime? before}) async {
    await loadUsage();
    usage.removeWhere((u) => before == null || u.at.isBefore(before));
    await _saveUsage();
    notifyListeners();
  }

  // ---- Media library (media_library.dart) ----

  static const _mediaKey = 'mediaLibrary';

  List<MediaItem> mediaItems = [];

  /// Every folder, also empty ones ("Easter", "Easter/Backgrounds").
  List<String> mediaFolders = [];
  bool _mediaLoaded = false;

  /// Shown on the projector over the lyrics (played or as an overlay).
  LiveMedia? live;
  int _liveStarts = 0;

  Future<void> loadMedia() async {
    if (_mediaLoaded) return;
    _mediaLoaded = true;
    try {
      final raw = await _store.read(_mediaKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        // Items added together by earlier versions could share an id
        // (which mixed them up): each gets its own.
        final ids = <String>{};
        var repaired = false;
        mediaItems = [
          for (final i in (j['items'] as List?) ?? const [])
            if (MediaItem.fromJson(i) case final item?)
              if (ids.add(item.id))
                item
              else
                () {
                  repaired = true;
                  final fresh = item.withNewId();
                  ids.add(fresh.id);
                  return fresh;
                }(),
        ];
        if (repaired) _saveMedia();
        mediaFolders = [
          for (final f in (j['folders'] as List?) ?? const []) f as String,
        ];
      }
    } catch (e) {
      debugPrint('Failed to load media library: $e');
    }
    // Pictures and videos already used by the projector settings.
    var added = false;
    for (final ref in projection.media) {
      if (mediaItems.any((m) => m.file?.id == ref.id)) continue;
      mediaItems.add(MediaItem.fromFile(ref));
      added = true;
    }
    if (added) _saveMedia();
    notifyListeners();
  }

  void _saveMedia() {
    _store.write(
      _mediaKey,
      jsonEncode({
        'items': [for (final m in mediaItems) m.toJson()],
        'folders': mediaFolders,
      }),
    );
  }

  void _mediaChanged() {
    _saveMedia();
    notifyListeners();
  }

  void addMedia(MediaItem item) {
    if (item.folder.isNotEmpty) addMediaFolder(item.folder, notify: false);
    mediaItems.add(item);
    _mediaChanged();
  }

  void renameMedia(MediaItem item, String name) {
    if (name.trim().isEmpty) return;
    item.name = name.trim();
    _mediaChanged();
  }

  void moveMedia(MediaItem item, String folder) {
    item.folder = folder;
    _mediaChanged();
  }

  /// Removes [item] from the library; its file is kept while the projector
  /// settings or a setlist still use it.
  Future<void> deleteMedia(MediaItem item) async {
    mediaItems.remove(item);
    if (live?.item.id == item.id) stopLive();
    _mediaChanged();
    final ref = item.file;
    if (ref == null) return;
    bool uses(MediaItem? m) => m?.file?.id == ref.id;
    final used =
        projection.media.any((m) => m.id == ref.id) ||
        mediaItems.any(uses) ||
        setlists.any(
          (s) => s.entries.any((e) => uses(e.media) || uses(e.background)),
        );
    if (!used) await MediaStore.delete(ref);
  }

  void addMediaFolder(String path, {bool notify = true}) {
    // Its parents too.
    for (var p = path; p.isNotEmpty; p = parentFolder(p)) {
      if (!mediaFolders.contains(p)) mediaFolders.add(p);
    }
    mediaFolders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (notify) _mediaChanged();
  }

  /// Renames the folder [path] (its last part) to [name], with everything
  /// in it.
  void renameMediaFolder(String path, String name) {
    name = name.replaceAll('/', '-').trim();
    if (name.isEmpty) return;
    final parent = parentFolder(path);
    final to = parent.isEmpty ? name : '$parent/$name';
    String moved(String f) => f == path
        ? to
        : f.startsWith('$path/')
        ? to + f.substring(path.length)
        : f;
    mediaFolders = {for (final f in mediaFolders) moved(f)}.toList();
    for (final m in mediaItems) {
      m.folder = moved(m.folder);
    }
    addMediaFolder(to, notify: false);
    _mediaChanged();
  }

  /// Deletes the folder [path]; what was in it moves up to its parent.
  void deleteMediaFolder(String path) {
    final parent = parentFolder(path);
    String moved(String f) => f == path
        ? parent
        : f.startsWith('$path/')
        ? (parent.isEmpty ? '' : '$parent/') + f.substring(path.length + 1)
        : f;
    mediaFolders = {
      for (final f in mediaFolders)
        if (f != path) moved(f),
    }.where((f) => f.isNotEmpty).toList();
    for (final m in mediaItems) {
      m.folder = moved(m.folder);
    }
    _mediaChanged();
  }

  /// Shows [item] on the projector: played full screen, over the lyrics,
  /// or as the background.
  void showMedia(MediaItem item, LiveMode mode) {
    if (mode == LiveMode.background) {
      final ref = item.file;
      if (ref == null || !item.canBeBackground) return;
      updateProjection((p) {
        p.bgType = BackgroundType.media;
        p.bgMedia = ref;
      });
      return;
    }
    live = LiveMedia(item, mode, started: ++_liveStarts);
    liveTime.value = (0, 0);
    if (blackout) blackout = false;
    broadcastState();
    notifyListeners();
  }

  /// How far the media playing has got (seconds) and its length, as the
  /// projector reports it; (0, 0) until it does.
  final liveTime = ValueNotifier<(double, double)>((0, 0));

  /// Jumps the media playing to [seconds] (0: from the start).
  void seekLive(double seconds) {
    if (live == null) return;
    if (!remoteEdit || remoteControl) {
      sync.send({'type': 'liveSeek', 'to': seconds});
    }
    LiveControl.seeks.add(seconds); // the preview here follows too
    liveTime.value = (seconds, liveTime.value.$2);
  }

  void restartLive() {
    seekLive(0);
    setLivePlaying(true);
  }

  void stopLive() {
    if (live == null) return;
    live = null;
    broadcastState();
    notifyListeners();
  }

  void setLivePlaying(bool on) {
    final l = live;
    if (l == null || l.playing == on) return;
    live = l.withPlaying(on);
    broadcastState();
    notifyListeners();
  }

  /// Puts [item] in [set] (at [at], else at the end), to [mode] when the
  /// setlist reaches it.
  void addMediaToSetlist(
    Setlist set,
    MediaItem item, {
    LiveMode mode = LiveMode.play,
    int? at,
  }) {
    final entry = SetEntry(
      type: EntryType.media,
      title: item.name,
      extra: {'media': item.toJson(), 'mode': mode.name},
    );
    set.entries.insert(
      (at ?? set.entries.length).clamp(0, set.entries.length),
      entry,
    );
    _save();
    notifyListeners();
  }

  void setEntryMode(SetEntry entry, LiveMode mode) {
    entry.extra['mode'] = mode.name;
    _save();
    notifyListeners();
  }

  /// A song entry's own background (null: the usual one).
  void setEntryBackground(SetEntry entry, MediaItem? item) {
    if (item == null || !item.canBeBackground) {
      entry.extra.remove('bg');
    } else {
      entry.extra['bg'] = item.toJson();
    }
    _save();
    if (entry.id == activeEntryId) broadcastState();
    notifyListeners();
  }

  /// The projector settings as shown: the setlist song's own background
  /// in place of the usual one.
  ProjectionSettings get shownProjection {
    final bg = activeEntry?.background?.file;
    if (bg == null) return projection;
    return ProjectionSettings()..updateFrom({
      ...projection.toJson(),
      'bgType': BackgroundType.media.name,
      'bgMedia': bg.toJson(),
    });
  }

  void updateProjection(void Function(ProjectionSettings p) change) {
    final tidy = projection.tidyLyrics;
    final showLinked = projection.linked.show;
    final intro = (projection.blankSlide, projection.titleSlide);
    change(projection);
    if (projection.tidyLyrics != tidy ||
        projection.linked.show != showLinked ||
        (projection.blankSlide, projection.titleSlide) != intro) {
      _rebuildSlides(keepIndex: true);
    }
    broadcastState();
    _save();
    notifyListeners();
  }

  /// Sends a picture/video to a cast screen in pieces.
  Future<void> _sendMedia(String id) async {
    final ref = [
      ...projection.media,
      ?live?.item.file,
      ?activeEntry?.background?.file,
    ].where((m) => m.id == id).firstOrNull;
    if (ref == null) return;
    final bytes = await MediaStore.bytes(ref);
    if (bytes == null || bytes.isEmpty) return;
    final text = base64Encode(bytes);
    const size = 256 * 1024;
    final n = (text.length / size).ceil();
    for (var i = 0; i < n; i++) {
      sync.send({
        'type': 'mediaChunk',
        'id': id,
        'i': i,
        'n': n,
        'data': text.substring(i * size, min((i + 1) * size, text.length)),
      });
      await Future<void>.delayed(Duration.zero); // keep the UI responsive
    }
  }

  /// The app was rebuilt; the operator window can reload to get it
  /// (projector screens reload by themselves).
  bool updateAvailable = false;

  /// A cast (Chromecast / presentation display) is running.
  bool get casting => sync.casting;

  Future<String?> startCast() async {
    final error = await sync.startCast();
    notifyListeners();
    return error;
  }

  void stopCast() {
    sync.stopCast();
    notifyListeners();
  }

  /// Something is showing the projection (window, screen or cast).
  bool get projecting => projectorActive || casting;

  /// Opens the projector window (and wakes screens that were stopped).
  void startProjection() {
    sync.send({'type': 'start'});
    openProjectorWindow();
  }

  /// Stops every projection: closes projector windows, blanks other
  /// screens (phones / TV browsers) and ends Chromecast and other casts.
  Future<void> stopProjection() async {
    sync.send({'type': 'stop'});
    if (sync.casting) sync.stopCast();
    _projectorAlive(false);
    notifyListeners();
    try {
      await castStopAll();
    } catch (_) {
      // No local server (or no Chromecast support): nothing to stop.
    }
    notifyListeners();
  }

  void toggleBlackout() {
    blackout = !blackout;
    _sendRemote('blackout', blackout);
    broadcastState();
    notifyListeners();
  }

  /// Title of the next song in the setlist this song was opened from.
  String? get nextSongTitle {
    final set = setlistById(activeSetlistId);
    if (set == null) return null;
    final i = set.entries.indexWhere((e) => e.id == activeEntryId);
    for (var j = i + 1; j < set.entries.length; j++) {
      final e = set.entries[j];
      if (e.type == EntryType.song) return songById(e.songId)?.displayTitle;
    }
    return null;
  }

  StageData? get stageData {
    final song = currentSong;
    if (song == null) return null;
    return StageData(
      song: song,
      raw: effectiveRaw,
      transpose: shapeTranspose,
      displayKey: shapeKey,
      soundingKey: currentKey,
      capo: currentCapo,
      format: format,
      sheetFont: settings.sheetFont,
      chordFont: settings.chordFont,
      nextTitle: nextSongTitle,
      passingGlow: settings.gospelGlow,
    );
  }

  /// What the projector shows, for the operator's preview ([ink]: with
  /// the slides' annotations).
  ProjectionData get projectionData => projectionDataWith();

  ProjectionData projectionDataWith({bool ink = true}) => ProjectionData(
    settings: shownProjection,
    live: live,
    preview: true,
    slides: slides,
    selection: selection,
    transitionSeconds: transitionDuration,
    projectorFont: projectorFont,
    blackout: blackout,
    stage: stageData,
    countdown: countdown,
    ink: ink ? slideInk : null,
  );

  // ---- Annotations (see ink.dart) ----

  /// The chord sheet's annotations.
  List<InkStroke> sheetInk(Song song) =>
      InkStroke.listFromJson(song.extra['ink']);

  void setSheetInk(Song song, List<InkStroke> strokes) {
    if (strokes.isEmpty) {
      song.extra.remove('ink');
    } else {
      song.extra['ink'] = InkStroke.listToJson(strokes);
    }
    inkVersion.value++;
    _save();
  }

  /// Bumped whenever an annotation changes (the drawings listen to it).
  final ValueNotifier<int> inkVersion = ValueNotifier(0);

  /// Each slide's annotations (by slide number), for the open song.
  List<List<InkStroke>> get slideInk {
    final song = currentSong;
    final key = (song, slides, inkVersion.value);
    if (_slideInkKey == key) return _slideInk;
    final all = song?.extra['slideInk'];
    _slideInkKey = key;
    return _slideInk = [
      for (final s in slides)
        all is Map ? InkStroke.listFromJson(all[s]) : const <InkStroke>[],
    ];
  }

  Object? _slideInkKey;
  List<List<InkStroke>> _slideInk = const [];

  void setSlideInk(int index, List<InkStroke> strokes) {
    final song = currentSong;
    if (song == null || index < 0 || index >= slides.length) return;
    final all = Map<String, dynamic>.of(
      (song.extra['slideInk'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    if (strokes.isEmpty) {
      all.remove(slides[index]);
    } else {
      all[slides[index]] = InkStroke.listToJson(strokes);
    }
    if (all.isEmpty) {
      song.extra.remove('slideInk');
    } else {
      song.extra['slideInk'] = all;
    }
    inkVersion.value++;
    _save();
    broadcastState();
  }

  // ---- Countdown timer ----

  static const defaultTimerMs = 5 * 60 * 1000;

  /// The timer's length (the timeline runs from 0 to this).
  int _timerTotalMs = defaultTimerMs;
  int get timerTotalSeconds => _timerTotalMs ~/ 1000;

  /// Time left when last started / paused / changed.
  int _timerMs = defaultTimerMs;
  DateTime _timerSince = DateTime.now();
  bool timerRunning = false;

  /// Started and not reset: shown on the projector.
  bool timerActive = false;
  Timer? _timerTicker;

  /// Whole seconds left, for the controls (updates while running).
  final timerSeconds = ValueNotifier<int>(defaultTimerMs ~/ 1000);

  int get timerRemainingMs => timerRunning
      ? max(0, _timerMs - DateTime.now().difference(_timerSince).inMilliseconds)
      : _timerMs;

  CountdownState get countdown => CountdownState(
    ms: timerRemainingMs,
    running: timerRunning,
    active: timerActive,
  );

  /// Adds (or with a negative number removes) time, to both the length
  /// and the time left.
  void timerAdd(int seconds) {
    final left = timerRemainingMs;
    _timerTotalMs = (_timerTotalMs + seconds * 1000).clamp(0, 24 * 3600000);
    _timerMs = (left + seconds * 1000).clamp(0, _timerTotalMs);
    _timerSince = DateTime.now();
    if (_timerMs == 0) timerRunning = false;
    _timerChanged();
  }

  /// Sets a new length (and starts over from it).
  void timerSet(int seconds) {
    _timerTotalMs = seconds * 1000;
    _timerMs = _timerTotalMs;
    _timerSince = DateTime.now();
    if (_timerMs == 0) timerRunning = false;
    _timerChanged();
  }

  /// Jumps to [elapsed] seconds into the timer (the timeline).
  void timerSeek(int elapsed) {
    _timerMs = (_timerTotalMs - elapsed * 1000).clamp(0, _timerTotalMs);
    _timerSince = DateTime.now();
    if (_timerMs == 0) timerRunning = false;
    _timerChanged();
  }

  void timerToggle() {
    if (timerRunning) {
      _timerMs = timerRemainingMs;
      timerRunning = false;
    } else {
      if (timerRemainingMs == 0) return;
      _timerSince = DateTime.now();
      timerRunning = true;
      timerActive = true;
    }
    _timerChanged();
  }

  /// Stopped, back to the full length and off the projector.
  void timerStop() {
    timerRunning = false;
    timerActive = false;
    _timerMs = _timerTotalMs;
    _timerChanged();
  }

  void _timerChanged() {
    timerSeconds.value = (timerRemainingMs / 1000).ceil();
    _timerTicker?.cancel();
    if (timerRunning) {
      _timerTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        timerSeconds.value = (timerRemainingMs / 1000).ceil();
        if (timerRemainingMs == 0) {
          // Time's up: stays at 0:00 on screen until reset.
          _timerMs = 0;
          timerRunning = false;
          _timerTicker?.cancel();
          broadcastState();
          notifyListeners();
        }
      });
    }
    broadcastState();
    notifyListeners();
  }

  void _applyJson(Map<String, dynamic> json) {
    _applyLibrary(json);
    final libs = [
      for (final l in (json['libraries'] as List?) ?? const [])
        ?LibraryInfo.fromJson(l),
    ];
    if (libs.isNotEmpty) {
      libraries
        ..clear()
        ..addAll(libs);
    }
    final open = json['libraryId'];
    libraryId = open is String && libraries.any((l) => l.id == open)
        ? open
        : libraries.first.id;
    final f = json['format'];
    if (f is Map<String, dynamic>) format.updateFrom(f);
    final pj = json['projection'];
    if (pj is Map<String, dynamic>) projection.updateFrom(pj);
    final st = json['settings'];
    if (st is Map<String, dynamic>) settings.updateFrom(st);
    projectorFont = settings.projectorFont;
    fontScale = (json['fontScale'] as num?)?.toDouble() ?? 1.0;
    transitionDuration =
        (json['transitionDuration'] as num?)?.toDouble() ?? 0.25;
  }

  Map<String, dynamic> toJson() => {
    'songs': songs.map((s) => s.toJson()).toList(),
    'tags': tags.map((t) => t.toJson()).toList(),
    'setlists': setlists.map((s) => s.toJson()).toList(),
    'trash': trash.map((s) => s.toJson()).toList(),
    'format': format.toJson(),
    'settings': settings.toJson(),
    'projection': projection.toJson(),
    'selectedSongID': selectedSongId,
    'fontScale': fontScale,
    'transitionDuration': transitionDuration,
    'backupIdentity': ?backupIdentity,
    'libraries': libraries.map((l) => l.toJson()).toList(),
    'libraryId': libraryId,
  };

  /// The library's "identity" from the original app's backup (kept so a
  /// backup written for that app says it's the same library).
  String? backupIdentity;

  /// Pretty JSON for the Export download.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Saves shortly after the last change, so rapid edits (sliders, size
  /// buttons) write once instead of rewriting the whole library each time.
  /// How long to wait after a change before saving (tests use zero).
  static Duration saveDelay = const Duration(milliseconds: 400);

  void _save() {
    if (saveDelay == Duration.zero) {
      flush();
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _store.write(_mainKey, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Failed to save library: $e');
    }
    _sendLibraryEdits();
    saves.value++;
  }

  /// Counts saves (library or settings changed): backups and sync wake on
  /// it, not on every slide change.
  final ValueNotifier<int> saves = ValueNotifier(0);

  // ---- Editing from another device (a browser on the same Wi-Fi) ----
  // Every window of the app sends what changed in its library (song by
  // song; tags and setlists whole) over the local server's relay, and
  // applies what the others send. A window opened at chordpro.local:8080/
  // edit takes its library from the computer running the app instead of
  // its own storage, and never drives the projector.

  /// This window edits another computer's library (?view=edit).
  bool remoteEdit = false;

  // ---- Remote ----
  //
  // A window editing the computer's library can also be its remote: with
  // [remoteControl] on, the song (or setlist entry) opened here, the
  // slide picked here and blackout happen on the computer too, and this
  // window follows what the computer shows.

  /// This (editing) window also controls the computer's slides.
  bool remoteControl = false;

  /// What was last opened on the computer from here, or followed from it.
  String? _remoteOpened;

  /// Taking the computer's lead (nothing is sent back meanwhile).
  bool _following = false;

  /// How many slides the computer has for its song (-1: not known).
  int _computerSlides = -1;

  Future<void> setRemoteControl(bool on) async {
    if (!remoteEdit || on == remoteControl) return;
    remoteControl = on;
    _remoteSynced = false;
    notifyListeners();
    await _store.write('remote_control', on ? '1' : '0');
    // Starts where the computer is (rather than changing its screen).
    if (on) sync.send({'type': 'remoteHello'});
  }

  void _sendRemote(String action, [Object? value]) {
    if (!remoteEdit || !remoteControl || _following) return;
    sync.send({'type': 'remote', 'action': action, 'value': value});
  }

  /// Opens this window's song on the computer (once per song).
  void _remoteOpen() {
    final key = '$selectedSongId|$activeSetlistId|$activeEntryId';
    if (key == _remoteOpened) return;
    _remoteOpened = key;
    if (selectedSongId == null || bibleSongs.containsKey(selectedSongId)) {
      return;
    }
    _sendRemote('open', {
      'song': selectedSongId,
      'setlist': activeSetlistId,
      'entry': activeEntryId,
    });
  }

  /// The computer's state: this window opens the same song and slide.
  void _followComputer(Map<String, dynamic> msg) {
    _following = true;
    try {
      final songId = msg['songId'] as String?;
      final entryId = msg['entryId'] as String?;
      if (songById(songId) != null &&
          (songId != selectedSongId || entryId != activeEntryId)) {
        final set = setlistById(msg['setlistId'] as String?);
        final entry = set?.entries.where((e) => e.id == entryId).firstOrNull;
        if (set != null && entry != null) {
          selectEntry(set, entry);
        } else {
          selectSong(songId);
        }
      }
      _remoteOpened = '$selectedSongId|$activeSetlistId|$activeEntryId';
      _computerSlides = (msg['slides'] as List?)?.length ?? -1;
      final part = (msg['part'] as num?)?.toInt() ?? -1;
      final at = (msg['index'] as num?)?.toInt() ?? 0;
      if (songId == selectedSongId) {
        if (part >= 0 && slidePartIndex.contains(part)) {
          selectPart(part);
        } else if (_computerSlides == slides.length) {
          goTo(at, broadcast: false);
        }
      }
      // The rest of what's on the screen (unless this window has just
      // changed it: an older answer mustn't undo that).
      final quiet =
          DateTime.now().difference(_remoteSentAt) >= remoteEchoWindow;
      if (msg['remote'] case final Map pres when quiet || !_remoteSynced) {
        _applyPresentation(Map<String, dynamic>.from(pres));
      }
      // The computer's media, to show from here.
      if (msg['media'] case final List list) {
        final items = [for (final m in list) ?MediaItem.fromJson(m)];
        if (jsonEncode([for (final m in items) m.toJson()]) !=
            jsonEncode([for (final m in mediaItems) m.toJson()])) {
          mediaItems = items;
        }
      }
      _remoteSynced = true;
      _remoteKey = _presentationKey;
      notifyListeners();
    } finally {
      _following = false;
    }
  }

  /// This Remote window has the computer's state (until then nothing of
  /// its own is sent: turning the remote on never changes the screen).
  bool _remoteSynced = false;

  /// The presentation state last sent to, or taken from, the computer.
  String? _remoteKey;
  DateTime _remoteSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long after changing something a Remote window ignores the
  /// computer's state (answers to its earlier changes, still on the way).
  static Duration remoteEchoWindow = const Duration(milliseconds: 700);

  /// What a Remote window and the computer keep the same, besides the
  /// song and the slide: the projector settings (background, text,
  /// underscan, the timer's look…), blackout, the media playing, the
  /// countdown timer and the scripture shown beside the song.
  Map<String, dynamic> _presentationState() => {
    'projection': projection.toJson(),
    'fontScale': fontScale,
    'transitionDuration': transitionDuration,
    'font': settings.projectorFont,
    'blackout': blackout,
    'live': live?.toJson(),
    'timer': {
      'total': _timerTotalMs,
      'ms': timerRemainingMs,
      'running': timerRunning,
      'active': timerActive,
    },
    'scripture': _sidePassage?.toJson(),
  };

  /// [_presentationState] as one string that only changes when something
  /// was changed (not as a running timer counts down).
  String get _presentationKey => jsonEncode({
    ..._presentationState(),
    'timer': [
      _timerTotalMs,
      timerRunning,
      timerActive,
      timerRunning ? _timerSince.millisecondsSinceEpoch + _timerMs : _timerMs,
    ],
  });

  /// A Remote window: sends what changed here to the computer.
  void _remotePush() {
    if (!remoteControl || !_remoteSynced || _following) return;
    final key = _presentationKey;
    if (key == _remoteKey) return;
    _remoteKey = key;
    _remoteSentAt = DateTime.now();
    _sendRemote('state', _presentationState());
  }

  /// Takes [v] (see [_presentationState]) from the other side: only what
  /// differs is changed.
  void _applyPresentation(Map<String, dynamic> v) {
    var changed = false;
    if (v['projection'] case final Map p) {
      final next = ProjectionSettings()
        ..updateFrom(Map<String, dynamic>.from(p));
      if (jsonEncode(next.toJson()) != jsonEncode(projection.toJson())) {
        updateProjection((x) => x.updateFrom(next.toJson()));
      }
    }
    final scale = (v['fontScale'] as num?)?.toDouble();
    if (scale != null && scale != fontScale) {
      fontScale = scale;
      changed = true;
    }
    final transition = (v['transitionDuration'] as num?)?.toDouble();
    if (transition != null && transition != transitionDuration) {
      transitionDuration = transition;
      changed = true;
    }
    if (v['font'] case final String font when font != settings.projectorFont) {
      updateSettings((s) => s.projectorFont = font);
    }
    if (v['blackout'] case final bool dark when dark != blackout) {
      blackout = dark;
      changed = true;
    }
    if (v.containsKey('live')) {
      final next = LiveMedia.fromJson(v['live']);
      if (jsonEncode(next?.toJson()) != jsonEncode(live?.toJson())) {
        if (next?.started != live?.started) liveTime.value = (0, 0);
        live = next;
        if (next != null && next.started > _liveStarts) {
          _liveStarts = next.started;
        }
        changed = true;
      }
    }
    if (v['timer'] case final Map t) {
      final total = (t['total'] as num?)?.toInt() ?? _timerTotalMs;
      final ms = (t['ms'] as num?)?.toInt() ?? timerRemainingMs;
      final running = t['running'] == true;
      final active = t['active'] == true;
      if (total != _timerTotalMs ||
          running != timerRunning ||
          active != timerActive ||
          (ms - timerRemainingMs).abs() > 1500) {
        _timerTotalMs = total;
        _timerMs = ms;
        _timerSince = DateTime.now();
        timerRunning = running;
        timerActive = active;
        _timerChanged();
      }
    }
    if (v.containsKey('scripture')) {
      final next = BiblePassage.fromJson(v['scripture']);
      if (next != _sidePassage) {
        if (next == null) {
          closeScripture();
        } else if (currentSong != null) {
          // (A version only the other side has: nothing to show.)
          unawaited(showPassage(next).catchError((Object _) {}));
        }
      }
    }
    if (changed) {
      broadcastState();
      notifyListeners();
    }
  }

  /// Editing: the library's name on that computer; null until it answers.
  String? remoteLibraryName;

  /// Editing: why the library couldn't be fetched (null: fine).
  String? remoteError;

  /// This window in library messages.
  final String _syncId = newId();

  /// The library as last sent or received: each song as JSON by id, and
  /// tags and setlists as JSON. Null: not yet taken.
  Map<String, String>? _syncedSongs;
  Map<String, String> _syncedTrash = {};
  String _syncedTags = '', _syncedSets = '';
  String? _syncedLibrary;

  /// Editing mode keeps its own settings, and never touches this
  /// browser's own library.
  String get _mainKey => remoteEdit ? 'remote_edit_state' : _storageKey;
  String get _selKey => remoteEdit ? 'remote_edit_selection' : _selectionKey;

  static Map<String, String> _encodeSongs(List<Song> list) => {
    for (final s in list) s.id: jsonEncode(s.toJson()),
  };

  void _snapshotLibrary() {
    _syncedSongs = _encodeSongs(songs);
    _syncedTrash = _encodeSongs(trash);
    _syncedTags = jsonEncode([for (final t in tags) t.toJson()]);
    _syncedSets = jsonEncode([for (final s in setlists) s.toJson()]);
    _syncedLibrary = libraryId;
  }

  /// Sends what changed in the library since it was last in step.
  void _sendLibraryEdits() {
    final synced = _syncedSongs;
    if (synced == null) return;
    if (_syncedLibrary != libraryId) {
      // Another library opened: the others start over with it.
      _snapshotLibrary();
      if (!remoteEdit) {
        sync.send({
          'type': 'libraryFull',
          'from': _syncId,
          'library': libraryId,
          'name': currentLibrary.name,
          'data': _libraryJson(),
        });
      }
      return;
    }
    (List<Object?>, List<String>) diff(
      Map<String, String> before,
      Map<String, String> now,
    ) => (
      [
        for (final e in now.entries)
          if (before[e.key] != e.value) jsonDecode(e.value),
      ],
      [
        for (final id in before.keys)
          if (!now.containsKey(id)) id,
      ],
    );
    final nowSongs = _encodeSongs(songs);
    final nowTrash = _encodeSongs(trash);
    final tagsNow = jsonEncode([for (final t in tags) t.toJson()]);
    final setsNow = jsonEncode([for (final s in setlists) s.toJson()]);
    final (changed, deleted) = diff(synced, nowSongs);
    final (trashChanged, trashDeleted) = diff(_syncedTrash, nowTrash);
    final msg = <String, dynamic>{
      if (changed.isNotEmpty) 'songs': changed,
      if (deleted.isNotEmpty) 'deleted': deleted,
      if (trashChanged.isNotEmpty) 'trash': trashChanged,
      if (trashDeleted.isNotEmpty) 'trashDeleted': trashDeleted,
      if (tagsNow != _syncedTags) 'tags': jsonDecode(tagsNow),
      if (setsNow != _syncedSets) 'setlists': jsonDecode(setsNow),
    };
    if (msg.isEmpty) return;
    _syncedSongs = nowSongs;
    _syncedTrash = nowTrash;
    _syncedTags = tagsNow;
    _syncedSets = setsNow;
    sync.send({
      'type': 'libraryEdit',
      'from': _syncId,
      'library': libraryId,
      ...msg,
    });
  }

  /// Applies another window's changes (or its whole library).
  void _applyLibraryEdit(Map<String, dynamic> msg) {
    if (msg['type'] == 'libraryFull') return; // only editors follow
    final synced = _syncedSongs ??= _encodeSongs(songs);
    final current = currentSong?.id;
    final shown = currentSong == null
        ? null
        : jsonEncode(currentSong!.toJson());
    void upsert(List<Song> into, Map<String, String> record, Object? list) {
      for (final j in (list as List?) ?? const []) {
        final song = Song.fromJson(Map<String, dynamic>.from(j as Map));
        final i = into.indexWhere((s) => s.id == song.id);
        if (i >= 0) {
          into[i] = song;
        } else {
          into.add(song);
        }
        record[song.id] = jsonEncode(song.toJson());
      }
    }

    void remove(List<Song> from, Map<String, String> record, Object? ids) {
      for (final id in ((ids as List?) ?? const []).cast<String>()) {
        from.removeWhere((s) => s.id == id);
        record.remove(id);
      }
    }

    upsert(songs, synced, msg['songs']);
    remove(songs, synced, msg['deleted']);
    upsert(trash, _syncedTrash, msg['trash']);
    remove(trash, _syncedTrash, msg['trashDeleted']);
    if (msg['tags'] case final List list) {
      tags
        ..clear()
        ..addAll(list.map((t) => Tag.fromJson(Map<String, dynamic>.from(t))));
      _syncedTags = jsonEncode([for (final t in tags) t.toJson()]);
    }
    if (msg['setlists'] case final List list) {
      setlists
        ..clear()
        ..addAll(
          list.map((s) => Setlist.fromJson(Map<String, dynamic>.from(s))),
        );
      _syncedSets = jsonEncode([for (final s in setlists) s.toJson()]);
    }
    if (current != null && songById(current) == null) {
      selectedSongId = songs.isEmpty ? null : songs.first.id;
      activeSetlistId = null;
      activeEntryId = null;
      _rebuildSlides();
    } else if (currentSong != null &&
        jsonEncode(currentSong!.toJson()) != shown) {
      // The song on screen was edited elsewhere.
      _rebuildSlides(keepIndex: true);
    }
    _save();
    notifyListeners();
  }

  /// Changes from cloud sync (cloud_sync.dart): songs added or changed
  /// ([upserts]: the song, and whether it's in the Trash), songs gone for
  /// good ([removed]), and tags and setlists when they changed.
  void applySynced({
    List<(Song, bool)> upserts = const [],
    Iterable<String> removed = const [],
    List<Tag>? tags,
    List<Setlist>? setlists,
  }) {
    final shown = currentSong == null
        ? null
        : jsonEncode(currentSong!.toJson());
    for (final (song, inTrash) in upserts) {
      songs.removeWhere((s) => s.id == song.id);
      trash.removeWhere((s) => s.id == song.id);
      (inTrash ? trash : songs).add(song);
    }
    for (final id in removed) {
      songs.removeWhere((s) => s.id == id);
      trash.removeWhere((s) => s.id == id);
    }
    if (tags != null) {
      this.tags
        ..clear()
        ..addAll(tags);
    }
    if (setlists != null) {
      this.setlists
        ..clear()
        ..addAll(setlists);
    }
    if (currentSong == null) {
      selectedSongId = songs.isEmpty ? null : songs.first.id;
      activeSetlistId = null;
      activeEntryId = null;
      _rebuildSlides();
    } else if (jsonEncode(currentSong!.toJson()) != shown) {
      _rebuildSlides(keepIndex: true);
    }
    _save();
    notifyListeners();
  }

  /// Editing: asks the computer running the app for its library.
  Future<void> _joinRemote() async {
    sync.sendOnly = {
      'libraryRequest',
      'libraryEdit',
      'remote',
      'remoteHello',
      'liveSeek',
    };
    final answer = Completer<Map<String, dynamic>?>();
    final sub = sync.messages.listen((msg) {
      if (msg['type'] == 'library' &&
          msg['to'] == _syncId &&
          !answer.isCompleted) {
        answer.complete(msg);
      }
    });
    // Asked again now and then: the relay may still be connecting.
    final ask = Timer.periodic(const Duration(seconds: 2), (_) {
      sync.send({'type': 'libraryRequest', 'from': _syncId});
    });
    sync.send({'type': 'libraryRequest', 'from': _syncId});
    final msg = await answer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
    ask.cancel();
    await sub.cancel();
    if (msg == null) {
      remoteError =
          'The app on your computer didn’t answer. Check it’s open and on '
          'the same Wi-Fi, then reload this page.';
      _applyLibrary(const {});
      return;
    }
    _takeRemoteLibrary(msg);
  }

  void _takeRemoteLibrary(Map<String, dynamic> msg) {
    final data = Map<String, dynamic>.from(msg['data'] as Map);
    _applyLibrary(data);
    libraryId = msg['library'] as String? ?? libraryId;
    remoteLibraryName = msg['name'] as String? ?? 'Library';
    remoteError = null;
    activeSetlistId = null;
    activeEntryId = null;
    if (currentSong == null && songs.isNotEmpty) {
      selectedSongId = songs.first.id;
    }
    _snapshotLibrary();
    if (_syncedLibrary != null) {
      _rebuildSlides();
      notifyListeners();
    }
  }

  void broadcastState() {
    // A Remote window drives the computer; it has no screens of its own.
    if (remoteEdit) {
      _remoteOpen();
      _remotePush();
      return;
    }
    noteSongUse();
    sync.send({
      'type': 'state',
      // (For Remote windows: everything they show and change.)
      'remote': _presentationState(),
      'media': [for (final m in mediaItems) m.toJson()],
      'slides': slides,
      'index': index,
      // (For Remote windows, which follow along.)
      'songId': selectedSongId,
      'setlistId': activeSetlistId,
      'entryId': activeEntryId,
      'part': selectedPart,
      'fontScale': fontScale,
      'transitionDuration': transitionDuration,
      'font': projectorFont,
      'projection': shownProjection.toJson(),
      'blackout': blackout,
      'live': live?.toJson(),
      'stage': stageData?.toJson(),
      'timer': countdown.toJson(),
      'ink': {
        for (final (i, strokes) in slideInk.indexed)
          if (strokes.isNotEmpty) '$i': InkStroke.listToJson(strokes),
      },
    });
  }

  @override
  void onIndexChanged() {
    // A Remote window: the computer shows the same slide.
    _sendRemote('goto', {
      'part': selectedPart,
      'index': index,
      'count': slides.length,
    });
  }

  /// Re-splits the current song. [keepIndex] keeps the selected part
  /// (when only lyric tidying changed).
  void _rebuildSlides({bool keepIndex = false}) {
    _syncMetronome();
    if (!keepIndex) {
      index = 0;
      selection.value = 0;
    }
    final song = currentSong;
    parts = song == null ? [] : partsOf(effectiveRaw);
    final intro = song == null ? const <String>[] : introSlides(song);
    slidePartIndex = [
      for (final _ in intro) -1,
      for (var i = 0; i < parts.length; i++)
        if (!parts[i].isMarker) i,
    ];
    slides = [
      ...intro,
      for (final i in slidePartIndex)
        if (i >= 0)
          projection.linked.show ? parts[i].slide : parts[i].mainSlide,
    ];
    // Scripture shown beside the song: its slides follow the song's
    // (another song, or a passage on its own, ends it).
    if (!keepIndex || song == null) {
      _sidePassage = null;
      _sideSong = null;
    }
    scriptureNames = [];
    final side = _sideSong;
    if (side != null) {
      final sideParts = partsOf(
        ChordPro.applyStructure(side.raw, side.structure),
      );
      for (final part in sideParts) {
        if (part.isMarker) continue;
        slidePartIndex.add(-1);
        slides.add(projection.linked.show ? part.slide : part.mainSlide);
        scriptureNames.add(
          (part.lines.isEmpty
                  ? null
                  : ChordPro.sectionName(part.lines.first)) ??
              side.title,
        );
      }
    }
    broadcastState();
  }

  // ---- Songs ----

  /// Opens a song from the library (not from a setlist).
  void selectSong(String? id) {
    if (id == selectedSongId && activeEntryId == null) return;
    selectedSongId = id;
    activeSetlistId = null;
    activeEntryId = null;
    _rebuildSlides();
    _saveSelection();
    notifyListeners();
  }

  /// Page mode / columns for [song] (its own, or everyone's).
  SheetLayout layoutFor(Song song) => SheetLayout.of(format, song.extra);

  /// Changes page mode / columns, for the open song only or for all songs.
  void setLayout({bool? pageMode, int? columns, required bool thisSong}) {
    final song = currentSong;
    if (thisSong && song != null) {
      final now = layoutFor(song);
      song.extra['layout'] = {
        'pageMode': pageMode ?? now.pageMode,
        'columns': columns ?? now.columns,
      };
      _save();
      notifyListeners();
      return;
    }
    updateFormat((f) {
      if (pageMode != null) f.pageMode = pageMode;
      if (columns != null) f.columns = columns;
    });
  }

  // ---- Images on a song's sheet (see sheet_images.dart) ----

  /// The images placed on [song]'s sheet, as stored (`extra['images']`).
  List<Map<String, dynamic>> sheetImagesOf(Song song) => [
    for (final j in (song.extra['images'] as List?) ?? const [])
      if (j is Map) Map<String, dynamic>.from(j),
  ];

  /// Keeps [song]'s images ([notify]: redraw).
  void setSheetImages(
    Song song,
    List<Map<String, dynamic>> images, {
    bool notify = true,
  }) {
    if (images.isEmpty) {
      song.extra.remove('images');
    } else {
      song.extra['images'] = images;
    }
    _save();
    if (notify) notifyListeners();
  }

  // ---- Sticky notes (on a song) ----

  List<StickyNote> stickiesOf(Song song) => [
    for (final j in (song.extra['stickies'] as List?) ?? const [])
      if (j is Map) StickyNote.fromJson(j),
  ];

  void _saveStickies(Song song, List<StickyNote> notes) {
    if (notes.isEmpty) {
      song.extra.remove('stickies');
    } else {
      song.extra['stickies'] = [for (final n in notes) n.toJson()];
    }
    _save();
  }

  /// Adds a note to the open song at [at] (top-left, in the app window).
  StickyNote? addSticky(Offset at) {
    final song = currentSong;
    if (song == null) return null;
    final note = StickyNote(x: at.dx, y: at.dy);
    _saveStickies(song, [...stickiesOf(song), note]);
    notifyListeners();
    return note;
  }

  /// Saves a changed note. Typing doesn't redraw the app ([notify] off).
  void updateSticky(Song song, StickyNote note, {bool notify = false}) {
    final notes = stickiesOf(song);
    final i = notes.indexWhere((n) => n.id == note.id);
    if (i < 0) return;
    notes[i] = note;
    _saveStickies(song, notes);
    if (notify) notifyListeners();
  }

  void removeSticky(Song song, String id) {
    _saveStickies(song, [
      for (final n in stickiesOf(song))
        if (n.id != id) n,
    ]);
    notifyListeners();
  }

  /// Chord beats for [song] (its own setting, or everyone's).
  BeatSettings beatsFor(Song song) => BeatSettings.of(format, song.extra);

  /// The open song follows everyone's layout again.
  void clearSongLayout() {
    final song = currentSong;
    if (song == null || song.extra.remove('layout') == null) return;
    _save();
    notifyListeners();
  }

  /// Accidentals for [song] (its own setting, or everyone's).
  Accidentals accidentalsFor(Song song) =>
      SongAccidentals.of(format, song.extra).accidentals;

  /// Whether [song] has its own accidentals setting (ignores the global).
  bool songOwnsAccidentals(Song song) =>
      SongAccidentals.of(format, song.extra).own;

  /// Saves an accidentals choice for the open song only (it then ignores
  /// the global setting).
  void setSongAccidentals(Accidentals a) {
    final song = currentSong;
    if (song == null) return;
    song.extra['accidentals'] = a.name;
    _save();
    notifyListeners();
  }

  /// The open song follows everyone's accidentals again.
  void clearSongAccidentals() {
    final song = currentSong;
    if (song == null || song.extra.remove('accidentals') == null) return;
    _save();
    notifyListeners();
  }

  /// Song ids in the order the library list shows them (kept up to date
  /// by the sidebar), for swiping between songs.
  List<String> get libraryOrder => _order;
  List<String> _order = const [];

  /// Bumped when the library list order changes (the swipe strip listens).
  final libraryOrderVersion = ValueNotifier<int>(0);

  set libraryOrder(List<String> ids) {
    if (listEquals(ids, _order)) return;
    _order = ids;
    // Called while the sidebar builds: tell the strip on the next frame.
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => libraryOrderVersion.value++,
    );
  }

  /// Swipes to the next (+1) / previous (-1) song: within the setlist the
  /// song was opened from, otherwise in library order.
  bool canGoSong(int dir) => _songStep(dir, apply: false);

  void goSong(int dir) => _songStep(dir, apply: true);

  /// The song a swipe in [dir] would open (null at either end).
  SheetSpec? neighbour(int dir) {
    final n = neighbours(dir, 1);
    return n.isEmpty ? null : n.first;
  }

  /// A setlist's songs, each as the setlist has it (order, key, capo,
  /// arrangement). Dividers and missing songs are skipped.
  List<SheetSpec> setlistSpecs(Setlist set) => [
    for (final e in set.entries)
      if (e.type == EntryType.song && songById(e.songId) != null)
        specFor(songById(e.songId)!, set: set, entry: e),
  ];

  /// The slides a song projects (as [slides] does for the open one).
  List<String> slidesOf(SheetSpec spec) => [
    ...introSlides(spec.song),
    for (final i in spec.slidePartIndex)
      if (i >= 0)
        projection.linked.show ? spec.parts[i].slide : spec.parts[i].mainSlide,
  ];

  /// The slides before [song]'s lyrics (see projection.dart): blank, then
  /// title, as the projection settings say.
  List<String> introSlides(Song song) => [
    if (projection.blankSlide) blankSlide,
    if (projection.titleSlide)
      titleSlide(song.displayTitle, song.displayArtist),
  ];

  /// Up to [count] songs in [dir], nearest first (for drawing ahead).
  List<SheetSpec> neighbours(int dir, int count) {
    final out = <SheetSpec>[];
    final set = setlistById(activeSetlistId);
    if (set != null) {
      final i = set.entries.indexWhere((e) => e.id == activeEntryId);
      for (var j = i + dir; j >= 0 && j < set.entries.length; j += dir) {
        final e = set.entries[j];
        final song = songById(e.songId);
        if (e.type == EntryType.song && song != null) {
          out.add(specFor(song, set: set, entry: e));
          if (out.length == count) break;
        }
      }
      return out;
    }
    final order = _libraryOrder;
    final i = order.indexOf(selectedSongId ?? '');
    if (i < 0) return out;
    for (var j = i + dir; j >= 0 && j < order.length; j += dir) {
      final song = songById(order[j]);
      if (song != null) out.add(specFor(song));
      if (out.length == count) break;
    }
    return out;
  }

  /// The open song, in the same form as [neighbour].
  SheetSpec? get currentSpec {
    final song = currentSong;
    if (song == null) return null;
    return specFor(song, set: setlistById(activeSetlistId), entry: activeEntry);
  }

  /// Everything needed to draw a song's sheet (with set-specific key,
  /// capo and arrangement applied).
  SheetSpec specFor(Song saved, {Setlist? set, SetEntry? entry}) {
    // (With the songs nested under the entry, if any.)
    final song = playedSong(saved, entry, set: set);
    final specific = entry != null && set != null && set.setSpecific;
    final transpose = specific ? entry.transpose : song.transpose;
    final capo = specific ? entry.capo : song.capo;
    final structure = structureFor(song, entry);
    final shown = song.gospelRaw(mark: true);
    final raw = format.followArrangement
        ? ChordPro.applyStructure(shown, structure)
        : shown;
    final parts = partsOf(raw);
    return SheetSpec(
      id: '${song.id}|${entry?.id ?? ''}',
      song: song,
      raw: raw,
      transpose: transpose - capo,
      displayKey: song.writtenKey?.transposed(transpose - capo),
      soundingKey: song.writtenKey?.transposed(transpose),
      capo: capo,
      parts: parts,
      slidePartIndex: [
        for (final _ in introSlides(song)) -1,
        for (var i = 0; i < parts.length; i++)
          if (!parts[i].isMarker) i,
      ],
    );
  }

  /// Song parts, remembered so flipping back and forth never re-parses.
  List<SongPart> partsOf(String raw) {
    final key = '${projection.tidyLyrics}|$raw';
    final hit = _partsCache.remove(key);
    if (hit != null) {
      _partsCache[key] = hit;
      return hit;
    }
    final parts = ChordPro.parts(raw, tidy: projection.tidyLyrics);
    _partsCache[key] = parts;
    if (_partsCache.length > 24) _partsCache.remove(_partsCache.keys.first);
    return parts;
  }

  final Map<String, List<SongPart>> _partsCache = {};

  List<String> get _libraryOrder => libraryOrder.isNotEmpty
      ? libraryOrder
      : [
          for (final s in [
            ...songs,
          ]..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
            s.id,
        ];

  bool _songStep(int dir, {required bool apply}) {
    final set = setlistById(activeSetlistId);
    if (set != null) {
      final i = set.entries.indexWhere((e) => e.id == activeEntryId);
      for (var j = i + dir; j >= 0 && j < set.entries.length; j += dir) {
        final e = set.entries[j];
        if ((e.type == EntryType.song && songById(e.songId) != null) ||
            (e.type == EntryType.media && e.media != null) ||
            (e.type == EntryType.bible && e.passage != null)) {
          if (apply) selectEntry(set, e);
          return true;
        }
      }
      return false;
    }
    final order = _libraryOrder;
    final i = order.indexOf(selectedSongId ?? '');
    final j = i + dir;
    if (i < 0 || j < 0 || j >= order.length) return false;
    if (apply) selectSong(order[j]);
    return true;
  }

  /// Opens a song from a setlist, so set-specific edits apply.
  void selectEntry(Setlist setlist, SetEntry entry) {
    if (entry.type == EntryType.bible) {
      final p = entry.passage;
      if (p != null) unawaited(showPassage(p, set: setlist, entry: entry));
      return;
    }
    if (entry.type == EntryType.media) {
      final item = entry.media;
      if (item == null) return;
      activeSetlistId = setlist.id;
      activeEntryId = entry.id;
      showMedia(item, entry.mediaMode);
      _saveSelection();
      notifyListeners();
      return;
    }
    if (entry.type != EntryType.song) return;
    // Moving on to a song ends what was playing.
    live = null;
    selectedSongId = entry.songId;
    activeSetlistId = setlist.id;
    activeEntryId = entry.id;
    _rebuildSlides();
    _saveSelection();
    notifyListeners();
  }

  /// Sets [songId]'s icon (null: none) without opening the song.
  void setIconOf(String songId, String? icon) {
    final song = songById(songId);
    if (song == null) return;
    if (icon == null) {
      song.extra.remove('icon');
    } else {
      song.extra['icon'] = icon;
    }
    _save();
    notifyListeners();
  }

  void addOrUpdate(Song song) {
    // A Band Sync song: edited for this session only.
    if (bandSongs.containsKey(song.id)) {
      bandSongs[song.id] = song.copy();
      _rebuildSlides(keepIndex: true);
      notifyListeners();
      return;
    }
    final i = songs.indexWhere((s) => s.id == song.id);
    if (i >= 0) {
      // Edited: its date moves on (import's "if newer" goes by it).
      final changed =
          jsonEncode({...songs[i].toJson(), 'date': null}) !=
          jsonEncode({...song.toJson(), 'date': null});
      songs[i] = song.copy();
      if (changed) songs[i].date = DateTime.now();
    } else {
      songs.add(song.copy()..date ??= DateTime.now());
      activeSetlistId = null;
      activeEntryId = null;
    }
    selectedSongId = song.id;
    _save();
    _rebuildSlides();
    notifyListeners();
  }

  /// Moves a song to the Trash. Setlists keep their entry so restoring the
  /// song brings it back there too.
  void deleteSong(String id) {
    final song = songById(id);
    if (song == null) return;
    songs.remove(song);
    trash.insert(0, song);
    if (id == selectedSongId) {
      selectedSongId = songs.isEmpty ? null : songs.first.id;
      activeSetlistId = null;
      activeEntryId = null;
      _rebuildSlides();
    }
    _save();
    notifyListeners();
  }

  void restoreSong(Song song) {
    trash.remove(song);
    songs.add(song);
    _save();
    notifyListeners();
  }

  void deleteForever(Song song) {
    trash.remove(song);
    for (final set in setlists) {
      set.entries.removeWhere((e) => e.songId == song.id);
    }
    _save();
    notifyListeners();
  }

  void emptyTrash() {
    for (final song in [...trash]) {
      deleteForever(song);
    }
  }

  // ---- Tags ----

  Tag addTag(String name, {String? color}) {
    final tag = Tag(name: name, color: color);
    tags.add(tag);
    _save();
    notifyListeners();
    return tag;
  }

  void updateTag(Tag tag, {String? name, String? color, bool? hidden}) {
    if (name != null) tag.name = name;
    if (color != null) tag.color = color.isEmpty ? null : color;
    if (hidden != null) tag.hidden = hidden;
    _save();
    notifyListeners();
  }

  void deleteTag(Tag tag) {
    tags.remove(tag);
    for (final s in [...songs, ...trash]) {
      s.tags.remove(tag.id);
    }
    _save();
    notifyListeners();
  }

  // ---- Setlists ----

  Setlist createSetlist(String name) {
    final set = Setlist(name: name, date: DateTime.now());
    setlists.add(set);
    _save();
    notifyListeners();
    return set;
  }

  void updateSetlist(
    Setlist set, {
    String? name,
    DateTime? eventDate,
    bool clearEventDate = false,
    String? notes,
  }) {
    if (name != null) set.name = name;
    if (eventDate != null) set.eventDate = eventDate;
    if (clearEventDate) set.eventDate = null;
    if (notes != null) set.notes = notes;
    _save();
    notifyListeners();
  }

  void deleteSetlist(Setlist set) {
    setlists.remove(set);
    if (activeSetlistId == set.id) {
      activeSetlistId = null;
      activeEntryId = null;
    }
    _save();
    notifyListeners();
  }

  void addSongsToSetlist(Setlist set, List<String> songIds) {
    for (final id in songIds) {
      final song = songById(id);
      set.entries.add(
        SetEntry(
          songId: id,
          transpose: song?.transpose ?? 0,
          capo: song?.capo ?? 0,
        ),
      );
    }
    _save();
    notifyListeners();
  }

  // ---- Bible passages (see bible.dart) ----

  /// Passages shown as slides: songs that are never in the library, kept
  /// only while the app runs (by [BiblePassage.key]).
  final Map<String, Song> bibleSongs = {};
  final Map<String, BiblePassage> _biblePassages = {};

  /// A passage shown from the Bible tool while a song is open: the song
  /// stays, the passage's slides follow its own ([scriptureStart] on).
  BiblePassage? _sidePassage;
  Song? _sideSong;

  /// The section name of each scripture slide after the song's.
  List<String> scriptureNames = [];

  /// The first scripture slide after the song's (-1: none).
  int get scriptureStart =>
      scriptureNames.isEmpty ? -1 : slides.length - scriptureNames.length;

  /// The passage on screen (null: a song, or nothing).
  BiblePassage? get currentPassage =>
      _sidePassage ?? _biblePassages[selectedSongId];

  /// The passage on screen was opened from a setlist (it is the setlist's
  /// own, not one picked in the Bible tool).
  bool get passageFromSetlist =>
      _sidePassage == null && currentPassage != null && activeEntryId != null;

  /// Shows [p]. From [set]'s [entry], or with no song open: on its own,
  /// like a song. Otherwise the open song stays and the passage's slides
  /// go after its own.
  Future<void> showPassage(
    BiblePassage p, {
    Setlist? set,
    SetEntry? entry,
  }) async {
    final lib = BibleLibrary.instance;
    final bible = await lib.load(p.version);
    final second = p.second == null || lib.versionById(p.second) == null
        ? null
        : await lib.load(p.second!);
    final text = passageText(
      p,
      bible,
      second: second,
      numbers: lib.numbers,
      reference: lib.reference,
    );
    final id = 'bible:${p.key}';
    final song = Song(
      id: id,
      title: text.title,
      artist: p.versions,
      raw: text.raw,
      structure: text.structure,
    );
    lib.last = p;
    lib.save();
    final open = currentSong;
    if (entry == null && open != null && !bibleSongs.containsKey(open.id)) {
      _sidePassage = p;
      _sideSong = song;
      live = null;
      _rebuildSlides(keepIndex: true);
      if (scriptureStart >= 0) goTo(scriptureStart);
      notifyListeners();
      return;
    }
    bibleSongs[id] = song;
    _biblePassages[id] = p;
    live = null;
    selectedSongId = id;
    activeSetlistId = set?.id;
    activeEntryId = entry?.id;
    _rebuildSlides();
    // Straight to the first verses (past the blank and title slides).
    final first = slidePartIndex.indexWhere((i) => i >= 0);
    if (first > 0) goTo(first);
    notifyListeners();
  }

  /// Takes the scripture slides after the song's away again.
  void closeScripture() {
    final start = scriptureStart;
    if (_sidePassage == null) return;
    _sidePassage = null;
    _sideSong = null;
    if (start >= 0 && index >= start) {
      index = (start - 1).clamp(0, slides.length - 1);
      selection.value = index;
    }
    _rebuildSlides(keepIndex: true);
    notifyListeners();
  }

  /// Puts [p] at the end of [set] (it shows only there, not in the
  /// library).
  SetEntry addPassageToSetlist(Setlist set, BiblePassage p) {
    final entry = SetEntry(
      type: EntryType.bible,
      title: p.reference,
      extra: {'bible': p.toJson()},
    );
    set.entries.add(entry);
    _save();
    notifyListeners();
    return entry;
  }

  /// Every passage saved in a setlist, with its setlist.
  List<(Setlist, SetEntry)> get savedPassages => [
    for (final set in setlists)
      for (final e in set.entries)
        if (e.type == EntryType.bible && e.passage != null) (set, e),
  ];

  void addMarker(Setlist set, EntryType type, String title, {String? color}) {
    set.entries.add(SetEntry(type: type, title: title, color: color));
    _save();
    notifyListeners();
  }

  void updateEntry(SetEntry entry, {String? title, String? color}) {
    if (title != null) entry.title = title;
    if (color != null) entry.color = color.isEmpty ? null : color;
    _save();
    notifyListeners();
  }

  void removeEntry(Setlist set, SetEntry entry) {
    set.entries.remove(entry);
    if (activeEntryId == entry.id) {
      activeEntryId = null;
      activeSetlistId = null;
    }
    _save();
    notifyListeners();
  }

  void reorderEntries(Setlist set, int oldIndex, int newIndex) {
    final e = set.entries.removeAt(oldIndex);
    set.entries.insert(newIndex, e);
    _save();
    notifyListeners();
  }

  /// [child] (a song entry) dropped on [parent]: nested under it, after the
  /// songs already there (with any nested under [child] itself).
  void nestEntry(Setlist set, SetEntry child, SetEntry parent) {
    if (identical(child, parent) ||
        child.type != EntryType.song ||
        parent.type != EntryType.song ||
        child.songId == null) {
      return;
    }
    parent.subSongIds = [
      ...parent.subSongIds,
      child.songId!,
      ...child.subSongIds,
    ];
    set.entries.remove(child);
    if (activeEntryId == child.id) activeEntryId = parent.id;
    _nestingChanged(parent);
  }

  /// Nested song [index] of [parent] out again, as its own entry right
  /// after it.
  void unnestSong(Setlist set, SetEntry parent, int index) {
    final ids = parent.subSongIds;
    if (index < 0 || index >= ids.length) return;
    final id = ids.removeAt(index);
    parent.subSongIds = ids;
    set.entries.insert(set.entries.indexOf(parent) + 1, SetEntry(songId: id));
    _nestingChanged(parent);
  }

  /// A nested song moved up or down among the others under [parent].
  void moveSubSong(SetEntry parent, int index, int by) {
    final ids = parent.subSongIds;
    final to = index + by;
    if (index < 0 || index >= ids.length || to < 0 || to >= ids.length) {
      return;
    }
    ids.insert(to, ids.removeAt(index));
    parent.subSongIds = ids;
    _nestingChanged(parent);
  }

  /// The setlist's rows as the side pane shows them: each entry, then the
  /// songs nested under it (depth 1, their index in [SetlistRow.sub]).
  List<SetlistRow> setlistRows(Setlist set) => [
    for (final e in set.entries) ...[
      SetlistRow(e),
      for (final (k, id) in e.subSongIds.indexed)
        SetlistRow(e, sub: k, songId: id),
    ],
  ];

  /// Row [from] (with the songs nested under it) moved to before row [to]
  /// (rows as [setlistRows]), at [depth]: 1 nests it under the song above,
  /// 0 makes it an entry of its own (as Keydeck's slide groups).
  void moveSetlistRow(Setlist set, int from, int to, int depth) {
    final rows = [
      for (final r in setlistRows(set)) (r: r, depth: r.isSub ? 1 : 0),
    ];
    if (from < 0 || from >= rows.length) return;
    var end = from + 1;
    if (!rows[from].r.isSub) {
      while (end < rows.length && rows[end].r.isSub) {
        end++;
      }
    }
    final block = rows.sublist(from, end);
    rows.removeRange(from, end);
    // (Dropped inside itself: it stays where it is.)
    final at =
        (to <= from
                ? to
                : to <= end
                ? from
                : to - block.length)
            .clamp(0, rows.length);
    rows.insertAll(at, [
      (r: block.first.r, depth: depth),
      for (final b in block.skip(1)) (r: b.r, depth: 1),
    ]);

    final out = <SetEntry>[];
    final subs = <SetEntry, List<String>>{};
    SetEntry? host;
    String? movedTo; // the active entry's new place, if it was nested
    for (final (:r, :depth) in rows) {
      final songId = r.isSub ? r.songId : r.entry.songId;
      if (depth == 1 &&
          host != null &&
          songId != null &&
          (r.isSub || r.entry.type == EntryType.song)) {
        subs[host]!.add(songId);
        if (!r.isSub && r.entry.id == activeEntryId) movedTo = host.id;
        continue;
      }
      final SetEntry e;
      if (r.isSub) {
        final song = songById(r.songId);
        e = SetEntry(
          songId: r.songId,
          transpose: song?.transpose ?? 0,
          capo: song?.capo ?? 0,
        );
      } else {
        e = r.entry;
      }
      out.add(e);
      subs[e] = [];
      host = e.type == EntryType.song && e.songId != null ? e : null;
    }
    for (final e in out) {
      e.subSongIds = subs[e]!;
    }
    set.entries
      ..clear()
      ..addAll(out);
    if (movedTo != null) activeEntryId = movedTo;
    if (activeSetlistId == set.id) _rebuildSlides(keepIndex: true);
    _save();
    notifyListeners();
  }

  void _nestingChanged(SetEntry parent) {
    if (activeEntryId == parent.id) _rebuildSlides(keepIndex: true);
    _save();
    notifyListeners();
  }

  /// Turning set-specific edits on starts each entry from the song's
  /// current key and capo, so nothing changes until you edit it.
  void setSetSpecific(Setlist set, bool value) {
    if (value && !set.setSpecific) {
      for (final e in set.entries) {
        final song = songById(e.songId);
        e.transpose = song?.transpose ?? 0;
        e.capo = song?.capo ?? 0;
      }
    }
    set.setSpecific = value;
    _save();
    notifyListeners();
  }

  // ---- Formatting ----

  void updateFormat(void Function(SheetFormat f) change) {
    final before = format.followArrangement;
    change(format);
    if (format.followArrangement != before) _rebuildSlides();
    broadcastState(); // the stage view shows the formatted sheet
    _save();
    notifyListeners();
  }

  void setFontScale(double value, {bool persist = false}) {
    fontScale = value;
    broadcastState();
    if (persist) _save();
    notifyListeners();
  }

  void setTransitionDuration(double value, {bool persist = false}) {
    transitionDuration = value;
    broadcastState();
    if (persist) _save();
    notifyListeners();
  }

  // ---- Import ----

  /// Reads what [files] hold, without changing the library:
  ///  * a song-library backup (songs with `rawData`, playlists, tags, trash),
  ///  * an export from this app or the Mac app's `songs.json`,
  ///  * FreeShow songs (`.show`),
  ///  * plain ChordPro files.
  ImportBatch readImport(List<(String, String)> files) {
    final batch = ImportBatch();
    for (final (name, text) in files) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      final lower = name.toLowerCase();
      // SongbookPro's data (inside its .sbp / .sbpbackup zips).
      if (songbookProData(text) case final sbp?) {
        final (:songs, :sets) = parseSongbookPro(sbp);
        batch.isBackup = batch.isBackup || sets.isNotEmpty;
        batch.songs.addAll(songs);
        batch.setlists.addAll(sets);
        continue;
      }
      // An OnSong song file.
      if (lower.endsWith('.onsong')) {
        batch.songs.add(onSongToSong(text, fileName: name));
        continue;
      }
      if (decoded is Map<String, dynamic> && isLibraryBackup(decoded)) {
        final lib = LibraryBackup.parse(decoded);
        if (decoded['identity'] is String) {
          batch.identity = decoded['identity'] as String;
        }
        batch.isBackup = true;
        batch.tags.addAll(lib.tags);
        batch.songs.addAll(lib.songs);
        batch.trash.addAll(lib.trash);
        batch.setlists.addAll(lib.setlists);
      } else if (decoded is Map<String, dynamic> && decoded['songs'] is List) {
        batch.isBackup = true;
        List<Map<String, dynamic>> list(String key) =>
            ((decoded as Map)[key] as List? ?? []).cast<Map<String, dynamic>>();
        batch.songs.addAll(list('songs').map(Song.fromJson));
        batch.tags.addAll(list('tags').map(Tag.fromJson));
        batch.setlists.addAll(list('setlists').map(Setlist.fromJson));
        batch.trash.addAll(list('trash').map(Song.fromJson));
      } else if (freeShowData(decoded) case final show?) {
        // A FreeShow song (.show).
        batch.songs.add(importFreeShow(show, fileName: name));
      } else if (text.trim().isNotEmpty) {
        // Several songs in one file: split at each {new_song}.
        final parts = splitSongs(text);
        final fallback = name.replaceAll(RegExp(r'\.[^.]+$'), '');
        for (final (k, part) in parts.indexed) {
          final titles = ChordProHeader.parse(part).titles;
          batch.songs.add(
            Song(
              title: titles.isNotEmpty
                  ? titles.first
                  : parts.length > 1
                  ? '$fallback ${k + 1}'
                  : fallback,
              raw: part,
              date: DateTime.now(),
            ),
          );
        }
      }
    }
    return batch;
  }

  static String _titleKey(Song s) =>
      '${s.title.trim().toLowerCase()}|${s.artist.trim().toLowerCase()}';

  /// The library's copy of [s]: the same id, or else the same title and
  /// artist.
  Song? matchingSong(Song s) =>
      songs.where((e) => e.id == s.id).firstOrNull ??
      songs.where((e) => _titleKey(e) == _titleKey(s)).firstOrNull;

  /// The library's copy of [s]: the same id, or else the same name.
  Setlist? matchingSetlist(Setlist s) =>
      setlists.where((e) => e.id == s.id).firstOrNull ??
      setlists
          .where(
            (e) => e.name.trim().toLowerCase() == s.name.trim().toLowerCase(),
          )
          .firstOrNull;

  /// Adds [batch] to the library as [options] say. Re-importing the same
  /// file with the defaults updates in place.
  ImportSummary applyImport(
    ImportBatch batch, [
    ImportOptions options = const ImportOptions(),
  ]) {
    var nSongs = 0, nSets = 0, nTags = 0, nTrash = 0;
    if (batch.identity != null) backupIdentity = batch.identity;
    if (options.restore) {
      // Exactly the backup: everything else in this library goes.
      tags
        ..clear()
        ..addAll(batch.tags);
      songs
        ..clear()
        ..addAll(batch.songs);
      trash
        ..clear()
        ..addAll(batch.trash.where((t) => songById(t.id) == null));
      setlists
        ..clear()
        ..addAll(batch.setlists);
      activeSetlistId = null;
      activeEntryId = null;
      selectedSongId = songs.isEmpty
          ? null
          : (songs.toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey)))
                .first
                .id;
      final summary = ImportSummary(
        songs.length,
        setlists.length,
        tags.length,
        trash.length,
      );
      _rebuildSlides();
      _save();
      notifyListeners();
      return summary;
    }

    // Tags: the same id or name is the same tag.
    final tagIds = <String, String>{};
    for (final t in batch.tags) {
      final mine =
          tags.where((e) => e.id == t.id).firstOrNull ??
          tags
              .where((e) => e.name.toLowerCase() == t.name.toLowerCase())
              .firstOrNull;
      if (mine == null) {
        tags.add(t);
        nTags++;
      } else {
        tagIds[t.id] = mine.id;
      }
    }
    Song withId(Song s, String id) {
      final j = s.toJson();
      j['id'] = id;
      j['tags'] = [for (final t in s.tags) tagIds[t] ?? t];
      return Song.fromJson(j);
    }

    // Songs: the file's ids of songs already here → the library's ids (so
    // the file's setlists point at them).
    final songIds = <String, String>{};
    String? lastId;
    for (final s in batch.songs) {
      final mine = matchingSong(s);
      if (mine == null) {
        songs.add(withId(s, s.id));
        trash.removeWhere((t) => t.id == s.id);
      } else {
        songIds[s.id] = mine.id;
        final take = switch (options.songs) {
          ImportSongs.skip => false,
          ImportSongs.replace => true,
          ImportSongs.newer =>
            s.date != null &&
                (mine.date == null || s.date!.isAfter(mine.date!)),
        };
        if (!take) continue;
        songs[songs.indexOf(mine)] = withId(s, mine.id);
      }
      lastId = songIds[s.id] ?? s.id;
      nSongs++;
    }
    for (final s in batch.trash) {
      if (songById(s.id) == null && !trash.any((t) => t.id == s.id)) {
        trash.add(s);
        nTrash++;
      }
    }

    // Setlists.
    SetEntry entry(SetEntry e) {
      final to = songIds[e.songId];
      final subs = e.subSongIds;
      final movedSubs = [for (final id in subs) songIds[id] ?? id];
      if (to == null && listEquals(subs, movedSubs)) return e;
      final copy = SetEntry.fromJson({
        ...e.toJson(),
        'songId': ?to ?? e.songId,
        'extra': {...e.extra},
      });
      if (subs.isNotEmpty) copy.subSongIds = movedSubs;
      return copy;
    }

    for (final s in batch.setlists) {
      final incoming = Setlist.fromJson({
        ...s.toJson(),
        'entries': [for (final e in s.entries) entry(e).toJson()],
      });
      final mine = matchingSetlist(incoming);
      if (mine == null) {
        setlists.add(incoming);
      } else {
        switch (options.setlists) {
          case ImportSetlists.skip:
            continue;
          case ImportSetlists.replace:
            setlists[setlists.indexOf(mine)] = Setlist.fromJson({
              ...incoming.toJson(),
              'id': mine.id,
            });
          case ImportSetlists.merge:
            // Adds the songs (and dividers) it doesn't have yet, in order.
            for (final e in incoming.entries) {
              final there = mine.entries.any(
                (m) => e.type == EntryType.song
                    ? m.songId == e.songId
                    : m.id == e.id || (m.type == e.type && m.title == e.title),
              );
              if (!there) mine.entries.add(e);
            }
        }
      }
      nSets++;
    }

    final summary = ImportSummary(nSongs, nSets, nTags, nTrash);
    if (!summary.isEmpty) {
      if (lastId != null) {
        selectedSongId = lastId;
        activeSetlistId = null;
        activeEntryId = null;
      }
      _rebuildSlides();
      _save();
      notifyListeners();
    }
    return summary;
  }

  /// Reads and adds [files] in one go (see [readImport], [applyImport]).
  ImportSummary importFiles(
    List<(String, String)> files, [
    ImportOptions options = const ImportOptions(),
  ]) => applyImport(readImport(files), options);
}

/// What import files hold, before it's added to the library.
class ImportBatch {
  final songs = <Song>[];
  final tags = <Tag>[];
  final setlists = <Setlist>[];
  final trash = <Song>[];

  /// A whole library (so it can replace this one).
  bool isBackup = false;
  String? identity;

  bool get isEmpty => songs.isEmpty && setlists.isEmpty && trash.isEmpty;

  void addAll(ImportBatch other) {
    songs.addAll(other.songs);
    tags.addAll(other.tags);
    setlists.addAll(other.setlists);
    trash.addAll(other.trash);
    isBackup |= other.isBackup;
    identity ??= other.identity;
  }
}

/// Songs already in the library: leave them, take the file's copy when it
/// was edited later, or always take the file's copy.
enum ImportSongs { skip, newer, replace }

/// Setlists already in the library: add the songs they're missing, take
/// the file's copy, or leave them.
enum ImportSetlists { merge, replace, skip }

class ImportOptions {
  /// Replace the whole library with the backup.
  final bool restore;
  final ImportSongs songs;
  final ImportSetlists setlists;

  const ImportOptions({
    this.restore = false,
    this.songs = ImportSongs.replace,
    this.setlists = ImportSetlists.replace,
  });
}

/// A projector window: mirrors the operator's slides over the sync channel.
class ProjectorModel extends SlideState {
  final ProjectionSettings projection = ProjectionSettings();

  Timer? _alive;

  @override
  void dispose() {
    _alive?.cancel();
    super.dispose();
  }

  final Map<String, List<String?>> _mediaParts = {};
  final Map<String, Completer<Uint8List?>> _mediaWaiting = {};

  /// Asks the operator window for a picture/video (cast screens).
  Future<Uint8List?> fetchMedia(MediaRef ref) {
    final waiting = _mediaWaiting[ref.id];
    if (waiting != null) return waiting.future;
    final c = _mediaWaiting[ref.id] = Completer<Uint8List?>();
    sync.send({'type': 'mediaRequest', 'id': ref.id});
    return c.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        _mediaWaiting.remove(ref.id);
        return null;
      },
    );
  }

  void _mediaChunk(Map<String, dynamic> msg) {
    final id = msg['id'] as String;
    final n = msg['n'] as int;
    final parts = _mediaParts[id] ??= List<String?>.filled(n, null);
    parts[msg['i'] as int] = msg['data'] as String;
    if (parts.every((p) => p != null)) {
      _mediaParts.remove(id);
      _mediaWaiting.remove(id)?.complete(base64Decode(parts.join()));
    }
  }

  bool blackout = false;
  StageData? stage;
  CountdownState? countdown;
  LiveMedia? live;
  List<List<InkStroke>> ink = const [];

  ProjectionData get projectionData => ProjectionData(
    ink: ink,
    settings: projection,
    slides: slides,
    selection: selection,
    transitionSeconds: transitionDuration,
    projectorFont: projectorFont,
    blackout: blackout,
    stage: stage,
    countdown: countdown,
    live: live,
    lowPower: _remote,
  );

  /// A TV / Chromecast opened through the local server or casting.
  bool get _remote {
    final q = Uri.base.queryParameters;
    return q['net'] == '1' || q['cast'] == '1';
  }

  /// Moving between parts only updates the selection signal (the lyrics,
  /// highlight and footer listen to it), not the whole projector screen.
  @override
  void onIndexChanged() {}

  Size? _size;

  Map<String, dynamic>? get _sizeMsg =>
      _size == null ? null : {'w': _size!.width, 'h': _size!.height};

  /// Called by the projector screen whenever its window size changes.
  void reportSize(Size size) {
    if (size == _size) return;
    _size = size;
    sync.send({'type': 'alive', ...?_sizeMsg});
  }

  void start() {
    sync.messages.listen((msg) {
      switch (msg['type']) {
        case 'state':
          slides = List<String>.from(msg['slides'] as List);
          index = msg['index'] as int;
          fontScale = (msg['fontScale'] as num).toDouble();
          transitionDuration = (msg['transitionDuration'] as num).toDouble();
          final pj = msg['projection'];
          if (pj is Map<String, dynamic>) projection.updateFrom(pj);
          blackout = msg['blackout'] as bool? ?? false;
          stage = StageData.fromJson(msg['stage']);
          countdown = CountdownState.fromJson(msg['timer']);
          live = LiveMedia.fromJson(msg['live']);
          final inkMsg = msg['ink'];
          ink = [
            for (var i = 0; i < slides.length; i++)
              inkMsg is Map
                  ? InkStroke.listFromJson(inkMsg['$i'])
                  : const <InkStroke>[],
          ];
          if (projection.timerFont.isNotEmpty) {
            FontService.ensure(projection.timerFont)
                .then((_) => notifyListeners());
          }
          selection.value = index;
          final font = msg['font'] as String? ?? 'default';
          if (font != projectorFont) {
            projectorFont = font;
            FontService.ensure(font).then((_) => notifyListeners());
          }
          notifyListeners();
        case 'index':
          goTo(msg['index'] as int, broadcast: false);
        case 'mediaChunk':
          _mediaChunk(msg);
        case 'liveSeek':
          LiveControl.seeks.add((msg['to'] as num?)?.toDouble() ?? 0);
        case 'stop':
          // The operator pressed Stop: close this window if we can,
          // otherwise go dark and stop reporting in.
          _alive?.cancel();
          _alive = null;
          stopped = true;
          notifyListeners();
          closeWindow();
        case 'start':
          if (stopped) {
            stopped = false;
            _startAlive();
            notifyListeners();
          }
        case 'newBuild':
          // Projector screens (windows, TVs, Chromecasts) always run the
          // latest version: reload as soon as a new one is built.
          Future<void>.delayed(const Duration(milliseconds: 500), reloadPage);
      }
    });
    // A cast / presentation screen hears the operator over its connection
    // and has its own storage, so it fetches pictures/videos from there.
    final q = Uri.base.queryParameters;
    if (q['net'] == '1') MediaStore.remote = fetchMedia;
    // Media playing here tells the operator how far it has got.
    LiveControl.report = (pos, dur, playing) => sync.send({
      'type': 'liveTime',
      'pos': pos,
      'dur': dur,
      'playing': playing,
      'started': live?.started,
    });
    if (q['cast'] == '1') {
      sync.listenAsReceiver();
      MediaStore.remote = fetchMedia;
    }
    _startAlive();
    onWindowClose(() => sync.send({'type': 'bye'}));
  }

  /// Stopped by the operator (screen stays black until started again).
  bool stopped = false;

  void _startAlive() {
    sync.send({'type': 'hello', ...?_sizeMsg});
    // Tell the operator window this projector is still open (and its size).
    _alive?.cancel();
    _alive = Timer.periodic(
      const Duration(seconds: 2),
      (_) => sync.send({'type': 'alive', ...?_sizeMsg}),
    );
  }
}

/// A song ready to draw: see [PresenterModel.specFor].
class SheetSpec {
  /// Song id plus setlist entry id (the same song can be in a set twice).
  final String id;
  final Song song;
  final String raw;
  final int transpose;
  final MusicKey? displayKey;
  final MusicKey? soundingKey;
  final int capo;
  final List<SongPart> parts;
  final List<int> slidePartIndex;

  const SheetSpec({
    required this.id,
    required this.song,
    required this.raw,
    required this.transpose,
    required this.displayKey,
    required this.soundingKey,
    required this.capo,
    required this.parts,
    required this.slidePartIndex,
  });
}

const _accentFolds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ř': 'r',
  'ł': 'l',
  'đ': 'd',
  'ď': 'd',
  'ť': 't',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
};

/// Lower case with accents removed ("Élevé" → "eleve"), so accented
/// letters sort, group and search with their plain counterparts.
final _chordsForSearch = RegExp(r'\[[^\]]*\]');
final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Text for searching: accents folded ("Alléluia" → "alleluia", also when
/// the accent is a separate mark), chords dropped, and only letters and
/// digits kept — spaces, hyphens and punctuation don't count, so
/// "Al[G]lé - lu - ia" is "alleluia" too.
String searchKey(String text) =>
    foldAccents(text.replaceAll(_chordsForSearch, ''))
        .replaceAll(_notLetterOrDigit, '');

/// The words of [text] for searching (accents folded, chords dropped).
Set<String> searchWords(String text) => {
  for (final w in foldAccents(
    text.replaceAll(_chordsForSearch, ''),
  ).split(_notLetterOrDigit))
    if (w.isNotEmpty) w,
};

/// Whether [query] is found in [key] (a [searchKey]): all of it, spaces and
/// punctuation ignored, or each of its words, in any order.
bool searchMatches(String key, String query) {
  final whole = searchKey(query);
  if (whole.isEmpty || key.contains(whole)) return true;
  final words = [
    for (final w in query.split(RegExp(r'\s+')))
      if (searchKey(w).isNotEmpty) searchKey(w),
  ];
  return words.length > 1 && words.every(key.contains);
}

String foldAccents(String text) {
  // One pass over the text (this runs for every song when sorting and
  // searching): most characters stay as they are.
  final lower = text.toLowerCase();
  StringBuffer? out;
  for (var i = 0; i < lower.length; i++) {
    final unit = lower.codeUnitAt(i);
    final folded = unit < 0xC0 ? null : _accentFoldsByUnit[unit];
    if (folded != null) {
      (out ??= StringBuffer(lower.substring(0, i))).write(folded);
    } else {
      out?.writeCharCode(unit);
    }
  }
  return out?.toString() ?? lower;
}

final Map<int, String> _accentFoldsByUnit = {
  for (final e in _accentFolds.entries) e.key.codeUnitAt(0): e.value,
};

/// A sticky note on a song (saved with the song).
class StickyNote {
  final String id;
  String text;
  double x, y, width, height;
  int colour;
  bool bold;
  bool italic;
  double size;

  /// Pinned to the chord sheet (scrolls with it); [x], [y] are then
  /// positions on the sheet instead of the window.
  bool pinned;

  /// Mixed formatting: runs of text with their own bold / italic / size
  /// (`[{t, b, i, s}, …]`); null = all in the note's own style.
  List<Map<String, dynamic>>? runs;

  StickyNote({
    String? id,
    this.text = '',
    required this.x,
    required this.y,
    this.width = 272,
    this.height = 170,
    this.colour = 0xFFFFF475,
    this.bold = false,
    this.italic = false,
    this.size = 16,
    this.runs,
    this.pinned = false,
  }) : id = id ?? _newId();

  static String _newId() =>
      'n${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    'colour': colour,
    'bold': bold,
    'italic': italic,
    'size': size,
    if (runs != null) 'runs': runs,
    if (pinned) 'pinned': true,
  };

  static StickyNote fromJson(Map j) {
    double d(Object? v, double f) => (v as num?)?.toDouble() ?? f;
    return StickyNote(
      id: j['id'] as String?,
      text: j['text'] as String? ?? '',
      x: d(j['x'], 40),
      y: d(j['y'], 120),
      width: d(j['w'], 220),
      height: d(j['h'], 160),
      colour: (j['colour'] as num?)?.toInt() ?? 0xFFFFF475,
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      size: d(j['size'], 16),
      pinned: j['pinned'] == true,
      runs: (j['runs'] as List?)
          ?.whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(),
    );
  }
}

/// A song shown on the projector (see [PresenterModel.usage]).
class SongUse {
  final String songId, title, artist, ccli;
  final DateTime at;
  final String? setlist;
  const SongUse({
    required this.songId,
    required this.title,
    required this.artist,
    required this.ccli,
    required this.at,
    this.setlist,
  });

  Map<String, dynamic> toJson() => {
    'song': songId,
    'title': title,
    if (artist.isNotEmpty) 'artist': artist,
    if (ccli.isNotEmpty) 'ccli': ccli,
    'at': at.toIso8601String(),
    if (setlist != null) 'setlist': setlist,
  };

  static SongUse fromJson(Map<String, dynamic> j) => SongUse(
    songId: j['song'] as String? ?? '',
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    ccli: j['ccli'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    setlist: j['setlist'] as String?,
  );
}

/// A row of a setlist as the side pane shows it: an entry, or (with [sub])
/// the [sub]-th song nested under [entry].
class SetlistRow {
  final SetEntry entry;
  final int? sub;
  final String? songId;
  const SetlistRow(this.entry, {this.sub, this.songId});
  bool get isSub => sub != null;
}
