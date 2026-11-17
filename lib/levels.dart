// The levels meter (the tuner panel's Levels tab): how loud the
// microphone hears the room or the band. By default as sound level, the
// everyday decibels Apple Watch shows (about 30 in a quiet room, 60 for
// talking, 80 and up loud), averaged over a moment; sound techs can pick
// other ways to measure (decibels below full scale, RMS…).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How a block of samples becomes one level.
enum LevelMethod {
  // Everyday decibels, like Apple Watch: the usual one.
  soundLevel(
    'Sound level (dB)',
    'Like Apple Watch: about 30 quiet, 60 talking, 80 and up loud',
  ),
  // More, for sound techs.
  dbfsRms('dBFS (average)', 'Below the microphone’s maximum: 0 is the most'),
  dbfs('dBFS (peak)', 'The loudest moments, below the maximum'),
  peak('Max', 'Loudest sample'),
  sqrtRms('√RMS', 'Square root of the RMS (more movement when quiet)'),
  rms('RMS', 'Root mean square: the average power'),
  logRms('Log RMS', 'RMS on a log scale'),
  avg('Avg', 'Average of the samples’ size');

  final String label;
  final String description;
  const LevelMethod(this.label, this.description);

  /// Measured in decibels below the microphone's maximum (negative).
  bool get decibels => this == dbfs || this == dbfsRms;

  /// Everyday sound level (positive decibels).
  bool get soundLevelDb => this == soundLevel;

  /// Measured in decibels at all (either kind).
  bool get peakIsDb => decibels || soundLevelDb;
}

/// The level of [samples] by [method]: decibels (−∞…0) for the dB ones,
/// else 0…1.
double measureLevel(Float32List samples, LevelMethod method) {
  if (samples.isEmpty) return method.peakIsDb ? -120 : 0;
  var peak = 0.0, sumSq = 0.0, sumAbs = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
    sumSq += s * s;
    sumAbs += a;
  }
  final rms = math.sqrt(sumSq / samples.length);
  double db(double v) => v <= 1e-6 ? -120 : 20 * math.log(v) / math.ln10;
  return switch (method) {
    LevelMethod.dbfs => db(peak),
    LevelMethod.dbfsRms || LevelMethod.soundLevel => db(rms),
    LevelMethod.peak => peak,
    LevelMethod.rms => rms,
    LevelMethod.sqrtRms => math.sqrt(rms),
    LevelMethod.logRms => math.log(1 + 99 * rms) / math.log(100),
    LevelMethod.avg => sumAbs / samples.length,
  };
}

/// The meter: listens while on, [level] (0…1, smoothed) and [peak] for
/// drawing, [value] for the number shown.
class LevelMeter extends ChangeNotifier {
  LevelMethod method;

  /// Gain before the display (0.25×–4×): more for a quiet room.
  double scale;

  /// Sound level: decibels added so the reading matches a sound meter or
  /// a watch (microphones differ).
  int calibration;

  LevelMeter({
    this.method = LevelMethod.soundLevel,
    this.scale = 1,
    this.calibration = 0,
  });

  /// Sound level = A-weighted decibels below the microphone's maximum +
  /// this, + [calibration]. Android asks microphones for about −22 dBFS
  /// at 90 dB (its voice recognition / unprocessed sources); laptops at
  /// a sensible input level are close.
  static const soundOffset = 112.0;

  /// Samples per second of what [add] gets (for the A-weighting).
  int sampleRate = 48000;

  AWeighting? _weighting;

  /// The sound-level scale: 30 dB (a quiet room) to 120 (painfully loud).
  static const soundLow = 30.0, soundHigh = 120.0;

  /// Where it gets loud (Apple Watch warns from 80 dB).
  static const loud = 80.0;

  /// Sound level: the power averaged over about half a second.
  double _power = 0;

  StreamSubscription<Float32List>? _sub;

  /// Listening (to the tuner's microphone).
  bool on = false;

  /// What the meter shows: 0…1 (smoothed), the held peak, the raw value
  /// (dB for the dB methods, else 0…1), and a clip warning.
  double level = 0, peak = 0, value = 0;
  bool clipping = false;

  DateTime _peakAt = DateTime(0);
  DateTime _clipAt = DateTime(0);
  DateTime _lastNotify = DateTime(0);
  DateTime _lastAdd = DateTime.now();

  /// The decibels shown across the meter: −60 dB at the bottom.
  static const floorDb = -60.0;

  /// Listens to [samples] (the microphone the tuner opened).
  void listen(Stream<Float32List> samples) {
    _sub?.cancel();
    _sub = samples.listen(add);
    on = true;
    notifyListeners();
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    on = false;
    _power = 0;
    _weighting = null;
    level = peak = value = 0;
    clipping = false;
    notifyListeners();
  }

