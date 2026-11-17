// The read score drawn as clean notation (the "Notes" view, and the PDF
// export): measures spaced by their notes, packed into lines across the
// width, symbols from Bravura (glyphs.dart).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'score.dart';
import 'shapes.dart';

final _pathCache = <String, Path>{};

/// Glyph [name] as a path, 1 unit = 1 staff space, y down, origin on its
/// baseline.
Path glyphPath(String name) => _pathCache.putIfAbsent(name, () {
  final p = Path()..fillType = PathFillType.nonZero;
  for (final poly in pathPolygons(glyphs[name]!.path, steps: 6)) {
    p.addPolygon([for (final (x, y) in poly) Offset(x / 250, -y / 250)], true);
  }
  return p;
});

/// Where a note was drawn (for tapping it, highlighting it).
class DrawnNote {
  final int note;
  final Rect rect;
  const DrawnNote(this.note, this.rect);
}

class _Col {
  final double onset;
  double x = 0, width = 0;
  _Col(this.onset);
}

class _Bar {
  final int index;
  final List<_Col> cols;
  double width;
  double x = 0;
  _Bar(this.index, this.cols, this.width);
}

/// The score laid out at a width: lines of measures and where every note
/// is.
class ScoreLayout {
  final Score score;
  final double width, space;
  final lines = <List<_Bar>>[];
  final drawn = <DrawnNote>[];
  final measureRects = <int, Rect>{};
  late final double height;
  late final double staffGap, lineHeight, top;

  ScoreLayout(this.score, this.width, {this.space = 8}) {
    final sp = space;
    staffGap = sp * 10;
    lineHeight = sp * 4 + (score.staves - 1) * staffGap + sp * 9;
    top = sp * 5;
    final byMeasure = <int, List<ScoreNote>>{};
    for (final n in score.notes) {
      byMeasure.putIfAbsent(n.measure, () => []).add(n);
    }
    // Each measure: a column per moment something starts, wider for
    // longer gaps (like engravers do).
    final bars = <_Bar>[];
    for (final (mi, m) in score.measures.indexed) {
      final ns = byMeasure[mi] ?? const <ScoreNote>[];
      final onsets = {for (final n in ns) (n.onset * 96).round() / 96}.toList()
        ..sort();
      if (onsets.isEmpty) onsets.add(m.onset);
      final cols = [for (final o in onsets) _Col(o)];
      var x = sp * 1.5;
      for (var i = 0; i < cols.length; i++) {
        final next = i + 1 < cols.length
            ? cols[i + 1].onset
            : m.onset + m.length;
        final gap = math.max(0.125, next - cols[i].onset);
        final acc = ns.any(
          (n) => (n.onset - cols[i].onset).abs() < 0.01 && n.accidental != null,
        );
        if (acc) x += sp * 1.2;
        cols[i].x = x;
        cols[i].width = sp * (2.4 + 2.6 * math.sqrt(gap));
        x += cols[i].width;
      }
      bars.add(_Bar(mi, cols, x + sp * 0.5));
    }
    // Lines: as many measures as fit; then stretched to the width.
    final head = _headWidth(true);
    final headLater = _headWidth(false);
    var cur = <_Bar>[];
    var used = head;
    for (final b in bars) {
      final room = width - sp * 2;
      if (cur.isNotEmpty && used + b.width > room) {
        lines.add(cur);
        cur = [];
        used = headLater;
      }
      cur.add(b);
      used += b.width;
    }
    if (cur.isNotEmpty) lines.add(cur);
    for (final (li, line) in lines.indexed) {
      final start = sp + (li == 0 ? head : headLater);
      final natural = line.fold(0.0, (w, b) => w + b.width);
      final room = width - sp - start;
      // The last line isn't stretched much.
      final stretch = li == lines.length - 1 && natural < room * 0.7
          ? 1.0
          : room / natural;
      var x = start;
      for (final b in line) {
        b.x = x;
        for (final c in b.cols) {
          c.x *= stretch;
          c.width *= stretch;
        }
        b.width *= stretch;
        x += b.width;
      }
    }
    height = top + lines.length * lineHeight + sp * 2;
  }

  double _headWidth(bool first) {
    final sp = space;
    var w = sp * 3.6 + score.fifths.abs() * sp * 1.0;
    if (first) w += sp * 2.4;
    return w + sp;
  }

