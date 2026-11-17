// The music symbols (glyphs.dart) as outlines: SVG path data read into
// polygons (curves flattened), and filled into small black-and-white
// pictures, for the reader to compare what it finds with.

import 'dart:math' as math;
import 'dart:typed_data';

import 'glyphs.dart';

/// [d] (SVG path data) as closed polygons, curves flattened into [steps]
/// pieces. Handles M L H V C S Q T Z, absolute and relative.
List<List<(double, double)>> pathPolygons(String d, {int steps = 8}) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsQqTtZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final out = <List<(double, double)>>[];
  var poly = <(double, double)>[];
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double? cx2, cy2; // last control point (for S / T)
  bool isNum(int k) =>
      k < tokens.length && !RegExp('[A-Za-z]').hasMatch(tokens[k]);
  double next() => double.parse(tokens[i++]);

  void close() {
    if (poly.length > 2) out.add(poly);
    poly = [];
  }

  void cubic(double x1, double y1, double x2, double y2, double ex, double ey) {
    for (var k = 1; k <= steps; k++) {
      final t = k / steps, u = 1 - t;
      poly.add((
        u * u * u * x +
            3 * u * u * t * x1 +
            3 * u * t * t * x2 +
            t * t * t * ex,
        u * u * u * y +
            3 * u * u * t * y1 +
            3 * u * t * t * y2 +
            t * t * t * ey,
      ));
    }
    x = ex;
    y = ey;
  }

  while (i < tokens.length) {
    if (!isNum(i)) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        close();
        x = ox + next();
        y = oy + next();
        sx = x;
        sy = y;
        poly.add((x, y));
        cmd = rel ? 'l' : 'L'; // more pairs are lines
        cx2 = null;
      case 'L':
        x = ox + next();
        y = oy + next();
        poly.add((x, y));
        cx2 = null;
      case 'H':
        x = ox + next();
        poly.add((x, y));
        cx2 = null;
      case 'V':
        y = oy + next();
        poly.add((x, y));
        cx2 = null;
      case 'C':
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        final ex = ox + next(), ey = oy + next();
        cubic(x1, y1, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
      case 'S':
        final x1 = cx2 == null ? x : 2 * x - cx2;
        final y1 = cy2 == null ? y : 2 * y - cy2;
        final x2 = ox + next(), y2 = oy + next();
        final ex = ox + next(), ey = oy + next();
        cubic(x1, y1, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
      case 'Q' || 'T':
        final double qx, qy;
        if (cmd.toUpperCase() == 'Q') {
          qx = ox + next();
          qy = oy + next();
        } else {
          qx = cx2 == null ? x : 2 * x - cx2;
          qy = cy2 == null ? y : 2 * y - cy2;
        }
        final ex = ox + next(), ey = oy + next();
        cubic(
          x + 2 / 3 * (qx - x),
          y + 2 / 3 * (qy - y),
          ex + 2 / 3 * (qx - ex),
          ey + 2 / 3 * (qy - ey),
          ex,
          ey,
        );
        cx2 = qx;
        cy2 = qy;
      case 'Z':
        x = sx;
        y = sy;
        close();
        cx2 = null;
      default:
        i++; // unknown: skip
    }
  }
  close();
  return out;
}

/// A black-and-white picture (1 = ink), row by row.
class Mask {
  final int w, h;
  final Uint8List px;
  Mask(this.w, this.h) : px = Uint8List(w * h);
  bool at(int x, int y) => px[y * w + x] == 1;
}

/// [polys] (y up) filled (non-zero) into a [w] × [h] picture, the box
/// [x0,y0]–[x1,y1] (font units) stretched over it.
Mask fillPolygons(
  List<List<(double, double)>> polys,
  double x0,
  double y0,
  double x1,
  double y1,
  int w,
  int h,
) {
  final m = Mask(w, h);
  for (var row = 0; row < h; row++) {
    // Sample in the middle of the row; y up in font units.
    final fy = y1 - (row + 0.5) / h * (y1 - y0);
    final hits = <(double, int)>[];
    for (final p in polys) {
      for (var k = 0; k < p.length; k++) {
        final (ax, ay) = p[k];
        final (bx, by) = p[(k + 1) % p.length];
        if ((ay <= fy && by > fy) || (by <= fy && ay > fy)) {
          final t = (fy - ay) / (by - ay);
          hits.add((ax + t * (bx - ax), by > ay ? 1 : -1));
        }
      }
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    var wind = 0;
    for (var k = 0; k + 1 < hits.length; k++) {
      wind += hits[k].$2;
      if (wind == 0) continue;
      final from = ((hits[k].$1 - x0) / (x1 - x0) * w).round();
      final to = ((hits[k + 1].$1 - x0) / (x1 - x0) * w).round();
      for (var c = math.max(0, from); c < math.min(w, to); c++) {
        m.px[row * w + c] = 1;
      }
    }
  }
  return m;
}

final _polyCache = <String, List<List<(double, double)>>>{};

/// The glyph [name] as polygons (font units, y up).
List<List<(double, double)>> glyphPolygons(String name) =>
    _polyCache.putIfAbsent(name, () => pathPolygons(glyphs[name]!.path));

/// The glyph [name] filled into a [w] × [h] picture (its own box
/// stretched to fit), for comparing with a symbol found on the page.
Mask glyphMask(String name, int w, int h) {
  final g = glyphs[name]!;
  return fillPolygons(
    glyphPolygons(name),
    g.x,
    g.y,
    g.x + g.w,
    g.y + g.h,
    w,
    h,
  );
}
