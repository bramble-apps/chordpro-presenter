import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ink.dart';

enum InkTool { pen, highlighter, eraser, select }

/// What is being annotated: the chord sheet, or the slide on the projector.
enum InkTarget { sheet, slide }

/// Annotating: on or off, what, with which tool and colours, and undo /
/// redo for the drawing being worked on (see [bind]).
class InkController extends ChangeNotifier {
  bool _active = false;
  bool get active => _active;
  set active(bool v) {
    if (v == _active) return;
    _active = v;
    selected = null;
    notifyListeners();
  }

  InkTarget _target = InkTarget.sheet;
  InkTarget get target => _target;
  set target(InkTarget v) {
    if (v == _target) return;
    _target = v;
    selected = null;
    notifyListeners();
  }

  InkTool _tool = InkTool.pen;
  InkTool get tool => _tool;
  set tool(InkTool v) {
    if (v == _tool) return;
    _tool = v;
    if (v != InkTool.select) selected = null;
    notifyListeners();
  }

  Color penColor = const Color(0xFFE53935);
  Color highlighterColor = const Color(0xFFFFEB3B);

  /// The colour of the pen or highlighter (whichever is in use, or was
  /// last).
  Color get color => _tool == InkTool.highlighter ? highlighterColor : penColor;
  void setColor(Color c) {
    if (_tool == InkTool.highlighter) {
      highlighterColor = c;
    } else {
      penColor = c;
    }
    notifyListeners();
  }

  /// The line widths to choose from (width units), thinnest first.
  static const penSizes = [0.0015, 0.0025, 0.0035, 0.006, 0.01];
  static const highlighterSizes = [0.008, 0.013, 0.02, 0.03, 0.045];

  int penSize = 2;
  int highlighterSize = 2;
  double penOpacity = 1;
  double highlighterOpacity = 1;

  /// The pen's or highlighter's size (whichever is in use, or was last).
  int get size => _tool == InkTool.highlighter ? highlighterSize : penSize;
  void setSize(int i) {
    _tool == InkTool.highlighter ? highlighterSize = i : penSize = i;
    notifyListeners();
  }

  double get opacity =>
      _tool == InkTool.highlighter ? highlighterOpacity : penOpacity;
  void setOpacity(double v) {
    _tool == InkTool.highlighter ? highlighterOpacity = v : penOpacity = v;
    notifyListeners();
  }

  /// The stroke picked with the move tool.
  String? selected;

  void select(String? id) {
    if (id == selected) return;
    selected = id;
    notifyListeners();
  }

  // ---- The drawing being worked on, with undo / redo ----

  String? _key;
  List<InkStroke> Function()? _read;
  void Function(List<InkStroke>)? _write;
  final List<List<InkStroke>> _undo = [];
  final List<List<InkStroke>> _redo = [];

  /// The drawing to work on ([key] names it: a new one starts a fresh undo
  /// history).
  void bind(
    String key,
    List<InkStroke> Function() read,
    void Function(List<InkStroke>) write,
  ) {
    _read = read;
    _write = write;
    if (key == _key) return;
    _key = key;
    _undo.clear();
    _redo.clear();
    selected = null;
  }

  List<InkStroke> get strokes => _read?.call() ?? const [];

  /// Replaces the drawing with [next] (one undo step).
  void commit(List<InkStroke> next) {
    final write = _write;
    if (write == null) return;
    _undo.add(strokes);
    _redo.clear();
    write(next);
    notifyListeners();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty || _write == null) return;
    _redo.add(strokes);
    _write!(_undo.removeLast());
    selected = null;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty || _write == null) return;
    _undo.add(strokes);
    _write!(_redo.removeLast());
    selected = null;
    notifyListeners();
  }
}

/// A drawing over something (the chord sheet, a slide). With an active
/// [controller] whose drawing this is, it can be drawn on; otherwise it
/// only shows [strokes] and lets taps through.
class InkCanvas extends StatefulWidget {
  final List<InkStroke> strokes;
  final InkController? controller;
  final bool editable;

