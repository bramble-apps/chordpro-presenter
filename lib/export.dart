// Song export: ChordPro, plain text and PDF. All three use the song as it
// is currently shown: arrangement applied, chords in the current key (capo
// shapes), key changes from the structure.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'abc.dart';
import 'browser.dart';
import 'chordpro.dart';
import 'fonts.dart';
import 'format.dart';
import 'music.dart';
import 'scanner/engrave.dart';
import 'state.dart';

/// Everything an export needs, captured from the model.
class ExportSource {
  final Song song;
  final String raw;
  final int transpose;
  final MusicKey? shapeKey;
  final MusicKey? soundingKey;
  final int capo;
  final SheetFormat format;
  final AppSettings settings;

  ExportSource.from(PresenterModel m)
    : song = m.currentSong!,
      raw = m.effectiveRaw,
      transpose = m.shapeTranspose,
      shapeKey = m.shapeKey,
      soundingKey = m.currentKey,
      capo = m.currentCapo,
      format = m.format,
      settings = m.settings;

  /// A song as a setlist (or the library) has it: its arrangement, key and
  /// capo there.
  ExportSource.spec(SheetSpec s, PresenterModel m)
    : song = s.song,
      raw = s.raw,
      transpose = s.transpose,
      shapeKey = s.displayKey,
      soundingKey = s.soundingKey,
      capo = s.capo,
      format = m.format,
      settings = m.settings;

  String get fileStem {
    final t = song.displayTitle.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '').trim();
    return t.isEmpty ? 'song' : t;
  }

  /// Chord as displayed, in the user's notation, with a key change of
  /// [extra] semitones applied.
  String chord(String c, int extra, {bool standard = false}) => renderDualChord(
    c,
    transpose: transpose + extra,
    key: shapeKey?.transposed(extra),
    notation: standard ? ChordNotation.standard : format.notation,
    dual: standard ? null : format.dualNotation,
    minorStyle: standard ? MinorStyle.m : format.minorStyle,
    accidentals: standard ? Accidentals.auto : format.accidentals,
  );

  String get detailsLine {
    final h = ChordProHeader.parse(song.raw);
    final tempo = song.tempo.isNotEmpty ? song.tempo : (h.tempo ?? '');
    final time = song.timeSignature.isNotEmpty
        ? song.timeSignature
        : (h.time ?? '');
    return [
      if (soundingKey != null) 'Key ${soundingKey!.name}',
      if (capo > 0) 'Capo $capo',
      if (tempo.isNotEmpty) '${tempo.trim()} BPM',
      if (time.isNotEmpty) time.trim(),
      if (song.duration.isNotEmpty) song.duration,
    ].join('  ·  ');
  }

  String get artistLine {
    final h = ChordProHeader.parse(song.raw);
    return song.artist.isNotEmpty ? song.artist : (h.artist ?? '');
  }

  String get subtitleLine {
    final h = ChordProHeader.parse(song.raw);
    return song.subtitle.isNotEmpty ? song.subtitle : (h.subtitle ?? '');
  }

  List<String> get footerLines => [
    if (song.copyright.isNotEmpty) song.copyright,
    if (song.ccli.isNotEmpty) 'CCLI Song # ${song.ccli}',
    if (song.ccliLicense.isNotEmpty) 'CCLI License # ${song.ccliLicense}',
    if (song.footer.isNotEmpty && song.footer != song.copyright) song.footer,
  ];
}

final _meta = RegExp(
  r'^\s*\{\s*(title|t|subtitle|st|artist|key|capo|tempo|time|duration|ccli|'
  r'ccli_license|copyright|footer|album|composer|lyricist|sorttitle)\s*:',
  caseSensitive: false,
);
final _transpose = RegExp(
  r'^\s*\{\s*transpose\s*:\s*([+-]?\d+)\s*\}\s*$',
  caseSensitive: false,
);
final _chord = RegExp(r'\[([^\]]*)\]');

