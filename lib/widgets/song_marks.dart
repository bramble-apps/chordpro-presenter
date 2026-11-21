// A song's tempo, time signature and key as on printed music, in one short
// row beside its title: ♩ = 73 | 4/4 (stacked over a rule) | G, in a display
// face (Abril Fatface). Whatever the song doesn't have is left out.
import 'package:flutter/material.dart';

/// The display face of the marks.
const songMarksFamily = 'AbrilFatface';

class SongMarks extends StatelessWidget {
  /// Beats per minute as written ("73", "73 BPM"); empty: no tempo.
  final String tempo;

  /// "4/4", "6/8"…; empty: no time signature.
  final String time;

  /// The key's name ("G", "F#m"); null: no key.
  final String? keyName;

  /// The tempo's numbers and each time signature digit, in pixels; the key
  /// letter is a little larger (17 : 15).
  final double size;

  final Color? color;

  const SongMarks({
    super.key,
    required this.tempo,
    required this.time,
    required this.keyName,
    this.size = 15,
    this.color,
  });

  /// The number in [tempo] ("73 BPM" → 73), or the text as written.
  static String tempoText(String tempo) =>
      RegExp(r'\d+(?:[.,]\d+)?').firstMatch(tempo)?.group(0) ?? tempo.trim();

  /// [time] as its two numbers, or null when it isn't "n/m".
  static (String, String)? timeParts(String time) {
    final m = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(time);
    return m == null ? null : (m[1]!, m[2]!);
  }

  bool get isEmpty =>
      tempo.trim().isEmpty && time.trim().isEmpty && (keyName ?? '').isEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = color ?? scheme.onSurface;
    TextStyle face(double s) => TextStyle(
      fontFamily: songMarksFamily,
      fontSize: s,
      height: 1,
      color: ink,
      fontFeatures: const [FontFeature.liningFigures()],
    );
    final parts = <Widget>[
      if (tempo.trim().isNotEmpty)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QuarterNote(height: size * 1.15, color: ink),
            SizedBox(width: size * .2),
            Text('= ${tempoText(tempo)}', style: face(size)),
          ],
        ),
      if (time.trim().isNotEmpty)
        switch (timeParts(time)) {
          (final top, final bottom) => IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(top, textAlign: TextAlign.center, style: face(size)),
                Container(
                  height: 1.25,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  constraints: BoxConstraints(minWidth: size * .66),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                Text(bottom, textAlign: TextAlign.center, style: face(size)),
              ],
            ),
          ),
          null => Text(time.trim(), style: face(size)),
        },
      if (keyName case final k? when k.isNotEmpty)
        Text(k, style: face(size * 17 / 15)),
    ];
    final rule = Container(
      width: 1,
      height: size * 1.5,
      margin: EdgeInsets.symmetric(horizontal: size * .8),
      color: scheme.outlineVariant,
    );
    return Semantics(
      label: [
        if (tempo.trim().isNotEmpty) '${tempoText(tempo)} beats per minute',
        if (time.trim().isNotEmpty) '${time.trim()} time',
        if (keyName case final k? when k.isNotEmpty) 'key of $k',
      ].join(', '),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) rule,
              parts[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A quarter note (filled head, stem up), drawn so it matches the face on
/// every device (fonts rarely have ♩ in a matching weight).
class _QuarterNote extends StatelessWidget {
  final double height;
  final Color color;
  const _QuarterNote({required this.height, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(height * 12 / 30, height),
    painter: _NotePainter(color),
  );
}

class _NotePainter extends CustomPainter {
  final Color color;
  _NotePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // drawn on a 12 × 30 grid
    canvas.scale(size.width / 12, size.height / 30);
    final paint = Paint()..color = color;
    canvas
      ..save()
      ..translate(5, 25)
      ..rotate(-22 * 3.14159265 / 180)
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 7.2),
        paint,
      )
      ..restore()
      ..drawRRect(
        RRect.fromLTRBR(8.6, 1, 10.2, 24.5, const Radius.circular(.8)),
        paint,
      );
  }

  @override
  bool shouldRepaint(_NotePainter old) => old.color != color;
}
