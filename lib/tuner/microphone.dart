import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../browser.dart';
import 'pitch.dart';

/// The microphone as a stream of samples (−1…1, mono). In a browser it is
/// opened directly with the fewest possible demands; installed apps
/// (Android, iOS, macOS, Windows, Linux) use the `record` plugin, which
/// also asks for permission (the native permission entries are already in
/// the platform folders).
class Microphone {
  /// Samples per second (the device's own rate in a browser).
  int sampleRate = 44100;
  WebMic? _web;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final _out = StreamController<Float32List>.broadcast();

  Stream<Float32List> get samples => _out.stream;

  /// Starts listening. False when the user (or the browser) says no.
  Future<bool> start() async {
    if (kIsWeb) {
      try {
        final mic = await openWebMic(_out.add);
        _web = mic;
        sampleRate = mic.sampleRate;
        return true;
      } catch (e) {
        throw StateError(
          'Opening the microphone: $e (${await describeAudioInputs()})',
        );
      }
    }
    final bool allowed;
    try {
      allowed = await _recorder.hasPermission();
    } catch (e) {
      throw StateError('Asking for the microphone: $e');
    }
    if (!allowed) return false;
    // Android's default source turns quiet sounds up and loud ones down
    // (whatever autoGain says), which squeezes the levels meter: the raw
    // one if the phone has it, else voice recognition (kept level too).
    const sources = [
      AndroidAudioSource.unprocessed,
      AndroidAudioSource.voiceRecognition,
      AndroidAudioSource.defaultSource,
    ];
    Stream<Uint8List>? bytes;
    Object? error;
    for (final source in sources) {
      try {
        bytes = await _recorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: sampleRate,
            numChannels: 1,
            // Processing meant for voice calls bends the pitch: off.
            autoGain: false,
            echoCancel: false,
            noiseSuppress: false,
            androidConfig: AndroidRecordConfig(audioSource: source),
          ),
        );
        break;
      } catch (e) {
        error = e;
        if (defaultTargetPlatform != TargetPlatform.android) break;
      }
    }
    if (bytes == null) throw StateError('Starting the microphone: $error');
    var carry = <int>[];
    _sub = bytes.listen((chunk) {
      // 16-bit little-endian samples; a chunk can end mid-sample.
      final data = carry.isEmpty ? chunk : Uint8List.fromList(carry + chunk);
      final whole = data.length & ~1;
      carry = data.sublist(whole);
      final view = ByteData.sublistView(data, 0, whole);
      final out = Float32List(whole ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = view.getInt16(i * 2, Endian.little) / 32768;
      }
      _out.add(out);
    });
    return true;
  }

  Future<void> stop() async {
    _web?.stop();
    _web = null;
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    if (!kIsWeb) await _recorder.dispose();
    await _out.close();
  }
}

/// What the tuner shows: the note heard, or null while nothing clear is
/// playing.
class TunerReading {
  final Pitch pitch;
  const TunerReading(this.pitch);
}

/// Turns a stream of samples into tuner readings: about 20 a second, close
/// readings averaged (steady), a new note followed at once, and the last
/// note held for a few seconds after the sound stops.
class TunerController {
  /// Samples per second of what's fed in (set once the mic is open).
  int sampleRate;
  double a4;
  final PitchDetector detector;

  /// The latest reading (null = nothing heard for a while).
  final reading = ValueNotifier<TunerReading?>(null);

  /// When a pitch was last heard (drives the pointer's spin).
  DateTime lastHeard = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long the last note stays up after the sound stops.
  static const hold = Duration(seconds: 5);

  // Analysed at about 22–24 kHz (pairs of samples averaged when the
  // microphone runs faster): plenty for any instrument, half the work.
  static const _size = 4096;
  final _buffer = Float32List(_size);
  var _filled = 0;
  var _sinceLast = 0;
  var _half = false;
  double? _pending;
  var _quietSamples = 0;
  double? _hz;
  var _lastAt = 0; // in analysed samples

  TunerController({
    required this.sampleRate,
    this.a4 = 440,
    this.detector = const PitchDetector(),
  });

  StreamSubscription<Float32List>? _sub;

  void listen(Stream<Float32List> samples) {
    _sub?.cancel();
    _sub = samples.listen(add);
  }

  /// Stops listening (the tuner was switched off).
  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  int get _rate => sampleRate > 30000 ? sampleRate ~/ 2 : sampleRate;

  void _push(double s) {
    _buffer[_filled % _size] = s;
    _filled++;
    _sinceLast++;
  }

  /// Feeds samples in.
  void add(Float32List chunk) {
    final halve = sampleRate > 30000;
    for (final s in chunk) {
      if (!halve) {
        _push(s);
      } else if (_half) {
        _push((_pending! + s) / 2);
        _half = false;
      } else {
        _pending = s;
        _half = true;
      }
      if (_filled >= _size && _sinceLast >= _rate ~/ 20) {
        _sinceLast = 0;
        _analyse();
      }
    }
  }

  void _analyse() {
    final start = _filled % _size;
    final window = Float32List(_size)
      ..setRange(0, _size - start, _buffer, start)
      ..setRange(_size - start, _size, _buffer);
    final p = detector.detect(window, _rate, a4: a4);
    if (p == null) {
      _quietSamples += _rate ~/ 20;
      if (_hz != null && _quietSamples > _rate * hold.inSeconds) {
        _hz = null;
        reading.value = null;
      }
      return;
    }
    _quietSamples = 0;
    // Close to the last reading and soon after it: average (steady
    // needle). Otherwise a new note: go straight there.
    final recent = _filled - _lastAt < _rate ~/ 8;
    final near =
        _hz != null && (12 * math.log(p.hz / _hz!) / math.ln2).abs() < 0.5;
    _hz = recent && near ? (_hz! + p.hz) / 2 : p.hz;
    _lastAt = _filled;
    lastHeard = DateTime.now();
    reading.value = TunerReading(
      Pitch.fromHz(_hz!, a4: a4, clarity: p.clarity),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    reading.dispose();
  }
}