  const InkCanvas({
    super.key,
    required this.strokes,
    this.controller,
    this.editable = false,
  });

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

enum _Drag { none, draw, erase, move, resize }

class _InkCanvasState extends State<InkCanvas> {
  /// The stroke being drawn, or the drawing while erasing / moving.
  InkStroke? _live;
  List<InkStroke>? _working;
  _Drag _drag = _Drag.none;
  Offset _last = Offset.zero;
  Rect? _startBox;
  Offset _start = Offset.zero;

  InkController? get _c => widget.editable ? widget.controller : null;
  List<InkStroke> get _strokes => _working ?? widget.strokes;

  InkStroke? get _selected {
    final id = _c?.selected;
    if (id == null) return null;
    for (final s in _strokes) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The corner handle for resizing, in width units.
  Offset _handle(Rect box) => box.bottomRight;

  void _down(Offset local, double w) {
    final c = _c;
    if (c == null || w <= 0) return;
    final p = local / w;
    final slack = 10 / w;
    _last = p;
    _start = p;
    switch (c.tool) {
      case InkTool.pen || InkTool.highlighter:
        _drag = _Drag.draw;
        final hl = c.tool == InkTool.highlighter;
        _live = InkStroke(
          highlighter: hl,
          color: hl
              ? c.highlighterColor.withValues(alpha: c.highlighterOpacity)
              : c.penColor.withValues(alpha: c.penOpacity),
          width: hl
              ? InkController.highlighterSizes[c.highlighterSize]
              : InkController.penSizes[c.penSize],
          points: [p],
        );
      case InkTool.eraser:
        _drag = _Drag.erase;
        _working = [...widget.strokes];
        _erase(p, slack);
      case InkTool.select:
        final sel = _selected;
        if (sel != null && (p - _handle(sel.bounds)).distance <= 16 / w) {
          _drag = _Drag.resize;
          _startBox = sel.bounds;
          _working = [...widget.strokes];
        } else if (sel != null && sel.bounds.inflate(slack).contains(p)) {
          _drag = _Drag.move;
          _working = [...widget.strokes];
        } else {
          // Topmost stroke under the pointer.
          final hit = widget.strokes.reversed
              .where((s) => s.hits(p, slack))
              .firstOrNull;
          c.select(hit?.id);
          if (hit != null) {
            _drag = _Drag.move;
            _working = [...widget.strokes];
          }
        }
    }
    setState(() {});
  }

  void _erase(Offset p, double slack) {
    _working!.removeWhere((s) => s.hits(p, slack));
  }

  void _move(Offset local, double w) {
    if (_c == null || w <= 0 || _drag == _Drag.none) return;
    final p = local / w;
    switch (_drag) {
      case _Drag.draw:
        final live = _live!;
        if ((p - live.points.last).distance * w < 1.5) return;
        _live = InkStroke(
          id: live.id,
          highlighter: live.highlighter,
          color: live.color,
          width: live.width,
          points: [...live.points, p],
        );
      case _Drag.erase:
        _erase(p, 10 / w);
      case _Drag.move:
        final id = _c!.selected;
        _working = [
          for (final s in _working!) s.id == id ? s.moved(p - _last) : s,
        ];
      case _Drag.resize:
        final id = _c!.selected;
        final from = _startBox!;
        // Keep the top-left corner; the handle follows the pointer.
        final br = from.bottomRight + (p - _start);
        final to = Rect.fromLTRB(
          from.left,
          from.top,
          math.max(from.left + 12 / w, br.dx),
          math.max(from.top + 12 / w, br.dy),
        );
        final now = _working!.firstWhere((s) => s.id == id);
        _working = [
          for (final s in _working!) s.id == id ? s.fitted(now.bounds, to) : s,
        ];
      case _Drag.none:
        break;
    }
    _last = p;
    setState(() {});
  }

  void _up() {
    final c = _c;
    final drag = _drag;
    _drag = _Drag.none;
    if (c == null) return;
    switch (drag) {
      case _Drag.draw:
        final live = _live;
        _live = null;
        if (live != null) c.commit([...widget.strokes, live]);
      case _Drag.erase || _Drag.move || _Drag.resize:
        final next = _working;
        _working = null;
        if (next != null && !_sameAs(next, widget.strokes)) c.commit(next);
      case _Drag.none:
        break;
    }
    setState(() {});
  }

  static bool _sameAs(List<InkStroke> a, List<InkStroke> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final paint = CustomPaint(
          size: Size(w, box.maxHeight),
          painter: InkPainter(
            strokes: _strokes,
            live: _live,
            selected: c?.tool == InkTool.select ? _selected?.bounds : null,
            accent: Theme.of(context).colorScheme.primary,
          ),
        );
        if (c == null) return IgnorePointer(child: paint);
        return MouseRegion(
          cursor: c.tool == InkTool.select
              ? SystemMouseCursors.move
              : SystemMouseCursors.precise,
          // Claims every touch at once, so drawing never selects text or
          // drags the page underneath.
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _down(e.localPosition, w),
              onPointerMove: (e) => _move(e.localPosition, w),
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _up(),
              child: paint,
            ),
          ),
        );
      },
    );
  }
}

