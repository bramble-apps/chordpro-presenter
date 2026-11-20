import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'resize_hold.dart';
import '../eink.dart';

/// One song in the swipe strip.
class SwipePage {
  /// Stable id (song + setlist entry): the drawn sheet is kept while the
  /// id stays the same, so a song that slides in is never redrawn.
  final String id;
  final Widget child;
  const SwipePage(this.id, this.child);
}

/// Swipe sideways (two fingers on a trackpad, or one finger on a touch
/// screen) between songs.
///
/// The songs on either side are drawn ahead of time, so the incoming song
/// is already there when it slides in. The pull is elastic with a growing
/// half-circle arrow; reaching the threshold switches at once. Turning back
/// or stopping short springs back with a slight bounce.
class SongSwipe extends StatefulWidget {
  final SwipePage current;

  /// Songs before / after the current one, nearest first. The nearest is
  /// what a swipe opens; the rest are drawn ahead for quick succession.
  final List<SwipePage> before;
  final List<SwipePage> after;

  /// Called once the new song is in place (+1 next, -1 previous).
  final void Function(int dir) onGo;

  /// Off: the song stays put (e.g. while drawing on it).
  final bool enabled;

  const SongSwipe({
    super.key,
    required this.current,
    required this.onGo,
    this.enabled = true,
    this.before = const [],
    this.after = const [],
  });

  /// How far (on screen) the sheet must be pulled to switch songs.
  static const threshold = 64.0;

  /// Number of pulls started (for tests).
  @visibleForTesting
  static int debugPulls = 0;

  /// True while the sheet's width is animating (the sidebar sliding): the
  /// songs before and after, which are out of sight, keep their layout
  /// until it settles, so only the song on screen is laid out each frame.
  static final resizing = ValueNotifier<bool>(false);

  @override
  State<SongSwipe> createState() => _SongSwipeState();
}

enum _Axis { horizontal, vertical }

class _SongSwipeState extends State<SongSwipe> with TickerProviderStateMixin {
  static const _gap = 24.0;

  /// Strip offset in pixels (negative = moved left = towards the next song).
  late final _offset = AnimationController.unbounded(vsync: this);

  /// The end of a previous switch still gliding in when a new swipe
  /// starts; it finishes on its own underneath the new pull.
  late final _glide = AnimationController.unbounded(vsync: this);
  late final _moved = Listenable.merge([_offset, _glide]);
  double get _shown => _offset.value + _glide.value;

  /// Arrow state; only changes when it really changes (the arrow itself is
  /// not rebuilt every frame).
  final _indicator = ValueNotifier<(int, bool)>((0, false));

  double _width = 600;
  double get _page => _width + _gap;

  /// Finger travel so far (before the rubber band).
  double _raw = 0;
  bool _dragging = false;

  /// Direction of a switch in progress (the strip is gliding to the page).
  int _committing = 0;

  /// While swiping, the sheet itself must not scroll up / down.
  bool _locked = false;

  /// Pages that have been drawn. Songs further ahead are drawn one at a
  /// time while nothing is moving, so a swipe never waits for one.
  final Set<String> _ready = {};
  Timer? _warm;

  Set<String> get _ids => {
    widget.current.id,
    for (final p in widget.before) p.id,
    for (final p in widget.after) p.id,
  };

  @override
  void initState() {
    super.initState();
    _ready.addAll(_ids);
  }

  @override
  void didUpdateWidget(SongSwipe old) {
    super.didUpdateWidget(old);
    _ready.retainAll(_ids);
    _ready.add(widget.current.id);
    _scheduleWarm();
  }