/// ChordPro file. Chords are written in standard names (C, Am…) in the
/// current key so any ChordPro app can read them.
String exportChordPro(ExportSource src, {required bool includeChords}) {
  final s = src.song;
  final out = <String>[
    '{title: ${s.displayTitle}}',
    if (src.subtitleLine.isNotEmpty) '{subtitle: ${src.subtitleLine}}',
    if (src.artistLine.isNotEmpty) '{artist: ${src.artistLine}}',
    if (includeChords && src.soundingKey != null)
      '{key: ${src.soundingKey!.name}}',
    if (includeChords && src.capo > 0) '{capo: ${src.capo}}',
    if (s.tempo.isNotEmpty) '{tempo: ${s.tempo}}',
    if (s.timeSignature.isNotEmpty) '{time: ${s.timeSignature}}',
    if (s.duration.isNotEmpty) '{duration: ${s.duration}}',
    if (s.composer.isNotEmpty) '{composer: ${s.composer}}',
    if (s.lyricist.isNotEmpty) '{lyricist: ${s.lyricist}}',
    if (s.copyright.isNotEmpty) '{copyright: ${s.copyright}}',
    if (s.ccli.isNotEmpty) '{ccli: ${s.ccli}}',
    if (s.ccliLicense.isNotEmpty) '{ccli_license: ${s.ccliLicense}}',
    if (s.footer.isNotEmpty) '{footer: ${s.footer}}',
    if (s.notes.isNotEmpty) '{comment: ${s.notes.replaceAll('\n', ' ')}}',
    // ChordPro's way of carrying any other field.
    for (final e in s.custom.entries)
      if (e.value.trim().isNotEmpty) '{meta: ${e.key} ${e.value.trim()}}',
    '',
  ];
  var extra = 0;
  for (final line in src.raw.replaceAll('\r\n', '\n').split('\n')) {
    if (_meta.hasMatch(line)) continue;
    // (Linked sections are an app setting, not ChordPro.)
    if (line.trim() == linkMarker) continue;
    final t = _transpose.firstMatch(line);
    if (t != null) {
      extra = int.parse(t.group(1)!);
      final key = src.soundingKey?.transposed(extra);
      out.add('{comment: Key change${key != null ? ' → ${key.name}' : ''}}');
      continue;
    }
    out.add(
      includeChords
          ? line.replaceAllMapped(
              _chord,
              (m) => '[${src.chord(m.group(1)!, extra, standard: true)}]',
            )
          : line.replaceAll(_chord, '').replaceAll(RegExp(r' {2,}'), ' '),
    );
  }
  return '${out.join('\n').trimRight()}\n';
}

/// Plain text: chords on their own line above the lyrics (monospace
/// alignment), or lyrics only.
String exportText(ExportSource src, {required bool includeChords}) {
  final out = <String>[
    src.song.displayTitle,
    if (src.artistLine.isNotEmpty) src.artistLine,
    if (src.subtitleLine.isNotEmpty) src.subtitleLine,
    if (includeChords && src.detailsLine.isNotEmpty) src.detailsLine,
    '',
  ];
  if (src.song.notes.isNotEmpty) out.addAll([src.song.notes, '']);
  var extra = 0;
  for (final part in ChordPro.parts(src.raw)) {
    if (part.isMarker) {
      extra = part.keyChange!;
      final key = src.soundingKey?.transposed(extra);
      out.addAll([
        '--- Key change${key != null ? ' → ${key.name}' : ''} ---',
        '',
      ]);
      continue;
    }
    for (final line in ChordPro.sheetLines(part.raw)) {
      if (line == pageBreakMarker || line.startsWith(transposeMarker)) continue;
      if (line.startsWith(abcMarker)) {
        // An ABC tune, as typed.
        if (includeChords) {
          out.addAll(line.substring(abcMarker.length).split(tabLineBreak));
        }
        continue;
      }
      if (line.startsWith(tabMarker)) {
        // A tab, as typed.
        if (includeChords) {
          out.addAll(line.substring(tabMarker.length).split(tabLineBreak));
        }
        continue;
      }
      if (line.startsWith(rhythmMarker)) {
        // A strum pattern, as arrows.
        if (includeChords) {
          out.add(
            'Strum: ${parseRhythm(line.substring(rhythmMarker.length)).map((s) => s.symbol + (s.accent ? '>' : '')).join(' ')}',
          );
        }
        continue;
      }
      if (line.isEmpty || ChordPro.isSectionLabel(line)) {
        out.add(line);
        continue;
      }
      final segs = ChordPro.plainSegments(line);
      final lyric = segs.map((s) => s.text).join();
      if (includeChords && segs.any((s) => s.chord?.isNotEmpty ?? false)) {
        final chords = StringBuffer();
        var col = 0;
        for (final seg in segs) {
          if (seg.chord != null && seg.chord!.isNotEmpty) {
            final c = src.chord(seg.chord!, extra);
            if (chords.length < col) {
              chords.write(' ' * (col - chords.length));
            } else if (chords.isNotEmpty) {
              chords.write(' '); // previous chord ran long
            }
            chords.write(c);
          }
          col += seg.text.length;
        }
        out.add(chords.toString().trimRight());
      }
      if (lyric.trim().isNotEmpty) out.add(lyric.trimRight());
    }
    out.add('');
  }
  if (src.footerLines.isNotEmpty) out.addAll(['', ...src.footerLines]);
  return '${out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight()}\n';
}

