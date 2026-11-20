import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../abc.dart';
import '../browser.dart';
import '../fonts.dart';
import '../pads/sf2.dart';
import '../scanner/engrave.dart';
import '../scanner/playback.dart';
import '../scanner/score.dart';
import '../eink.dart';

/// An ABC tune on the chord sheet: drawn as music by the sheet music
/// scanner's engraver, with a play button (the scanner's grand piano) that
/// lights each note as it sounds. A tune that can't be read shows as typed.
class AbcView extends StatefulWidget {
  final List<String> lines;
  final TextStyle style;
  final Color ink, accent;

  /// The song's tempo, for tunes without a Q: field.
  final int bpm;

  const AbcView({
    super.key,
    required this.lines,
    required this.style,
    required this.ink,
    required this.accent,
    this.bpm = 100,
  });

  @override
  State<AbcView> createState() => _AbcViewState();
}

class _AbcViewState extends State<AbcView> with SingleTickerProviderStateMixin {
  late String _text = widget.lines.join('\n');
  late Score? _score = _read();
  late final Ticker _ticker = createTicker(_tick);

  ScoreLayout? _layout;
  double _layoutWidth = 0;

  /// The sound, made once per tune (and tempo).
  Float32List? _audio;
  String? _audioKey;
  Performance? _perf;
  bool _playing = false, _preparing = false;
  Set<int> _lit = const {};

  /// The sampled piano, shared by every tune.
  static PadSound? _piano;

  Score? _read() {
    final s = parseAbc(_text);
    if (s != null && !RegExp(r'^\s*Q:', multiLine: true).hasMatch(_text)) {
      s.tempo = widget.bpm;
    }
    return s;
  }

  @override
  void didUpdateWidget(AbcView old) {
    super.didUpdateWidget(old);
    final text = widget.lines.join('\n');
    if (text != _text || old.bpm != widget.bpm) {
      _stop();
      _text = text;
      _score = _read();
      _layout = null;
      _audio = null;
      _perf = null;
    }
  }

  @override
  void dispose() {
    if (_playing) stopSound();
    _ticker.dispose();
    super.dispose();
  }

  PlaySettings get _settings => PlaySettings(tempo: _score!.tempo);

  Future<void> _play() async {
    final score = _score;
    if (score == null) return;
    if (_playing) {
      _stop();
      return;
    }
    final key = '${score.tempo} $_text';
    if (_audio == null || _audioKey != key) {
      setState(() => _preparing = true);
      try {
        _piano ??= PadSound.decode(
          (await rootBundle.load('assets/sounds/piano.pad')).buffer
              .asUint8List(),
        );
      } catch (_) {
        // No sampled piano (tests): the built-in one plays.
      }
      // Let the spinner show before the work.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final perf = _perf = perform(score, _settings);
      _audio = render(score, perf, _settings, sounds: {grandPiano: ?_piano});
      _audioKey = key;
      if (!mounted) return;
      setState(() => _preparing = false);
    }
    playSound(_audio!, playbackRate);
    setState(() => _playing = true);
    _ticker
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final perf = _perf;
    if (perf == null) return;
    // (Real time: animations may be sped up, see setEink.)
    final q =
        elapsed.inMicroseconds * timeDilation / 1e6 / (60 / _score!.tempo);
    if (q > perf.length + 0.25) {
      _stop();
      return;
    }
    // (only when the notes sounding change, not on every frame)
    final lit = {
      for (final n in perf.notes)
        if (n.start <= q && q < n.start + n.length) n.note,
    };
    if (!setEquals(lit, _lit)) setState(() => _lit = lit);
  }

  void _stop() {
    if (_playing) stopSound();
    if (_ticker.isActive) _ticker.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _lit = const {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    if (score == null) {
      // Not readable as music: the text as typed.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _text,
          style: TextStyle(
            fontFamily: FontOption('cousine', '').family,
            fontFamilyFallback: const ['monospace'],
            fontSize: (widget.style.fontSize ?? 16) * 0.9,
            color: widget.ink,
          ),
        ),
      );
    }
    // Staff size follows the sheet's text size.
    final space = ((widget.style.fontSize ?? 16) * 0.45).clamp(5.0, 14.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (_layout == null ||
                    _layoutWidth != c.maxWidth ||
                    _layout!.space != space) {
                  _layoutWidth = c.maxWidth;
                  _layout = ScoreLayout(score, c.maxWidth, space: space);
                }
                final layout = _layout!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (score.title.isNotEmpty)
                      Text(
                        score.title,
                        style: widget.style.copyWith(
                          fontStyle: FontStyle.italic,
                          color: widget.ink.withValues(alpha: 0.75),
                        ),
                      ),
                    SizedBox(
                      width: c.maxWidth,
                      height: layout.height,
                      child: CustomPaint(
                        painter: ScorePainter(
                          layout,
                          ink: widget.ink,
                          accent: widget.accent,
                          lit: _lit,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _preparing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: AppSpinner(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: _playing ? 'Stop' : 'Play this tune',
                  visualDensity: VisualDensity.compact,
                  color: widget.accent,
                  icon: Icon(
                    _playing
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  onPressed: _play,
                ),
        ],
      ),
    );
  }
}
