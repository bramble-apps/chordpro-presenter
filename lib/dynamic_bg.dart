// Dynamic backgrounds: moving wallpapers for the projector, ported from
// Keydeck (bramble-office/keynote-linux): the model from
// crates/kn-model/src/motionbg.rs, the renderer from
// crates/kn-render/src/motion.rs, the controls from
// crates/kn-app/src/inspector.rs. Keep the numbers the same as there.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

part 'dynamic_bg_presets.dart';

/// One colour of a background's "Colors" bar, at [at] (0…1) along it.
class DynamicStop {
  final double at;
  final Color color;
  const DynamicStop(this.at, this.color);
}

/// A built-in dynamic background, as Keydeck's theme stores it.
class DynamicPreset {
  final String name;

  /// Which renderer draws it: KNGradientLinearBase, KNGradientTerrainBase,
  /// KNGradientTerrainFlyover, KNGradientDiffusionBase, KNWavesBase,
  /// KNWavesSymmetrical, KNGraphicSpheresBase.
  final String family;
  final List<DynamicStop> colors;
  final Map<String, double> nums;

  /// Waves: the colour behind them.
  final Color? background;
  final String? blendMode;

  const DynamicPreset({
    required this.name,
    required this.family,
    required this.colors,
    required this.nums,
    this.background,
    this.blendMode,
  });
}

/// One slider of a dynamic background.
class DynamicControl {
  final String label;

  /// The property it sets.
  final String prop;
  final double min, max;

  /// Decimals shown; the − / + buttons step by 1 with none, else by 0.1.
  final int decimals;
  final String suffix;
  const DynamicControl(
    this.label,
    this.prop,
    this.min,
    this.max,
    this.decimals, [
    this.suffix = '',
  ]);

  double get step => decimals == 0 ? 1 : 0.1;

  /// Used while the background doesn't set the property.
  double get fallback => (min + max) / 2;

  /// "33.7°", "5" (whole numbers without decimals).
  String format(double v) {
    final whole = decimals == 0 || (v - v.truncateToDouble()).abs() < 1e-9;
    return '${v.toStringAsFixed(whole ? 0 : decimals)}$suffix';
  }
}

/// The sliders each renderer has (Keydeck's `motion_controls`).
List<DynamicControl> dynamicControls(String family) => switch (family) {
  'KNGradientTerrainBase' => const [
    DynamicControl('Speed', 'noise_speed', 0, 100, 2),
    DynamicControl('Height', 'noise_amplitude', 0, 10, 2),
    DynamicControl('Peaks', 'noise_scale_horizontal', 0.01, 10, 2),
  ],
  'KNGradientTerrainFlyover' => const [
    DynamicControl('Movement', 'noise_movement', -100, 100, 0),
    DynamicControl('Height', 'noise_amplitude', 0, 10, 2),
    DynamicControl('Peaks', 'noise_scale_horizontal', 0.01, 10, 2),
  ],
  'KNGradientDiffusionBase' => const [
    DynamicControl('Speed', 'noise_speed', 0, 5, 2),
    DynamicControl('Complexity', 'noise_octaves_iterations', 1, 8, 0),
    DynamicControl('Frequency', 'scale', 0.1, 5, 2),
  ],
  'KNWavesBase' || 'KNWavesSymmetrical' => const [
    DynamicControl('Speed', 'speed', 0, 100, 0),
    DynamicControl('Amplitude', 'amplitude', 0, 10, 2),
    DynamicControl('Wavelength', 'scale', 0.1, 10, 2),
    DynamicControl('Focus', 'blur', 0, 10, 2),
  ],
  'KNGraphicSpheresBase' => const [
    DynamicControl('Speed', 'speed', 0, 100, 0),
    DynamicControl('Complexity', 'noise_scale', 0, 10, 2),
    DynamicControl('Pattern', 'offset', 0, 10, 2),
  ],
  _ => const [
    DynamicControl('Angle', 'angle', 0, 360, 1, '°'),
    DynamicControl('Scale', 'scale', 0.1, 5, 2),
    DynamicControl('Speed', 'speed', 0, 100, 2),
  ],
};

/// Whole-number properties (Keydeck's `INTS`).
const _intProps = {
  'random_number_seed',
  'pixels_per_division',
  'instance_count',
  'noise_octaves_iterations',
};

/// The projector's dynamic background: a preset, plus whatever was changed
/// from it (like Keydeck's variation of a preset: only the changes).
class DynamicBg {
  final DynamicPreset preset;

  /// Changed colours, by their place in the Colors bar.
  final Map<int, Color> _colors;
  final Map<String, double> _nums;
  Color? _background;

