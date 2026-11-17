// Sheet music scanner: open a photo, picture or PDF of printed music, read
// the notes (offline), then play it with the notes lit up as they sound
// (tap a measure to start there), at any tempo, key and with any
// instrument; correct what was misread; export MusicXML, MIDI, WAV or PDF;
// and turn the harmony into chords for a song.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../abc.dart';
import '../browser.dart';
import '../pads/pad_controller.dart' show PadSoundStore;
import '../pads/sf2.dart';
import '../pdfs.dart';
import '../scanner/engrave.dart';
import '../scanner/harmony.dart';
import '../scanner/playback.dart';
import '../scanner/reader.dart';
import '../scanner/scan_store.dart';
import '../scanner/score.dart';
import '../scanner/score_export.dart';
import '../state.dart';
import '../eink.dart';

/// Opens the scanner: on [files] (name, bytes) if given (read straight
/// away), else on the list of kept scans. [song]: the song the music
/// belongs to (chords can be added to it).
Future<void> openScanner(
  BuildContext context,
  PresenterModel model, {
  List<(String, Uint8List)>? files,
  Song? song,
  String? source,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        ScannerScreen(model: model, files: files, song: song, source: source),
  ),
);

class ScannerScreen extends StatefulWidget {
  final PresenterModel model;
  final List<(String, Uint8List)>? files;
  final Song? song;

  /// Where [files] came from (a song's attachment id): a scan of it made
  /// before opens straight away.
  final String? source;
  const ScannerScreen({
    super.key,
    required this.model,
    this.files,
    this.song,
    this.source,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

/// The pages' pixels for the reader (grey), and pictures to show.
Future<(List<PageImage>, List<ScanPage>)> pagesOf(
  List<(String, Uint8List)> files,
) async {
  final gray = <PageImage>[];
  final shown = <ScanPage>[];
  for (final (_, bytes) in files) {
    if (PdfStore.looksLikePdf(bytes)) {
      await for (final r in Printing.raster(bytes, dpi: 220)) {
        final g = _toGray(r.pixels, r.width, r.height);
        gray.add(PageImage(r.width, r.height, g));
        shown.add(ScanPage(await r.toPng(), r.width, r.height));
      }
      continue;
    }
    // A picture: big enough for the reader, not more than it needs.
    final probe = await ui.instantiateImageCodec(bytes);
    final f0 = await probe.getNextFrame();
    final w0 = f0.image.width;
    f0.image.dispose();
    final target = w0 > 2800 ? 2800 : (w0 < 1600 ? 1800 : w0);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: target);
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final g = _toGray(data!.buffer.asUint8List(), img.width, img.height);
    gray.add(PageImage(img.width, img.height, g));
    shown.add(ScanPage(bytes, img.width, img.height));
    img.dispose();
  }
  return (gray, shown);
}

Uint8List _toGray(Uint8List rgba, int w, int h) {
  final g = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final a = rgba[i * 4 + 3];
    final v =
        (rgba[i * 4] * 77 + rgba[i * 4 + 1] * 150 + rgba[i * 4 + 2] * 29) >> 8;
    // Transparent counts as paper.
    g[i] = (v * a + 255 * (255 - a)) ~/ 255;
  }
  return g;
}

Score _readInBackground((List<PageImage>, String) args) =>
    readScore(args.$1, title: args.$2);

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  PresenterModel get model => widget.model;

  List<ScanInfo> _saved = [];
  String? _id;
  String _title = '';
  String? _songId;
  String? _source;
  Score? _score;
  List<ScanPage> _pages = [];
  PlaySettings _play = PlaySettings();
  String? _busy;
  bool _notesView = false;
  bool _editing = false;
  int? _selected;

  // Playback: the whole performance rendered once (for these settings and
  // this version of the score), then played from wherever.
  Float32List? _audio;
  String? _audioKey;
  Future<Float32List>? _rendering;
  int _revision = 0;
  bool _preparing = false;
  static PadSound? _piano;

  // Page pictures, smaller, for recolouring notes as they play.
  final _pageImages = <int, ui.Image>{};
  final _decoding = <int>{};

  void _forgetPageImages() {
    for (final img in _pageImages.values) {
      img.dispose();
    }
    _pageImages.clear();
  }

  ui.Image? _pageImage(int p) {
    final img = _pageImages[p];
    if (img != null || _decoding.contains(p) || p >= _pages.length) return img;
    _decoding.add(p);
    () async {
      try {
        final page = _pages[p];
        final codec = await ui.instantiateImageCodec(
          page.image,
          targetWidth: math.min(page.width, 1600),
        );
        final frame = await codec.getNextFrame();
        if (!mounted) return;
        // Keep a few pages (they're big).
        if (_pageImages.length >= 4) {
          final first = _pageImages.keys.first;
          _pageImages.remove(first)?.dispose();
        }
        setState(() => _pageImages[p] = frame.image);
      } catch (_) {
      } finally {
        _decoding.remove(p);
      }
    }();
    return null;
  }

