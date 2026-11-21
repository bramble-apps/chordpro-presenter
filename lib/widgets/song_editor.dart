import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chord_beats.dart';
import '../browser.dart';
import '../format.dart';
import '../music.dart';
import '../pdfs.dart';
import '../song_icons.dart';
import '../state.dart';
import 'chord_beats_editor.dart';
import 'chordpro_field.dart';
import 'structure_editor.dart';
import '../eink.dart';
import 'detent_sheet.dart';

/// Edit dialog with three tabs: the ChordPro text, each chord's beats, and
/// song details (key, tempo, CCLI, tags...). "Save" (⌘S) keeps the changes; "Cancel" drops
/// them (a new song is only added on Save).
class SongEditor extends StatefulWidget {
  final Song song;
  final List<Tag> tags;

  /// For the chord beats settings (everyone's), in the Chord Beats tab.
  final PresenterModel? model;

  const SongEditor({
    super.key,
    required this.song,
    required this.tags,
    this.model,
    this.sheet = false,
  });

  /// In a phone's sheet: the screen's full width, tighter edges.
  final bool sheet;

  static Future<Song?> show(
    BuildContext context,
    Song song, {
    required List<Tag> tags,
    PresenterModel? model,
  }) {
    // Phones: a sheet from the bottom, edge to edge (no room lost to a
    // dialog's margins).
    if (useDetentSheet(context)) {
      return showDetentSheet<Song>(
        context,
        builder: (_) =>
            SongEditor(song: song, tags: tags, model: model, sheet: true),
      );
    }
    return showAppDialog<Song>(
      context: context,
      builder: (_) => SongEditor(song: song, tags: tags, model: model),
    );
  }

  @override
  State<SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<SongEditor> {
  late final Song _song = widget.song.copy();

  late final _title = TextEditingController(text: _song.title);
  late final _raw = ChordProController(text: _song.raw);

  /// Each chord's beats (Chord Beats tab), saved with the song.
  late final Map<String, int> _beats = chordBeatsOf(_song);
  late final Map<String, TextEditingController> _fields = {
    'Artist': TextEditingController(text: _song.artist),
    'Subtitle': TextEditingController(text: _song.subtitle),
    'Tempo (BPM)': TextEditingController(text: _song.tempo),
    'Time signature': TextEditingController(text: _song.timeSignature),
    'Duration': TextEditingController(text: _song.duration),
    'Composer': TextEditingController(text: _song.composer),
    'Lyricist': TextEditingController(text: _song.lyricist),
    'Copyright': TextEditingController(text: _song.copyright),
    'CCLI song #': TextEditingController(text: _song.ccli),
    'CCLI license #': TextEditingController(text: _song.ccliLicense),
    'Footer': TextEditingController(text: _song.footer),
    'Reference link (YouTube…)': TextEditingController(text: _song.audioUrl),
    'Notes': TextEditingController(text: _song.notes),
  };

  /// The person's own fields (name, value), in order.
  late final List<(TextEditingController, TextEditingController)> _custom = [
    for (final e in _song.custom.entries)
      (
        TextEditingController(text: e.key),
        TextEditingController(text: e.value),
      ),
  ];

  Map<String, String> get _customFields => {
    for (final (n, v) in _custom)
      if (n.text.trim().isNotEmpty) n.text.trim(): v.text.trim(),
  };

  /// Field names used on other songs (to pick from, as OnSong offers).
  List<String> get _knownFieldNames {
    final names = <String>{};
    for (final s in widget.model?.songs ?? const <Song>[]) {
      names.addAll(s.custom.keys);
    }
    final here = {for (final (n, _) in _custom) n.text.trim()};
    return names.where((n) => !here.contains(n)).toList()..sort();
  }

  @override
  void dispose() {
    _title.dispose();
    _raw.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final (n, v) in _custom) {
      n.dispose();
      v.dispose();
    }
    super.dispose();
  }

  String _f(String label) => _fields[label]!.text.trim();

  Song get _working => _withBeats(_song.copy())
    ..title = _title.text
    ..raw = _raw.text
    ..artist = _f('Artist')
    ..subtitle = _f('Subtitle')
    ..tempo = _f('Tempo (BPM)')
    ..timeSignature = _f('Time signature')
    ..duration = _f('Duration')
    ..composer = _f('Composer')
    ..lyricist = _f('Lyricist')
    ..copyright = _f('Copyright')
    ..ccli = _f('CCLI song #')
    ..ccliLicense = _f('CCLI license #')
    ..footer = _f('Footer')
    ..audioUrl = _f('Reference link (YouTube…)')
    ..notes = _f('Notes')
    ..custom = _customFields;

