import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../browser.dart';
import '../eink.dart';
import '../levels.dart';
import '../music.dart';
import '../state.dart';
import '../tuner/microphone.dart';
import '../tuner/pitch.dart';
import 'floating_panel.dart';

/// Chromatic tuner: the note heard, a needle for how sharp or flat it is,
/// and the frequency. In tune = within ±5 cents. Its Levels tab shows how
/// loud the microphone hears the room, drawn the same way. Shown as a
/// floating panel (or full screen); it listens while it is on (the power
/// button).
class TunerPanel extends StatefulWidget {
  final PresenterModel model;

  /// For tests: samples to listen to instead of the microphone.
  final Stream<dynamic>? debugSamples;

  final VoidCallback? onClose;

  /// Filling the screen (and how to switch).
  final bool fullscreen;
  final VoidCallback? onFullscreen;

  const TunerPanel({
    super.key,
    required this.model,
    this.debugSamples,
    this.onClose,
    this.fullscreen = false,
    this.onFullscreen,
  });

  @override
  State<TunerPanel> createState() => _TunerPanelState();
}

enum _MicState { off, starting, listening, denied, insecure, blocked, failed }

class _TunerPanelState extends State<TunerPanel> {
  Microphone? _mic;
  late final TunerController _tuner = TunerController(
    sampleRate: 44100,
    a4: widget.model.settings.tunerA4.toDouble(),
  );
  var _state = _MicState.starting;

  /// Showing the Levels tab (else the tuner).
  /// The Levels tab showing (remembered, like the rest of the screen).
  late bool _levelsTab = widget.model.uiValue<bool>('tuner.levels') ?? false;

  void _showLevels(bool on) {
    setState(() => _levelsTab = on);
    widget.model.setUi('tuner.levels', on);
  }

  late final LevelMeter _levels = LevelMeter(
    method:
        LevelMethod.values.asNameMap()[widget.model.settings.levelsMethod] ??
        LevelMethod.soundLevel,
    scale: widget.model.settings.levelsScale,
    calibration: widget.model.settings.levelsCalibration,
  );

  /// The browser's / system's own words when the microphone won't start.
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Switched on or off with the power button (on when opened).
  void _power() {
    if (_state == _MicState.off) {
      setState(() => _state = _MicState.starting);
      _start();
    } else {
      _mic?.dispose();
      _mic = null;
      _tuner.stopListening();
      _levels.stopListening();
      setState(() => _state = _MicState.off);
    }
  }

  Future<void> _start() async {
    final test = widget.debugSamples;
    if (test != null) {
      final samples = test.cast<Float32List>().asBroadcastStream();
      _tuner.listen(samples);
      _levels.listen(samples);
      setState(() => _state = _MicState.listening);
      return;
    }
    if (!micAllowedHere) {
      setState(() => _state = _MicState.insecure);
      return;
    }
    try {
      final mic = _mic = Microphone();
      final ok = await mic.start();
      if (!mounted) return;
      if (!ok) {
        setState(() => _state = _MicState.denied);
        return;
      }
      _tuner
        ..sampleRate = mic.sampleRate
        ..listen(mic.samples);
      _levels
        ..sampleRate = mic.sampleRate
        ..listen(mic.samples);
      setState(() => _state = _MicState.listening);
    } catch (e) {
      debugLog('tuner failed: $e');
      if (mounted) {
        setState(() {
          // Browsers say "not found" / "not allowed" when the system (not
          // the browser) is keeping the microphone from them.
          final text = '$e';
          _state =
              text.contains('NotFoundError') || text.contains('NotAllowedError')
              ? _MicState.blocked
              : _MicState.failed;
          _error = text;
        });
      }
    }
  }

  @override
  void dispose() {
    // Stop listening as soon as the tuner closes.
    _mic?.dispose();
    _tuner.dispose();
    _levels.dispose();
    super.dispose();
  }

