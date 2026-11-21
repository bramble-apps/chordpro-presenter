// The key finder: listens through the microphone while you sing or play
// (piano, guitar, anything) and shows the key it hears, drawn like the
// tuner: the key in big letters, a "how sure" ruler with the tuner's round
// pointer, and the notes heard as bars, the key's own notes lit.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../browser.dart';
import '../eink.dart';
import '../music.dart';
import '../tuner/key_detect.dart';
import '../tuner/microphone.dart';
import 'tuner_panel.dart' show MicProblem, MicState;
import '../bramble_icons.dart';

/// The key finder page. [written] is the song's key (to offer moving the
/// song to the key heard); [onUse] gets the semitones to transpose by.
class KeyFinderView extends StatefulWidget {
  final double size;
  final MusicKey? written;
  final int transpose;
  final ValueChanged<int> onUse;

  /// For tests: samples to listen to instead of the microphone.
  final Stream<Float32List>? debugSamples;
  final int debugRate;

  const KeyFinderView({
    super.key,
    required this.size,
    required this.written,
    required this.transpose,
    required this.onUse,
    this.debugSamples,
    this.debugRate = 44100,
  });

  @override
  State<KeyFinderView> createState() => _KeyFinderViewState();
}

/// The major key (or the relative major of a minor one): two keys with the
/// same notes give the same number.
int _shared(MusicKey k) => k.minor ? (k.root + 3) % 12 : k.root;

class _KeyFinderViewState extends State<KeyFinderView> {
  Microphone? _mic;
  late final KeyListener _listener = KeyListener(sampleRate: widget.debugRate);
  var _state = MicState.starting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final test = widget.debugSamples;
    if (test != null) {
      _listener.listen(test);
      setState(() => _state = MicState.listening);
      return;
    }
    if (!micAllowedHere) {
      setState(() => _state = MicState.insecure);
      return;
    }
    try {
      final mic = _mic = Microphone();
      final ok = await mic.start();
      if (!mounted) return;
      if (!ok) {
        setState(() => _state = MicState.denied);
        return;
      }
      _listener
        ..sampleRate = mic.sampleRate
        ..listen(mic.samples);
      setState(() => _state = MicState.listening);
    } catch (e) {
      debugLog('key finder failed: $e');
      if (mounted) {
        final text = '$e';
        setState(() {
          _state = text.contains('NotFoundError') || text.contains('NotAllowedError')
              ? MicState.blocked
              : MicState.failed;
          _error = text;
        });
      }
    }
  }

  @override
  void dispose() {
    // stop listening as soon as the page closes
    _mic?.dispose();
    _listener.dispose();
    super.dispose();
  }

  /// Semitones that move the song to the key heard (from where it is now
  /// to the same key or its relative minor / major), −6…5.
  int? _offsetFor(MusicKey heard) {
    final w = widget.written;
    if (w == null) return null;
    final d = (_shared(heard) - _shared(w) + 12) % 12;
    return d > 5 ? d - 12 : d;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (_state == MicState.starting) {
      return SizedBox(width: size, height: size * .8, child: const Center(child: AppSpinner()));
    }
    if (_state != MicState.listening) {
      return SizedBox(width: size, child: MicProblem(state: _state, detail: _error));
    }
    return SizedBox(
      width: size,
      child: ValueListenableBuilder<KeyGuess?>(
        valueListenable: _listener.guess,
        builder: (context, guess, _) => _face(context, guess),
      ),
    );
  }

  Widget _face(BuildContext context, KeyGuess? guess) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = isEink(context);
    final d = motion(context, const Duration(milliseconds: 280));
    final offset = guess == null ? null : _offsetFor(guess.key);
    final target = offset == null ? null : widget.written!.transposed(offset);
    final already = offset != null && offset == widget.transpose;
    final scale = guess == null
        ? const <int>{}
        : {
            for (final i in guess.key.minor ? const [0, 2, 3, 5, 7, 8, 10] : const [0, 2, 4, 5, 7, 9, 11])
              (guess.key.root + i) % 12,
          };
    const names = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        // the key heard, big (or the listening light until there's enough)
        SizedBox(
          height: 92,
          child: Center(
            child: guess == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: _listener.level,
                        builder: (context, level, _) => AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 44 + 16 * level,
                          height: 44 + 16 * level,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ink
                                ? scheme.surface
                                : scheme.primary.withValues(alpha: .12 + .3 * level),
                            border: ink ? Border.all(color: scheme.onSurface, width: inkW(2)) : null,
                          ),
                          child: Icon(BrambleIcons.microphoneFill, color: ink ? scheme.onSurface : scheme.primary),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sing or play a few bars',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        MusicKey(guess.key.root, false).name,
                        key: const ValueKey('key-finder-key'),
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            guess.key.minor ? 'minor' : 'major',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'or ${guess.runnerUp.name}',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        // how sure: a ruler with the tuner's round pointer gliding along it
        _SureRuler(sure: guess?.sure ?? 0, duration: d),
        const SizedBox(height: 14),
        // the notes heard; the key's own notes lit
        SizedBox(
          height: 70,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 12; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: d,
                          curve: Curves.easeOut,
                          height: 4 + 44 * (guess?.notes[i] ?? 0),
                          decoration: BoxDecoration(
                            color: scale.contains(i)
                                ? (ink ? scheme.onSurface : scheme.primary)
                                : (ink ? scheme.surface : scheme.outlineVariant),
                            border: ink ? Border.all(color: scheme.onSurface, width: inkW(1)) : null,
                            borderRadius: BorderRadius.circular(inkR(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          names[i],
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: guess != null && i == guess.key.root ? FontWeight.w700 : FontWeight.w400,
                            color: scale.contains(i) ? scheme.onSurface : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: guess == null ? null : () => setState(_listener.reset),
              icon: const Icon(BrambleIcons.arrowsClockwise, size: 18),
              label: const Text('Start over'),
            ),
            const Spacer(),
            if (target != null)
              FilledButton(
                key: const ValueKey('key-finder-use'),
                onPressed: already ? null : () => widget.onUse(offset!),
                child: Text(already ? 'In ${target.name}' : 'Use ${target.name}'),
              ),
          ],
        ),
      ],
    );
  }
}

