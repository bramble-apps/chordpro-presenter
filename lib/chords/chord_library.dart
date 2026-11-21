import 'package:flutter/material.dart';

import '../state.dart';
import 'chord_db.dart';
import 'chord_diagram.dart';
import 'chord_sound.dart';
import 'chord_strip.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// Chord Library: every diagram for a chord on an instrument, plus the
/// shapes you made (My chords). Tap a diagram to hear it; + makes a shape.
Future<void> showChordLibrary(BuildContext context, PresenterModel model) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => _ChordLibraryDialog(model: model),
    );

class _ChordLibraryDialog extends StatefulWidget {
  final PresenterModel model;
  const _ChordLibraryDialog({required this.model});

  @override
  State<_ChordLibraryDialog> createState() => _ChordLibraryDialogState();
}

class _ChordLibraryDialogState extends State<_ChordLibraryDialog> {
  PresenterModel get model => widget.model;
  late Instrument _instrument = model.settings.chordInstrument;
  bool _mine = false;
  int _root = 0;
  String _suffix = 'major';
  int? _bass;

  @override
  void initState() {
    super.initState();
    ChordLibrary.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  ChordName get _chord => ChordName(_root, _suffix, _bass);

  @override
  Widget build(BuildContext context) {
    final s = model.settings;
    final suffixes = ChordLibrary.suffixesFor(_instrument);
    if (!suffixes.contains(_suffix) && suffixes.isNotEmpty) {
      _suffix = suffixes.first;
    }
    final custom = [
      for (final c in s.customChords)
        if (c.instrument == _instrument) c,
    ];
    final shapes = _mine
        ? custom
        : ChordLibrary.shapesFor(_instrument, _chord, custom: custom);
    final screen = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Chord Library')),
          IconButton(
            tooltip: 'Make your own shape',
            icon: const Icon(BrambleIcons.plus),
            onPressed: () => _add(context),
          ),
        ],
      ),
      content: SizedBox(
        width: screen.width < 760 ? screen.width : 720,
        height: screen.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<Instrument>(
                  showSelectedIcon: false,
                  segments: [
                    for (final i in Instrument.values)
                      ButtonSegment(value: i, label: Text(i.label)),
                  ],
                  selected: {_instrument},
                  onSelectionChanged: (v) =>
                      setState(() => _instrument = v.first),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: false,
                      label: Text('All chords'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('My chords (${custom.length})'),
                    ),
                  ],
                  selected: {_mine},
                  onSelectionChanged: (v) => setState(() => _mine = v.first),
                ),
              ],
            ),
            if (!_mine) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Chord'),
                  AppDropdown<int>(
                    value: _root,
                    items: [
                      for (var pc = 0; pc < 12; pc++)
                        DropdownMenuItem(value: pc, child: Text(noteName(pc))),
                    ],
                    onChanged: (v) => setState(() => _root = v ?? 0),
                  ),
                  AppDropdown<String>(
                    value: _suffix,
                    items: [
                      for (final x in suffixes)
                        DropdownMenuItem(value: x, child: Text(x)),
                    ],
                    onChanged: (v) => setState(() => _suffix = v ?? 'major'),
                  ),
                  const Text('/'),
                  AppDropdown<int?>(
                    value: _bass,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('–'),
                      ),
                      for (var pc = 0; pc < 12; pc++)
                        DropdownMenuItem<int?>(
                          value: pc,
                          child: Text(noteName(pc)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _bass = v),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: shapes.isEmpty
                  ? Center(
                      child: Text(
                        _mine
                            ? 'No shapes of your own yet. Tap + to make one.'
                            : 'No diagrams for this chord.',
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final shape in shapes)
                            ChordDiagram(
                              name: chordLabel(
                                ChordName(shape.root, shape.suffix, shape.bass),
                              ),
                              shape: shape,
                              instrument: _instrument,
                              showFingers: s.showDiagramFingers,
                              onTap: () =>
                                  playChord(shape, speed: s.chordPlaySpeed),
                              onLongPress: shape.customId == null
                                  ? null
                                  : () => _delete(context, shape),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final shape = await showChordEditor(
      context,
      instrument: _instrument,
      chord: _mine ? null : _chord,
    );
    if (shape == null) return;
    model.updateSettings((s) => s.customChords = [...s.customChords, shape]);
    setState(() => _mine = true);
  }

  Future<void> _delete(BuildContext context, ChordShape shape) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this shape?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    model.updateSettings(
      (s) => s.customChords = [
        for (final c in s.customChords)
          if (c.customId != shape.customId) c,
      ],
    );
    setState(() {});
  }
}

/// The Chord Editor: name, base fret, and for each string the fret and
/// finger (guitar / ukulele), or the keys (piano), with a live preview.
Future<ChordShape?> showChordEditor(
  BuildContext context, {
  required Instrument instrument,
  ChordName? chord,
}) => showAppDialog<ChordShape>(
  context: context,
  builder: (_) => _ChordEditor(instrument: instrument, chord: chord),
);

class _ChordEditor extends StatefulWidget {
  final Instrument instrument;
  final ChordName? chord;
  const _ChordEditor({required this.instrument, this.chord});

  @override
  State<_ChordEditor> createState() => _ChordEditorState();
}