  DynamicBg([DynamicPreset? preset])
    : preset = preset ?? dynamicPresets.first,
      _colors = {},
      _nums = {};

  /// The preset called [name] (the first one if there is none).
  static DynamicPreset presetNamed(String? name) => dynamicPresets.firstWhere(
    (p) => p.name == name,
    orElse: () => dynamicPresets.first,
  );

  String get name => preset.name;
  String get family => preset.family;
  String? get blendMode => preset.blendMode;

  /// Waves have a colour behind them.
  bool get hasBackground => family.startsWith('KNWaves');

  /// Nothing changed from the preset.
  bool get isPreset =>
      _colors.isEmpty && _nums.isEmpty && _background == null;

  List<DynamicStop> get colors => [
    for (var i = 0; i < preset.colors.length; i++)
      DynamicStop(preset.colors[i].at, _colors[i] ?? preset.colors[i].color),
  ];

  Color? get background => _background ?? preset.background;

  double? numberOrNull(String name) => _nums[name] ?? preset.nums[name];
  double number(String name, double fallback) =>
      numberOrNull(name) ?? fallback;

  /// A slider's value.
  double value(DynamicControl c) => number(c.prop, c.fallback);

  void setColor(int index, Color c) {
    if (index < 0 || index >= preset.colors.length) return;
    _colors[index] = c;
  }

  void setBackground(Color c) => _background = c;

  void setNum(String name, double v) {
    _nums[name] = _intProps.contains(name) ? v.roundToDouble() : v;
    // Peaks sets both directions (Keynote keeps them equal).
    if (name == 'noise_scale_horizontal') _nums['noise_scale_vertical'] = v;
  }

  void setValue(DynamicControl c, double v) =>
      setNum(c.prop, v.clamp(c.min, c.max).toDouble());

  /// Same moving picture (Keydeck's `looks_same`).
  bool looksSame(DynamicBg other) => lookKey == other.lookKey;

  /// Changes whenever the picture would.
  String get lookKey => toJson().toString();

  Map<String, dynamic> toJson() => {
    'preset': preset.name,
    if (_colors.isNotEmpty)
      'colors': {
        for (final e in _colors.entries) '${e.key}': e.value.toARGB32(),
      },
    if (_nums.isNotEmpty) 'nums': Map<String, double>.of(_nums),
    'background': ?_background?.toARGB32(),
  };

  static DynamicBg fromJson(Object? j) {
    if (j is! Map) return DynamicBg();
    final bg = DynamicBg(presetNamed(j['preset'] as String?));
    final colors = j['colors'];
    if (colors is Map) {
      for (final e in colors.entries) {
        final i = int.tryParse('${e.key}');
        final v = e.value;
        if (i != null && v is num) bg.setColor(i, Color(v.toInt()));
      }
    }
    final nums = j['nums'];
    if (nums is Map) {
      for (final e in nums.entries) {
        final v = e.value;
        if (v is num) bg._nums['${e.key}'] = v.toDouble();
      }
    }
    final b = j['background'];
    if (b is num) bg._background = Color(b.toInt());
    return bg;
  }

  DynamicBg copy() => fromJson(toJson());
}

// ------------------------------------------------------------------ renderer

/// How fast each built-in background moves compared with the renderer
/// (Keydeck fitted these to Keynote's playback).
const _calibration = {
  'Rainbow': 2.833,
  'Ocean Floor': 1.06,
  'Neptune': 0.263,
  'Snow Day': 0.224,
  'Neon Splash': 0.432,
  'Jade Cliffs': 0.843,
  'Stormy Seas': 0.63,
  'Poolside': 0.269,
  'Nebula': 0.75,
  'Black Smoke': 0.89,
  'Lime Juice': 0.213,
  'Solar Flare': 0.084,
  'Sunset Dunes': 1.82,
  'Morning Surf': 0.12,
  'Lava Lamp': 0.563,
  'Flamingo': 0.449,
  'Cool Breeze': 0.09,
  'Purple Vista': 0.561,
};

double _timeFactor(DynamicBg bg) =>
    _calibration[bg.name] ??
    switch (bg.family) {
      'KNGradientTerrainBase' => 0.97,
      'KNGradientTerrainFlyover' => 0.63,
      'KNGradientDiffusionBase' => 0.3,
      'KNWavesBase' || 'KNWavesSymmetrical' => 0.11,
      'KNGraphicSpheresBase' => 0.43,
      _ => 0.28,
    };

enum _Family { linear, terrain, flyover, diffusion, waves, wavesSym, spheres }