  double staffTop(int line, int staff) =>
      top + line * lineHeight + staff * staffGap;

  /// y of [diatonic] on [staff]'s lines in [line].
  double noteY(int line, int staff, int diatonic) {
    final clef = score.clefs[math.min(staff, score.clefs.length - 1)];
    return staffTop(line, staff) + (clef.topLine - diatonic) * space / 2;
  }

  /// The note tapped at [p], if any.
  int? noteAt(Offset p) {
    for (final d in drawn) {
      if (d.rect.inflate(space * 0.4).contains(p)) return d.note;
    }
    return null;
  }

  int? measureAt(Offset p) {
    for (final e in measureRects.entries) {
      if (e.value.contains(p)) return e.key;
    }
    return null;
  }
}

/// Draws [layout] (and works out where every note went).
class ScorePainter extends CustomPainter {
  final ScoreLayout layout;
  final Color ink, accent;

  /// Notes to colour (playing, chosen).
  final Set<int> lit;
  final int? selected;

  ScorePainter(
    this.layout, {
    required this.ink,
    required this.accent,
    this.lit = const {},
    this.selected,
  });

  Score get score => layout.score;
  double get sp => layout.space;

  void _glyph(
    Canvas c,
    String name,
    double x,
    double y,
    Color color, [
    double scale = 1,
  ]) {
    c.save();
    c.translate(x, y);
    c.scale(sp * scale);
    c.drawPath(glyphPath(name), Paint()..color = color);
    c.restore();
  }

  double _glyphW(String name) => glyphs[name]!.w / 250 * sp;

  @override
  void paint(Canvas canvas, Size size) {
    layout.drawn.clear();
    layout.measureRects.clear();
    final line = Paint()
      ..color = ink.withValues(alpha: 0.75)
      ..strokeWidth = math.max(1, sp * 0.12);
    final byMeasure = <int, List<int>>{};
    for (final (i, n) in score.notes.indexed) {
      byMeasure.putIfAbsent(n.measure, () => []).add(i);
    }
    for (final (li, bars) in layout.lines.indexed) {
      final left = sp;
      final right = bars.last.x + bars.last.width;
      for (var st = 0; st < score.staves; st++) {
        final top = layout.staffTop(li, st);
        for (var k = 0; k < 5; k++) {
          canvas.drawLine(
            Offset(left, top + k * sp),
            Offset(right, top + k * sp),
            line,
          );
        }
        // Clef, key, time.
        final clef = score.clefs[math.min(st, score.clefs.length - 1)];
        final (gName, gLine) = switch (clef) {
          Clef.treble => ('gClef', 3),
          Clef.bass => ('fClef', 1),
          Clef.alto => ('cClef', 2),
          Clef.tenor => ('cClef', 1),
        };
        _glyph(canvas, gName, left + sp * 0.6, top + gLine * sp, ink);
        var x = left + sp * 3.6;
        final sharpsAt = [0, 3, -1, 2, 5, 1, 4]; // F C G D A E B, treble
        final flatsAt = [4, 1, 5, 2, 6, 3, 7];
        final clefShift = switch (clef) {
          Clef.treble => 0,
          Clef.bass => 2,
          Clef.alto => 1,
          Clef.tenor => -1,
        };
        for (var k = 0; k < score.fifths.abs(); k++) {
          final pos = (score.fifths > 0 ? sharpsAt[k] : flatsAt[k]) + clefShift;
          _glyph(
            canvas,
            score.fifths > 0 ? 'sharp' : 'flat',
            x,
            top + pos * sp / 2,
            ink,
          );
          x += sp * 1.0;
        }
        if (li == 0) {
          x += sp * 0.4;
          for (final (num, y) in [
            (score.beats, top + sp),
            (score.beatType, top + sp * 3),
          ]) {
            var dx = x;
            for (final d in '$num'.split('')) {
              _glyph(canvas, 'timeSig$d', dx, y, ink);
              dx += _glyphW('timeSig$d');
            }
          }
        }
      }
      // Bar lines (across the staves of the line).
      final top0 = layout.staffTop(li, 0);
      final bot = layout.staffTop(li, score.staves - 1) + sp * 4;
      canvas.drawLine(Offset(left, top0), Offset(left, bot), line);
      if (li == 0 || true) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${bars.first.index + 1}',
            style: TextStyle(
              color: ink.withValues(alpha: 0.6),
              fontSize: sp * 1.3,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (bars.first.index > 0) tp.paint(canvas, Offset(left, top0 - sp * 3));
        tp.dispose();
      }
      for (final b in bars) {
        final m = score.measures[b.index];
        final bx = b.x + b.width;
        canvas.drawLine(Offset(bx, top0), Offset(bx, bot), line);
        if (m.repeatEnd) {
          canvas.drawRect(
            Rect.fromLTRB(bx - sp * 0.1, top0, bx + sp * 0.4, bot),
            Paint()..color = ink,
          );
          for (var st = 0; st < score.staves; st++) {
            final t = layout.staffTop(li, st);
            for (final yy in [t + sp * 1.5, t + sp * 2.5]) {
              canvas.drawCircle(
                Offset(bx - sp * 0.8, yy),
                sp * 0.22,
                Paint()..color = ink,
              );
            }
          }
        }
        if (m.repeatStart) {
          canvas.drawRect(
            Rect.fromLTRB(b.x - sp * 0.4, top0, b.x + sp * 0.1, bot),
            Paint()..color = ink,
          );
          for (var st = 0; st < score.staves; st++) {
            final t = layout.staffTop(li, st);
            for (final yy in [t + sp * 1.5, t + sp * 2.5]) {
              canvas.drawCircle(
                Offset(b.x + sp * 0.8, yy),
                sp * 0.22,
                Paint()..color = ink,
              );
            }
          }
        }
        layout.measureRects[b.index] = Rect.fromLTRB(
          b.x,
          top0 - sp * 2,
          bx,
          bot + sp * 2,
        );
        _measureNotes(canvas, li, b, byMeasure[b.index] ?? const []);
      }
    }
  }