// ---- PDF ----

/// (bold, italic) for each 52-letter block of Unicode's Mathematical
/// Alphanumeric Symbols, starting at U+1D400: bold, italic, bold italic,
/// script, bold script, fraktur, double-struck, bold fraktur, sans, sans
/// bold, sans italic, sans bold italic, monospace.
const _mathStyles = [
  (true, false), (false, true), (true, true), (false, true), (true, true),
  (false, false), (true, false), (true, false), (false, false), (true, false),
  (false, true), (true, true), (false, false), //
];

/// Splits [text] into runs, turning "styled" Unicode letters (𝘛𝘰, 𝐁𝐨𝐥𝐝 —
/// used in some song libraries to fake italics/bold) into plain letters
/// with real bold/italic. PDF fonts don't contain those characters.
List<(String, bool, bool)> foldStyledLetters(String text) {
  final runs = <(String, bool, bool)>[];
  var buf = StringBuffer();
  var cur = (false, false);
  void push((bool, bool) style, String chars) {
    if (style != cur && buf.isNotEmpty) {
      runs.add((buf.toString(), cur.$1, cur.$2));
      buf = StringBuffer();
    }
    cur = style;
    buf.write(chars);
  }

  for (final cp in text.runes) {
    if (cp >= 0x1D400 && cp < 0x1D400 + 52 * _mathStyles.length) {
      final o = cp - 0x1D400;
      final i = o % 52;
      push(
        _mathStyles[o ~/ 52],
        String.fromCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26),
      );
    } else if (cp >= 0x1D7CE && cp <= 0x1D7FF) {
      final o = cp - 0x1D7CE;
      push((
        o ~/ 10 == 0 || o ~/ 10 == 3,
        false,
      ), String.fromCharCode(0x30 + o % 10));
    } else if (cp >= 0xFF01 && cp <= 0xFF5E) {
      // Full-width ＡＢＣ１２３（） -> ABC123()
      push((false, false), String.fromCharCode(cp - 0xFF01 + 0x21));
    } else if (_plain.containsKey(cp)) {
      push((false, false), _plain[cp]!);
    } else if (_invisible(cp)) {
      continue;
    } else {
      push((false, false), String.fromCharCode(cp));
    }
  }
  if (buf.isNotEmpty) runs.add((buf.toString(), cur.$1, cur.$2));
  return runs;
}

/// Symbols PDF fonts usually lack, written the plain way.
const _plain = {
  0x266F: '#', // ♯
  0x266D: 'b', // ♭
  0x266E: '', // ♮
  0x2248: '~', // ≈
  0x2260: '!=', // ≠
  0x2192: '->', // →
  0x2190: '<-', // ←
  0x2B91: '->', // ⮑
  0x21B3: '->', // ↳
  0x2026: '...', // …
};

/// Characters with nothing to print: C1 controls, private-use symbols,
/// variation selectors, zero-width and text-direction marks.
bool _invisible(int cp) =>
    (cp >= 0x80 && cp <= 0x9F) ||
    (cp >= 0xE000 && cp <= 0xF8FF) ||
    (cp >= 0xFE00 && cp <= 0xFE0F) ||
    (cp >= 0x200B && cp <= 0x200F) ||
    (cp >= 0x202A && cp <= 0x202E) ||
    (cp >= 0x2066 && cp <= 0x2069) ||
    cp == 0xFEFF;