/// 32-bit multiply that is also right when compiled to JavaScript (whose
/// numbers lose the low bits of a large product).
int _mul32(int a, int b) => _js
    ? ((a & 0xFFFF) * b + ((((a >> 16) & 0xFFFF) * b) & 0xFFFF) * 0x10000) &
          0xFFFFFFFF
    : (a * b) & 0xFFFFFFFF;

/// Compiled to JavaScript (where whole numbers are doubles).
const bool _js = identical(0, 0.0);

/// 0…65535 for a grid point.
int _hash(int x, int y) => _hashEnd(_hashX(x) ^ _hashY(y));

int _hashX(int x) => _mul32(x & 0xFFFFFFFF, 0x8da6b343);
int _hashY(int y) => _mul32(y & 0xFFFFFFFF, 0xd8163841);

int _hashEnd(int h) {
  h ^= h >> 13;
  h = _mul32(h, 0x85ebca6b);
  h ^= h >> 16;
  return h & 0xffff;
}

double _clamp(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);

double _smoothstep(double e0, double e1, double x) {
  final k = _clamp((x - e0) / (e1 - e0), 0, 1);
  return k * k * (3 - 2 * k);
}

double _fract(double x) => x - x.truncateToDouble();

/// One wave / ridge line across the screen.
class _Layer {
  /// Its height at each column.
  final Float64List ys;
  final double r, g, b, alpha, soft;

  /// Terrain: how lit each column is.
  final Float64List? light;
  _Layer(this.ys, this.r, this.g, this.b, this.alpha, this.soft, [this.light]);
}

/// Draws a dynamic background's frames on the CPU, small (the picture is
/// soft by nature and is scaled up smoothly when shown).
class DynamicRenderer {
  final int w, h;

  /// The Colors bar: (fraction, r, g, b) per stop, in order.
  late final Float64List _stops;

  late final _Family _fam;
  late final double _factor;
  late final double _aspect;
  // shared
  late final double _speed, _scale, _angle;
  late final double _contrast, _brightness, _saturation, _gamma;
  late final double _grain, _grainSpeed, _paletteOffset;
  // noise
  late final double _amp, _octaves, _noiseScale, _noiseSpeed, _movement;
  late final double _fogDistance, _fogPower, _zoom;
  // waves
  late final double _density, _waveAmp, _envelope, _yOffset, _blur;
  late final double _opacity, _offset;
  late final bool _multiply;
  late final double _bgR, _bgG, _bgB;

  // this frame
  double _t = 0, _tReal = 0;
  List<_Layer> _layers = const [];
  double _skyTopR = 0, _skyTopG = 0, _skyTopB = 0;
  double _skyBotR = 0, _skyBotG = 0, _skyBotB = 0;

  /// x to the power of the gamma, for x from 0 to 1 in 4096 steps (the
  /// power itself is slow to work out three times per pixel).
  Float64List? _gammaTable;

  Uint32List? _grainX;

  // spheres: each ball's centre and radius² this frame
  final Float64List _ballX = Float64List(12),
      _ballY = Float64List(12),
      _ballR2 = Float64List(12);

  // a colour being worked out (no objects made per pixel)
  double _r = 0, _g = 0, _b = 0;

  // the grid square each noise layer last used (neighbouring pixels share it)
  final Int32List _cellX = Int32List(8), _cellY = Int32List(8);
  final Float64List _cell = Float64List(32);
  final Uint8List _cellSet = Uint8List(8);