  void _setA4(int hz) {
    widget.model.updateSettings((s) => s.tunerA4 = hz);
    _tuner.a4 = hz.toDouble();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a4 = widget.model.settings.tunerA4;
    final solfege = widget.model.format.notation == ChordNotation.solfege;
    final on = _state != _MicState.off;
    final body = switch (_state) {
      _MicState.listening => SizedBox(
        width: 340,
        child: _levelsTab
            ? _LevelsFace(meter: _levels)
            : _TunerFace(tuner: _tuner, solfege: solfege),
      ),
      _MicState.starting => const SizedBox(
        width: 340,
        height: 200,
        child: Center(child: AppSpinner()),
      ),
      _MicState.off => SizedBox(
        width: 340,
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            IconButton.filledTonal(
              tooltip: 'Turn the tuner on',
              iconSize: 40,
              icon: const Icon(Icons.power_settings_new),
              onPressed: _power,
            ),
            Text(
              _levelsTab ? 'Levels off' : 'Tuner off',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      _ => SizedBox(
        width: 340,
        child: _Problem(state: _state, detail: _error),
      ),
    };
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: inkE(widget.fullscreen ? 0 : 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(inkR(widget.fullscreen ? 0 : 18)),
        side: widget.fullscreen
            ? BorderSide.none
            : BorderSide(color: scheme.outline, width: inkW(1.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Title bar: drag it to move the tuner.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: FloatingDragArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        spacing: 6,
                        children: [
                          Icon(Icons.drag_indicator, color: scheme.outline),
                          // (Shrink in a narrow panel.)
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                spacing: 2,
                                children: [
                                  _Tab(
                                    label: 'Tuner',
                                    selected: !_levelsTab,
                                    onTap: () => _showLevels(false),
                                  ),
                                  _Tab(
                                    label: 'Levels',
                                    selected: _levelsTab,
                                    onTap: () => _showLevels(true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: on ? 'Turn the tuner off' : 'Turn the tuner on',
                  isSelected: on,
                  // (E-ink: the theme's own on look, white on black.)
                  color: on && !isEink(context) ? scheme.primary : null,
                  icon: const Icon(Icons.power_settings_new),
                  onPressed: _power,
                ),
                if (widget.onFullscreen != null)
                  IconButton(
                    tooltip: widget.fullscreen
                        ? 'Exit full screen'
                        : 'Full screen',
                    icon: Icon(
                      widget.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                    onPressed: widget.onFullscreen,
                  ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Close tuner',
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Full screen: grows with the window (readable from across
              // the room), up to about twice its normal size.
              child: LayoutBuilder(
                builder: (context, box) => Center(
                  child: SizedBox(
                    width: widget.fullscreen
                        ? math.min(box.maxWidth, 720)
                        : box.maxWidth,
                    height: widget.fullscreen
                        ? math.min(box.maxHeight, 560)
                        : box.maxHeight,
                    child: FittedBox(
                      fit: widget.fullscreen
                          ? BoxFit.contain
                          : BoxFit.scaleDown,
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_levelsTab)
            _LevelsControls(meter: _levels, model: widget.model)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Text(
                    'A = ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  IconButton(
                    tooltip: 'Lower reference',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: a4 > 415 ? () => _setA4(a4 - 1) : null,
                  ),
                  Text(
                    '$a4 Hz',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Raise reference',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: a4 < 466 ? () => _setA4(a4 + 1) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The tuner face: the note on top, and a cents ruler with a round pointer
/// gliding along it. The pointer is a rounded star when off (smoothing into
/// a circle as you get in tune), shows the cents and ♯ / ♭ / ♮, spins while
/// it hears sound and slowly stops when it goes quiet, and takes colour by
/// how far off you are. Inspired by the Chronal app's tuner.
class _TunerFace extends StatefulWidget {
  final TunerController tuner;
  final bool solfege;
  const _TunerFace({required this.tuner, required this.solfege});

  @override
  State<_TunerFace> createState() => _TunerFaceState();
}

class _TunerFaceState extends State<_TunerFace> with TickerProviderStateMixin {
  /// Where the pointer sits (cents, springs to each reading).
  late final _cents = AnimationController.unbounded(vsync: this);

  /// Redraws the ruler each frame (nothing else rebuilds).
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  double _spin = 0; // turns
  double _bumps = 0; // how star-shaped (0 = circle)
  Color? _fill;
  Color? _ink;
  bool _hearing = false;

  /// E-ink: the pointer jumps (no spring, spin or wobble), a few redraws
  /// a second.
  bool eink = false;
  DateTime _drawn = DateTime(0);

  @override
  void initState() {
    super.initState();
    widget.tuner.reading.addListener(_onReading);
    _ticker.start();
  }

  @override
  void dispose() {
    widget.tuner.reading.removeListener(_onReading);
    _ticker.dispose();
    _cents.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onReading() {
    final r = widget.tuner.reading.value;
    _hearing = r != null;
    if (r == null) {
      setState(() {});
      return;
    }
    if (eink) {
      if (DateTime.now().difference(_drawn).inMilliseconds < 250) return;
      _drawn = DateTime.now();
      _cents.value = r.pitch.cents.clamp(-50.0, 50.0);
      setState(() {});
      return;
    }
    // A springy glide to the new spot (keeps its current speed).
    _cents.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: 240,
          ratio: 0.82,
        ),
        _cents.value,
        r.pitch.cents.clamp(-50.0, 50.0),
        _cents.velocity,
      ),
    );
    setState(() {}); // the note name
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final scheme = Theme.of(context).colorScheme;
    if (eink) {
      final (fill, ink) = (scheme.onSurface, scheme.surface);
      if (_bumps != 0 || _fill != fill || _cents.value != _drawnAt) {
        _bumps = 0;
        _fill = fill;
        _ink = ink;
        _drawnAt = _cents.value;
        _frame.value++;
      }
      return;
    }
    // Spins while hearing, slowing to a stop over a few seconds of quiet.
    final quiet =
        DateTime.now().difference(widget.tuner.lastHeard).inMilliseconds /
        TunerController.hold.inMilliseconds;
    final energy = _hearing ? math.pow(1 - quiet.clamp(0.0, 1.0), 3) : 0.0;
    _spin += dt * 0.45 * energy;
    // Shape and colour ease toward where the pointer is.
    final c = _cents.value.abs();
    final ease = 1 - math.exp(-dt * 10);
    _bumps += ((_hearing ? (c / 50).clamp(0.0, 1.0) : 0) - _bumps) * ease;
    final (fill, ink) = _colours(scheme, _hearing ? c : null);
    _fill = Color.lerp(_fill ?? fill, fill, ease);
    _ink = Color.lerp(_ink ?? ink, ink, ease);
    _frame.value++;
  }

  /// Pointer colours by how far off: strong in tune, then the accent
  /// tints, then grey.
  static (Color, Color) _colours(ColorScheme s, double? cents) {
    if (cents == null) return (s.surfaceContainerHighest, s.onSurfaceVariant);
    if (cents < 5) return (s.onSurfaceVariant, s.surface);
    if (cents < 20) return (s.primaryContainer, s.onPrimaryContainer);
    if (cents < 30) return (s.tertiaryContainer, s.onTertiaryContainer);
    if (cents < 40) return (s.secondaryContainer, s.onSecondaryContainer);
    return (s.surfaceContainerHighest, s.onSurface);
  }

  double? _drawnAt;

  @override
  Widget build(BuildContext context) {
    eink = isEink(context);
    final scheme = Theme.of(context).colorScheme;
    final p = widget.tuner.reading.value?.pitch;
    final name = p?.name(solfege: widget.solfege);
    final flat = p == null || !(name ?? '').contains('#')
        ? null
        : Pitch(
            p.hz,
            p.midi + 1,
            0,
            1,
          ).name(solfege: widget.solfege).replaceAll('#', '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                name == null ? '–' : name.replaceAll('#', '♯'),
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: name == null
                      ? scheme.outlineVariant
                      : scheme.secondary,
                ),
              ),
              if (p != null)
                Text(
                  '${p.octave}',
                  style: TextStyle(
                    fontSize: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (flat != null) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  width: 1,
                  height: 40,
                  color: scheme.outlineVariant,
                ),
                Text(
                  '$flat♭',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w500,
                    color: scheme.secondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          p == null ? 'Play a note' : '${p.hz.toStringAsFixed(1)} Hz',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (p != null && p.cents.abs() <= 5)
          Text('In tune', style: TextStyle(color: scheme.primary)),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _Ruler(repaint: _frame, state: this, scheme: scheme),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cents ruler (−50 … +50, a tick every 5) and the pointer.
class _Ruler extends CustomPainter {
  final _TunerFaceState state;
  final ColorScheme scheme;
  _Ruler({
    required Listenable repaint,
    required this.state,
    required this.scheme,
  }) : super(repaint: repaint);

  Color _tickColour(int n, bool live) {
    if (!live) return scheme.outlineVariant;
    final a = n.abs();
    if (a < 5) return scheme.onSurfaceVariant;
    if (a < 20) return scheme.primary.withValues(alpha: 0.55);
    if (a < 30) return scheme.tertiary.withValues(alpha: 0.55);
    if (a < 40) return scheme.secondary.withValues(alpha: 0.55);
    return scheme.outlineVariant;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final live = state._hearing;
    const side = 18.0;
    final w = size.width - side * 2;
    double xOf(double cents) => side + (cents + 50) / 100 * w;
    const rulerH = 46.0;
    final base = size.height - 18;

    // Ticks, longest at 0 and ±50, then every 10.
    for (var i = 0; i <= 20; i++) {
      final n = i * 5 - 50;
      final len = n == 0
          ? rulerH * 0.9
          : n.abs() == 50
          ? rulerH
          : n % 10 == 0
          ? rulerH * 0.64
          : rulerH * 0.5;
      final x = xOf(n.toDouble());
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - len),
        Paint()
          ..color = _tickColour(n, live)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
      if (n % 10 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: n > 0 ? '+$n' : '$n',
            style: TextStyle(fontSize: 11, color: _tickColour(n, live)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x - label.width / 2, base + 4));
      }
    }

    // The pointer: a soft 12-pointed star / circle above the ruler.
    final cents = state._cents.value.clamp(-50.0, 50.0);
    const r = 40.0;
    final cx = xOf(cents).clamp(side + r * 0.6, size.width - side - r * 0.6);
    final cy = base - rulerH - r - 10;
    final path = Path();
    const points = 240;
    final depth = 0.04 + 0.11 * state._bumps;
    for (var k = 0; k <= points; k++) {
      final t = k / points * 2 * math.pi;
      final rr =
          r * (1 + depth * math.cos(12 * (t + state._spin * 2 * math.pi)));
      final pt = Offset(cx + rr * math.cos(t), cy + rr * math.sin(t));
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    final fill = state._fill ?? scheme.surfaceContainerHighest;
    final ink = state._ink ?? scheme.onSurfaceVariant;
    canvas.drawPath(path, Paint()..color = fill);
    // A small arrow from the pointer down to its spot on the ruler.
    final tip = Offset(xOf(cents), base - rulerH - 2);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 7, tip.dy - 9)
        ..lineTo(tip.dx + 7, tip.dy - 9)
        ..close(),
      Paint()..color = fill.withValues(alpha: 0.6),
    );
    if (!live) return;
    final c = cents.round();
    final number = TextPainter(
      text: TextSpan(
        text: c > 0 ? '+$c' : '$c',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final sign = TextPainter(
      text: TextSpan(
        text: c > 0
            ? '♯'
            : c < 0
            ? '♭'
            : '♮',
        style: TextStyle(fontSize: 20, color: ink, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = cy - (number.height + sign.height) / 2;
    number.paint(canvas, Offset(cx - number.width / 2, top));
    sign.paint(canvas, Offset(cx - sign.width / 2, top + number.height));
  }

  @override
  bool shouldRepaint(_Ruler old) => old.scheme != scheme;
}

/// A tab in the panel's title (Tuner, Levels).
class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(inkR(999)),
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(inkR(999)),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The Levels tab: the level in big numbers, and a ruler of decibels (or
/// of 0–100 for the plain methods) lit green, amber and red up to the
/// level, with the same round pointer as the tuner gliding along it,
/// showing the level. It spins with the sound, gets spikier the louder it
/// is, and turns red when the sound clips; the peak hangs as a marker.
class _LevelsFace extends StatefulWidget {
  final LevelMeter meter;
  const _LevelsFace({required this.meter});

  @override
  State<_LevelsFace> createState() => _LevelsFaceState();
}

class _LevelsFaceState extends State<_LevelsFace>
    with TickerProviderStateMixin {
  LevelMeter get m => widget.meter;

  /// Where the pointer sits (0…1, springs to each level).
  late final _at = AnimationController.unbounded(vsync: this);
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _spin = 0, _bumps = 0;
  Color? _fill, _ink;

  /// E-ink: black and white, the pointer jumps, a few redraws a second.
  bool eink = false;
  DateTime _drawn = DateTime(0);
  double? _drawnAt;

  @override
  void initState() {
    super.initState();
    m.addListener(_onLevel);
    _ticker.start();
  }

  @override
  void dispose() {
    m.removeListener(_onLevel);
    _ticker.dispose();
    _at.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onLevel() {
    if (eink) {
      final now = DateTime.now();
      if (now.difference(_drawn).inMilliseconds < 250) return;
      _drawn = now;
      _at.value = m.level;
      setState(() {});
      return;
    }
    _at.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 0.8),
        _at.value,
        m.level,
        _at.velocity,
      ),
    );
    setState(() {}); // the big number
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final scheme = Theme.of(context).colorScheme;
    if (eink) {
      if (_fill != scheme.onSurface || _at.value != _drawnAt) {
        _bumps = 0;
        _fill = scheme.onSurface;
        _ink = scheme.surface;
        _drawnAt = _at.value;
        _frame.value++;
      }
      return;
    }
    final l = m.level;
    // Louder: spins faster, and spikier.
    _spin += dt * (0.08 + 0.9 * l * l);
    final ease = 1 - math.exp(-dt * 10);
    _bumps += ((l * 1.1).clamp(0.0, 1.0) - _bumps) * ease;
    final (fill, ink) = _colours(scheme, l, m.clipping, m.method.soundLevelDb);
    _fill = Color.lerp(_fill ?? fill, fill, ease);
    _ink = Color.lerp(_ink ?? ink, ink, ease);
    _frame.value++;
  }

  static const green = Color(0xFF34C759);
  static const amber = Color(0xFFFFB020);
  static const red = Color(0xFFFF3B30);

  /// The colour at [at] (0…1) along the meter: for sound level, amber
  /// from 80 dB (where Apple Watch warns) and red from 95.
  static Color zone(double at, {bool soundLevel = false}) {
    if (soundLevel) {
      final db =
          LevelMeter.soundLow +
          at * (LevelMeter.soundHigh - LevelMeter.soundLow);
      return db < LevelMeter.loud
          ? green
          : db < 95
          ? amber
          : red;
    }
    return at < 0.7
        ? green
        : at < 0.88
        ? amber
        : red;
  }

  static (Color, Color) _colours(
    ColorScheme s,
    double level,
    bool clip,
    bool soundLevel,
  ) {
    if (clip) return (red, Colors.white);
    if (level < 0.02) return (s.surfaceContainerHighest, s.onSurfaceVariant);
    final c = zone(level, soundLevel: soundLevel);
    return (
      Color.lerp(s.surfaceContainerHighest, c, 0.55)!,
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
          ? Colors.white
          : Colors.black87,
    );
  }

  @override
  Widget build(BuildContext context) {
    eink = isEink(context);
    final scheme = Theme.of(context).colorScheme;
    final db = m.method.peakIsDb;
    final everyday = m.method.soundLevelDb;
    final loud = everyday && m.value.round() >= LevelMeter.loud;
    // Under the number: OK / LOUD for sound level (as Apple Watch says),
    // else the method's name.
    var (String note, Color noteColour) = m.clipping
        ? ('Too loud: clipping', red)
        : everyday
        ? (loud ? 'LOUD' : 'OK', loud ? amber : green)
        : (m.method.label, scheme.onSurfaceVariant);
    if (eink) noteColour = scheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          // (Shrinks rather than run off the panel.)
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  m.number,
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: eink
                        ? scheme.onSurface
                        : m.clipping
                        ? red
                        : scheme.secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (db)
                  Text(
                    ' dB',
                    style: TextStyle(
                      fontSize: 22,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  width: 1,
                  height: 40,
                  color: scheme.outlineVariant,
                ),
                Text(
                  LevelMeter.format(m.valueAt(m.peak)),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w500,
                    color: scheme.secondary.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  ' peak',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          note,
          style: TextStyle(
            color: noteColour,
            fontWeight: everyday || m.clipping ? FontWeight.w700 : null,
            letterSpacing: everyday && !m.clipping ? 1.2 : null,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LevelRuler(
                repaint: _frame,
                state: this,
                scheme: scheme,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The levels ruler: ticks from the bottom of the scale (−60 dB, or 0) to
/// full (0 dB, or 100), lit up to the level; the peak; the pointer.
class _LevelRuler extends CustomPainter {
  final _LevelsFaceState state;
  final ColorScheme scheme;
  _LevelRuler({
    required Listenable repaint,
    required this.state,
    required this.scheme,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final m = state.m;
    final everyday = m.method.soundLevelDb;
    const side = 18.0;
    final w = size.width - side * 2;
    double xOf(double at) => side + at.clamp(0.0, 1.0) * w;
    const rulerH = 46.0;
    final base = size.height - 18;
    final level = state._at.value.clamp(0.0, 1.0);
    final peakTick = (m.peak * 24).round();

    // 25 ticks (every 2.5 dB, or 4), labelled every fourth; longest at the
    // ends and at the zones' edges.
    for (var i = 0; i <= 24; i++) {
      final at = i / 24;
      final lit = at <= level + 0.001 && m.on;
      final on = lit || (i == peakTick && m.peak > 0.02);
      // E-ink: lit ticks thick and black, the rest thin.
      final colour = state.eink
          ? scheme.onSurface
          : on
          ? _LevelsFaceState.zone(at, soundLevel: everyday)
          : scheme.outlineVariant;
      final len = i == 0 || i == 24
          ? rulerH
          : i % 4 == 0
          ? rulerH * 0.64
          : rulerH * 0.5;
      final x = xOf(at);
      canvas.drawLine(
        Offset(x, base),
        Offset(x, base - len),
        Paint()
          ..color = colour
          ..strokeWidth = state.eink && !on ? 1 : 3.5
          ..strokeCap = StrokeCap.round,
      );
      if (i % 4 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: LevelMeter.format(m.valueAt(at)),
            style: TextStyle(
              fontSize: 11,
              color: state.eink
                  ? scheme.onSurface
                  : lit
                  ? _LevelsFaceState.zone(at, soundLevel: everyday)
                  : scheme.outline,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x - label.width / 2, base + 4));
      }
    }

    // The pointer: the tuner's soft star, over the level.
    const r = 40.0;
    final cx = xOf(level).clamp(side + r * 0.6, size.width - side - r * 0.6);
    final cy = base - rulerH - r - 10;
    final path = Path();
    const points = 240;
    final depth = 0.04 + 0.11 * state._bumps;
    for (var k = 0; k <= points; k++) {
      final t = k / points * 2 * math.pi;
      final rr =
          r * (1 + depth * math.cos(12 * (t + state._spin * 2 * math.pi)));
      final pt = Offset(cx + rr * math.cos(t), cy + rr * math.sin(t));
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    final fill = state._fill ?? scheme.surfaceContainerHighest;
    final ink = state._ink ?? scheme.onSurfaceVariant;
    canvas.drawPath(path, Paint()..color = fill);
    final tip = Offset(xOf(level), base - rulerH - 2);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 7, tip.dy - 9)
        ..lineTo(tip.dx + 7, tip.dy - 9)
        ..close(),
      Paint()..color = fill.withValues(alpha: 0.6),
    );
    if (!m.on) return;
    final number = TextPainter(
      text: TextSpan(
        text: m.number,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final db = m.method.peakIsDb;
    final unit = TextPainter(
      text: TextSpan(
        text: db ? 'dB' : m.method.label,
        style: TextStyle(fontSize: db ? 16 : 11, color: ink, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = cy - (number.height + unit.height) / 2;
    number.paint(canvas, Offset(cx - number.width / 2, top));
    unit.paint(canvas, Offset(cx - unit.width / 2, top + number.height));
  }

  @override
  bool shouldRepaint(_LevelRuler old) => old.scheme != scheme;
}

/// Under the Levels tab: how it measures (decibels unless chosen
/// otherwise) and its scale.
class _LevelsControls extends StatefulWidget {
  final LevelMeter meter;
  final PresenterModel model;
  const _LevelsControls({required this.meter, required this.model});

  @override
  State<_LevelsControls> createState() => _LevelsControlsState();
}

class _LevelsControlsState extends State<_LevelsControls> {
  LevelMeter get m => widget.meter;

  void _save() => widget.model.updateSettings((s) {
    s.levelsMethod = m.method.name;
    s.levelsScale = m.scale;
    s.levelsCalibration = m.calibration;
  });

  void _calibrate(int by) {
    setState(() => m.calibration = (m.calibration + by).clamp(-30, 30));
    _save();
  }

  void _scaleBy(int steps) {
    // ¼× … 4×, in quarter-octave steps (1× in the middle).
    final e = ((math.log(m.scale) / math.ln2) * 4).round() + steps;
    setState(() => m.scale = math.pow(2, e.clamp(-8, 8) / 4).toDouble());
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: AppDropdown<LevelMethod>(
              value: m.method,
              isDense: true,
              underline: const SizedBox.shrink(),
              isExpanded: true,
              items: [
                for (final method in LevelMethod.values)
                  DropdownMenuItem(
                    value: method,
                    child: Text(method.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => m.method = v);
                _save();
              },
            ),
          ),
          const SizedBox(width: 8),
          if (m.method.soundLevelDb) ...[
            // Microphones differ: match a sound meter or a watch. (The
            // word goes on narrow phones; the buttons say it.)
            if (MediaQuery.sizeOf(context).width >= 420)
              Tooltip(
                message:
                    'If your watch or a sound meter reads differently, '
                    'adjust until they match',
                child: Text(
                  'Calibrate',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            IconButton(
              tooltip: 'Read lower',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: m.calibration > -30 ? () => _calibrate(-1) : null,
            ),
            Text(
              '${m.calibration >= 0 ? '+' : '−'}${m.calibration.abs()} dB',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Read higher',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: m.calibration < 30 ? () => _calibrate(1) : null,
            ),
          ] else ...[
            Text('Scale', style: TextStyle(color: scheme.onSurfaceVariant)),
            IconButton(
              tooltip: 'Less',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 18),
              onPressed: m.scale > 0.26 ? () => _scaleBy(-1) : null,
            ),
            Text(
              '${m.scale.toStringAsFixed(m.scale < 1 ? 2 : 1)}×',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'More',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 18),
              onPressed: m.scale < 3.9 ? () => _scaleBy(1) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  final _MicState state;
  final String? detail;
  const _Problem({required this.state, this.detail});

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (state) {
      _MicState.denied => (
        Icons.mic_off_outlined,
        'Microphone access was turned down. Allow it for this app (in the '
            "browser's address bar or the system settings), then open the "
            'tuner again.',
      ),
      _MicState.blocked => (
        Icons.mic_off_outlined,
        'Your computer is keeping the microphone from this browser. On a '
            'Mac: System Settings → Privacy & Security → Microphone, turn '
            'on your browser (e.g. Zen), then quit and reopen it. On '
            'Windows: Settings → Privacy → Microphone.',
      ),
      _MicState.insecure => (
        Icons.lock_outline,
        'Browsers only allow the microphone on a secure page. Open the app '
            'on this computer (localhost) or over https to use the tuner '
            'here. The installed app version doesn\'t have this limit.',
      ),
      _ => (
        Icons.error_outline,
        'Couldn\'t start the microphone. Check that one is connected and '
            'not in use by another app.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