  /// Draws the next not-yet-drawn page once things are still.
  void _scheduleWarm() {
    if (_warm?.isActive ?? false) return;
    if (_ids.difference(_ready).isEmpty) return;
    _warm = Timer(const Duration(milliseconds: 90), () {
      if (!mounted) return;
      if (_dragging || _offset.isAnimating || _glide.isAnimating) {
        _scheduleWarm();
        return;
      }
      // Nearest first.
      final order = [
        for (var i = 0; i < 3; i++) ...[
          if (i < widget.after.length) widget.after[i].id,
          if (i < widget.before.length) widget.before[i].id,
        ],
      ];
      final id = order.firstWhere(
        (id) => !_ready.contains(id),
        orElse: () => '',
      );
      if (id.isEmpty) return;
      setState(() => _ready.add(id));
      _scheduleWarm();
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _streamTimer?.cancel();
    _warm?.cancel();
    _offset.dispose();
    _glide.dispose();
    _indicator.dispose();
    super.dispose();
  }

  SwipePage? _pageIn(int dir) {
    final list = dir > 0 ? widget.after : widget.before;
    return list.isEmpty ? null : list.first;
  }

  bool _canGo(int dir) => _pageIn(dir) != null;

  // ---- Rubber band ----

  double _limit(int dir) => _canGo(dir) ? 170 : 36;

  /// Follows the finger at first, then resists more and more. Pulling
  /// towards a missing song barely moves.
  double _rubber(double raw) {
    if (raw == 0) return 0;
    final l = _limit(raw < 0 ? 1 : -1);
    return raw.sign * l * (1 - 1 / (raw.abs() / l + 1));
  }

  double _unrubber(double shown) {
    if (shown == 0) return 0;
    final l = _limit(shown < 0 ? 1 : -1);
    final y = math.min(shown.abs(), l * 0.98);
    return shown.sign * (l / (1 - y / l) - l);
  }

  // ---- Drag ----
  //
  // Nothing waits for the fingers to lift (browsers can't tell when a
  // trackpad is let go):
  //  * reaching the threshold switches straight away;
  //  * turning back springs back, at the speed you were moving;
  //  * stopping short (a pause) gives up and springs back.

  /// Furthest pull in this swipe (finger travel).
  double _peak = 0;

  /// The rest of this gesture is ignored (it already switched / gave up).
  bool _swallow = false;

  void _begin() {
    if (_dragging) return;
    if (_committing != 0) _finishCommit();
    _offset.stop();
    _dragging = true;
    SongSwipe.debugPulls++;
    _raw = _unrubber(_offset.value);
    _peak = _raw.abs();
    if (!_locked) setState(() => _locked = true);
  }

  /// How fast the sheet moves for a given finger speed at this point of
  /// the rubber band.
  double _shownVelocity(double rawVelocity) {
    if (_raw == 0) return rawVelocity;
    final l = _limit(_raw < 0 ? 1 : -1);
    final k = l / (_raw.abs() + l);
    return rawVelocity * k * k;
  }

  /// Moves by [dx] of finger travel; [velocity] is the finger's current
  /// speed (px/s), used to hand the motion over without a jolt.
  void _move(double dx, double velocity) {
    if (_swallow) return;
    _begin();
    _raw += dx;
    final v = _rubber(_raw);
    _offset.value = v;
    final dir = v < 0 ? 1 : (v > 0 ? -1 : 0);
    final target = dir == 0 ? null : _pageIn(dir);
    if (target != null && !_ready.contains(target.id)) {
      setState(() => _ready.add(target.id));
    }
    _indicator.value = (target == null ? 0 : dir, false);

    if (target != null && v.abs() >= SongSwipe.threshold) {
      _end();
      HapticFeedback.selectionClick();
      _commit(dir, _shownVelocity(velocity));
      return;
    }
    _peak = math.max(_peak, _raw.abs());
    final goingBack = dx != 0 && dx.sign == -_raw.sign;
    if (goingBack && _raw.abs() < _peak - 10) {
      _end();
      _settle(_shownVelocity(velocity));
    }
  }

  /// Stopped short: give up.
  void _giveUp([double velocity = 0]) {
    if (!_dragging) return;
    _end();
    _settle(_shownVelocity(velocity));
  }

  void _end() {
    _dragging = false;
    _swallow = true;
    _freshGesture = false;
    _pending = 0;
    _run.clear();
    _sincePeak = 0;
    _dipped = false;
    _endSign = _recent.isEmpty ? 0 : _recent.last.$1.sign;
  }

  /// Springs back with an ever-so-slight bounce.
  void _settle(double velocity) {
    if (isEink(context)) {
      _offset.value = 0;
      _unlock();
      return;
    }
    _offset
        .animateWith(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1,
              stiffness: 520,
              ratio: 0.74,
            ),
            _offset.value,
            0,
            velocity,
            tolerance: const Tolerance(distance: 0.3, velocity: 5),
          ),
        )
        .then((_) => _unlock());
  }

