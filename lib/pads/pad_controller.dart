import 'dart:async';

import 'package:flutter/foundation.dart';

import '../browser.dart';
import '../state.dart';
import 'pad_synth.dart';
import 'sf2.dart';

/// A pad sound to choose: built in, or taken from a SoundFont.
class PadChoice {
  /// `warm`, `shimmer`, `soft`, or `sf:<id>`.
  final String id;
  final String name;
  const PadChoice(this.id, this.name);

  bool get imported => id.startsWith('sf:');
}

/// SoundFont presets taken into the app, kept by id.
abstract final class PadSoundStore {
  static final _store = KeyValueStore();
  static String _key(String id) => 'padsound:$id';

  static Future<void> save(String id, PadSound sound) =>
      _store.writeBytes(_key(id), sound.encode());

  static Future<PadSound?> load(String id) async {
    final bytes = await _store.readBytes(_key(id));
    return bytes == null ? null : PadSound.decode(bytes);
  }

  static Future<void> delete(String id) => _store.delete(_key(id));
}

/// The worship pad: a held chord in a key, crossfading to the next key.
/// It follows the song's key (as you move through songs) unless turned off;
/// tapping a key plays it (tapping the one playing stops).
class PadController extends ChangeNotifier {
  final PresenterModel model;

  PadController(this.model) {
    _songKey = model.currentKey?.root;
    key = _songKey ?? 0;
    model.addListener(_followSong);
  }

  AppSettings get _s => model.settings;

  /// The key held (0 = C … 11 = B).
  int key = 0;
  bool playing = false;

  /// Making the sound (a moment, the first time for each key).
  bool busy = false;

  /// Why the chosen sound can't play (it fell back to the built-in one).
  String? problem;

  int? _songKey;

  /// The song's key, as it sounds (null: the song has none).
  int? get songKey => _songKey;

  void _followSong() {
    final k = model.currentKey?.root;
    if (k == _songKey) return;
    _songKey = k;
    if (k == null || !_s.padFollow) return;
    if (k != key) {
      key = k;
      if (playing) _start();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    model.removeListener(_followSong);
    super.dispose();
  }

  List<PadChoice> get choices => [
    for (final p in BuiltInPad.values) PadChoice(p.name, p.label),
    for (final m in _s.padSounds)
      PadChoice('sf:${m['id']}', m['name'] ?? 'Sound'),
  ];

  PadChoice get choice => choices.firstWhere(
    (c) => c.id == _s.padSound,
    orElse: () => choices.first,
  );

  /// Plays [k]; the key playing stops instead.
  void tapKey(int k) {
    if (playing && k == key) {
      stop();
      return;
    }
    key = k;
    play();
  }

  void play() {
    playing = true;
    notifyListeners();
    _start();
  }

  void stop() {
    playing = false;
    busy = false;
    _gen++;
    padStop(_s.padFade.clamp(0.5, 4.0));
    notifyListeners();
  }

  void toggle() => playing ? stop() : play();

  void setVolume(double v) {
    model.updateSettings((s) => s.padVolume = v);
    padVolume(v);
  }

  /// Changes that make a new sound: it fades in quickly if playing.
  void change(void Function(AppSettings s) edit) {
    model.updateSettings(edit);
    if (playing) _start(fade: 0.8);
    notifyListeners();
  }

  void setFollow(bool on) {
    model.updateSettings((s) => s.padFollow = on);
    if (on && _songKey != null && _songKey != key) {
      key = _songKey!;
      if (playing) _start();
    }
    notifyListeners();
  }

  // ---- Making and playing the sound ----

  int _gen = 0;
  final Map<String, PadLoop> _loops = {};
  (String, PadSound)? _sound;

  Future<Object> _source() async {
    final id = _s.padSound;
    if (!id.startsWith('sf:')) {
      return BuiltInPad.values.firstWhere(
        (p) => p.name == id,
        orElse: () => BuiltInPad.warm,
      );
    }
    final have = _sound;
    if (have != null && have.$1 == id) return have.$2;
    final sound = await PadSoundStore.load(id.substring(3));
    if (sound == null) {
      problem = 'That sound isn’t on this device; playing Warm.';
      return BuiltInPad.warm;
    }
    _sound = (id, sound);
    return sound;
  }

  Future<void> _start({double? fade}) async {
    final gen = ++_gen;
    problem = null;
    final s = _s;
    final id =
        '${s.padSound}|$key|${s.padOctave}|'
        '${s.padTone.toStringAsFixed(2)}|${s.padReverb.toStringAsFixed(2)}';
    var loop = _loops[id];
    if (loop == null) {
      busy = true;
      notifyListeners();
      // (Lets the screen show "busy" before the work.)
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (gen != _gen) return;
      final source = await _source();
      if (gen != _gen) return;
      final PadLoop dry;
      if (source is PadSound) {
        dry = renderSoundFont(source, padNotes(key, s.padOctave));
      } else {
        final pad = source as BuiltInPad;
        dry = renderBuiltIn(
          pad,
          padNotes(key, s.padOctave, shimmer: pad == BuiltInPad.shimmer),
        );
      }
      await Future<void>.delayed(Duration.zero);
      if (gen != _gen) return;
      normalize(dry);
      loop = applyEffects(dry, tone: s.padTone, reverb: s.padReverb);
      _loops[id] = loop;
      // Keep the last few (about 2.5 MB each).
      while (_loops.length > 8) {
        _loops.remove(_loops.keys.first);
      }
    }
    if (gen != _gen || !playing) return;
    busy = false;
    padVolume(s.padVolume);
    padPlay(loop.left, loop.right, loop.rate, fade ?? s.padFade);
    notifyListeners();
  }

  // ---- SoundFonts ----

  /// Takes [presets] out of [file] into the app; the first becomes the
  /// sound in use.
  Future<void> importPresets(
    Sf2File file,
    List<Sf2Preset> presets,
    String fileName,
  ) async {
    final added = <Map<String, String>>[];
    for (final p in presets) {
      final id = newId();
      final sound = file.extract(p.index, p.name);
      await PadSoundStore.save(id, sound);
      added.add({'id': id, 'name': p.name, 'file': fileName});
      await Future<void>.delayed(Duration.zero);
    }
    if (added.isEmpty) return;
    change(
      (s) => s
        ..padSounds = [...s.padSounds, ...added]
        ..padSound = 'sf:${added.first['id']}',
    );
  }

  Future<void> deleteSound(PadChoice c) async {
    if (!c.imported) return;
    final id = c.id.substring(3);
    await PadSoundStore.delete(id);
    _loops.removeWhere((k, _) => k.startsWith('${c.id}|'));
    if (_sound?.$1 == c.id) _sound = null;
    change((s) {
      s.padSounds = [
        for (final m in s.padSounds)
          if (m['id'] != id) m,
      ];
      if (s.padSound == c.id) s.padSound = BuiltInPad.warm.name;
    });
  }
}

/// Reads a SoundFont's bytes (null: not a SoundFont, with why).
(Sf2File?, String?) readSoundFont(Uint8List bytes) {
  try {
    return (Sf2File.parse(bytes), null);
  } on Sf2Error catch (e) {
    return (null, e.message);
  } catch (e) {
    return (null, 'Couldn’t read this SoundFont ($e).');
  }
}
