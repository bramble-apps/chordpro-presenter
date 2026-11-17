// SoundFont 2 (.sf2): reads the presets, and takes one preset out as a
// small "pad sound" (just its samples and how to play them) to keep in the
// app. Only what a sustained pad needs is read: key / velocity ranges,
// tuning, loops, volume and pan (no modulators, filters or LFOs).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class Sf2Error implements Exception {
  final String message;
  const Sf2Error(this.message);
  @override
  String toString() => message;
}

/// A preset as listed in the file.
class Sf2Preset {
  final int index;
  final String name;
  final int bank;
  final int program;

  /// Its sounds loop (so it holds as a pad); a piano or a pluck doesn't.
  final bool sustains;
  const Sf2Preset(
    this.index,
    this.name,
    this.bank,
    this.program,
    this.sustains,
  );
}

/// Generator numbers used (SoundFont 2.04, §8.1.2).
abstract final class _G {
  static const startOffset = 0;
  static const endOffset = 1;
  static const loopStartOffset = 2;
  static const loopEndOffset = 3;
  static const startCoarse = 4;
  static const endCoarse = 12;
  static const pan = 17;
  static const sustainVolEnv = 37;
  static const instrument = 41;
  static const keyRange = 43;
  static const velRange = 44;
  static const loopStartCoarse = 45;
  static const attenuation = 48;
  static const loopEndCoarse = 50;
  static const coarseTune = 51;
  static const fineTune = 52;
  static const sampleId = 53;
  static const sampleModes = 54;
  static const scaleTuning = 56;
  static const rootKey = 58;
}

class _Zone {
  final Map<int, int> gens; // raw 16-bit amounts (signed)
  const _Zone(this.gens);
  int? operator [](int g) => gens[g];
  (int, int) range(int g) {
    final v = gens[g];
    if (v == null) return (0, 127);
    return (v & 0xFF, (v >> 8) & 0xFF);
  }
}

class _Sample {
  final String name;
  final int start, end, loopStart, loopEnd, rate, pitch, correction, type;
  const _Sample(
    this.name,
    this.start,
    this.end,
    this.loopStart,
    this.loopEnd,
    this.rate,
    this.pitch,
    this.correction,
    this.type,
  );
}

/// A whole .sf2 file, read.
class Sf2File {
  final Uint8List _bytes;
  final int _smpl; // where the 16-bit samples start
  final int _smplLength; // in samples
  final List<(String, int, int, int)> _presets; // name, program, bank, bag
  final List<(int, int)> _pbag, _ibag; // generator index, modulator index
  final List<(int, int)> _pgen, _igen; // operator, amount
  final List<(String, int)> _inst; // name, bag
  final List<_Sample> _samples;

  Sf2File._(
    this._bytes,
    this._smpl,
    this._smplLength,
    this._presets,
    this._pbag,
    this._pgen,
    this._inst,
    this._ibag,
    this._igen,
    this._samples,
  );