  /// One block of samples (also fed directly by tests).
  void add(Float32List samples) {
    final now = DateTime.now();
    final raw = measureLevel(samples, method);
    // Gain: a multiple for the plain ones, decibels added for the dB ones.
    final gainDb = 20 * math.log(scale) / math.ln10;
    final dt = now.difference(_lastAdd).inMicroseconds / 1e6;
    _lastAdd = now;
    if (method.soundLevelDb) {
      // A-weighted like a sound meter (and Apple Watch): the rumble of
      // fans and traffic counts as little as the ear hears it. Averaged
      // over about half a second, so the number is steady.
      final w = _weighting?.sampleRate == sampleRate
          ? _weighting!
          : _weighting = AWeighting(sampleRate);
      var sumSq = 0.0;
      for (final s in w.filter(samples)) {
        sumSq += s * s;
      }
      final ms = samples.isEmpty ? 0.0 : sumSq / samples.length;
      final a = (dt.clamp(0.0, 0.5) / (0.5 + dt.clamp(0.0, 0.5)));
      _power = _power == 0 ? ms : _power + (ms - _power) * a;
      final db = _power <= 1e-12 ? -120.0 : 10 * math.log(_power) / math.ln10;
      value = math.max(0, db + soundOffset + calibration);
      level = ((value - soundLow) / (soundHigh - soundLow)).clamp(0.0, 1.0);
    } else {
      value = method.decibels ? raw + gainDb : raw * scale;
      final target = method.decibels
          ? ((value - floorDb) / -floorDb).clamp(0.0, 1.0)
          : value.clamp(0.0, 1.0);
      // Up at once, down gently (about a second from full to nothing).
      level = target > level
          ? target
          : math.max(target, level - dt.clamp(0.0, 0.2) * 1.2);
    }
    if (level >= peak || now.difference(_peakAt).inMilliseconds > 1200) {
      // A new peak, or the old one held long enough: it falls.
      if (level >= peak) {
        peak = level;
        _peakAt = now;
      } else {
        peak = math.max(level, peak - dt.clamp(0.0, 0.2) * 0.6);
      }
    }
    // Clipping: the samples themselves touching full scale.
    var loud = 0.0;
    for (final s in samples) {
      if (s.abs() > loud) loud = s.abs();
    }
    if (loud >= 0.99) _clipAt = now;
    final wasClipping = clipping;
    clipping = now.difference(_clipAt).inMilliseconds < 800;
    // About 30 updates a second is plenty for the eye (a clip shows at
    // once).
    if (clipping != wasClipping ||
        now.difference(_lastNotify).inMilliseconds >= 30) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// The reading as shown, without its unit: "72", "−18" or "42".
  String get number {
    if (method.decibels && value <= -100) return '−∞';
    return format(method.peakIsDb ? value : value * 100);
  }

  /// The reading at [at] (0…1) along the meter's scale.
  double valueAt(double at) => method.soundLevelDb
      ? soundLow + at * (soundHigh - soundLow)
      : method.decibels
      ? floorDb * (1 - at)
      : at * 100;

  /// [v] rounded, with a proper minus sign.
  static String format(double v) => '${v.round()}'.replaceAll('-', '−');

  /// The number shown: "72 dB", "−18 dB" or "42" (out of 100).
  String get readout {
    if (!on) return '';
    if (method.soundLevelDb) return '${value.round()} dB';
    if (method.decibels) {
      return value <= -100
          ? '−∞ dB'
          : '${value.round()} dB'.replaceAll('-', '−');
    }
    return '${(value * 100).round()}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// The A-weighting filter (IEC 61672): how much each pitch counts, as the
/// ear hears it at everyday levels (0 dB at 1 kHz, −26 dB at 63 Hz).
/// Six first-order sections from the standard's poles, by the bilinear
/// transform.
class AWeighting {
  final int sampleRate;
  final List<(double, double, double)> _sections = [];
  late final List<double> _x1, _y1;
  double _gain = 1;

  AWeighting(this.sampleRate) {
    final k = 2.0 * sampleRate;
    for (final (f, high) in const [
      (20.598997, true),
      (20.598997, true),
      (107.65265, true),
      (737.86223, true),
      (12194.217, false),
      (12194.217, false),
    ]) {
      final w = 2 * math.pi * f, d = k + w;
      _sections.add(
        high ? (k / d, -k / d, (w - k) / d) : (w / d, w / d, (w - k) / d),
      );
    }
    _x1 = List.filled(_sections.length, 0);
    _y1 = List.filled(_sections.length, 0);
    _gain = 1 / response(1000);
  }

  /// The filter's gain (unnormalised until built) at [hz].
  double response(double hz) {
    final t = 2 * math.pi * hz / sampleRate;
    // z⁻¹ = cos t − i sin t.
    final zr = math.cos(t), zi = -math.sin(t);
    var re = _gain, im = 0.0;
    for (final (b0, b1, a1) in _sections) {
      final nr = b0 + b1 * zr, ni = b1 * zi;
      final dr = 1 + a1 * zr, di = a1 * zi;
      final dd = dr * dr + di * di;
      final hr = (nr * dr + ni * di) / dd, hi = (ni * dr - nr * di) / dd;
      (re, im) = (re * hr - im * hi, re * hi + im * hr);
    }
    return math.sqrt(re * re + im * im);
  }

  /// [samples] weighted (the filter remembers across calls).
  Float32List filter(Float32List samples) {
    final out = Float32List(samples.length);
    for (var n = 0; n < samples.length; n++) {
      var v = samples[n].toDouble();
      for (var i = 0; i < _sections.length; i++) {
        final (b0, b1, a1) = _sections[i];
        final y = b0 * v + b1 * _x1[i] - a1 * _y1[i];
        _x1[i] = v;
        _y1[i] = y;
        v = y;
      }
      out[n] = v * _gain;
    }
    return out;
  }
}
