// Annotations: pen and highlighter strokes drawn on a song's chord sheet or
// on its slides. Saved with the song (in `extra`):
//   'ink'       the chord sheet's strokes
//   'slideInk'  {slide text: strokes} (a repeated chorus shares its ink)
//
// Points are in units of the drawing area's width (x 0–1, y 0–height/width)
// so a drawing keeps its place and shape at any size: the operator's small
// preview, the projector, a TV.

import 'dart:math' as math;
import 'dart:ui';

import 'state.dart' show newId;

class InkStroke {
  final String id;

  /// Highlighter (wide, see-through, under the pen) or pen.
  final bool highlighter;
  final Color color;

  /// Line width, in width units.
  final double width;
  final List<Offset> points;

  InkStroke({
    String? id,
    required this.highlighter,
    required this.color,
    required this.width,
    required this.points,
  }) : id = id ?? newId();

  /// Where the stroke is (its line width included).
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var l = points.first.dx, r = l, t = points.first.dy, b = t;
    for (final p in points) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b).inflate(width / 2);
  }

  InkStroke _with(List<Offset> points, {double? width}) => InkStroke(
    id: id,
    highlighter: highlighter,
    color: color,
    width: width ?? this.width,
    points: points,
  );

  InkStroke moved(Offset by) => _with([for (final p in points) p + by]);

  /// Stretched so [from] (its old box) becomes [to]; the line gets thicker
  /// or thinner with it.
  InkStroke fitted(Rect from, Rect to) {
    final sx = from.width == 0 ? 1.0 : to.width / from.width;
    final sy = from.height == 0 ? 1.0 : to.height / from.height;
    return _with([
      for (final p in points)
        Offset(
          to.left + (p.dx - from.left) * sx,
          to.top + (p.dy - from.top) * sy,
        ),
    ], width: width * math.sqrt(sx * sy));
  }

  /// Whether [p] is on the line (within [slack]).
  bool hits(Offset p, double slack) {
    final reach = width / 2 + slack;
    if (!bounds.inflate(slack).contains(p)) return false;
    if (points.length == 1) return (points.first - p).distance <= reach;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(p, points[i - 1], points[i]) <= reach) {
        return true;
      }
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (highlighter) 'h': true,
    'c': color.toARGB32(),
    'w': _round(width),
    'p': [
      for (final p in points) ...[_round(p.dx), _round(p.dy)],
    ],
  };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  static InkStroke? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['p'];
    if (p is! List || p.length < 2) return null;
    return InkStroke(
      id: j['id'] as String?,
      highlighter: j['h'] == true,
      color: Color((j['c'] as num?)?.toInt() ?? 0xFF000000),
      width: (j['w'] as num?)?.toDouble() ?? 0.004,
      points: [
        for (var i = 0; i + 1 < p.length; i += 2)
          Offset((p[i] as num).toDouble(), (p[i + 1] as num).toDouble()),
      ],
    );
  }

  static List<InkStroke> listFromJson(Object? j) => [
    if (j is List)
      for (final e in j) ?fromJson(e),
  ];

  static List<Map<String, dynamic>> listToJson(List<InkStroke> strokes) => [
    for (final s in strokes) s.toJson(),
  ];
}