  late final Ticker _ticker = createTicker(_tick);
  Performance? _perf;
  bool _playing = false;
  double _q = 0;
  double _startQ = 0;
  final _clock = Stopwatch();
  Set<int> _lit = {};
  int? _litMeasure;
  final _scroll = ScrollController();
  Timer? _saveTimer;
  ScoreLayout? _layout;
  double _layoutWidth = 0;

  @override
  void initState() {
    super.initState();
    _songId = widget.song?.id;
    _source = widget.source;
    if (widget.files != null && widget.files!.isNotEmpty) {
      _openOrRead();
    } else {
      _loadList();
    }
  }

  @override
  void dispose() {
    _stopSoundOnly();
    _forgetPageImages();
    _ticker.dispose();
    _scroll.dispose();
    _saveTimer?.cancel();
    _saveNow();
    super.dispose();
  }

  String _titleOf(String file) =>
      file.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');

  Future<void> _loadList() async {
    final s = await ScanStore.list();
    if (mounted) setState(() => _saved = s);
  }

  // ---- Reading ----

  /// A song's sheet music: its scan from before if there is one (instant),
  /// else read now.
  Future<void> _openOrRead() async {
    final source = _source;
    final before = source == null ? null : await ScanStore.forSource(source);
    if (!mounted) return;
    if (before != null) {
      await _open(before);
      return;
    }
    await _readFiles(
      widget.files!,
      widget.song?.title ?? _titleOf(widget.files!.first.$1),
    );
  }

  /// Reads the kept pages again (after the reader got better, say).
  Future<void> _readAgain() async {
    final files = widget.files;
    _stop();
    if (files != null && files.isNotEmpty) {
      await _readFiles(files, _title);
    } else {
      _say('Open the music file again to read it afresh.');
    }
  }

  Future<void> _pick() async {
    final files = await pickBinaryFiles(sheetMusicExtensions);
    if (files.isEmpty || !mounted) return;
    _stop();
    _songId = null;
    _source = null;
    await _readFiles(files, _titleOf(files.first.$1));
  }

  Future<void> _readFiles(List<(String, Uint8List)> files, String title) async {
    setState(() => _busy = 'Opening…');
    try {
      final (gray, shown) = await pagesOf(files);
      if (!mounted) return;
      setState(
        () => _busy =
            'Reading the notes (${shown.length} page${shown.length == 1 ? '' : 's'})…',
      );
      // Let the message show before the work starts.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final score = kIsWeb
          ? await readScoreAsync(
              gray,
              title: title,
              onPage: (done) {
                if (mounted) {
                  setState(
                    () => _busy =
                        'Reading the notes: page ${math.min(done + 1, gray.length)} of ${gray.length}…',
                  );
                }
              },
            )
          : await compute(_readInBackground, (gray, title));
      final play = PlaySettings(tempo: score.tempo);
      // Two staves joined: a piano (or organ) part, so piano for both.
      for (var i = 0; i < score.staves; i++) {
        play.part(i);
      }
      // Replaces an older scan of the same file.
      final old = _source == null ? null : await ScanStore.forSource(_source!);
      if (old != null) await ScanStore.delete(old.id);
      final id = await ScanStore.add(
        title,
        shown,
        score,
        play,
        songId: _songId,
        source: _source,
      );
      if (!mounted) return;
      setState(() {
        _id = id;
        _title = title;
        _score = score;
        _pages = shown;
        _forgetPageImages();
        _play = play;
        _busy = null;
        _perf = null;
        _layout = null;
        _q = 0;
        _revision++;
      });
      _prepare();
      final found = score.notes.where((n) => !n.rest).length;
      _say(
        found == 0
            ? 'No notes found. Try a sharper, straighter picture (printed music, good light).'
            : 'Read $found notes in ${score.measures.length} measures. Tap a measure to play from there; ✎ to correct notes.',
      );
    } catch (e) {
      if (mounted) setState(() => _busy = null);
      _say('Couldn’t read that: $e');
    }
  }

  Future<void> _open(ScanInfo info) async {
    setState(() => _busy = 'Opening…');
    final got = await ScanStore.load(info.id);
    if (!mounted) return;
    if (got == null) {
      setState(() => _busy = null);
      _say('That scan is gone.');
      return;
    }
    setState(() {
      _id = info.id;
      _title = info.title;
      _songId = info.songId;
      _source = info.source;
      _score = got.$1;
      _play = got.$2;
      _pages = got.$3;
      _forgetPageImages();
      _busy = null;
      _perf = null;
      _layout = null;
      _q = 0;
      _revision++;
    });
    _prepare();
  }

  void _changed() {
    _score!.retime();
    _revision++;
    _perf = null;
    _layout = null;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
    setState(() {});
  }