  static Sf2File parse(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    String id(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    if (bytes.length < 12 || id(0) != 'RIFF' || id(8) != 'sfbk') {
      throw const Sf2Error('This isn’t a SoundFont (.sf2) file.');
    }
    // The chunks inside a LIST (or the file).
    Map<String, (int, int)> chunks(int from, int to) {
      final out = <String, (int, int)>{};
      var at = from;
      while (at + 8 <= to) {
        var name = id(at);
        final size = d.getUint32(at + 4, Endian.little);
        final body = at + 8;
        if (name == 'LIST' && body + 4 <= to) {
          name = 'LIST:${id(body)}';
          out[name] = (body + 4, math.min(body + size, to));
        } else {
          out[name] = (body, math.min(body + size, to));
        }
        at = body + size + (size & 1);
      }
      return out;
    }

    final top = chunks(12, bytes.length);
    final sdta = top['LIST:sdta'], pdta = top['LIST:pdta'];
    if (sdta == null || pdta == null) {
      throw const Sf2Error('This SoundFont is missing its sounds.');
    }
    final smpl = chunks(sdta.$1, sdta.$2)['smpl'];
    if (smpl == null) throw const Sf2Error('This SoundFont has no samples.');
    final p = chunks(pdta.$1, pdta.$2);
    (int, int) need(String name) =>
        p[name] ?? (throw Sf2Error('This SoundFont is incomplete ($name).'));

    String name20(int at) {
      final raw = bytes.sublist(at, at + 20);
      final end = raw.indexOf(0);
      return latin1.decode(end < 0 ? raw : raw.sublist(0, end)).trim();
    }

    List<T> records<T>(String chunk, int size, T Function(int at) read) {
      final (from, to) = need(chunk);
      return [for (var at = from; at + size <= to; at += size) read(at)];
    }

    int u16(int at) => d.getUint16(at, Endian.little);
    int s16(int at) => d.getInt16(at, Endian.little);
    int u32(int at) => d.getUint32(at, Endian.little);

    return Sf2File._(
      bytes,
      smpl.$1,
      (smpl.$2 - smpl.$1) ~/ 2,
      records(
        'phdr',
        38,
        (at) => (name20(at), u16(at + 20), u16(at + 22), u16(at + 24)),
      ),
      records('pbag', 4, (at) => (u16(at), u16(at + 2))),
      records('pgen', 4, (at) => (u16(at), s16(at + 2))),
      records('inst', 22, (at) => (name20(at), u16(at + 20))),
      records('ibag', 4, (at) => (u16(at), u16(at + 2))),
      records('igen', 4, (at) => (u16(at), s16(at + 2))),
      records(
        'shdr',
        46,
        (at) => _Sample(
          name20(at),
          u32(at + 20),
          u32(at + 24),
          u32(at + 28),
          u32(at + 32),
          u32(at + 36),
          bytes[at + 40],
          d.getInt8(at + 41),
          u16(at + 44),
        ),
      ),
    );
  }

  /// The zones from bag [from] to [to] (a global zone first, if any:
  /// [last] is the generator that ends a normal zone).
  (Map<int, int>?, List<_Zone>) _zones(
    List<(int, int)> bags,
    List<(int, int)> gens,
    int from,
    int to,
    int last,
  ) {
    Map<int, int>? global;
    final zones = <_Zone>[];
    for (var b = from; b < to && b + 1 < bags.length; b++) {
      final g = <int, int>{};
      for (var i = bags[b].$1; i < bags[b + 1].$1 && i < gens.length; i++) {
        g[gens[i].$1] = gens[i].$2;
      }
      if (g.containsKey(last)) {
        zones.add(_Zone(g));
      } else if (b == from) {
        global = g;
      }
    }
    return (global, zones);
  }

  /// Every preset (the last header only ends the list).
  List<Sf2Preset> get presets =>
      [
        for (var i = 0; i + 1 < _presets.length; i++)
          Sf2Preset(
            i,
            _presets[i].$1,
            _presets[i].$3,
            _presets[i].$2,
            _regions(i).any((r) => r.loop),
          ),
      ]..sort(
        (a, b) => a.bank != b.bank
            ? a.bank.compareTo(b.bank)
            : a.program.compareTo(b.program),
      );

  /// What preset [index] plays: one region per instrument zone it uses.
  List<_Region> _regions(int index) {
    final out = <_Region>[];
    final (pGlobal, pZones) = _zones(
      _pbag,
      _pgen,
      _presets[index].$4,
      _presets[index + 1].$4,
      _G.instrument,
    );
    for (final pz in pZones) {
      final pg = {...?pGlobal, ...pz.gens};
      final inst = pg[_G.instrument]!;
      if (inst < 0 || inst + 1 >= _inst.length) continue;
      final (iGlobal, iZones) = _zones(
        _ibag,
        _igen,
        _inst[inst].$2,
        _inst[inst + 1].$2,
        _G.sampleId,
      );
      for (final iz in iZones) {
        final ig = {...?iGlobal, ...iz.gens};
        final s = ig[_G.sampleId]!;
        if (s < 0 || s >= _samples.length) continue;
        final sample = _samples[s];
        if (sample.type & 0x8000 != 0) continue; // ROM sample
        (int, int) both(int g) {
          final a = _Zone(ig).range(g), b = _Zone(pg).range(g);
          return (math.max(a.$1, b.$1), math.min(a.$2, b.$2));
        }

        final keys = both(_G.keyRange), vels = both(_G.velRange);
        if (keys.$1 > keys.$2 || vels.$1 > vels.$2) continue;
        int sum(int g) => (ig[g] ?? 0) + (pg[g] ?? 0);
        int addr(int fine, int coarse) =>
            (ig[fine] ?? 0) + (ig[coarse] ?? 0) * 32768;
        final mode = (ig[_G.sampleModes] ?? 0) & 3;
        out.add(
          _Region(
            sample: s,
            keyLo: keys.$1,
            keyHi: keys.$2,
            velLo: vels.$1,
            velHi: vels.$2,
            start: sample.start + addr(_G.startOffset, _G.startCoarse),
            end: sample.end + addr(_G.endOffset, _G.endCoarse),
            loopStart:
                sample.loopStart + addr(_G.loopStartOffset, _G.loopStartCoarse),
            loopEnd: sample.loopEnd + addr(_G.loopEndOffset, _G.loopEndCoarse),
            loop: mode == 1 || mode == 3,
            root: switch (ig[_G.rootKey]) {
              final k? when k >= 0 && k <= 127 => k,
              _ => sample.pitch <= 127 ? sample.pitch : 60,
            },
            scale: ig[_G.scaleTuning] ?? 100,
            tune:
                sum(_G.coarseTune) * 100 + sum(_G.fineTune) + sample.correction,
            attenuation: sum(_G.attenuation),
            sustain: sum(_G.sustainVolEnv),
            pan: sum(_G.pan),
            rate: sample.rate,
          ),
        );
      }
    }
    return out;
  }

  /// Takes preset [index] out as a pad sound named [name]: the samples it
  /// plays (at a normal velocity), and how.
  PadSound extract(int index, String name) {
    final regions = [
      for (final r in _regions(index))
        if (r.velLo <= 100 && r.velHi >= 100) r,
    ];
    if (regions.isEmpty) {
      throw const Sf2Error('That preset has no sounds to play.');
    }
    final pcm = BytesBuilder(copy: false);
    final placed = <int, (int, int)>{}; // sample → (offset, length) in pcm
    var offset = 0;
    final zones = <PadZone>[];
    for (final r in regions) {
      final start = r.start.clamp(0, _smplLength);
      final end = r.end.clamp(start, _smplLength);
      if (end - start < 2) continue;
      final key = r.sample * 1000003 + start;
      final (at, length) = placed[key] ??= () {
        final n = end - start;
        pcm.add(
          Uint8List.sublistView(_bytes, _smpl + start * 2, _smpl + end * 2),
        );
        final spot = (offset, n);
        offset += n;
        return spot;
      }();
      final ls = (r.loopStart - start).clamp(0, length - 1);
      final le = (r.loopEnd - start).clamp(ls + 1, length);
      zones.add(
        PadZone(
          keyLo: r.keyLo,
          keyHi: r.keyHi,
          offset: at,
          length: length,
          loopStart: ls,
          loopEnd: le,
          loop: r.loop && le - ls > 8,
          root: r.root,
          scale: r.scale,
          tune: r.tune,
          // EMU's attenuation is 0.4 of what it says (as other players do).
          gain:
              math.pow(10, -(r.attenuation * 0.4) / 200).toDouble() *
              math.pow(10, -r.sustain.clamp(0, 1440) / 200).toDouble(),
          pan: (r.pan / 500).clamp(-1.0, 1.0),
          rate: r.rate,
        ),
      );
    }
    final bytes = pcm.toBytes();
    return PadSound(
      name,
      zones,
      Int16List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 2,
      ),
    );
  }
}