class _ChordEditorState extends State<_ChordEditor> {
  late final _name = TextEditingController(
    text: widget.chord == null ? '' : chordLabel(widget.chord!),
  );
  late final int _strings = widget.instrument.fretted
      ? stringTuning[widget.instrument]!.length
      : 0;
  late final List<int> _frets = List.filled(_strings, 0);
  late final List<int> _fingers = List.filled(_strings, 0);
  int _baseFret = 1;
  int? _barre;
  final Set<int> _keys = {};

  ChordName? get _parsed => ChordName.parse(_name.text.trim());

  ChordShape? get _shape {
    final c = _parsed;
    if (c == null) return null;
    return ChordShape(
      instrument: widget.instrument,
      root: c.root,
      suffix: c.suffix,
      bass: c.bass,
      baseFret: _baseFret,
      frets: [..._frets],
      fingers: [..._fingers],
      barres: [?_barre],
      keys: [..._keys]..sort(),
      customId: newId(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static const _stringNames = {
    Instrument.guitar: ['E', 'A', 'D', 'G', 'B', 'e'],
    Instrument.ukulele: ['G', 'C', 'E', 'A'],
  };

  @override
  Widget build(BuildContext context) {
    final shape = _shape;
    final fretted = widget.instrument.fretted;
    return AlertDialog(
      title: Text('New ${widget.instrument.label.toLowerCase()} chord'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Center(
                child: ChordDiagram(
                  name: _name.text.trim().isEmpty ? '?' : _name.text.trim(),
                  shape:
                      shape ??
                      ChordShape(
                        instrument: widget.instrument,
                        root: 0,
                        suffix: 'major',
                        baseFret: _baseFret,
                        frets: [..._frets],
                        fingers: [..._fingers],
                        barres: [?_barre],
                        keys: [..._keys],
                      ),
                  instrument: widget.instrument,
                  zoom: 1.4,
                  onTap: shape == null ? null : () => playChord(shape),
                ),
              ),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Cadd9',
                  border: const OutlineInputBorder(),
                  errorText: _name.text.trim().isNotEmpty && _parsed == null
                      ? 'Not a chord name this app knows'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (fretted) ...[
                Row(
                  children: [
                    const Text('Base fret'),
                    IconButton(
                      tooltip: 'Lower',
                      icon: const Icon(BrambleIcons.minus),
                      onPressed: _baseFret > 1
                          ? () => setState(() => _baseFret--)
                          : null,
                    ),
                    Text('$_baseFret'),
                    IconButton(
                      tooltip: 'Higher',
                      icon: const Icon(BrambleIcons.plus),
                      onPressed: _baseFret < 20
                          ? () => setState(() => _baseFret++)
                          : null,
                    ),
                    const Spacer(),
                    const Text('Barre '),
                    AppDropdown<int?>(
                      value: _barre,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('none'),
                        ),
                        for (var f = 1; f <= 5; f++)
                          DropdownMenuItem<int?>(
                            value: f,
                            child: Text('fret $f'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _barre = v),
                    ),
                  ],
                ),
                // Highest string on top, as on JustChords.
                for (var i = _strings - 1; i >= 0; i--)
                  Row(
                    spacing: 8,
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(_stringNames[widget.instrument]![i]),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: [
                              const ButtonSegment(value: -1, label: Text('×')),
                              const ButtonSegment(value: 0, label: Text('○')),
                              for (var f = 1; f <= 5; f++)
                                ButtonSegment(value: f, label: Text('$f')),
                            ],
                            selected: {_frets[i]},
                            onSelectionChanged: (v) =>
                                setState(() => _frets[i] = v.first),
                          ),
                        ),
                      ),
                      AppDropdown<int>(
                        value: _fingers[i],
                        items: [
                          const DropdownMenuItem(value: 0, child: Text('–')),
                          for (var f = 1; f <= 4; f++)
                            DropdownMenuItem(value: f, child: Text('$f')),
                        ],
                        onChanged: (v) => setState(() => _fingers[i] = v ?? 0),
                      ),
                    ],
                  ),
              ] else ...[
                const Text('Tap the keys of the chord:'),
                _KeyPicker(
                  keys: _keys,
                  onToggle: (k) => setState(
                    () => _keys.contains(k) ? _keys.remove(k) : _keys.add(k),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(_keys.clear),
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: shape == null ? null : () => Navigator.pop(context, shape),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Two octaves of keys to tap (piano editor).
class _KeyPicker extends StatelessWidget {
  final Set<int> keys;
  final ValueChanged<int> onToggle;
  const _KeyPicker({required this.keys, required this.onToggle});

  static const _whites = [0, 2, 4, 5, 7, 9, 11];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / 14;
        const h = 90.0;
        Widget key(int note, Rect r, bool black) => Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            onTap: () => onToggle(note),
            child: Container(
              decoration: BoxDecoration(
                color: keys.contains(note)
                    ? ChordDiagram.gold
                    : black
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                border: Border.all(color: Colors.black54),
              ),
            ),
          ),
        );
        return SizedBox(
          height: h,
          child: Stack(
            children: [
              for (var i = 0; i < 14; i++)
                key(
                  48 + (i ~/ 7) * 12 + _whites[i % 7],
                  Rect.fromLTWH(i * w, 0, w, h),
                  false,
                ),
              for (var i = 0; i < 14; i++)
                if (_whites[i % 7] != 4 && _whites[i % 7] != 11)
                  key(
                    48 + (i ~/ 7) * 12 + _whites[i % 7] + 1,
                    Rect.fromLTWH((i + 1) * w - w * 0.3, 0, w * 0.6, h * 0.6),
                    true,
                  ),
            ],
          ),
        );
      },
    );
  }
}