/// Draws strokes (in width units) at the canvas's width; highlighters go
/// under the pen.
class InkPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final InkStroke? live;

  /// The box around the stroke picked to move / resize (width units).
  final Rect? selected;
  final Color accent;

  const InkPainter({
    required this.strokes,
    this.live,
    this.selected,
    this.accent = const Color(0xFF2196F3),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (w <= 0) return;
    final all = [...strokes, ?live];
    for (final hl in [true, false]) {
      for (final s in all) {
        if (s.highlighter == hl) _stroke(canvas, s, w);
      }
    }
    final box = selected;
    if (box != null) {
      final r = Rect.fromLTRB(
        box.left * w,
        box.top * w,
        box.right * w,
        box.bottom * w,
      ).inflate(4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      // Resize handle (bottom right).
      canvas.drawCircle(
        r.bottomRight - const Offset(4, 4),
        8,
        Paint()..color = accent,
      );
      canvas.drawCircle(
        r.bottomRight - const Offset(4, 4),
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _stroke(Canvas canvas, InkStroke s, double w) {
    final pts = [for (final p in s.points) p * w];
    final paint = Paint()
      // (A highlighter at full opacity still lets the text through.)
      ..color = s.highlighter
          ? s.color.withValues(alpha: s.color.a * 0.4)
          : s.color
      ..strokeWidth = s.width * w
      ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        s.width * w / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    // Smooth: through the midpoints, bending at each point.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      !identical(old.strokes, strokes) ||
      !identical(old.live, live) ||
      old.selected != selected ||
      old.accent != accent;
}

/// A song's chord sheet annotations, over the sheet (scrolling with it).
/// Drawn on while annotating the sheet of the open song.
class SheetInkLayer extends StatelessWidget {
  final InkController controller;
  final String songId;

  /// The open song's id (only its sheet can be drawn on).
  final String? Function() currentSongId;
  final List<InkStroke> Function() read;
  final void Function(List<InkStroke>) write;

  /// Changes when the drawing or the open song changes.
  final Listenable changes;

  const SheetInkLayer({
    super.key,
    required this.controller,
    required this.songId,
    required this.currentSongId,
    required this.read,
    required this.write,
    required this.changes,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, changes]),
    builder: (context, _) {
      final editable =
          controller.active &&
          controller.target == InkTarget.sheet &&
          currentSongId() == songId;
      if (editable) controller.bind('sheet|$songId', read, write);
      return InkCanvas(
        strokes: read(),
        controller: controller,
        editable: editable,
      );
    },
  );
}