pw.Font? _fontFor(pw.ThemeData t, bool bold, bool italic) {
  final d = t.defaultTextStyle;
  return bold && italic
      ? d.fontBoldItalic
      : bold
      ? d.fontBold
      : italic
      ? d.fontItalic
      : d.fontNormal;
}

Future<pw.Font?> _fontFile(String file) async {
  try {
    return pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  } catch (_) {
    return null;
  }
}

/// Regular/bold/italic/bold-italic for a font id. The app's default font
/// (Roboto) isn't bundled, so Noto Sans stands in for it in PDFs.
Future<pw.ThemeData> _pdfTheme(String fontId) async {
  final option = builtInFonts.where((f) => f.id == fontId).firstOrNull;
  if (option != null && option.files.isNotEmpty) {
    final files = option.files;
    final regular = await _fontFile(files[0]);
    if (regular != null) {
      final bold = await _fontFile(files[1]);
      final italic = await _fontFile(files[2]);
      final boldItalic = files.length > 3 ? await _fontFile(files[3]) : bold;
      return pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );
    }
  }
  if (fontId.startsWith('custom_')) {
    final bytes = await KeyValueStore().read('font:$fontId');
    if (bytes != null && bytes.isNotEmpty) {
      final font = pw.Font.ttf(
        ByteData.sublistView(Uint8List.fromList(_b64(bytes))),
      );
      return pw.ThemeData.withFont(base: font, bold: font, italic: font);
    }
  }
  return _pdfTheme('notosans');
}

List<int> _b64(String s) => const Base64Codec().decode(s);

/// Characters a font can draw (from its regular file). Anything else is
/// left out of the PDF rather than printed as an empty box.
Future<Set<int>> _coverage(String fontId) async {
  try {
    ByteData? data;
    final option = builtInFonts.where((f) => f.id == fontId).firstOrNull;
    if (option != null && option.files.isNotEmpty) {
      data = await rootBundle.load('assets/fonts/${option.files.first}');
    } else if (fontId.startsWith('custom_')) {
      final b = await KeyValueStore().read('font:$fontId');
      if (b != null && b.isNotEmpty) {
        data = ByteData.sublistView(Uint8List.fromList(_b64(b)));
      }
    }
    if (data == null) return await _coverage('notosans');
    return TtfParser(data).charToGlyphIndexMap.keys.toSet();
  } catch (_) {
    return const {};
  }
}

PdfColor _pdfColor(String? name, PdfColor fallback) {
  final c = colorNamed(name);
  if (c == null) return fallback;
  return PdfColor(c.r, c.g, c.b);
}

enum PaperSize { letter, a4 }