  DynamicRenderer(DynamicBg bg, int w, int h)
    : w = math.max(w, 2),
      h = math.max(h, 2) {
    final stops = [...bg.colors];
    if (stops.isEmpty) {
      stops.addAll(const [
        DynamicStop(0, Color.from(alpha: 1, red: 0.2, green: 0.3, blue: 0.8)),
        DynamicStop(1, Color.from(alpha: 1, red: 0.9, green: 0.3, blue: 0.6)),
      ]);
    }
    // (a stable sort, like the original's)
    for (var i = 1; i < stops.length; i++) {
      final s = stops[i];
      var k = i - 1;
      while (k >= 0 && stops[k].at > s.at) {
        stops[k + 1] = stops[k];
        k--;
      }
      stops[k + 1] = s;
    }
    _stops = Float64List(stops.length * 4);
    for (var i = 0; i < stops.length; i++) {
      _stops[i * 4] = stops[i].at;
      _stops[i * 4 + 1] = stops[i].color.r;
      _stops[i * 4 + 2] = stops[i].color.g;
      _stops[i * 4 + 3] = stops[i].color.b;
    }
    double n(String k, double d) => bg.number(k, d);
    _fam = switch (bg.family) {
      'KNGradientTerrainBase' => _Family.terrain,
      'KNGradientTerrainFlyover' => _Family.flyover,
      'KNGradientDiffusionBase' => _Family.diffusion,
      'KNWavesBase' => _Family.waves,
      'KNWavesSymmetrical' => _Family.wavesSym,
      'KNGraphicSpheresBase' => _Family.spheres,
      _ => _Family.linear,
    };
    _factor = _timeFactor(bg);
    _aspect = this.w / this.h;
    _speed = n('speed', 50);
    _scale = n('scale', 1);
    _angle = n('angle', 45);
    _contrast = n('contrast', 1);
    _brightness = n('brightness', 0);
    _saturation =
        n('saturation', 1) * math.sqrt(math.max(n('color_saturation', 1), 0));
    _gamma = n('gamma', 1) * n('color_gamma', 1);
    _grain = n('grain_intensity', 0.3);
    _grainSpeed = n('grain_speed', 1);
    _paletteOffset = n('color_palette_offset', 0);
    _amp = n('noise_amplitude', 2);
    _octaves = _clamp(n('noise_octaves', 3), 1, 6);
    _noiseScale = n('noise_scale_horizontal', n('noise_scale', 1));
    _noiseSpeed = n('noise_speed', 1);
    _movement = n('noise_movement', 0);
    _fogDistance = n('fog_distance', 1);
    _fogPower = n('fog_power', 6);
    _zoom = n('zoom', 50);
    _density = n('density', 3);
    _waveAmp = n('amplitude', 1);
    _envelope = n('envelope', 0.5);
    _yOffset = n('y_offset', 0);
    _blur = n('blur', 0.5);
    _opacity = n('motion_background_opacity', 0.3);
    _offset = n('offset', 1);
    _multiply = bg.blendMode == 'Multiply';
    final back = bg.background;
    _bgR = back?.r ?? 0;
    _bgG = back?.g ?? 0;
    _bgB = back?.b ?? 0;
    final gam = math.sqrt(_clamp(_gamma, 0.3, 3));
    if (gam != 1) {
      final table = Float64List(4098);
      for (var i = 0; i < table.length; i++) {
        table[i] = math.pow(i / 4096, gam) as double;
      }
      _gammaTable = table;
    }
  }

  /// The whole frame at time [t] (seconds), as RGBA bytes.
  static Uint8List frame(DynamicBg bg, double t, int w, int h) {
    final r = DynamicRenderer(bg, w, h)..begin(t);
    final out = Uint8List(r.w * r.h * 4);
    r.rows(0, r.h, out);
    return out;
  }

  /// Start the frame at time [t]; then draw its rows with [rows].
  void begin(double t) {
    _t = t * _factor;
    _tReal = t;
    _cellSet.fillRange(0, _cellSet.length, 0);
    _columns();
  }

  // ---- the Colors bar ----

  /// Sets _r, _g, _b to the bar's colour at [x].
  void _pal(double x) {
    final s = _stops;
    final n = s.length ~/ 4;
    if (x <= s[0]) {
      _r = s[1];
      _g = s[2];
      _b = s[3];
      return;
    }
    for (var i = 1; i < n; i++) {
      final o = i * 4;
      if (x <= s[o]) {
        final p = o - 4;
        var k = _clamp((x - s[p]) / math.max(s[o] - s[p], 1e-5), 0, 1);
        k = k * k * (3 - 2 * k);
        _r = s[p + 1] + (s[o + 1] - s[p + 1]) * k;
        _g = s[p + 2] + (s[o + 2] - s[p + 2]) * k;
        _b = s[p + 3] + (s[o + 3] - s[p + 3]) * k;
        return;
      }
    }
    final o = (n - 1) * 4;
    _r = s[o + 1];
    _g = s[o + 2];
    _b = s[o + 3];
  }

  // ---- noise ----

  double _noise(double x, double y, int slot) {
    final xf = x.floorToDouble(), yf = y.floorToDouble();
    final fx = x - xf, fy = y - yf;
    final ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    final xi = xf.toInt(), yi = yf.toInt();
    final o = slot * 4;
    if (_cellSet[slot] == 0 || _cellX[slot] != xi || _cellY[slot] != yi) {
      _cellSet[slot] = 1;
      _cellX[slot] = xi;
      _cellY[slot] = yi;
      _cell[o] = _hash(xi, yi) / 65535.0;
      _cell[o + 1] = _hash(xi + 1, yi) / 65535.0;
      _cell[o + 2] = _hash(xi, yi + 1) / 65535.0;
      _cell[o + 3] = _hash(xi + 1, yi + 1) / 65535.0;
    }
    final a = _cell[o], b = _cell[o + 1], c = _cell[o + 2], d = _cell[o + 3];
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
  }