  Song _withBeats(Song s) {
    setChordBeats(s, _beats);
    return s;
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  void _save() {
    if (_canSave) Navigator.of(context).pop(_working);
  }

  static final _allKeys = [
    for (final minor in [false, true])
      for (var root = 0; root < 12; root++) MusicKey(root, minor),
  ];

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: _frame(
        DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                // As far from the top as from the sides (the sheet's
                // grabber takes its top 16)
                padding: widget.sheet
                    ? const EdgeInsets.fromLTRB(20, 4, 20, 0)
                    : const EdgeInsets.fromLTRB(20, 20, 20, 0),
                // The title, then the buttons on the same line
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _title,
                        autofocus: widget.song.title.isEmpty,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'Song title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _rewriteButton(),
                    const SizedBox(width: 4),
                    // Round ✕ and ✓ (cancel, save)
                    IconButton.filledTonal(
                      tooltip: 'Cancel',
                      style: _roundButton(context, tonal: true),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 8),
                    ListenableBuilder(
                      listenable: _title,
                      builder: (context, _) => IconButton.filled(
                        tooltip: 'Save',
                        style: _roundButton(context),
                        onPressed: _canSave ? _save : null,
                        icon: const Icon(Icons.check),
                      ),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'ChordPro'),
                  Tab(text: 'Chord Beats'),
                  Tab(text: 'Details'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [_chordProTab(), _beatsTab(), _detailsTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A dialog on a desktop or tablet; in a phone's sheet, just the page.
  /// ✕ and ✓: no room around them for touch (the circle is the edge, so
  /// the padding to it is what's seen); ✕ in the surface's own tint, not
  /// the theme's second colour.
  static ButtonStyle _roundButton(BuildContext context, {bool tonal = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: tonal ? scheme.surfaceContainerHighest : null,
      foregroundColor: tonal ? scheme.onSurface : null,
    );
  }

  Widget _frame(Widget page) => widget.sheet
      ? Material(type: MaterialType.transparency, child: page)
      : Dialog(
          insetPadding: const EdgeInsets.all(24),
          // (the edge-to-edge text area takes the rounded corners)
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 800),
            child: page,
          ),
        );

  /// "Rewrite into key": the chords written out in another key for good
  /// (as JustChords' tool), rather than transposed when shown.
  Widget _rewriteButton() => PopupMenuButton<MusicKey>(
    tooltip: 'Rewrite into key',
    position: PopupMenuPosition.under,
    icon: const Icon(Icons.swap_vert),
    itemBuilder: (context) {
      final from = (_working..key = _song.key).writtenKey;
      return [
        const PopupMenuItem<MusicKey>(
          enabled: false,
          child: Text('Rewrite the chords into…'),
        ),
        for (final k in _allKeys)
          if (from == null || k.minor == from.minor)
            PopupMenuItem(
              value: k,
              enabled: from != null && k.root != from.root,
              child: Text(
                from != null && k.root == from.root
                    ? '${k.name} (now)'
                    : k.name,
              ),
            ),
      ];
    },
    onSelected: (target) {
      final from = (_working..key = _song.key).writtenKey;
      if (from == null) return;
      setState(() {
        _raw.text = rewriteIntoKey(
          _raw.text,
          normalizeTranspose(target.root - from.root),
          target,
        );
        _song.key = target;
        // Written in the new key now: shown and played as written.
        _song.transpose = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chords rewritten from ${from.name} into ${target.name}.',
          ),
        ),
      );
    },
  );

  // The text area fills the tab edge to edge, from under the tabs' line to
  // the bottom (its own side gaps inside it; its buttons float over it).
  Widget _chordProTab() =>
      ChordProField(controller: _raw, songKey: _song.writtenKey);

  Widget _beatsTab() => ListenableBuilder(
    listenable: Listenable.merge([_raw, _fields['Time signature']!]),
    builder: (context, _) => ChordBeatsEditor(
      song: () => _working,
      model: widget.model,
      ownSettings: _song.extra['beats'] as Map<String, dynamic>?,
      onOwnSettings: (v) => setState(
        () =>
            v == null ? _song.extra.remove('beats') : _song.extra['beats'] = v,
      ),
      beats: _beats,
    ),
  );

  Widget _detailsTab() {
    Widget field(String label, {int maxLines = 1, String? hint}) => TextField(
      controller: _fields[label],
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );

    Widget pair(Widget a, Widget b) => Row(
      spacing: 12,
      children: [
        Expanded(child: a),
        Expanded(child: b),
      ],
    );

    return StatefulBuilder(
      builder: (context, setLocal) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          pair(field('Artist'), field('Subtitle')),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: AppDropdownField<MusicKey?>(
                  // (Follows a "Rewrite into key".)
                  key: ValueKey(_song.key?.name),
                  initialValue: _allKeys
                      .where(
                        (k) =>
                            k.root == _song.key?.root &&
                            k.minor == _song.key?.minor,
                      )
                      .firstOrNull,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Written key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Auto (from chords)'),
                    ),
                    for (final k in _allKeys)
                      DropdownMenuItem(value: k, child: Text(k.name)),
                  ],
                  onChanged: (k) => _song.key = k,
                ),
              ),
              Expanded(
                child: AppDropdownField<int>(
                  initialValue: _song.capo.clamp(0, 9),
                  decoration: const InputDecoration(
                    labelText: 'Capo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (var i = 0; i <= 9; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(i == 0 ? 'None' : '$i'),
                      ),
                  ],
                  onChanged: (v) => _song.capo = v ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            children: [
              Expanded(child: field('Tempo (BPM)')),
              Expanded(child: field('Time signature', hint: '4/4')),
              Expanded(child: field('Duration', hint: '3:30')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _song.structure.isEmpty
                      ? 'Structure: played as written'
                      : 'Structure: ${_song.structure.map((i) => i.isModulation ? 'key ${i.semitones > 0 ? '+' : ''}${i.semitones}' : i.name).join(' → ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('Edit structure…'),
                onPressed: () async {
                  final result = await StructureEditor.show(
                    context,
                    raw: _raw.text,
                    initial: _song.structure,
                    songKey: _song.writtenKey?.transposed(_song.transpose),
                  );
                  if (result == null) return;
                  setLocal(() {
                    _song.structure = result.structure;
                    _raw.text = result.raw;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Icon', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('None'),
                selected: _song.extra['icon'] == null,
                onSelected: (_) => setLocal(() => setSongIcon(_song, null)),
              ),
              for (final MapEntry(key: name, value: (icon, label))
                  in songIcons.entries)
                Tooltip(
                  message: label,
                  child: ChoiceChip(
                    showCheckmark: false,
                    labelPadding: EdgeInsets.zero,
                    label: Icon(icon, size: 20),
                    selected: _song.extra['icon'] == name,
                    onSelected: (_) => setLocal(() => setSongIcon(_song, name)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (widget.tags.isEmpty)
            const Text('No tags yet. Create them from ☰ → Manage tags.')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in widget.tags)
                  FilterChip(
                    avatar: CircleAvatar(
                      backgroundColor:
                          colorNamed(tag.color) ?? Colors.grey.shade500,
                      radius: 6,
                    ),
                    label: Text(tag.name),
                    selected: _song.tags.contains(tag.id),
                    onSelected: (on) => setLocal(() {
                      on ? _song.tags.add(tag.id) : _song.tags.remove(tag.id);
                    }),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            'Sheet music (PDFs and pictures)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Shown in tabs beside the ChordPro, in this order (a song with '
            'no ChordPro shows just these).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final (i, p) in pdfsOf(_song).indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                p.isImage
                    ? Icons.image_outlined
                    : Icons.picture_as_pdf_outlined,
              ),
              title: Text(p.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: i == 0
                        ? null
                        : () => setLocal(() {
                            final list = pdfsOf(_song);
                            list.insert(i - 1, list.removeAt(i));
                            setPdfs(_song, list);
                          }),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: i == pdfsOf(_song).length - 1
                        ? null
                        : () => setLocal(() {
                            final list = pdfsOf(_song);
                            list.insert(i + 1, list.removeAt(i));
                            setPdfs(_song, list);
                          }),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => setLocal(
                      () => setPdfs(_song, [
                        for (final q in pdfsOf(_song))
                          if (q.id != p.id) q,
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach PDF or picture…'),
              onPressed: () async {
                final files = await pickBinaryFiles(sheetMusicExtensions);
                final added = <PdfRef>[];
                for (final (name, bytes) in files) {
                  if (!PdfStore.looksLikeSheetMusic(bytes)) continue;
                  added.add(await PdfStore.add(name, bytes));
                }
                if (added.isEmpty) return;
                setLocal(() => setPdfs(_song, [...pdfsOf(_song), ...added]));
              },
            ),
          ),
          const SizedBox(height: 16),
          pair(field('Composer'), field('Lyricist')),
          const SizedBox(height: 12),
          field('Copyright', maxLines: 2),
          const SizedBox(height: 12),
          pair(field('CCLI song #'), field('CCLI license #')),
          const SizedBox(height: 12),
          field('Footer', maxLines: 2),
          const SizedBox(height: 12),
          field('Reference link (YouTube…)'),
          const SizedBox(height: 12),
          field('Notes', maxLines: 4),
          const SizedBox(height: 20),
          _customSection(setLocal),
        ],
      ),
    );
  }

  /// Custom fields: any name and value (Theme, Season, Arranger…), shown
  /// with the song's details and found by search.
  Widget _customSection(StateSetter setLocal) {
    final theme = Theme.of(context);
    void add(String name) => setLocal(() {
      _custom.add((TextEditingController(text: name), TextEditingController()));
    });
    final known = _knownFieldNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text('Custom fields', style: theme.textTheme.titleSmall),
        Text(
          'Your own details for this song, like Theme, Season or Arranger. '
          'They show with the song’s details and search finds them.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (i, (name, value)) in _custom.indexed)
          Row(
            spacing: 8,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: value,
                  decoration: const InputDecoration(
                    labelText: 'Value',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove this field',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setLocal(() {
                  final (n, v) = _custom.removeAt(i);
                  n.dispose();
                  v.dispose();
                }),
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add field'),
              onPressed: () => add(''),
            ),
            for (final n in known.take(8))
              ActionChip(label: Text('+ $n'), onPressed: () => add(n)),
          ],
        ),
      ],
    );
  }
}