  /// Glides the strip until the new song is in place, then switches.
  void _commit(int dir, double velocity) {
    _committing = dir;
    _indicator.value = (dir, true);
    if (isEink(context)) {
      // Straight to the new song.
      _offset.value = -dir * _page;
      _finishCommit();
      _unlock();
      return;
    }
    _offset
        .animateWith(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1,
              stiffness: 600,
              ratio: 1,
            ),
            _offset.value,
            -dir * _page,
            // Keep the finger's speed, but always head the right way.
            dir > 0 ? math.min(velocity, 0) : math.max(velocity, 0),
            tolerance: const Tolerance(distance: 0.5, velocity: 10),
          ),
        )
        .then((_) {
          if (_committing != 0 && !_dragging) _finishCommit();
          _unlock();
        });
  }

  /// The new song is in place (or a new swipe started on the way): switch,
  /// keeping whatever distance is left so nothing jumps.
  void _finishCommit() {
    final dir = _committing;
    _committing = 0;
    final left = _offset.value + dir * _page;
    final velocity = _offset.isAnimating ? _offset.velocity : 0.0;
    _offset.stop();
    _offset.value = 0;
    _indicator.value = (0, false);
    widget.onGo(dir);
    // Whatever was left keeps gliding in smoothly on its own.
    if (left.abs() > 0.5) {
      _glide.value = left + _glide.value;
      _glide.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(mass: 1, stiffness: 600, ratio: 1),
          _glide.value,
          0,
          velocity,
          tolerance: const Tolerance(distance: 0.5, velocity: 10),
        ),
      );
    }
  }

  void _unlock() {
    if (!_dragging && _committing == 0 && _locked && mounted) {
      setState(() => _locked = false);
    }
  }

  // ---- Trackpad: a stream of sideways scroll events. A short pause ends
  // the gesture (and gives up if it hadn't switched yet). ----

  _Axis? _axis;
  Timer? _idle;
  final List<(double dx, double dt)> _recent = [];
  Duration _lastStamp = Duration.zero;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final d = event.scrollDelta;
    _axis ??= d.dx.abs() > d.dy.abs() ? _Axis.horizontal : _Axis.vertical;
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 90), _trackpadIdle);
    if (_axis != _Axis.horizontal) return;
    // Ours: don't let the sheet scroll or the browser go Back / Forward.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
    if (d.dx == 0) return;
    _trackpadMove(-d.dx, event.timeStamp);
  }

  // Desktop apps (Linux, macOS, Windows) report a two-finger swipe as a
  // pan gesture instead of scroll events: the same swipe, with a clear end
  // when the fingers lift.
  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _idle?.cancel();
    _axis = null;
    _lastStamp = e.timeStamp;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final d = e.panDelta;
    if (d == Offset.zero) return;
    _axis ??= d.dx.abs() > d.dy.abs() ? _Axis.horizontal : _Axis.vertical;
    if (_axis != _Axis.horizontal || d.dx == 0) return;
    _trackpadMove(d.dx, e.timeStamp);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent e) {
    _idle?.cancel();
    _trackpadIdle();
  }

  /// Sideways trackpad movement of [dx] (positive: fingers moving right).
  void _trackpadMove(double dx, Duration timeStamp) {
    // Time between events (tests send no timestamps: assume 60 per second).
    var dt = (timeStamp - _lastStamp).inMicroseconds / 1e6;
    _lastStamp = timeStamp;
    if (dt <= 0 || dt > 0.1) dt = 1 / 60;
    _recent.add((dx, dt));
    if (_recent.length > 4) _recent.removeAt(0);
    final fresh = !_stream;
    _stream = true;
    _streamTimer?.cancel();
    _streamTimer = Timer(const Duration(milliseconds: 250), () {
      _stream = false;
    });
    if (_dragging) {
      _move(dx, _trackpadVelocity());
      return;
    }
    if (_startsSwipe(dx, fresh: fresh)) {
      final travel = _freshGesture ? _pending : _run.fold(0.0, (a, b) => a + b);
      _pending = 0;
      _run.clear();
      _swallow = false;
      _move(travel, _trackpadVelocity());
    }
  }

  void _trackpadIdle() {
    _giveUp();
    _axis = null;
    _recent.clear();
  }

  // Deciding when trackpad movement is a new swipe. Fingers lifting send a
  // little jitter, and macOS keeps "coasting" after a lift (it can even
  // jump up a little at first, then only fades). So:
  //  * after a real pause in the stream: a swipe starts once the fingers
  //    have travelled a few pixels;
  //  * straight out of the previous swipe (no pause): only movement that
  //    keeps speeding up — fingers starting a new swipe — counts.

  /// Scroll events are still arriving (no pause of a quarter second).
  bool _stream = false;
  Timer? _streamTimer;

  /// This stream began with a pause, and hasn't switched / given up yet.
  bool _freshGesture = false;

  /// Travel not yet used (counted into the swipe once it starts).
  double _pending = 0;
  final List<double> _run = [];

  /// After a switch: the rest of that same swipe may still be speeding up.
  /// A new swipe only counts once the movement has first dipped (slowed
  /// to half its top speed, or turned around).
  double _sincePeak = 0;
  bool _dipped = false;
  double _endSign = 0;

  bool _startsSwipe(double dx, {required bool fresh}) {
    if (fresh) {
      _freshGesture = true;
      _pending = 0;
      _run.clear();
    }
    if (_pending != 0 && dx.sign != _pending.sign) {
      _pending = 0;
      _run.clear();
    }
    _pending += dx;
    if (_freshGesture) {
      _run.add(dx);
      if (_run.length > 3) _run.removeAt(0);
      return _pending.abs() >= 8;
    }
    if (!_dipped) {
      _sincePeak = math.max(_sincePeak, dx.abs());
      if (dx.abs() <= _sincePeak * 0.5 ||
          (_endSign != 0 && dx.sign != _endSign)) {
        _dipped = true;
        _run.clear();
      }
      return false;
    }
    _run.add(dx);
    if (_run.length > 3) _run.removeAt(0);
    if (_run.length < 3 || _run.any((v) => v.sign != dx.sign)) return false;
    final a = _run[0].abs(), b = _run[1].abs(), c = _run[2].abs();
    return a < b && b < c && c >= 4 && c >= a * 1.8;
  }

  double _trackpadVelocity() {
    var dx = 0.0, dt = 0.0;
    for (final (x, t) in _recent) {
      dx += x;
      dt += t;
    }
    return dt == 0 ? 0 : (dx / dt).clamp(-4000.0, 4000.0);
  }

  // ---- Touch: read the finger directly (the sheet's text selection
  // would otherwise claim sideways drags). ----

  int? _touch;
  Offset _touchStart = Offset.zero;
  _Axis? _touchAxis;
  VelocityTracker? _tracker;

  void _onDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch &&
        e.kind != PointerDeviceKind.stylus) {
      return;
    }
    if (_touch != null) {
      _touchAxis = _Axis.vertical; // A second finger: not a swipe.
      return;
    }
    _touch = e.pointer;
    _touchStart = e.position;
    _touchAxis = null;
    _swallow = false;
    _tracker = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  double get _touchVelocity =>
      _tracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _touch || _touchAxis == _Axis.vertical) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    if (_touchAxis == null) {
      final d = e.position - _touchStart;
      if (d.distance < kTouchSlop) return;
      _touchAxis = d.dx.abs() > d.dy.abs() * 1.2
          ? _Axis.horizontal
          : _Axis.vertical;
      if (_touchAxis == _Axis.horizontal) _move(d.dx, _touchVelocity);
      return;
    }
    _move(e.delta.dx, _touchVelocity); // Sideways only.
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _touch) return;
    _touch = null;
    if (_touchAxis == _Axis.horizontal) {
      _giveUp(e is PointerUpEvent ? _touchVelocity : 0.0);
    }
    _touchAxis = null;
    _tracker = null;
    _swallow = false;
  }

  // ---- Drawing ----

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600;
        Widget page(SwipePage p, int slot) {
          final ready = _ready.contains(p.id);
          return AnimatedBuilder(
            key: ValueKey(p.id),
            animation: _moved,
            builder: (context, child) {
              // Whole device pixels: text stays crisp while moving.
              final x = ((slot * _page + _shown) * dpr).round() / dpr;
              return Transform.translate(offset: Offset(x, 0), child: child);
            },
            child: RepaintBoundary(
              // (the window being resized: every song holds its layout
              // until it settles; the sidebar sliding: the ones either side)
              child: slot == 0
                  ? ResizeHold(
                      child: ready ? p.child : const SizedBox.expand(),
                    )
                  : ValueListenableBuilder<bool>(
                      valueListenable: SongSwipe.resizing,
                      builder: (context, frozen, child) =>
                          ResizeHold(hold: frozen, child: child!),
                      child: ready ? p.child : const SizedBox.expand(),
                    ),
            ),
          );
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: widget.enabled ? _onSignal : null,
          onPointerPanZoomStart: widget.enabled ? _onPanZoomStart : null,
          onPointerPanZoomUpdate: widget.enabled ? _onPanZoomUpdate : null,
          onPointerPanZoomEnd: widget.enabled ? _onPanZoomEnd : null,
          onPointerDown: widget.enabled ? _onDown : null,
          onPointerMove: widget.enabled ? _onMove : null,
          onPointerUp: widget.enabled ? _onUp : null,
          onPointerCancel: widget.enabled ? _onUp : null,
          child: ScrollConfiguration(
            // Locked to sideways while swiping.
            behavior: _locked
                ? ScrollConfiguration.of(context)
                      .copyWith(physics: const NeverScrollableScrollPhysics())
                : ScrollConfiguration.of(context),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (var i = 0; i < widget.before.length; i++)
                    page(widget.before[i], -1 - i),
                  for (var i = 0; i < widget.after.length; i++)
                    page(widget.after[i], 1 + i),
                  page(widget.current, 0),
                  _SwipeArrow(offset: _offset, state: _indicator, dpr: dpr),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Half-circle arrow at the edge the next song comes from. Its shape is
/// built once per direction / state; moving it is just a transform.
class _SwipeArrow extends StatelessWidget {
  final Animation<double> offset;
  final ValueListenable<(int, bool)> state;
  final double dpr;

  const _SwipeArrow({
    required this.offset,
    required this.state,
    required this.dpr,
  });

  static const _r = 30.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ValueListenableBuilder<(int, bool)>(
        valueListenable: state,
        builder: (context, s, _) {
          final (dir, met) = s;
          if (dir == 0) return const SizedBox.shrink();
          final right = dir > 0;
          final shape = TweenAnimationBuilder<double>(
            tween: Tween(end: met ? 1 : 0),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            builder: (context, t, _) => Container(
              width: _r,
              height: _r * 2,
              decoration: BoxDecoration(
                color: Color.lerp(
                  scheme.surfaceContainerHighest,
                  scheme.primary,
                  t,
                ),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 1 - t),
                  width: inkW(1),
                ),
                borderRadius: right
                    ? BorderRadius.horizontal(left: Radius.circular(inkR(_r)))
                    : BorderRadius.horizontal(right: Radius.circular(inkR(_r))),
              ),
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: 1 + 0.15 * t,
                child: Icon(
                  right
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                  size: 20,
                  color: Color.lerp(
                    scheme.onSurfaceVariant,
                    scheme.onPrimary,
                    t,
                  ),
                ),
              ),
            ),
          );
          return Align(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: offset,
              child: RepaintBoundary(child: shape),
              builder: (context, child) {
                final p = (offset.value.abs() / SongSwipe.threshold).clamp(
                  0.0,
                  1.0,
                );
                // Slides out from the edge as the pull grows.
                final hidden = (1 - Curves.easeOut.transform(p)) * (_r + 2);
                final x = ((right ? hidden : -hidden) * dpr).round() / dpr;
                return Transform.translate(
                  offset: Offset(x, 0),
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * p,
                    alignment: right
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: child,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