/// Builds the PDF. [scale] is 0.5–1.5 (100% = the sizes set in Format).
/// An ABC tune drawn as music for a PDF page (null if it has no notes or
/// can't be drawn here).
Future<pw.Widget?> _abcPdf(String abc) async {
  final score = parseAbc(abc);
  if (score == null) return null;
  try {
    const width = 520.0; // points: the page's text width, about
    final layout = ScoreLayout(score, width, space: 6);
    final image = await renderLayout(layout, 0, layout.height, 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Image(pw.MemoryImage(png.buffer.asUint8List()), width: width),
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List> exportPdf(
  ExportSource src, {
  required bool includeChords,
  double scale = 1.0,
  PaperSize paper = PaperSize.letter,
  int columns = 1,
  String? marginLabels,
}) async {
  final doc = pw.Document(title: src.song.displayTitle);
  await addPdfPages(
    doc,
    src,
    includeChords: includeChords,
    scale: scale,
    paper: paper,
    columns: columns,
    marginLabels: marginLabels,
  );
  return doc.save();
}

/// Adds a song's pages to [doc] (one song, or one of a setlist's).
/// [marginLabels] 'left' / 'right' puts section labels as badges on a rail
/// in that margin, '' above as text (null: as in the song's Format).
Future<void> addPdfPages(
  pw.Document doc,
  ExportSource src, {
  required bool includeChords,
  double scale = 1.0,
  PaperSize paper = PaperSize.letter,
  int columns = 1,
  String? marginLabels,
}) async {
  final f = src.format;
  final side = marginLabels ?? f.marginLabels;
  final textTheme = await _pdfTheme(src.settings.sheetFont);
  final textGlyphs = await _coverage(src.settings.sheetFont);
  final chordGlyphs = src.settings.chordFont == src.settings.sheetFont
      ? textGlyphs
      : await _coverage(src.settings.chordFont);
  final chordTheme = src.settings.chordFont == src.settings.sheetFont
      ? textTheme
      : await _pdfTheme(src.settings.chordFont);
  const grey = PdfColor.fromInt(0xFF555555);

  // Writing a linked piece (a verse's translation…): Format → linked look.
  var inLinked = false;
  final look = f.linked;
  bool isBold(SheetElement e) => f[e].bold || (inLinked && look.bold);
  bool isItalic(SheetElement e) => f[e].italic || (inLinked && look.italic);

  pw.TextStyle style(
    SheetElement e, {
    PdfColor color = PdfColors.black,
    bool chord = false,
  }) {
    final s = f[e];
    final t = chord ? chordTheme : textTheme;
    final bold = isBold(e), italic = isItalic(e);
    final font = bold && italic
        ? t.defaultTextStyle.fontBoldItalic
        : bold
        ? t.defaultTextStyle.fontBold
        : italic
        ? t.defaultTextStyle.fontItalic
        : t.defaultTextStyle.fontNormal;
    var c = _pdfColor(s.color, color);
    if (inLinked) {
      final own = look.color;
      if (own != null && !chord) c = PdfColor(own.r, own.g, own.b);
      // Dimmed: mixed towards the white page.
      if (look.dim) {
        c = PdfColor(
          c.red + (1 - c.red) * 0.45,
          c.green + (1 - c.green) * 0.45,
          c.blue + (1 - c.blue) * 0.45,
        );
      }
    }
    return pw.TextStyle(
      font: font,
      fontSize: s.size * scale * (inLinked ? look.size / 100 : 1),
      color: c,
      decoration: s.underline ? pw.TextDecoration.underline : null,
    );
  }

  /// Text spans with styled Unicode letters folded to real bold/italic.
  List<pw.TextSpan> spans(
    SheetElement e,
    String text,
    pw.TextStyle st, {
    bool chord = false,
  }) {
    final t = chord ? chordTheme : textTheme;
    final glyphs = chord ? chordGlyphs : textGlyphs;
    String printable(String run) => glyphs.isEmpty
        ? run
        : String.fromCharCodes(
            run.runes.where(
              (c) => c <= 0x20 || c == 0xA0 || glyphs.contains(c),
            ),
          );
    return [
      for (final (run, b, i) in foldStyledLetters(text))
        pw.TextSpan(
          text: printable(run),
          style: st.copyWith(
            font: _fontFor(t, isBold(e) || b, isItalic(e) || i),
          ),
        ),
    ];
  }

  pw.Widget text(SheetElement e, String value, pw.TextStyle st) =>
      pw.RichText(text: pw.TextSpan(children: spans(e, value, st)));

  /// Chord text (some libraries put words like "To Chorus" in chords).
  pw.Widget chordText(String value) => pw.RichText(
    text: pw.TextSpan(
      children: spans(
        SheetElement.chords,
        value,
        style(SheetElement.chords, chord: true),
        chord: true,
      ),
    ),
  );

  final children = <pw.Widget>[];
  void add(SheetElement e, String value, {PdfColor color = PdfColors.black}) {
    if (f[e].hidden || value.isEmpty) return;
    children.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: text(e, f[e].apply(value), style(e, color: color)),
      ),
    );
  }

  add(SheetElement.title, src.song.displayTitle);
  add(SheetElement.artist, src.artistLine, color: grey);
  add(SheetElement.artist, src.subtitleLine, color: grey);
  if (includeChords) add(SheetElement.details, src.detailsLine, color: grey);
  children.add(pw.SizedBox(height: 10 * scale));
  if (src.song.notes.isNotEmpty && !f[SheetElement.notes].hidden) {
    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F1F1)),
        child: text(
          SheetElement.notes,
          f[SheetElement.notes].apply(src.song.notes),
          style(SheetElement.notes),
        ),
      ),
    );
  }

  final lyricStyle = style(SheetElement.lyrics);
  final chordStyle = style(SheetElement.chords, chord: true);
  final showChords = includeChords && !f[SheetElement.chords].hidden;
  final showLyrics = !f[SheetElement.lyrics].hidden;

  // Where the title block ends and each part starts (for columns).
  final headerCount = children.length;
  final partStarts = <int>[];
  var extra = 0;
  for (final part in ChordPro.parts(src.raw)) {
    partStarts.add(children.length);
    if (part.isMarker) {
      extra = part.keyChange!;
      final key = src.soundingKey?.transposed(extra);
      add(
        SheetElement.headings,
        'Key change${key != null ? ' → ${key.name}' : ''}',
        color: grey,
      );
      continue;
    }
    final pieces = part.pieceLines;
    String? marginLabel;
    for (var p = 0; p < pieces.length; p++) {
      // Linked pieces: hidden or styled as set in Format.
      if (p > 0 && !look.show) continue;
      inLinked = p > 0;
      for (final line in ChordPro.sheetLines(pieces[p].join('\n'))) {
        if (line == pageBreakMarker || line.startsWith(transposeMarker)) {
          continue;
        }
        if (line.startsWith(abcMarker)) {
          // An ABC tune, engraved (as typed if it can't be read).
          if (showChords) {
            final abc = line
                .substring(abcMarker.length)
                .split(tabLineBreak)
                .join('\n');
            children.add(
              await _abcPdf(abc) ??
                  pw.Text(
                    abc,
                    style: pw.TextStyle(
                      font: await _fontFile('Cousine-Regular.ttf'),
                      fontSize: 9 * scale,
                    ),
                    softWrap: false,
                  ),
            );
          }
          continue;
        }
        if (line.startsWith(tabMarker)) {
          // A tab, as typed, in a fixed-width font.
          if (showChords) {
            final mono = await _fontFile('Cousine-Regular.ttf');
            children.add(
              pw.Text(
                line.substring(tabMarker.length).split(tabLineBreak).join('\n'),
                style: pw.TextStyle(font: mono, fontSize: 9 * scale),
                softWrap: false,
              ),
            );
          }
          continue;
        }
        if (line.startsWith(rhythmMarker)) {
          // A strum pattern: the strokes over their counts, in one line.
          if (showChords) {
            final strokes = parseRhythm(line.substring(rhythmMarker.length));
            final counts = rhythmCounts(
              strokes.length,
              beatsPerBar(src.song.timeSignature),
            );
            children.add(
              chordText(
                [
                  for (var k = 0; k < strokes.length; k++)
                    // Letters, not arrows: every PDF font has them.
                    '${strokes[k].action}${strokes[k].accent ? '>' : ''}${counts[k].isEmpty ? '' : counts[k]}',
                ].join('  '),
              ),
            );
          }
          continue;
        }
        if (line.isEmpty) {
          children.add(pw.SizedBox(height: 4 * scale));
        } else if (ChordPro.isSectionLabel(line)) {
          if (side.isNotEmpty) {
            // (in the margin: the part's first label, as a badge)
            marginLabel ??= ChordPro.sectionName(line);
            continue;
          }
          children.add(pw.SizedBox(height: 4 * scale));
          add(SheetElement.headings, line, color: grey);
        } else {
          final segs = ChordPro.plainSegments(line);
          final has = segs.any((s) => s.chord?.isNotEmpty ?? false);
          final lyric = segs.map((s) => s.text).join();
          final apply = f[SheetElement.lyrics].apply;
          pw.Widget? w;
          if (!has || !showChords) {
            if (showLyrics && lyric.trim().isNotEmpty) {
              w = text(SheetElement.lyrics, apply(lyric), lyricStyle);
            }
          } else if (!showLyrics) {
            w = chordText(
              segs
                  .where((s) => s.chord?.isNotEmpty ?? false)
                  .map((s) => src.chord(s.chord!, extra))
                  .join('   '),
            );
          } else if (f.chordsInline) {
            w = pw.RichText(
              text: pw.TextSpan(
                children: [
                  for (final s in segs) ...[
                    if (s.chord?.isNotEmpty ?? false)
                      ...spans(
                        SheetElement.chords,
                        '${src.chord(s.chord!, extra)} ',
                        chordStyle,
                        chord: true,
                      ),
                    ...spans(SheetElement.lyrics, apply(s.text), lyricStyle),
                  ],
                ],
              ),
            );
          } else {
            // Each word is a column: chord row over lyric row. Both rows get a
            // fixed height, and spaces are non-breaking so a chord over a gap
            // keeps its width and stays on the chord row.
            String keep(String v) =>
                v.isEmpty ? '\u00A0' : v.replaceAll(' ', '\u00A0');
            final chordH = f[SheetElement.chords].size * scale * 1.3;
            final lyricH = f[SheetElement.lyrics].size * scale * 1.3;
            w = pw.Wrap(
              children: [
                for (final s in segs)
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        height: chordH,
                        child: chordText(
                          s.chord == null
                              ? '\u00A0'
                              : '${src.chord(s.chord!, extra)}\u00A0',
                        ),
                      ),
                      pw.SizedBox(
                        height: lyricH,
                        child: text(
                          SheetElement.lyrics,
                          keep(apply(s.text)),
                          lyricStyle,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          }
          if (w != null) {
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: w,
              ),
            );
          }
        }
      }
    }
    inLinked = false;
    if (marginLabel != null) {
      _railPart(children, partStarts.last, side, marginLabel, scale, grey);
    }
    children.add(pw.SizedBox(height: 6 * scale));
  }

  final footer = src.footerLines;
  final pageFormat = paper == PaperSize.a4
      ? PdfPageFormat.a4
      : PdfPageFormat.letter;

  pw.Widget footerFor(int page, int pages) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (!f[SheetElement.footer].hidden && footer.isNotEmpty)
        pw.Text(
          f[SheetElement.footer].apply(footer.join('\n')),
          style: style(SheetElement.footer, color: grey),
        ),
      if (pages > 1)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '$page / $pages',
            style: pw.TextStyle(fontSize: 8 * scale, color: grey),
          ),
        ),
    ],
  );

  if (columns > 1) {
    _addColumnPages(
      doc,
      pageFormat: pageFormat,
      theme: textTheme,
      columns: columns,
      header: children.sublist(0, headerCount),
      parts: [
        for (var i = 0; i < partStarts.length; i++)
          children.sublist(
            partStarts[i],
            i + 1 < partStarts.length ? partStarts[i + 1] : children.length,
          ),
      ],
      footerFor: footerFor,
    );
    return;
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: paper == PaperSize.a4
          ? PdfPageFormat.a4
          : PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(40),
      theme: textTheme,
      footer: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (!f[SheetElement.footer].hidden && footer.isNotEmpty)
            pw.Text(
              f[SheetElement.footer].apply(footer.join('\n')),
              style: style(SheetElement.footer, color: grey),
            ),
          if (context.pagesCount > 1)
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8 * scale, color: grey),
              ),
            ),
        ],
      ),
      build: (_) => children,
    ),
  );
}

