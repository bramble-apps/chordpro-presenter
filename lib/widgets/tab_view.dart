import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../browser.dart';
import '../fonts.dart';
import '../tabs.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// A guitar / ukulele tab on the chord sheet. [modern]: solid strings with
/// the frets sitting on them, bar lines across (as Ultimate Guitar draws
/// them); otherwise the text as typed, in a fixed-width font. A play
/// button plays it (a plucked string per note, at the song's tempo), a
/// marker following along. Wide tabs scroll sideways.
class TabView extends StatefulWidget {
  final List<String> lines;
  final bool modern;
  final TextStyle style;
  final Color ink;
  final Color accent;
  final int bpm;
  final int capo;

  const TabView({
    super.key,
    required this.lines,
    required this.modern,
    required this.style,
    required this.ink,
    required this.accent,
    this.bpm = 90,
    this.capo = 0,
  });

  @override
  State<TabView> createState() => _TabViewState();
}

class _TabViewState extends State<TabView> with SingleTickerProviderStateMixin {
  late TabBlock _block = parseTab(widget.lines);
  late final Ticker _ticker = createTicker(_tick);

  /// While playing: which system, and the column sounding now.
  int? _playing;
  double _column = -1;
  int _firstColumn = 0;

  @override
  void didUpdateWidget(TabView old) {
    super.didUpdateWidget(old);
    if (old.lines.join('\n') != widget.lines.join('\n')) {
      _block = parseTab(widget.lines);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _play(int index, TabSystem system) {
    final (samples, _) = renderTab(system, bpm: widget.bpm, capo: widget.capo);
    playSound(samples, tabSampleRate);
    final played = system.notes.where((n) => n.fret >= 0);
    _firstColumn = played.isEmpty ? 0 : played.first.column;
    setState(() {
      _playing = index;
      _column = _firstColumn.toDouble();
    });
    _ticker
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final system = _block.systems.elementAt(_playing!);
    final step = tabColumnSeconds(widget.bpm);
    // (Real time: animations may be sped up, see setEink.)
    final col =
        _firstColumn + elapsed.inMicroseconds * timeDilation / 1e6 / step;
    final end = system.notes.isEmpty ? 0 : system.notes.last.column + 2;
    if (col > end) {
      _ticker.stop();
      setState(() {
        _playing = null;
        _column = -1;
      });
      return;
    }
    setState(() => _column = col);
  }

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: FontOption('cousine', '').family,
      fontFamilyFallback: const ['monospace'],
      fontSize: (widget.style.fontSize ?? 16) * 0.9,
      color: widget.ink,
      height: 1.25,
    );
    var systemIndex = 0;
    final children = <Widget>[];
    for (final part in _block.parts) {
      if (part is String) {
        children.add(Text(part, style: mono));
        continue;
      }
      final system = part as TabSystem;
      final i = systemIndex++;
      final playing = _playing == i;
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: widget.modern
                    ? _ModernTab(
                        system: system,
                        style: mono,
                        ink: widget.ink,
                        accent: widget.accent,
                        column: playing ? _column : null,
                      )
                    : _ClassicTab(
                        system: system,
                        style: mono,
                        accent: widget.accent,
                        column: playing ? _column : null,
                      ),
              ),
            ),
            IconButton(
              tooltip: playing ? 'Playing…' : 'Play this tab',
              visualDensity: VisualDensity.compact,
              color: widget.accent,
              icon: Icon(
                playing ? BrambleIcons.waveform : BrambleIcons.tbPlayerPlay,
              ),
              onPressed: system.notes.any((n) => n.fret >= 0)
                  ? () => _play(i, system)
                  : null,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: children,
      ),
    );
  }
}