  /// Layered noise; [slot]: which remembered grid squares to use (a
  /// different one for each place this is called from, up to 6 layers).
  double _fbm(double x, double y, double octaves, [int slot = 0]) {
    var v = 0.0, a = 0.5, norm = 0.0;
    final n = octaves.ceil();
    final whole = octaves.floorToDouble();
    for (var i = 0; i < n; i++) {
      final w = i < whole ? 1.0 : math.max(_fract(octaves), 0.001);
      v += a * w * _noise(x, y, (slot + i) & 7);
      norm += a * w;
      a *= 0.5;
      // rotate and grow so octaves don't line up
      final nx = x * 1.6 + y * 1.2, ny = -x * 1.2 + y * 1.6;
      x = nx + 17.3;
      y = ny + 9.1;
    }
    return v / math.max(norm, 1e-4);
  }

  // ---- ridges and waves, worked out once per column ----

  void _columns() {
    final layers = <_Layer>[];
    final t = _t;
    _pal(0);
    _skyTopR = _skyBotR = _r;
    _skyTopG = _skyBotG = _g;
    _skyTopB = _skyBotB = _b;
    if (_fam == _Family.terrain && _noiseScale < 0.5) {
      // very broad hills (Nebula): one smooth crest, coloured by depth
      final drift = t * 0.12 * (_movement / 100);
      final morph = t * 0.05 * math.sqrt(math.max(_noiseSpeed, 0.5));
      final amp = _clamp(_amp / 4, 0.15, 2);
      final ys = Float64List(w);
      for (var x = 0; x < w; x++) {
        final u = x / w - 0.5;
        final hgt = _fbm(u * _aspect * 0.55 + drift + 3.1, 0.7 + morph, 2) - 0.5;
        ys[x] = 0.56 - u * 0.08 - hgt * amp * 1.2;
      }
      _pal(0);
      final r0 = _r, g0 = _g, b0 = _b;
      _pal(0.25);
      _skyTopR = r0 + (_r - r0) * 0.1;
      _skyTopG = g0 + (_g - g0) * 0.1;
      _skyTopB = b0 + (_b - b0) * 0.1;
      _skyBotR = r0 + (_r - r0) * 0.16;
      _skyBotG = g0 + (_g - g0) * 0.16;
      _skyBotB = b0 + (_b - b0) * 0.16;
      layers.add(_Layer(ys, _r, _g, _b, 1, 0.03 + _blur * 0.02));
    } else if (_fam == _Family.terrain || _fam == _Family.flyover) {
      const n = 28;
      final flyover = _fam == _Family.flyover;
      // flyover: layers move towards the viewer; terrain: ridges drift
      final fly = flyover
          ? t *
                0.04 *
                (math.max(_movement.abs(), 20) / 100) *
                (_movement.isNegative ? 0.5 : 1.0)
          : 0.0;
      final drift = t * 0.12 * (_movement / 100);
      final morph = t * 0.05 * math.sqrt(math.max(_noiseSpeed, 0.5));
      _pal(0);
      final r0 = _r, g0 = _g, b0 = _b;
      _pal(0.2);
      _skyBotR = r0 + (_r - r0) * 0.5;
      _skyBotG = g0 + (_g - g0) * 0.5;
      _skyBotB = b0 + (_b - b0) * 0.5;
      // zoom: the camera's field of view (larger = finer hills)
      final freq = _clamp(_noiseScale / 4, 1.1, 3) * _clamp(_zoom / 50, 0.5, 2);
      final amp = _clamp(_amp / 4, 0.15, 2);
      final oct = math.max(_octaves * 0.5, 1.0);
      for (var i = 0; i < n; i++) {
        // depth 1 = far, 0 = near; flyover layers loop forward
        var d = 1 - (i + 0.5) / n;
        var pass = 0.0;
        if (flyover) {
          final z = d + fly;
          pass = z.floorToDouble();
          d = z - pass;
        }
        final persp = 1 / (0.35 + d * 2.2);
        final horizon = flyover ? 0.30 : 0.42;
        final base = horizon + (1 - d) * (1 - horizon) * 0.95;
        final seed = i * 7.31 + pass * 3.7;
        final ys = Float64List(w);
        for (var x = 0; x < w; x++) {
          final u = x / w - 0.5;
          final nx = u * _aspect * freq * (0.25 + d * 1.6) * 3 + seed + drift;
          final hgt = _fbm(nx, seed * 0.37 + morph, oct);
          final ridge = math.max(hgt - 0.3, 0) * amp * persp * 0.32;
          ys[x] = base - ridge;
        }
        // colour by nearness; fog towards the sky in the distance
        final near = 1 - d;
        _pal(flyover ? 0.28 + 0.42 * near : 0.15 + 0.85 * near);
        final fog =
            math.pow(
                  _clamp(d / math.max(_fogDistance, 0.2), 0, 1),
                  math.max(_fogPower, 1) / 4,
                )
                as double;
        final k = fog * 0.85;
        final cr = _r + (_skyBotR - _r) * k;
        final cg = _g + (_skyBotG - _g) * k;
        final cb = _b + (_skyBotB - _b) * k;
        final fade = flyover
            ? _clamp(math.min((1 - d) * 6, d * 12), 0, 1)
            : 1.0;
        final light = Float64List(w);
        for (var x = 0; x < w; x++) {
          final a = ys[x < 2 ? 0 : x - 2];
          final b = ys[math.min(x + 2, w - 1)];
          // rising to the right faces the light (from the upper left)
          light[x] = _clamp(1 + (a - b) * w * 0.02, 0.6, 1.35);
        }
        layers.add(_Layer(ys, cr, cg, cb, fade, 0.004, light));
      }
    } else if (_fam == _Family.waves || _fam == _Family.wavesSym) {
      final n = _clamp((_density * 2).roundToDouble(), 3, 12).toInt();
      final soft = 0.004 + _blur * 0.05;
      final alpha = math.min(math.max(_opacity, 0.15), 0.6);
      for (var i = 0; i < n; i++) {
        final fi = i.toDouble();
        _pal((fi + 0.5) / n);
        final k1 = 0.6 + _fract(fi * 0.37) * _scale * 0.2;
        final k2 = 1.3 + _fract(fi * 0.61) * _scale * 0.3;
        final ph = fi * 1.7 + _offset + t * _speed * 0.02 * (1 + fi * 0.13);
        final ys = Float64List(w);
        for (var x = 0; x < w; x++) {
          final u = x / w;
          final e = 2 * u - 1;
          final env = _envelope > 0
              ? math.max(1 - _envelope * 0.5 * e * e, 0.2)
              : 1.0;
          final a = (0.04 + 0.045 * math.min(_waveAmp, 10)) * env;
          final v =
              math.sin(u * k1 * 3 + ph) * 0.6 +
              math.sin(u * k2 * 3 - ph * 1.3) * 0.4;
          ys[x] = v * a;
        }
        layers.add(_Layer(ys, _r, _g, _b, alpha, soft));
      }
    }
    _layers = layers;
  }