  void _saveNow() {
    final id = _id, score = _score;
    if (id == null || score == null) return;
    ScanStore.save(
      id,
      _title,
      score,
      _play,
      pages: _pages.length,
      songId: _songId,
      source: _source,
    );
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- Playing ----

  Performance get _performance => _perf ??= perform(_score!, _play);

  double get _secondsPerQuarter => 60 / _play.tempo;

  /// The sounds the mix uses: the grand piano, imported SoundFonts.
  Future<Map<String, PadSound>> _sounds() async {
    final sounds = <String, PadSound>{};
    try {
      _piano ??= PadSound.decode(
        (await rootBundle.load('assets/sounds/piano.pad')).buffer.asUint8List(),
      );
      sounds[grandPiano] = _piano!;
    } catch (_) {
      // No sampled piano (tests): the built-in one plays.
    }
    for (final p in _play.parts) {
      final id = p.soundId;
      if (id != null && !sounds.containsKey(id)) {
        final s = await PadSoundStore.load(id.replaceFirst('sf:', ''));
        if (s != null) sounds[id] = s;
      }
    }
    return sounds;
  }

  String get _key => '$_revision ${jsonEncode(_play.toJson())}';

  /// The rendered performance (made once per settings; reused for every
  /// start and jump).
  Future<Float32List> _ensureAudio() {
    final key = _key;
    if (_audio != null && _audioKey == key) return Future.value(_audio!);
    if (_rendering != null && _audioKey == key) return _rendering!;
    _audioKey = key;
    final score = _score!;
    final perf = _performance;
    return _rendering = () async {
      final sounds = await _sounds();
      // Let a frame through before the work.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final audio = render(score, perf, _play, sounds: sounds);
      if (_audioKey == key) _audio = audio;
      _rendering = null;
      return audio;
    }();
  }

  /// Renders ahead (after opening, or a change) so Play starts at once.
  void _prepare() {
    if (_score == null) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _score != null) _ensureAudio();
    });
  }

  Future<void> _start([double? from]) async {
    final score = _score;
    if (score == null) return;
    _stopSoundOnly();
    final perf = _performance;
    var at = from ?? _q;
    if (at >= perf.length - 0.01) at = 0;
    final ready = _audio != null && _audioKey == _key;
    if (!ready) setState(() => _preparing = true);
    final audio = await _ensureAudio();
    if (!mounted) return;
    if (_preparing) setState(() => _preparing = false);
    final offset = (at * _secondsPerQuarter * playbackRate).round().clamp(
      0,
      audio.length - 1,
    );
    playSound(Float32List.sublistView(audio, offset), playbackRate);
    _startQ = at;
    _q = at;
    _clock
      ..reset()
      ..start();
    if (!_ticker.isActive) _ticker.start();
    setState(() => _playing = true);
  }

  void _tick(Duration _) {
    if (!_playing) return;
    final q = _startQ + _clock.elapsedMicroseconds / 1e6 / _secondsPerQuarter;
    final perf = _performance;
    if (q > perf.length + 0.25) {
      _stop(toStart: true);
      return;
    }
    final lit = <int>{
      for (final n in perf.notes)
        if (n.start <= q && q < n.start + n.length) n.note,
    };
    final m = perf.measureAt(q);
    if (m != _litMeasure) _follow(m);
    setState(() {
      _q = q;
      _lit = lit;
      _litMeasure = m;
    });
  }

  void _stopSoundOnly() {
    if (_playing) stopSound();
  }

  void _stop({bool toStart = false}) {
    _stopSoundOnly();
    _clock.stop();
    if (_ticker.isActive) _ticker.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _lit = {};
      if (toStart) {
        _q = 0;
        _litMeasure = null;
      }
    });
  }

  /// Settings changed while playing: carry on from here with them.
  void _replay() {
    _perf = null;
    if (!_playing) _prepare();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
    if (_playing) _start(_q);
    setState(() {});
  }

  void _playMeasure(int m) {
    final at = _performance.startOf(m);
    if (at != null) _start(at);
  }

  /// Keeps the measure playing in view.
  void _follow(int? m) {
    if (m == null || !_scroll.hasClients) return;
    final score = _score!;
    double? y;
    if (_notesView) {
      final r = _layout?.measureRects[m];
      if (r != null) y = r.top;
    } else {
      final measure = score.measures[m];
      final width = _pageWidth;
      var top = 0.0;
      for (var p = 0; p < measure.page && p < _pages.length; p++) {
        top += _pages[p].height * width / _pages[p].width + 12;
      }
      final page = _pages[math.min(measure.page, _pages.length - 1)];
      y = top + measure.box.t * width / page.width;
    }
    if (y == null) return;
    final pos = _scroll.position;
    final view = pos.viewportDimension;
    if (y < pos.pixels + 20 || y > pos.pixels + view * 0.6) {
      _scroll.animateTo(
        (y - view * 0.2).clamp(0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  double _pageWidth = 600;

  // ---- Correcting ----

  ScoreNote? get _sel =>
      _selected == null || _score == null || _selected! >= _score!.notes.length
      ? null
      : _score!.notes[_selected!];

  void _tapAt(int? note, int? measure) {
    if (_editing) {
      setState(() => _selected = note);
      if (note == null && measure != null) _playMeasure(measure);
      return;
    }
    if (measure != null) _playMeasure(measure);
  }

  // ---- Exports ----

  String get _fileBase {
    final t = _title.trim().isEmpty ? 'score' : _title.trim();
    return t.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> _export(String what) async {
    final score = _score!;
    score.tempo = _play.tempo;
    switch (what) {
      case 'xml':
        downloadBytes(
          '$_fileBase.musicxml',
          Uint8List.fromList(
            scoreToMusicXml(score).codeUnits
                .map((c) => c > 255 ? 63 : c)
                .toList(),
          ),
          'application/vnd.recordare.musicxml+xml',
        );
      case 'abc':
        // As ABC text: paste it into a song between {start_of_abc} and
        // {end_of_abc} (the editor's Melody button) to show it there.
        final abc = scoreToAbc(score..title = _title);
        await Clipboard.setData(ClipboardData(text: abc));
        downloadTextFile('$_fileBase.abc', abc, mime: 'text/vnd.abc');
        _say(
          'ABC copied: paste it into a song with the editor’s Melody button.',
        );
      case 'midi':
        downloadBytes(
          '$_fileBase.mid',
          scoreToMidi(score, _play),
          'audio/midi',
        );
      case 'wav':
        setState(() => _busy = 'Making the audio…');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final sounds = <String, PadSound>{};
        for (final p in _play.parts) {
          final id = p.soundId;
          if (id != null) {
            final s = await PadSoundStore.load(id.replaceFirst('sf:', ''));
            if (s != null) sounds[id] = s;
          }
        }
        final perf = perform(score, _play);
        final wav = samplesToWav(
          render(score, perf, _play, sounds: sounds),
          playbackRate,
        );
        if (mounted) setState(() => _busy = null);
        downloadBytes('$_fileBase.wav', wav, 'audio/wav');
      case 'pdf':
        setState(() => _busy = 'Making the PDF…');
        try {
          downloadBytes('$_fileBase.pdf', await _pdf(score), 'application/pdf');
        } finally {
          if (mounted) setState(() => _busy = null);
        }
    }
  }

  Future<Uint8List> _pdf(Score score) async {
    const width = 760.0;
    final layout = ScoreLayout(score, width);
    final pageH = width * PdfPageFormat.a4.height / PdfPageFormat.a4.width;
    final doc = pw.Document(title: _title);
    // Whole lines on each page.
    var from = 0.0;
    var first = true;
    while (from < layout.height - 1) {
      final titleRoom = first ? 40.0 : 0.0;
      var to = from + pageH - 30 - titleRoom;
      // Back up to a line's end.
      final lineEnds = [
        for (var l = 1; l <= layout.lines.length; l++)
          layout.top + l * layout.lineHeight - layout.space * 3,
      ];
      final fit = lineEnds.where((e) => e > from && e <= to).toList();
      if (fit.isNotEmpty) to = fit.last;
      final img = await renderLayout(layout, from, to - from, 3);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
      img.dispose();
      final isFirst = first;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (isFirst && _title.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 12),
                  child: pw.Center(
                    child: pw.Text(
                      _title,
                      style: const pw.TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              pw.Image(pw.MemoryImage(png)),
            ],
          ),
        ),
      );
      from = to;
      first = false;
    }
    return doc.save();
  }

  // ---- Chords ----

  Future<void> _chords() async {
    final score = _score!;
    final shift = _play.transpose + _play.written.semitones;
    final guesses = guessChords(score, shift: shift);
    final text = chordsToChordPro(guesses, score.measures.length);
    final song = model.songById(_songId ?? '') ?? model.currentSong;
    await showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chords from the music'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                score.staves > 1
                    ? 'From the harmony, bar by bar (half bars where it changes).'
                    : 'From the melody alone: a starting point to check by ear.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Cousine'],
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              _say('Chords copied');
            },
            child: const Text('Copy'),
          ),
          if (song != null)
            FilledButton(
              onPressed: () {
                song.raw =
                    '${song.raw.trimRight()}\n\n{comment: Chords from the sheet music}\n$text\n';
                model.addOrUpdate(song);
                Navigator.pop(context);
                _say('Added to “${song.title}”');
              },
              child: Text('Add to “${song.title}”'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final score = _score;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          score == null
              ? 'Sheet music scanner'
              : (_title.isEmpty ? 'Scan' : _title),
        ),
        actions: score == null
            ? [
                IconButton(
                  tooltip: 'Open a photo, picture or PDF of sheet music',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: _busy == null ? _pick : null,
                ),
              ]
            : [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Scan'),
                      icon: Icon(Icons.image_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Notes'),
                      icon: Icon(Icons.music_note, size: 18),
                    ),
                  ],
                  selected: {_notesView},
                  onSelectionChanged: (v) =>
                      setState(() => _notesView = v.first),
                ),
                IconButton(
                  tooltip: _editing
                      ? 'Done correcting'
                      : 'Correct notes (tap one)',
                  isSelected: _editing,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() {
                    _editing = !_editing;
                    _selected = null;
                  }),
                ),
                IconButton(
                  tooltip: 'Chords from the music',
                  icon: const Icon(Icons.queue_music),
                  onPressed: _chords,
                ),
                PopupMenuButton<String>(
                  // Wide enough that its rows' titles stay on one line.
                  constraints: const BoxConstraints(
                    minWidth: 240,
                    maxWidth: 340,
                  ),
                  tooltip: 'Export and more',
                  onSelected: (v) async {
                    switch (v) {
                      case 'rename':
                        _rename();
                      case 'open':
                        _pick();
                      case 'again':
                        _readAgain();
                      case 'list':
                        _stop();
                        _saveNow();
                        setState(() {
                          _score = null;
                          _id = null;
                        });
                        _loadList();
                      default:
                        _export(v);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'xml',
                      child: ListTile(
                        leading: Icon(Icons.description_outlined),
                        title: Text('Export MusicXML'),
                        subtitle: Text('MuseScore, Finale, Sibelius, Dorico…'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'abc',
                      child: ListTile(
                        leading: Icon(Icons.text_snippet_outlined),
                        title: Text('Export ABC'),
                        subtitle: Text('Also copied, to paste into a song'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'midi',
                      child: ListTile(
                        leading: Icon(Icons.piano_outlined),
                        title: Text('Export MIDI'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'wav',
                      child: ListTile(
                        leading: Icon(Icons.audio_file_outlined),
                        title: Text('Export audio (WAV)'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'pdf',
                      child: ListTile(
                        leading: Icon(Icons.picture_as_pdf_outlined),
                        title: Text('Export PDF (the notes, redrawn)'),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('Rename…'),
                      ),
                    ),
                    if (widget.files != null)
                      const PopupMenuItem(
                        value: 'again',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('Read the music again'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'open',
                      child: ListTile(
                        leading: Icon(Icons.add_photo_alternate_outlined),
                        title: Text('Scan other music…'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'list',
                      child: ListTile(
                        leading: Icon(Icons.library_music_outlined),
                        title: Text('All scans'),
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Stack(
        children: [
          if (score == null) _start0() else _scoreBody(score),
          if (_busy != null)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: 0.8),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppSpinner(),
                      const SizedBox(height: 16),
                      Text(_busy!),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: score == null ? null : _transport(score),
    );
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _title);
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name'),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _title = name.trim());
    _saveNow();
  }

  Widget _start0() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read printed sheet music',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Open a photo, scan or PDF (several pages work). The notes are read on this device, '
                  'no internet needed. Then play them back with the notes lit up, change the tempo, key '
                  'and instrument, fix anything misread, export MusicXML, MIDI, audio or PDF, and get '
                  'the chords for a song.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Best with clearly printed music, straight and evenly lit (about 300 dpi for scans). '
                  'Treble, bass and alto clefs; notes, rests, dots, accidentals, ties, triplets, repeats, '
                  'two voices on a staff, and piano (two-staff) music. Not handwriting, tab or percussion.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy == null ? _pick : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Open photo, picture or PDF…'),
                ),
              ],
            ),
          ),
        ),
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Scans', style: theme.textTheme.titleMedium),
          for (final s in _saved)
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: Text(s.title),
              subtitle: Text(
                '${s.notes} notes · ${s.pages} page${s.pages == 1 ? '' : 's'}',
              ),
              onTap: () => _open(s),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await ScanStore.delete(s.id);
                  _loadList();
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _scoreBody(Score score) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editing) _editBar(score),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              _pageWidth = math.min(box.maxWidth - 24, 1100);
              if (_notesView) {
                final w = _pageWidth;
                if (_layout == null || _layoutWidth != w) {
                  _layout = ScoreLayout(score, w, space: w < 500 ? 6.5 : 8);
                  _layoutWidth = w;
                }
                final layout = _layout!;
                return SingleChildScrollView(
                  controller: _scroll,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.white,
                      child: GestureDetector(
                        onTapUp: (d) => _tapAt(
                          layout.noteAt(d.localPosition),
                          layout.measureAt(d.localPosition),
                        ),
                        child: CustomPaint(
                          size: Size(w, layout.height),
                          painter: ScorePainter(
                            layout,
                            ink: Colors.black,
                            accent: scheme.primary,
                            lit: _lit,
                            selected: _selected,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _pages.length,
                itemBuilder: (context, p) {
                  final page = _pages[p];
                  final w = _pageWidth;
                  final scale = w / page.width;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTapUp: (d) {
                          final x = d.localPosition.dx / scale,
                              y = d.localPosition.dy / scale;
                          int? note;
                          for (final (i, n) in score.notes.indexed) {
                            if (n.page == p && n.box.expand(6).contains(x, y)) {
                              note = i;
                              break;
                            }
                          }
                          _tapAt(note, score.measureAt(p, x, y));
                        },
                        child: SizedBox(
                          width: w,
                          height: page.height * scale,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                page.image,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: _ScanOverlay(
                                  score: score,
                                  page: p,
                                  scale: scale,
                                  lit: _lit,
                                  measure: _playing ? _litMeasure : null,
                                  selected: _selected,
                                  showAll: _editing,
                                  accent: scheme.primary,
                                  image: _lit.isEmpty ? null : _pageImage(p),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _editBar(Score score) {
    final n = _sel;
    final scheme = Theme.of(context).colorScheme;
    if (n == null) {
      return Material(
        color: scheme.surfaceContainerHigh,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Tap a note or rest to correct it. Boxes show what was read.',
          ),
        ),
      );
    }
    void edit(void Function() f) {
      f();
      _changed();
    }

    final name = n.rest
        ? 'Rest'
        : '${stepOf(n.diatonic)}${switch (n.alter) {
            1 => '♯',
            -1 => '♭',
            2 => '𝄪',
            -2 => '𝄫',
            _ => '',
          }}${n.diatonic ~/ 7}';
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          spacing: 6,
          children: [
            SizedBox(
              width: 56,
              child: Text(name, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (!n.rest) ...[
              IconButton.filledTonal(
                tooltip: 'Higher',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => edit(() => n.diatonic++),
              ),
              IconButton.filledTonal(
                tooltip: 'Lower',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => edit(() => n.diatonic--),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: 9,
                    label: Text('–'),
                    tooltip: 'No accidental',
                  ),
                  ButtonSegment(value: 1, label: Text('♯')),
                  ButtonSegment(value: -1, label: Text('♭')),
                  ButtonSegment(value: 0, label: Text('♮')),
                ],
                selected: {n.accidental ?? 9},
                onSelectionChanged: (v) =>
                    edit(() => n.accidental = v.first == 9 ? null : v.first),
              ),
            ],
            AppDropdown<String>(
              value: n.type,
              items: [
                for (final t in noteTypes.keys)
                  DropdownMenuItem(
                    value: t,
                    child: Text(switch (t) {
                      'whole' => 'Whole',
                      'half' => 'Half',
                      'quarter' => 'Quarter',
                      'eighth' => 'Eighth',
                      '16th' => '16th',
                      _ => '32nd',
                    }),
                  ),
              ],
              onChanged: (v) => edit(() => n.type = v!),
            ),
            FilterChip(
              label: const Text('Dot'),
              selected: n.dots > 0,
              onSelected: (v) => edit(() => n.dots = v ? 1 : 0),
            ),
            FilterChip(
              label: const Text('Triplet'),
              selected: n.triplet,
              onSelected: (v) => edit(() => n.triplet = v),
            ),
            if (!n.rest)
              FilterChip(
                label: const Text('Tied'),
                selected: n.tie,
                onSelected: (v) => edit(() => n.tie = v),
              ),
            FilterChip(
              label: const Text('Rest'),
              selected: n.rest,
              onSelected: (v) => edit(() => n.rest = v),
            ),
            if (score.staves == 1 || true)
              FilterChip(
                label: const Text('Voice 2'),
                tooltip: 'A second part on the same staff',
                selected: n.voice == 2,
                onSelected: (v) => edit(() => n.voice = v ? 2 : 1),
              ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              onPressed: () => edit(() {
                score.notes.removeAt(_selected!);
                _selected = null;
              }),
            ),
            TextButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play from here'),
              onPressed: () => _playMeasure(n.measure),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transport(Score score) {
    final scheme = Theme.of(context).colorScheme;
    final perfLen = _performance.length;
    final shift = _play.transpose;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              IconButton.filled(
                tooltip: _preparing
                    ? 'Getting the sound ready…'
                    : (_playing ? 'Pause' : 'Play'),
                icon: _preparing
                    ? const SizedBox.square(
                        dimension: 22,
                        child: AppSpinner(strokeWidth: 2.5),
                      )
                    : Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: _preparing
                    ? null
                    : () => _playing ? _stop() : _start(),
              ),
              IconButton(
                tooltip: 'Back to the start',
                icon: const Icon(Icons.skip_previous),
                onPressed: () {
                  final was = _playing;
                  _stop(toStart: true);
                  if (was) _start(0);
                },
              ),
              SizedBox(
                width: 60,
                child: Text(
                  _litMeasure == null
                      ? '${score.measures.length} bars'
                      : 'Bar ${_litMeasure! + 1}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('♩ = ${_play.tempo}'),
                  SizedBox(
                    width: 150,
                    child: Slider(
                      min: 50,
                      max: 330,
                      value: _play.tempo.toDouble().clamp(50, 330),
                      onChanged: (v) => setState(() {
                        // Keep the place while changing speed.
                        if (_playing) {
                          _startQ = _q;
                          _clock
                            ..reset()
                            ..start();
                        }
                        _play.tempo = v.round();
                      }),
                      onChangeEnd: (_) => _replay(),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Down a semitone',
                    icon: const Icon(Icons.remove),
                    onPressed: shift <= -24
                        ? null
                        : () {
                            _play.transpose--;
                            _replay();
                          },
                  ),
                  Tooltip(
                    message: 'Pitch (semitones, up to two octaves each way)',
                    child: Text(
                      shift == 0
                          ? 'Key ±0'
                          : 'Key ${shift > 0 ? '+' : ''}$shift',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Up a semitone',
                    icon: const Icon(Icons.add),
                    onPressed: shift >= 24
                        ? null
                        : () {
                            _play.transpose++;
                            _replay();
                          },
                  ),
                ],
              ),
              IconButton(
                tooltip: _play.sustain
                    ? 'Sustain on (notes ring on a little)'
                    : 'Sustain (notes ring on a little)',
                isSelected: _play.sustain,
                icon: const Icon(Icons.waves),
                onPressed: () {
                  _play.sustain = !_play.sustain;
                  _replay();
                },
              ),
              IconButton(
                tooltip: _play.reverb ? 'Reverb on' : 'Reverb (room sound)',
                isSelected: _play.reverb,
                icon: const Icon(Icons.surround_sound_outlined),
                onPressed: () {
                  _play.reverb = !_play.reverb;
                  _replay();
                },
              ),
              IconButton(
                tooltip: _play.metronome ? 'Metronome on' : 'Metronome',
                isSelected: _play.metronome,
                icon: const Icon(Icons.av_timer),
                onPressed: () {
                  _play.metronome = !_play.metronome;
                  _replay();
                },
              ),
              if (score.staves > 1) _partsButton(score),
              IconButton(
                tooltip: 'Instruments, mixer and sound',
                icon: const Icon(Icons.tune),
                onPressed: () => _mixer(score),
              ),
              if (perfLen > 0 && _q > 0)
                SizedBox(
                  width: 120,
                  child: AppProgressBar(value: (_q / perfLen).clamp(0, 1)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Which parts play: all by default; tick to hear one alone.
  Widget _partsButton(Score score) {
    final names = score.partNames;
    final playing = [
      for (var i = 0; i < names.length; i++)
        if (!_play.part(i).muted) i,
    ];
    final all = playing.length == names.length;
    return PopupMenuButton<int>(
      tooltip: 'Parts to play',
      onSelected: (i) {
        if (i < 0) {
          for (var k = 0; k < names.length; k++) {
            _play.part(k).muted = false;
          }
        } else if (i >= 1000) {
          // Just this one.
          for (var k = 0; k < names.length; k++) {
            _play.part(k).muted = k != i - 1000;
          }
        } else {
          final p = _play.part(i);
          p.muted = !p.muted;
          // Never all silent.
          if (playing.length == 1 && playing.first == i) p.muted = false;
        }
        _replay();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: all,
          child: const Text('All parts'),
        ),
        const PopupMenuDivider(),
        for (final (i, n) in names.indexed)
          CheckedPopupMenuItem(
            value: i,
            checked: playing.contains(i),
            child: Text(n),
          ),
        const PopupMenuDivider(),
        for (final (i, n) in names.indexed)
          PopupMenuItem(value: 1000 + i, child: Text('Only $n')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            const Icon(Icons.groups_outlined),
            Text(
              all
                  ? 'All parts'
                  : (playing.length == 1
                        ? names[playing.first]
                        : '${playing.length} parts'),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _mixer(Score score) async {
    final sounds = [
      for (final m in model.settings.padSounds)
        ('sf:${m['id']}', m['name'] ?? 'Sound'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          void change(void Function() f) {
            f();
            setLocal(() {});
            _replay();
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Mixer', style: Theme.of(context).textTheme.titleMedium),
                  for (var st = 0; st < score.staves; st++) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text(score.partNames[st])),
                        AppDropdown<String>(
                          value:
                              _play.part(st).soundId ??
                              _play.part(st).instrument.name,
                          items: [
                            for (final i in Instrument.values)
                              DropdownMenuItem(
                                value: i.name,
                                child: Text(i.label),
                              ),
                            for (final (id, name) in sounds)
                              DropdownMenuItem(
                                value: id,
                                child: Text('$name (SoundFont)'),
                              ),
                          ],
                          onChanged: (v) => change(() {
                            final p = _play.part(st);
                            if (v!.startsWith('sf:')) {
                              p.soundId = v;
                            } else {
                              p
                                ..soundId = null
                                ..instrument = Instrument.values.byName(v);
                            }
                          }),
                        ),
                        IconButton(
                          tooltip: _play.part(st).muted
                              ? 'Unmute'
                              : 'Mute (play the others alone)',
                          isSelected: _play.part(st).muted,
                          icon: Icon(
                            _play.part(st).muted
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                          onPressed: () => change(
                            () => _play.part(st).muted = !_play.part(st).muted,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _play.part(st).volume,
                      onChanged: (v) =>
                          setLocal(() => _play.part(st).volume = v),
                      onChangeEnd: (_) => _replay(),
                    ),
                  ],
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(child: Text('Written for')),
                      AppDropdown<Transposing>(
                        value: _play.written,
                        items: [
                          for (final t in Transposing.values)
                            DropdownMenuItem(value: t, child: Text(t.label)),
                        ],
                        onChanged: (v) => change(() => _play.written = v!),
                      ),
                    ],
                  ),
                  Text(
                    'Music for a transposing instrument plays at the pitch that instrument sounds.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tuning: A = ${_play.referenceA.round()} Hz',
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: Slider(
                          min: 380,
                          max: 480,
                          divisions: 100,
                          value: _play.referenceA.clamp(380, 480),
                          onChanged: (v) =>
                              setLocal(() => _play.referenceA = v),
                          onChangeEnd: (_) => _replay(),
                        ),
                      ),
                      TextButton(
                        onPressed: () => change(() => _play.referenceA = 440),
                        child: const Text('440'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Metronome'),
                    value: _play.metronome,
                    onChanged: (v) => change(() => _play.metronome = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Count in one bar'),
                    value: _play.countIn,
                    onChanged: (v) => change(() => _play.countIn = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sustain'),
                    subtitle: const Text(
                      'Notes ring on a little, like a light pedal',
                    ),
                    value: _play.sustain,
                    onChanged: (v) => change(() => _play.sustain = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reverb'),
                    subtitle: const Text('A little room sound'),
                    value: _play.reverb,
                    onChanged: (v) => change(() => _play.reverb = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Swing eighths'),
                    subtitle: const Text('Long-short, as in jazz and gospel'),
                    value: _play.swing,
                    onChanged: (v) => change(() => _play.swing = v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    setState(() {});
  }
}

/// On the page picture: what was read (while correcting), the notes
/// sounding, the measure playing.
class _ScanOverlay extends CustomPainter {
  final Score score;
  final int page;
  final double scale;
  final Set<int> lit;
  final int? measure;
  final int? selected;
  final bool showAll;
  final Color accent;

  /// The page picture (smaller), to recolour the ink of notes playing.
  final ui.Image? image;

  _ScanOverlay({
    required this.score,
    required this.page,
    required this.scale,
    required this.lit,
    required this.measure,
    required this.selected,
    required this.showAll,
    required this.accent,
    this.image,
  });

  Rect _r(Box b) =>
      Rect.fromLTRB(b.l * scale, b.t * scale, b.r * scale, b.b * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final m = measure;
    if (m != null &&
        m < score.measures.length &&
        score.measures[m].page == page) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _r(score.measures[m].box),
          const Radius.circular(6),
        ),
        Paint()..color = accent.withValues(alpha: 0.08),
      );
    }
    for (final (i, n) in score.notes.indexed) {
      if (n.page != page) continue;
      final r = _r(n.box).inflate(2);
      if (lit.contains(i)) {
        final img = image;
        if (img != null) {
          // The note's own ink, in the accent colour (paper stays clear).
          final pw = score.pages[page].$1, ph = score.pages[page].$2;
          final fx = img.width / pw, fy = img.height / ph;
          final grow = r.height * 0.15;
          final dst = r.inflate(grow);
          final src = Rect.fromLTRB(
            dst.left / scale * fx,
            dst.top / scale * fy,
            dst.right / scale * fx,
            dst.bottom / scale * fy,
          );
          canvas.drawImageRect(
            img,
            src,
            dst,
            Paint()
              ..colorFilter = ColorFilter.matrix([
                0,
                0,
                0,
                0,
                (accent.r * 255).roundToDouble(),
                0,
                0,
                0,
                0,
                (accent.g * 255).roundToDouble(),
                0,
                0,
                0,
                0,
                (accent.b * 255).roundToDouble(),
                -0.6,
                -1.17,
                -0.23,
                0,
                510,
              ]),
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(4)),
            Paint()..color = accent.withValues(alpha: 0.55),
          );
        }
      }
      if (showAll || i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == selected ? 2.5 : 1.2
            ..color = i == selected
                ? Colors.orange
                : (n.rest ? Colors.teal : accent).withValues(alpha: 0.8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScanOverlay old) => true;
}