/// A part's lines (from [start]) put beside a rail in the [side] margin,
/// with [name] shortened to a badge on it, by the part's middle line. Each
/// line keeps its own piece of the rail, so the part can still break across
/// pages and columns.
void _railPart(
  List<pw.Widget> children,
  int start,
  String side,
  String name,
  double scale,
  PdfColor grey,
) {
  if (children.length <= start) return;
  final gutter = 32 * scale;
  final left = side == 'left';
  final short = ChordPro.sectionAbbreviation(name);
  final chorus = short.startsWith('C') && !short.startsWith('Co');
  final rail = pw.BorderSide(color: chorus ? grey : PdfColors.grey500, width: .8);
  final badge = pw.SizedBox(
    width: gutter,
    child: pw.Center(
      child: pw.Container(
        padding: pw.EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1.5 * scale),
        decoration: pw.BoxDecoration(
          color: chorus ? PdfColors.grey800 : PdfColors.white,
          border: pw.Border.all(color: chorus ? PdfColors.grey800 : grey, width: .8),
          borderRadius: pw.BorderRadius.circular(3 * scale),
        ),
        child: pw.Text(
          short,
          style: pw.TextStyle(
            fontSize: 8 * scale,
            fontWeight: pw.FontWeight.bold,
            color: chorus ? PdfColors.white : grey,
          ),
        ),
      ),
    ),
  );
  final lines = children.sublist(start);
  final middle = lines.length ~/ 2;
  children.removeRange(start, children.length);
  for (var i = 0; i < lines.length; i++) {
    // (aligned: each line as wide as the page or column, so a right-hand
    // rail runs straight)
    final line = pw.Container(
      alignment: pw.Alignment.topLeft,
      margin: left
          ? pw.EdgeInsets.only(left: gutter / 2)
          : pw.EdgeInsets.only(right: gutter / 2),
      padding: left
          ? pw.EdgeInsets.only(left: gutter / 2)
          : pw.EdgeInsets.only(right: gutter / 2),
      decoration: pw.BoxDecoration(
        border: left ? pw.Border(left: rail) : pw.Border(right: rail),
      ),
      child: lines[i],
    );
    children.add(
      i != middle
          ? line
          : pw.Stack(
              children: [
                line,
                pw.Positioned(
                  left: left ? 0 : null,
                  right: left ? null : 0,
                  top: 0,
                  child: badge,
                ),
              ],
            ),
    );
  }
}

