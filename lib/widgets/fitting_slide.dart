import 'package:flutter/material.dart';

import '../bidi.dart';
import '../chordpro.dart';
import '../format.dart';

/// Lyrics on the projector: as large as [maxFontSize] allows while still
/// fitting the space, with a fade between slides. In song mode ([allSlides]
/// set) every part is shown and the current one is highlighted.
class FittingSlide extends StatelessWidget {
  final String text;
  final double maxFontSize;
  final double transitionSeconds;
  final double padding;
  final String? fontFamily;
  final Color color;
  final bool bold;
  final bool italic;
  final bool caps;
  final bool shadow;
  final TextAlign align;
  final Alignment position;

  /// Song mode: all slides, with [current] highlighted.
  final List<String>? allSlides;
  final int current;

  /// How linked pieces of a slide (a verse's translation…) look; null
  /// shows them as ordinary lines.
  final LinkedStyle? linked;

  /// Line height, as a multiple of the font size.
  final double lineHeight;

  const FittingSlide({
    super.key,
    required this.text,
    this.maxFontSize = 110,
    required this.transitionSeconds,
    this.padding = 48,
    this.fontFamily,
    this.color = Colors.white,
    this.bold = true,
    this.italic = false,
    this.caps = false,
    this.shadow = false,
    this.align = TextAlign.center,
    this.position = Alignment.center,
    this.allSlides,
    this.current = 0,
    this.linked,
    this.lineHeight = 1.2,
  });

  /// Remembered sizes, so revisiting a slide (or the preview and projector
  /// showing the same slide) doesn't measure again.
  static final Map<String, double> _cache = {};

  /// Largest size from [max] down (2-pixel steps, binary search) whose
  /// wrapped height fits.
  static double fittedFontSize(
    String text,
    double maxWidth,
    double maxHeight,
    double max,
    TextStyle style,
  ) {
    final key =
        '${maxWidth.round()}x${maxHeight.round()}|${max.round()}|'
        '${style.fontFamily}|${style.fontWeight}|${style.fontStyle}|'
        '${style.height}|$text';
    final cached = _cache[key];
    if (cached != null) return cached;

    final minSize = (max * 0.15).clamp(8.0, max);
    const step = 2.0;
    final steps = ((max - minSize) / step).floor();
    final painter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    bool fits(double size) {
      painter.text = TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      );
      painter.layout(maxWidth: maxWidth);
      return painter.height <= maxHeight;
    }

    var lo = 0, hi = steps, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (fits(minSize + mid * step)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    painter.dispose();
    final size = minSize + best * step;
    if (_cache.length > 400) _cache.clear();
    _cache[key] = size;
    return size;
  }

  /// Largest size whose linked pieces all fit: stacked (heights add up)
  /// or side by side (each in its own column).
  static double fittedLinkedSize(
    List<String> pieces,
    double maxWidth,
    double maxHeight,
    double max,
    TextStyle style,
    TextStyle Function(double size) linkedStyle,
    bool sideBySide,
  ) {
    final key =
        '${maxWidth.round()}x${maxHeight.round()}|${max.round()}|'
        '${style.fontFamily}|${style.fontWeight}|${style.fontStyle}|'
        '${style.height}|${linkedStyle(100)}|$sideBySide|${pieces.join('|')}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final minSize = (max * 0.15).clamp(8.0, max);
    const step = 2.0;
    final steps = ((max - minSize) / step).floor();
    final painter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    double height(String text, TextStyle st, double width) {
      painter.text = TextSpan(text: text, style: st);
      painter.layout(maxWidth: width);
      return painter.height;
    }

    bool fits(double size) {
      final main = style.copyWith(fontSize: size);
      final other = linkedStyle(size);
      if (sideBySide) {
        final gap = size * 0.8;
        final w = (maxWidth - gap * (pieces.length - 1)) / pieces.length;
        if (w < 20) return false;
        for (var i = 0; i < pieces.length; i++) {
          if (height(pieces[i], i == 0 ? main : other, w) > maxHeight) {
            return false;
          }
        }
        return true;
      }
      var total = height(pieces[0], main, maxWidth);
      for (final p in pieces.skip(1)) {
        total += size * 0.5 + height(p, other, maxWidth);
      }
      return total <= maxHeight;
    }

    var lo = 0, hi = steps, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (fits(minSize + mid * step)) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    painter.dispose();
    final size = minSize + best * step;
    if (_cache.length > 400) _cache.clear();
    _cache[key] = size;
    return size;
  }