/// How sure the key finder is: a ruler from "guessing" to "sure", filled up
/// to the pointer (a round dot, like the tuner's).
class _SureRuler extends StatelessWidget {
  final double sure;
  final Duration duration;
  const _SureRuler({required this.sure, required this.duration});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = isEink(context);
    final colour = ink
        ? scheme.onSurface
        : Color.lerp(scheme.tertiary, scheme.primary, sure.clamp(0.0, 1.0))!;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: sure.clamp(0.0, 1.0)),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            height: 26,
            child: CustomPaint(
              size: const Size(double.infinity, 26),
              painter: _SurePainter(t, colour, scheme, ink),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text('Guessing', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text('Sure', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _SurePainter extends CustomPainter {
  final double t;
  final Color colour;
  final ColorScheme scheme;
  final bool ink;
  _SurePainter(this.t, this.colour, this.scheme, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    const r = 11.0;
    final y = size.height / 2;
    final x0 = r, x1 = size.width - r;
    // ticks
    for (var i = 0; i <= 20; i++) {
      final x = x0 + (x1 - x0) * i / 20;
      final big = i % 5 == 0;
      canvas.drawLine(
        Offset(x, y - (big ? 7 : 4)),
        Offset(x, y + (big ? 7 : 4)),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = big ? 1.5 : 1,
      );
    }
    // the track, lit up to the pointer
    final at = x0 + (x1 - x0) * t;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(x0, y), Offset(at, y), Paint()
      ..color = colour
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    // the pointer
    canvas.drawCircle(Offset(at, y), r, Paint()..color = ink ? scheme.surface : colour);
    if (ink) {
      canvas.drawCircle(Offset(at, y), r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.onSurface);
    }
  }

  @override
  bool shouldRepaint(_SurePainter o) => o.t != t || o.colour != colour || o.ink != ink;
}

/// The key menu: the key wheel, with a microphone button that turns the
/// panel into the key finder (and a back arrow to return).
class KeyMenu extends StatefulWidget {
  final Widget Function(double size) wheel;
  final Widget Function(double size, VoidCallback back) finder;
  final Widget Function({required String title, required List<Widget> actions, required Widget Function(double) builder}) frame;
  const KeyMenu({super.key, required this.wheel, required this.finder, required this.frame});

  @override
  State<KeyMenu> createState() => _KeyMenuState();
}

class _KeyMenuState extends State<KeyMenu> {
  var _finding = false;

  @override
  Widget build(BuildContext context) {
    void back() => setState(() => _finding = false);
    return widget.frame(
      title: _finding ? 'Find the key' : 'Key',
      actions: [
        if (_finding)
          IconButton(
            tooltip: 'Back to the key wheel',
            icon: const Icon(BrambleIcons.arrowLeft),
            onPressed: back,
          )
        else
          IconButton(
            key: const ValueKey('key-finder-open'),
            tooltip: 'Find the key by ear (sing or play)',
            icon: const Icon(BrambleIcons.microphone),
            onPressed: () => setState(() => _finding = true),
          ),
      ],
      builder: (size) => _finding ? widget.finder(size, back) : widget.wheel(size),
    );
  }
}