  // ---- pixels ----

  /// Draw rows [y0] (included) to [y1] (not) of the frame into [out]
  /// (w × h × 4 RGBA bytes).
  void rows(int y0, int y1, Uint8List out) {
    final w = this.w, h = this.h;
    final t = _t;
    // colour grading
    final sat = 1 + (_clamp(_saturation, 0, 2) - 1) * 0.7;
    final con = 1 + (_clamp(_contrast, 0.3, 2) - 1) * 0.6;
    final gam = math.sqrt(_clamp(_gamma, 0.3, 3));
    final gammaTable = _gammaTable;
    final brightness = _brightness;
    final aspect = _aspect;
    final fam = _fam;
    final grainFrame = _grain > 0
        ? (_tReal * (6 + _clamp(_grainSpeed, 0, 100) * 0.18)).floor()
        : 0;
    final grain = _grain * 0.01;
    // (the columns' share of each pixel's grain, worked out once)
    final grainX = _grainX ??= Uint32List(w);
    if (_grain > 0) {
      for (var x = 0; x < w; x++) {
        grainX[x] = _hashX(x + grainFrame * 7919);
      }
    }
    // linear
    final rad = _angle * math.pi / 180;
    final dx = math.cos(rad), dy = -math.sin(rad);
    final linS = 1 / math.max(_scale, 0.2);
    final flow =
        math.sin(t * _speed * 0.006) * (0.15 + 0.1 * math.min(_scale, 3));
    // diffusion
    final ts = t * 0.09 * (_noiseSpeed + _speed * 0.01);
    // spheres
    final sts = t * math.max(_speed * 0.004, 0.03) + _offset;
    final ballX = _ballX, ballY = _ballY, ballR2 = _ballR2;
    if (fam == _Family.spheres) {
      // each layer: a cluster of balls orbiting a slowly moving centre, so
      // they merge into one organic shape
      for (var l = 0; l < 3; l++) {
        final fl = l.toDouble();
        final lx = aspect * (0.5 + 0.4 * math.sin(sts * 0.31 + fl * 2.4));
        final ly = 0.5 + 0.4 * math.cos(sts * 0.23 + fl * 1.7);
        for (var k = 0; k < 4; k++) {
          final fb = k + fl * 4;
          ballX[l * 4 + k] =
              lx + 0.35 * math.sin(sts * (0.7 + 0.13 * fb) + fb * 2.1);
          ballY[l * 4 + k] =
              ly + 0.3 * math.cos(sts * (0.5 + 0.11 * fb) + fb * 1.3);
          final rad =
              0.13 + 0.1 * _fract(fb * 0.77) * _clamp(_noiseScale / 5, 0.5, 1.5);
          ballR2[l * 4 + k] = rad * rad;
        }
      }
    }
    final ballEdge = 2.0 / h * 3;
    final ballAlpha = 0.75 + 0.25 * math.min(_opacity, 1);
    final sym = fam == _Family.wavesSym;
    final center = (sym ? 0.5 : 0.62) - _yOffset * 0.25;
    final broad = _fam == _Family.terrain && _noiseScale < 0.5;
    final layers = _layers;

    for (var y = y0; y < y1; y++) {
      final v = (y + 0.5) / h;
      var o = y * w * 4;
      final grainY = _hashY(y - grainFrame * 104729);
      for (var x = 0; x < w; x++) {
        final u = (x + 0.5) / w;
        double r, g, b;
        switch (fam) {
          case _Family.linear:
            // a soft gradient along the angle whose colours slowly flow,
            // warped by large noise
            final px = (u - 0.5) * aspect, py = v - 0.5;
            final warp =
                _fbm(
                  px * 0.9 + t * 0.09 * _speed / 40,
                  py * 0.9 - t * 0.07 * _speed / 40,
                  2,
                ) -
                0.5;
            final along =
                (px * dx + py * dy) / math.max(aspect, 1) * linS * 1.1 +
                0.55 +
                warp * 0.3;
            var k = _clamp(along + flow + _paletteOffset, -0.5, 1.5);
            // mirror outside 0..1 so the ends don't clamp hard
            if (k < 0) {
              k = -k;
            } else if (k > 1) {
              k = 2 - k;
            }
            _pal(k);
            r = _r;
            g = _g;
            b = _b;
          case _Family.diffusion:
            final px = (u - 0.5) * aspect * _scale * 0.55;
            final py = (v - 0.5) * _scale * 0.55;
            final q0 = _fbm(px + ts, py - ts * 0.7, 2, 0);
            final q1 = _fbm(px - ts * 0.6 + 5.2, py + ts + 1.3, 2, 2);
            final n = _fbm(
              px * 0.7 + q0 * _amp * 0.45,
              py * 0.7 + q1 * _amp * 0.45,
              2,
              4,
            );
            _pal(_clamp((n - 0.2) * 1.7, 0, 1));
            r = _r;
            g = _g;
            b = _b;
          case _Family.terrain when broad:
            final l = layers[0];
            final rr = l.ys[x];
            // sky: dark, with the crest's glow rising into it
            final glow = math.exp(-math.max(rr - v, 0) / 0.09) * 0.35;
            _pal(0.25);
            final sr = _skyTopR + (_skyBotR - _skyTopR) * v;
            final sg = _skyTopG + (_skyBotG - _skyTopG) * v;
            final sb = _skyTopB + (_skyBotB - _skyTopB) * v;
            final skyR = sr + (_r - sr) * glow;
            final skyG = sg + (_g - sg) * glow;
            final skyB = sb + (_b - sb) * glow;
            // below the crest: bright at the crest, down to its depth
            final d = _clamp((v - rr) / math.max(1 - rr, 0.05), 0, 1);
            _pal(0.25 + math.pow(d, 1.5) * 0.5);
            final k = _smoothstep(rr - l.soft, rr + l.soft, v);
            r = skyR + (_r - skyR) * k;
            g = skyG + (_g - skyG) * k;
            b = skyB + (_b - skyB) * k;
          case _Family.terrain || _Family.flyover:
            r = _skyTopR + (_skyBotR - _skyTopR) * v;
            g = _skyTopG + (_skyBotG - _skyTopG) * v;
            b = _skyTopB + (_skyBotB - _skyTopB) * v;
            // (ridges behind one that covers this pixel fully can't show)
            var first = layers.length - 1;
            while (first > 0) {
              final l = layers[first];
              if (l.alpha == 1 && v >= l.ys[x] + l.soft) break;
              first--;
            }
            for (var i = first; i < layers.length; i++) {
              final l = layers[i];
              final rr = l.ys[x];
              if (v <= rr - l.soft) continue;
              final cover = _smoothstep(rr - l.soft, rr + l.soft, v) * l.alpha;
              if (cover > 0) {
                // lit slopes lighter, a little darker below the ridge line
                final below = math.max(v - rr, 0) * 0.6;
                final shade = l.light![x] * (1 - (below < 0.15 ? below : 0.15));
                r += (l.r * shade - r) * cover;
                g += (l.g * shade - g) * cover;
                b += (l.b * shade - b) * cover;
              }
            }
          case _Family.waves || _Family.wavesSym:
            r = _bgR;
            g = _bgG;
            b = _bgB;
            for (var i = 0; i < layers.length; i++) {
              final l = layers[i];
              final rr = l.ys[x];
              double cover;
              if (sym) {
                // a band symmetric about the centre line
                final half = rr.abs() + 0.02;
                if ((v - center).abs() >= half + l.soft) continue;
                cover =
                    1 -
                    _smoothstep(half - l.soft, half + l.soft, (v - center).abs());
              } else {
                if (v <= center + rr - l.soft) continue;
                cover = _smoothstep(
                  center + rr - l.soft,
                  center + rr + l.soft,
                  v,
                );
              }
              if (cover > 0) {
                final k = cover * l.alpha;
                if (_multiply) {
                  r += (r * l.r - r) * k;
                  g += (g * l.g - g) * k;
                  b += (b * l.b - b) * k;
                } else {
                  r += (l.r - r) * k;
                  g += (l.g - g) * k;
                  b += (l.b - b) * k;
                }
              }
            }
          case _Family.spheres:
            // flat, overlapping blobs drifting slowly, in palette colours
            final px = u * aspect, py = v;
            _pal(0.5);
            r = _r;
            g = _g;
            b = _b;
            for (var l = 0; l < 3; l++) {
              var field = 0.0;
              for (var k = l * 4; k < l * 4 + 4; k++) {
                final ex = px - ballX[k], ey = py - ballY[k];
                final d2 = ex * ex + ey * ey;
                field += ballR2[k] / (d2 > 1e-4 ? d2 : 1e-4);
              }
              final cover = _smoothstep(1 - ballEdge, 1 + ballEdge, field);
              if (cover > 0) {
                _pal(const [1.0, 0.75, 0.25][l]);
                final k = cover * ballAlpha;
                r += (_r - r) * k;
                g += (_g - g) * k;
                b += (_b - b) * k;
              }
            }
        }

        // colour grading and film grain
        final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        r = (lum + (r - lum) * sat - 0.5) * con + 0.5 + brightness;
        g = (lum + (g - lum) * sat - 0.5) * con + 0.5 + brightness;
        b = (lum + (b - lum) * sat - 0.5) * con + 0.5 + brightness;
        r = r > 0 ? r : 0;
        g = g > 0 ? g : 0;
        b = b > 0 ? b : 0;
        if (gammaTable != null) {
          if (r < 1) {
            final f = r * 4096, i = f.toInt();
            r = gammaTable[i] + (gammaTable[i + 1] - gammaTable[i]) * (f - i);
          } else {
            r = math.pow(r, gam) as double;
          }
          if (g < 1) {
            final f = g * 4096, i = f.toInt();
            g = gammaTable[i] + (gammaTable[i + 1] - gammaTable[i]) * (f - i);
          } else {
            g = math.pow(g, gam) as double;
          }
          if (b < 1) {
            final f = b * 4096, i = f.toInt();
            b = gammaTable[i] + (gammaTable[i + 1] - gammaTable[i]) * (f - i);
          } else {
            b = math.pow(b, gam) as double;
          }
        }
        if (_grain > 0) {
          // fine and faint (the frame is scaled up, so strong grain would
          // turn blotchy)
          final gr = (_hashEnd(grainX[x] ^ grainY) / 65535.0 - 0.5) * grain;
          r += gr;
          g += gr;
          b += gr;
        }
        out[o] = (_clamp(r, 0, 1) * 255 + 0.5).toInt();
        out[o + 1] = (_clamp(g, 0, 1) * 255 + 0.5).toInt();
        out[o + 2] = (_clamp(b, 0, 1) * 255 + 0.5).toInt();
        out[o + 3] = 255;
        o += 4;
      }
    }
  }
}

/// A finished frame of a dynamic background.
class DynamicFrame {
  /// The look it shows ([DynamicBg.lookKey]).
  final String key;

  /// Its moment, in seconds.
  final double t;
  final int w, h;
  final Uint8List rgba;
  const DynamicFrame(this.key, this.t, this.w, this.h, this.rgba);
}