  @override
  Widget build(BuildContext context) {
    String prep(String s) {
      final clean = ChordPro.stripArtifacts(s);
      return caps ? clean.toUpperCase() : clean;
    }

    // Linked pieces: laid out with their own look (or as plain lines).
    final pieces = allSlides == null && text.contains(linkSeparator)
        ? [
            for (final p in text.split(linkSeparator))
              if (p.trim().isNotEmpty) prep(p),
          ]
        : null;
    if (pieces != null && linked != null && pieces.length > 1) {
      return _linkedSlide(pieces, linked!);
    }

    final slides = allSlides
        ?.map((s) => prep(s.replaceAll(linkSeparator, '\n')))
        .toList();
    final plain =
        slides?.join('\n\n') ??
        (pieces != null ? pieces.join('\n\n') : prep(text));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.9 - 2 * padding).clamp(
          10.0,
          double.infinity,
        );
        final height = (constraints.maxHeight - 2 * padding).clamp(
          10.0,
          double.infinity,
        );
        final style = TextStyle(
          color: color,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          height: lineHeight,
          shadows: shadow
              ? [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: maxFontSize * 0.08,
                    offset: Offset(0, maxFontSize * 0.03),
                  ),
                ]
              : null,
        );
        final size = fittedFontSize(plain, width, height, maxFontSize, style);
        final sized = style.copyWith(fontSize: size);

        final Widget textWidget = slides == null
            ? Text(
                plain,
                textAlign: align,
                style: sized,
                textDirection: directionOf(plain),
              )
            : Text.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      TextSpan(
                        text: i < slides.length - 1
                            ? '${slides[i]}\n\n'
                            : slides[i],
                        style: i == current
                            ? null
                            : TextStyle(color: color.withValues(alpha: 0.35)),
                      ),
                  ],
                ),
                textAlign: align,
                style: sized,
              );

        return RepaintBoundary(
          child: AnimatedSwitcher(
            duration: Duration(
              milliseconds: (transitionSeconds * 1000).round(),
            ),
            child: Align(
              key: ValueKey(slides == null ? plain : current),
              alignment: position,
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: SizedBox(width: width, child: textWidget),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Shadow>? _shadow(bool on) => on
      ? [
          Shadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: maxFontSize * 0.08,
            offset: Offset(0, maxFontSize * 0.03),
          ),
        ]
      : null;

  Widget _linkedSlide(List<String> pieces, LinkedStyle look) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.9 - 2 * padding).clamp(
          10.0,
          double.infinity,
        );
        final height = (constraints.maxHeight - 2 * padding).clamp(
          10.0,
          double.infinity,
        );
        final style = TextStyle(
          color: color,
          fontFamily: fontFamily,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          height: lineHeight,
          shadows: _shadow(shadow),
        );
        TextStyle other(double size) => TextStyle(
          color: look.colorOn(color),
          fontFamily: fontFamily,
          fontSize: size * look.size / 100,
          fontWeight: look.bold || bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: look.italic || italic
              ? FontStyle.italic
              : FontStyle.normal,
          height: lineHeight,
          shadows: _shadow(look.shadow),
        );
        final size = fittedLinkedSize(
          pieces,
          width,
          height,
          maxFontSize,
          style,
          other,
          look.sideBySide,
        );
        final main = style.copyWith(fontSize: size);
        final cross = switch (align) {
          TextAlign.left || TextAlign.start => CrossAxisAlignment.start,
          TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.center,
        };
        final Widget body = look.sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < pieces.length; i++) ...[
                    if (i > 0) SizedBox(width: size * 0.8),
                    Expanded(
                      child: Text(
                        pieces[i],
                        textAlign: align,
                        style: i == 0 ? main : other(size),
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: cross,
                children: [
                  for (var i = 0; i < pieces.length; i++) ...[
                    if (i > 0) SizedBox(height: size * 0.5),
                    Text(
                      pieces[i],
                      textAlign: align,
                      style: i == 0 ? main : other(size),
                    ),
                  ],
                ],
              );
        return RepaintBoundary(
          child: AnimatedSwitcher(
            duration: Duration(
              milliseconds: (transitionSeconds * 1000).round(),
            ),
            child: Align(
              key: ValueKey(pieces.join('|')),
              alignment: position,
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: SizedBox(width: width, child: body),
              ),
            ),
          ),
        );
      },
    );
  }
}