class _Region {
  final int sample, keyLo, keyHi, velLo, velHi;
  final int start, end, loopStart, loopEnd, root, scale, tune;
  final int attenuation, sustain, pan, rate;
  final bool loop;
  const _Region({
    required this.sample,
    required this.keyLo,
    required this.keyHi,
    required this.velLo,
    required this.velHi,
    required this.start,
    required this.end,
    required this.loopStart,
    required this.loopEnd,
    required this.loop,
    required this.root,
    required this.scale,
    required this.tune,
    required this.attenuation,
    required this.sustain,
    required this.pan,
    required this.rate,
  });
}

/// One sample of a pad sound and the keys it plays.
class PadZone {
  final int keyLo, keyHi;

  /// Where its samples are in [PadSound.pcm], and its loop (relative).
  final int offset, length, loopStart, loopEnd;
  final bool loop;

  /// The key it was recorded at; cents per key (100 = normal); cents off.
  final int root, scale, tune;
  final double gain, pan;
  final int rate;

  const PadZone({
    required this.keyLo,
    required this.keyHi,
    required this.offset,
    required this.length,
    required this.loopStart,
    required this.loopEnd,
    required this.loop,
    required this.root,
    required this.scale,
    required this.tune,
    required this.gain,
    required this.pan,
    required this.rate,
  });