  void _measureNotes(Canvas canvas, int li, _Bar b, List<int> ids) {
    double colX(double onset) {
      for (final c in b.cols) {
        if ((c.onset - onset).abs() < 0.011) return b.x + c.x;
      }
      return b.x + b.cols.first.x;
    }

    // Chords: notes of one staff and voice at one time.
    final groups = <(int, int, double), List<int>>{};
    for (final i in ids) {
      final n = score.notes[i];
      groups
          .putIfAbsent((
            n.staff,
            n.voice,
            (n.onset * 96).round() / 96,
          ), () => [])
          .add(i);
    }
    final ledger = Paint()
      ..color = ink.withValues(alpha: 0.8)
      ..strokeWidth = math.max(1, sp * 0.14);
    for (final e in groups.entries) {
      final (st, voice, onset) = e.key;
      final x = colX(onset);
      final top = layout.staffTop(li, st);
      final notes = [for (final i in e.value) score.notes[i]];
      if (notes.first.rest) {
        final n = notes.first;
        final i = e.value.first;
        final name = switch (n.type) {
          'whole' => 'restWhole',
          'half' => 'restHalf',
          'quarter' => 'restQuarter',
          'eighth' => 'rest8th',
          '16th' => 'rest16th',
          _ => 'rest32nd',
        };
        final y =
            top +
            sp * (n.type == 'whole' ? 1 : 2) +
            (voice == 2 ? sp * 2 : (notes.length > 1 ? 0 : 0));
        final color = _color(i);
        _glyph(canvas, name, x, y, color);
        final w = _glyphW(name);
        for (var d = 0; d < n.dots; d++) {
          canvas.drawCircle(
            Offset(x + w + sp * (0.5 + d * 0.5), top + sp * 1.5),
            sp * 0.18,
            Paint()..color = color,
          );
        }
        layout.drawn.add(
          DrawnNote(i, Rect.fromLTWH(x, y - sp * 1.5, w, sp * 3)),
        );
        continue;
      }
      // Stem direction: away from the middle (voice 2 down, voice 1 up when
      // two voices).
      final ys = [for (final n in notes) layout.noteY(li, st, n.diatonic)];
      final mid = top + sp * 2;
      final avg = ys.reduce((a, b) => a + b) / ys.length;
      final hasTwo = ids.any(
        (j) => score.notes[j].staff == st && score.notes[j].voice == 2,
      );
      final up = hasTwo ? voice == 1 : avg > mid;
      final type = notes.first.type;
      final headName = switch (type) {
        'whole' => 'noteheadWhole',
        'half' => 'noteheadHalf',
        _ => 'noteheadBlack',
      };
      final hw = _glyphW(headName);
      for (final (k, n) in notes.indexed) {
        final i = e.value[k];
        final y = ys[k];
        final color = _color(i);
        // Ledger lines.
        for (var ly = top - sp; ly >= y - sp * 0.1; ly -= sp) {
          canvas.drawLine(
            Offset(x - sp * 0.4, ly),
            Offset(x + hw + sp * 0.4, ly),
            ledger,
          );
        }
        for (var ly = top + sp * 5; ly <= y + sp * 0.1; ly += sp) {
          canvas.drawLine(
            Offset(x - sp * 0.4, ly),
            Offset(x + hw + sp * 0.4, ly),
            ledger,
          );
        }
        _glyph(canvas, headName, x, y, color);
        if (n.accidental != null) {
          final acc = switch (n.accidental!) {
            1 => 'sharp',
            -1 => 'flat',
            2 => 'doubleSharp',
            -2 => 'doubleFlat',
            _ => 'natural',
          };
          _glyph(canvas, acc, x - _glyphW(acc) - sp * 0.25, y, color);
        }
        for (var d = 0; d < n.dots; d++) {
          final onLine =
              ((y - top) / sp - ((y - top) / sp).round()).abs() < 0.1;
          canvas.drawCircle(
            Offset(x + hw + sp * (0.45 + d * 0.5), onLine ? y - sp * 0.5 : y),
            sp * 0.18,
            Paint()..color = color,
          );
        }
        if (n.tie) {
          final path = Path()
            ..moveTo(x + hw * 0.8, y + (up ? sp * 0.6 : -sp * 0.6))
            ..quadraticBezierTo(
              x + hw + sp * 1.5,
              y + (up ? sp * 1.4 : -sp * 1.4),
              x + hw + sp * 3,
              y + (up ? sp * 0.6 : -sp * 0.6),
            );
          canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = sp * 0.15,
          );
        }
        layout.drawn.add(DrawnNote(i, Rect.fromLTWH(x, y - sp * 0.5, hw, sp)));
      }
      if (type == 'whole') continue;
      // Stem and flags.
      final hiY = ys.reduce(math.min), loY = ys.reduce(math.max);
      final color = e.value.any(lit.contains) ? accent : ink;
      final stemX = up ? x + hw - sp * 0.06 : x + sp * 0.06;
      final flags = switch (type) {
        'eighth' => 1,
        '16th' => 2,
        '32nd' => 3,
        _ => 0,
      };
      final len = sp * (3.5 + math.max(0, flags - 1) * 0.75);
      final tip = up ? math.min(hiY - len, mid) : math.max(loY + len, mid);
      canvas.drawLine(
        Offset(stemX, up ? loY - sp * 0.2 : hiY + sp * 0.2),
        Offset(stemX, tip),
        Paint()
          ..color = color
          ..strokeWidth = sp * 0.13,
      );
      if (flags > 0) {
        final name = switch (flags) {
          1 => up ? 'flag8thUp' : 'flag8thDown',
          2 => up ? 'flag16thUp' : 'flag16thDown',
          _ => up ? 'flag32ndUp' : 'flag32ndDown',
        };
        _glyph(canvas, name, stemX - sp * 0.06, tip, color);
      }
      if (notes.first.triplet) {
        final tp = TextPainter(
          text: TextSpan(
            text: '3',
            style: TextStyle(
              color: color,
              fontSize: sp * 1.2,
              fontStyle: FontStyle.italic,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(stemX - tp.width / 2, up ? tip - sp * 1.8 : tip + sp * 0.3),
        );
        tp.dispose();
      }
    }
  }

  Color _color(int i) => i == selected
      ? Colors.orange
      : lit.contains(i)
      ? accent
      : ink;

  @override
  bool shouldRepaint(ScorePainter old) => true;
}

/// [layout] drawn into a picture (for PDF pages): a slice of its height.
Future<ui.Image> renderLayout(
  ScoreLayout layout,
  double from,
  double height,
  double scale,
) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas
    ..scale(scale)
    ..drawRect(
      Rect.fromLTWH(0, 0, layout.width, height),
      Paint()..color = Colors.white,
    )
    ..translate(0, -from);
  ScorePainter(
    layout,
    ink: Colors.black,
    accent: Colors.black,
  ).paint(canvas, Size(layout.width, layout.height));
  return rec.endRecording().toImage(
    (layout.width * scale).ceil(),
    (height * scale).ceil(),
  );
}