/// The tab as typed (fixed-width), the column playing tinted.
class _ClassicTab extends StatelessWidget {
  final TabSystem system;
  final TextStyle style;
  final Color accent;
  final double? column;
  const _ClassicTab({
    required this.system,
    required this.style,
    required this.accent,
    this.column,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidth = system.strings.fold(
      0,
      (w, s) => math.max(w, s.label.length),
    );
    final text = [
      for (final s in system.strings)
        '${s.label.padRight(labelWidth)}|${s.body}',
    ].join('\n');
    final charW = _charWidth(style);
    return Stack(
      children: [
        if (column != null)
          Positioned(
            left: (labelWidth + 1 + column!.floorToDouble()) * charW,
            top: 0,
            bottom: 0,
            width: charW * 1.5,
            child: ColoredBox(color: accent.withValues(alpha: 0.18)),
          ),
        Text(text, style: style, softWrap: false),
      ],
    );
  }
}

double _charWidth(TextStyle style) {
  final p = TextPainter(
    text: TextSpan(text: '0000000000', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = p.width / 10;
  p.dispose();
  return w;
}

/// Solid strings, the frets drawn on them, bar lines across.
class _ModernTab extends StatelessWidget {
  final TabSystem system;
  final TextStyle style;
  final Color ink;
  final Color accent;
  final double? column;
  const _ModernTab({
    required this.system,
    required this.style,
    required this.ink,
    required this.accent,
    this.column,
  });

  @override
  Widget build(BuildContext context) {
    final charW = _charWidth(style);
    final size = style.fontSize ?? 14;
    final row = size * 1.45;
    final labelW = size * 1.6;
    final width = labelW + (system.columns + 1) * charW;
    final height = row * system.strings.length;
    return CustomPaint(
      size: Size(width, height),
      painter: _ModernTabPainter(
        system: system,
        style: style,
        ink: ink,
        accent: accent,
        charW: charW,
        row: row,
        labelW: labelW,
        column: column,
      ),
    );
  }
}

class _ModernTabPainter extends CustomPainter {
  final TabSystem system;
  final TextStyle style;
  final Color ink, accent;
  final double charW, row, labelW;
  final double? column;
  const _ModernTabPainter({
    required this.system,
    required this.style,
    required this.ink,
    required this.accent,
    required this.charW,
    required this.row,
    required this.labelW,
    this.column,
  });

  double _x(num col) => labelW + col * charW;
  double _y(int string) => row * (string + 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final n = system.strings.length;
    final right = _x(system.columns);
    final line = Paint()
      ..color = ink.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    // The column playing now.
    if (column != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_x(column!) - charW * 0.2, 0, charW * 1.4, size.height),
          Radius.circular(inkR(charW * 0.4)),
        ),
        Paint()..color = accent.withValues(alpha: 0.18),
      );
    }
    // What's written on each string: frets (and x) bold, techniques
    // (h, p, b, /…) small; the string is drawn around them.
    final noteStyle = style.copyWith(color: ink, fontWeight: FontWeight.w700);
    final markStyle = style.copyWith(
      color: ink.withValues(alpha: 0.65),
      fontSize: (style.fontSize ?? 14) * 0.8,
      fontStyle: FontStyle.italic,
    );
    final labelStyle = style.copyWith(
      color: ink.withValues(alpha: 0.6),
      fontSize: (style.fontSize ?? 14) * 0.8,
      fontWeight: FontWeight.w600,
    );
    final left = labelW - charW * 0.3;
    for (var s = 0; s < n; s++) {
      final body = system.strings[s].body;
      final marks = <(TextPainter, double)>[];
      for (final m in RegExp(r'\d+|[xX]|[^\d\s|-]').allMatches(body)) {
        final t = m.group(0)!;
        final digits = RegExp(r'^\d+$|^[xX]$').hasMatch(t);
        final here =
            column != null && digits && (column! - m.start).abs() < 0.8;
        final tp = TextPainter(
          text: TextSpan(
            text: t,
            style: digits
                ? noteStyle.copyWith(color: here ? accent : ink)
                : markStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        marks.add((tp, _x(m.start) + charW * t.length / 2));
      }
      // The string, broken where something is written on it.
      var x = left;
      for (final (tp, cx) in marks) {
        final gapL = cx - tp.width / 2 - charW * 0.15;
        if (gapL > x) {
          canvas.drawLine(Offset(x, _y(s)), Offset(gapL, _y(s)), line);
        }
        x = math.max(x, cx + tp.width / 2 + charW * 0.15);
      }
      if (x < right) {
        canvas.drawLine(Offset(x, _y(s)), Offset(right, _y(s)), line);
      }
      for (final (tp, cx) in marks) {
        tp.paint(canvas, Offset(cx - tp.width / 2, _y(s) - tp.height / 2));
        tp.dispose();
      }
      final label = system.strings[s].label;
      if (label.isNotEmpty) {
        _text(canvas, label, Offset(labelW * 0.35, _y(s)), labelStyle);
      }
    }
    // The start and bar lines.
    final bar = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(left, _y(0)), Offset(left, _y(n - 1)), bar);
    for (final c in system.bars) {
      final bx = _x(c) + charW / 2;
      canvas.drawLine(Offset(bx, _y(0)), Offset(bx, _y(n - 1)), bar);
    }
  }

  void _text(Canvas canvas, String t, Offset center, TextStyle st) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: st),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_ModernTabPainter old) =>
      old.system != system ||
      old.column != column ||
      old.ink != ink ||
      old.accent != accent ||
      old.style != style;
}