  Map<String, dynamic> toJson() => {
    'k': [keyLo, keyHi],
    'o': offset,
    'n': length,
    'l': [loopStart, loopEnd, if (loop) 1 else 0],
    't': [root, scale, tune],
    'g': gain,
    'p': pan,
    'r': rate,
  };

  factory PadZone.fromJson(Map<String, dynamic> j) {
    List<int> ints(String k) => [
      for (final v in j[k] as List) (v as num).toInt(),
    ];
    final k = ints('k'), l = ints('l'), t = ints('t');
    return PadZone(
      keyLo: k[0],
      keyHi: k[1],
      offset: (j['o'] as num).toInt(),
      length: (j['n'] as num).toInt(),
      loopStart: l[0],
      loopEnd: l[1],
      loop: l[2] == 1,
      root: t[0],
      scale: t[1],
      tune: t[2],
      gain: (j['g'] as num).toDouble(),
      pan: (j['p'] as num).toDouble(),
      rate: (j['r'] as num).toInt(),
    );
  }
}

/// A sound from a SoundFont preset, kept in the app (much smaller than the
/// file: only that preset's samples).
class PadSound {
  final String name;
  final List<PadZone> zones;
  final Int16List pcm;
  const PadSound(this.name, this.zones, this.pcm);

  bool get sustains => zones.any((z) => z.loop);

  /// The zones that play [key] (the nearest ones if none cover it).
  List<PadZone> zonesFor(int key) {
    final hit = [
      for (final z in zones)
        if (z.keyLo <= key && key <= z.keyHi) z,
    ];
    if (hit.isNotEmpty) return hit;
    int far(PadZone z) => key < z.keyLo ? z.keyLo - key : key - z.keyHi;
    final best = zones.map(far).reduce(math.min);
    return [
      for (final z in zones)
        if (far(z) == best) z,
    ];
  }

  /// Stored as: header length (4 bytes), the JSON header, the samples.
  Uint8List encode() {
    final head = utf8.encode(
      jsonEncode({
        'v': 1,
        'name': name,
        'zones': [for (final z in zones) z.toJson()],
      }),
    );
    final pad = (4 + head.length).isOdd ? 1 : 0;
    final out = Uint8List(4 + head.length + pad + pcm.lengthInBytes);
    ByteData.sublistView(out).setUint32(0, head.length + pad, Endian.little);
    out.setRange(4, 4 + head.length, head);
    if (pad == 1) out[4 + head.length] = 0x20;
    out.setRange(4 + head.length + pad, out.length, Uint8List.sublistView(pcm));
    return out;
  }

  static PadSound decode(Uint8List bytes) {
    final n = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    final j = jsonDecode(utf8.decode(bytes.sublist(4, 4 + n))) as Map;
    final samples = bytes.sublist(4 + n); // a copy, so it's 2-byte aligned
    return PadSound('${j['name']}', [
      for (final z in j['zones'] as List)
        PadZone.fromJson(Map<String, dynamic>.from(z as Map)),
    ], Int16List.view(samples.buffer, 0, samples.length ~/ 2));
  }
}