/// Lays a song out in [columns] newspaper-style columns: the title block
/// across the top of page 1, then each part flowing down the columns and
/// on to the next page. Parts stay together unless one is taller than a
/// whole column (then it breaks between lines).
void _addColumnPages(
  pw.Document doc, {
  required PdfPageFormat pageFormat,
  required pw.ThemeData theme,
  required int columns,
  required List<pw.Widget> header,
  required List<List<pw.Widget>> parts,
  required pw.Widget Function(int page, int pages) footerFor,
}) {
  const margin = 40.0, gap = 20.0;
  final width = pageFormat.width - margin * 2;
  final columnWidth = (width - gap * (columns - 1)) / columns;
  final ctx = pw.Context(document: doc.document).inheritFrom(theme);

  double measure(pw.Widget w, double maxWidth) {
    w.layout(ctx, pw.BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
    return w.box!.height;
  }

  pw.Widget stack(List<pw.Widget> ws) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: ws,
  );

  // Room for the footer (with a page number) on every page.
  final footerHeight = measure(footerFor(1, 2), width) + 8;
  final columnHeight = pageFormat.height - margin * 2 - footerHeight;
  final headerWidget = stack(header);
  final headerHeight = measure(headerWidget, width);

  // Parts as unbreakable blocks (too-tall ones broken into lines).
  final blocks = <(pw.Widget, double)>[];
  for (final part in parts) {
    if (part.isEmpty) continue;
    final block = stack(part);
    final h = measure(block, columnWidth);
    if (h <= columnHeight) {
      blocks.add((block, h));
    } else {
      for (final line in part) {
        blocks.add((line, measure(line, columnWidth)));
      }
    }
  }

  // Fill columns, then pages.
  final pages = <List<List<pw.Widget>>>[];
  var page = List.generate(columns, (_) => <pw.Widget>[]);
  var column = 0;
  var top = headerHeight;
  var y = top;
  for (final (block, h) in blocks) {
    if (y + h > columnHeight && y > top) {
      column++;
      y = top;
      if (column >= columns) {
        pages.add(page);
        page = List.generate(columns, (_) => <pw.Widget>[]);
        column = 0;
        top = 0;
        y = 0;
      }
    }
    page[column].add(block);
    y += h;
  }
  pages.add(page);

  for (var p = 0; p < pages.length; p++) {
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(margin),
        theme: theme,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (p == 0) headerWidget,
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) pw.SizedBox(width: gap),
                    pw.SizedBox(width: columnWidth, child: stack(pages[p][c])),
                  ],
                ],
              ),
            ),
            footerFor(p + 1, pages.length),
          ],
        ),
      ),
    );
  }
}

// ---- Setlists ----

/// A setlist's file names: "01 Title.ext", in set order, unique.
List<String> setlistFileNames(List<ExportSource> songs, String ext) {
  final width = songs.length >= 100 ? 3 : 2;
  return [
    for (var i = 0; i < songs.length; i++)
      '${'${i + 1}'.padLeft(width, '0')} ${songs[i].fileStem}.$ext',
  ];
}

/// Files in a .zip.
Uint8List zipFiles(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// The whole setlist as one text file: its name, then each song.
String exportSetlistText(
  String name,
  List<ExportSource> songs, {
  required bool includeChords,
}) {
  final rule = '=' * 40;
  return [
    name,
    rule,
    for (var i = 0; i < songs.length; i++) ...[
      '',
      '${i + 1}. ${exportText(songs[i], includeChords: includeChords).trim()}',
      '',
      if (i < songs.length - 1) '-' * 40,
    ],
  ].join('\n');
}
