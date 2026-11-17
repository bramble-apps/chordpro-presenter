import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chord_db.dart';

/// One chord diagram with its name above: a fretboard box (guitar,
/// ukulele) or two octaves of keys (piano). [shape] null: the name over an
/// empty box (no shape known).
class ChordDiagram extends StatelessWidget {
  final String name;
  final ChordShape? shape;
  final Instrument instrument;
  final bool showFingers;

  /// Scale (1 = about 70 × 90 for a fretboard).
  final double zoom;

  /// The shape in use (a gold border), in the Chord Diagrams sheet.
  final bool selected;

  /// The name above the diagram (off where it's already shown nearby).
  final bool showName;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChordDiagram({
    super.key,
    required this.name,
    required this.shape,
    required this.instrument,
    this.showFingers = true,
    this.zoom = 1,
    this.selected = false,
    this.showName = true,
    this.onTap,
    this.onLongPress,
  });

  static const gold = Color(0xFFE0B03A);

  /// Its size (without the border's padding).
  static Size sizeOf(Instrument i, double zoom) => i == Instrument.piano
      ? Size(132 * zoom, 84 * zoom)
      : Size(72 * zoom, 96 * zoom);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final full = sizeOf(instrument, zoom);
    final size = showName ? full : Size(full.width, full.height - 18 * zoom);
    final ink = scheme.onSurface;
    final body = SizedBox.fromSize(
      size: size,
      child: Column(
        children: [
          if (showName)
            SizedBox(
              height: 18 * zoom,
              child: FittedBox(
                child: Text(
                  name,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14 * zoom,
                    color: ink,
                  ),
                ),
              ),
            ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: instrument == Instrument.piano
                  ? _PianoPainter(
                      keys: shape?.keys ?? const [],
                      ink: ink,
                      paper: scheme.surface,
                      lit: gold,
                    )
                  : _FretPainter(
                      shape: shape,
                      strings: stringTuning[instrument]!.length,
                      showFingers: showFingers,
                      ink: ink,
                      paper: scheme.surface,
                      zoom: zoom,
                    ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Chord $name',
      button: onTap != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(10 * zoom),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: EdgeInsets.all(6 * zoom),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10 * zoom),
            border: Border.all(
              color: selected ? gold : Colors.transparent,
              width: 2,
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// A fretboard box: strings down, five frets across, × / ○ above, dots
/// (finger numbers inside), barres as pills, the nut or the first fret's
/// number.
class _FretPainter extends CustomPainter {
  final ChordShape? shape;
  final int strings;
  final bool showFingers;
  final Color ink;
  final Color paper;
  final double zoom;

  const _FretPainter({
    required this.shape,
    required this.strings,
    required this.showFingers,
    required this.ink,
    required this.paper,
    required this.zoom,
  });

  static const _frets = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final top = 12 * zoom; // room for × / ○
    final left = 6 * zoom;
    final right = 14 * zoom; // room for the fret number
    final w = size.width - left - right;
    final h = size.height - top - 2 * zoom;
    final dx = w / (strings - 1);
    final dy = h / _frets;
    final line = Paint()
      ..color = ink.withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, zoom);
    for (var i = 0; i < strings; i++) {
      final x = left + i * dx;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), line);
    }
    for (var f = 0; f <= _frets; f++) {
      final y = top + f * dy;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), line);
    }
    final s = shape;
    final base = s?.baseFret ?? 1;
    if (base <= 1) {
      // The nut.
      canvas.drawRect(
        Rect.fromLTWH(left - zoom, top - 3 * zoom, w + 2 * zoom, 3.5 * zoom),
        Paint()..color = ink,
      );
    } else {
      _text(
        canvas,
        '$base',
        Offset(left + w + 3 * zoom, top + dy / 2),
        9 * zoom,
        ink,
        alignLeft: true,
      );
    }
    if (s == null) {
      _text(canvas, '?', Offset(left + w / 2, top + h / 2), 16 * zoom, ink);
      return;
    }
    final dot = Paint()..color = ink;
    final r = math.min(dx, dy) * 0.36;
    // Barres: from the first to the last string at that fret.
    final barred = <int>{};
    for (final b in s.barres) {
      final on = [
        for (var i = 0; i < s.frets.length; i++)
          if (s.frets[i] == b) i,
      ];
      if (on.length < 2) continue;
      final from = on.first, to = on.last;
      final y = top + (b - 0.5) * dy;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left + from * dx - r,
          y - r,
          left + to * dx + r,
          y + r,
          Radius.circular(r),
        ),
        dot,
      );
      for (var i = from; i <= to; i++) {
        if (s.frets[i] == b) barred.add(i);
      }
      final finger = s.fingers.length > from ? s.fingers[from] : 0;
      if (showFingers && finger > 0) {
        _text(
          canvas,
          '$finger',
          Offset(left + (from + to) / 2 * dx, y),
          r * 1.3,
          paper,
        );
      }
    }
    for (var i = 0; i < s.frets.length && i < strings; i++) {
      final f = s.frets[i];
      final x = left + i * dx;
      if (f < 0) {
        _text(canvas, '×', Offset(x, top - 7 * zoom), 10 * zoom, ink);
      } else if (f == 0) {
        canvas.drawCircle(
          Offset(x, top - 7 * zoom),
          2.8 * zoom,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, zoom),
        );
      } else if (!barred.contains(i)) {
        final c = Offset(x, top + (f - 0.5) * dy);
        canvas.drawCircle(c, r, dot);
        final finger = s.fingers.length > i ? s.fingers[i] : 0;
        if (showFingers && finger > 0) {
          _text(canvas, '$finger', c, r * 1.3, paper);
        }
      }
    }
  }

  void _text(
    Canvas canvas,
    String t,
    Offset at,
    double size,
    Color color, {
    bool alignLeft = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(alignLeft ? at.dx : at.dx - tp.width / 2, at.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FretPainter old) =>
      old.shape != shape ||
      old.showFingers != showFingers ||
      old.ink != ink ||
      old.zoom != zoom;
}

/// Two octaves of keys from C3; the chord's keys lit.
class _PianoPainter extends CustomPainter {
  final List<int> keys;
  final Color ink;
  final Color paper;
  final Color lit;

  const _PianoPainter({
    required this.keys,
    required this.ink,
    required this.paper,
    required this.lit,
  });

  static const _c3 = 48;
  static const _whites = [0, 2, 4, 5, 7, 9, 11];

  @override
  void paint(Canvas canvas, Size size) {
    final whiteW = size.width / 14;
    final h = size.height;
    final on = keys.toSet();
    final edge = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 14; i++) {
      final note = _c3 + (i ~/ 7) * 12 + _whites[i % 7];
      final r = Rect.fromLTWH(i * whiteW, 0, whiteW, h);
      canvas.drawRect(
        r,
        Paint()..color = on.contains(note) ? lit : Colors.white,
      );
      canvas.drawRect(r, edge);
    }
    // Black keys over the gaps (not after E or B).
    for (var i = 0; i < 14; i++) {
      final degree = _whites[i % 7];
      if (degree == 4 || degree == 11) continue;
      final note = _c3 + (i ~/ 7) * 12 + degree + 1;
      final r = Rect.fromLTWH(
        (i + 1) * whiteW - whiteW * 0.3,
        0,
        whiteW * 0.6,
        h * 0.6,
      );
      canvas.drawRect(
        r,
        Paint()..color = on.contains(note) ? lit : const Color(0xFF1E1E1E),
      );
      canvas.drawRect(r, edge);
    }
  }

  @override
  bool shouldRepaint(_PianoPainter old) =>
      old.keys != keys || old.ink != ink || old.lit != lit;
}
