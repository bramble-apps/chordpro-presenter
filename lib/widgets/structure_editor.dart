import 'package:flutter/material.dart';

import '../chordpro.dart';
import '../music.dart';
import '../translation.dart';
import 'translate_dialog.dart';
import '../eink.dart';
import '../bramble_icons.dart';

class StructureResult {
  final List<StructureItem> structure;

  /// Song text, changed if sections were edited with the pencil.
  final String raw;
  const StructureResult(this.structure, this.raw);
}

/// "Song structure" editor: build the play order from the song's sections,
/// add key changes (modulations), reorder by dragging.
class StructureEditor extends StatefulWidget {
  final String raw;
  final List<StructureItem> initial;

  /// Key the song is played in (to name modulation keys), if known.
  final MusicKey? songKey;
  final String? subtitle;

  /// Language for the translate (globe) button, and where to remember a
  /// new choice.
  final String translateTo;
  final ValueChanged<String>? onTranslateTo;

  /// Editing a setlist's arrangement (deleting it goes back to the song's
  /// own order).
  final bool inSetlist;

  /// The song's title (a first line that's just the title isn't a verse).
  final String? title;

  const StructureEditor({
    super.key,
    required this.raw,
    required this.initial,
    this.songKey,
    this.subtitle,
    this.translateTo = 'fr',
    this.onTranslateTo,
    this.inSetlist = false,
    this.title,
  });

  static Future<StructureResult?> show(
    BuildContext context, {
    required String raw,
    required List<StructureItem> initial,
    MusicKey? songKey,
    String? subtitle,
    String translateTo = 'fr',
    ValueChanged<String>? onTranslateTo,
    bool inSetlist = false,
    String? title,
  }) => showAppDialog<StructureResult>(
    context: context,
    builder: (_) => StructureEditor(
      raw: raw,
      initial: initial,
      songKey: songKey,
      subtitle: subtitle,
      translateTo: translateTo,
      onTranslateTo: onTranslateTo,
      inSetlist: inSetlist,
      title: title,
    ),
  );

  @override
  State<StructureEditor> createState() => _StructureEditorState();
}

class _Item {
  final int id;
  StructureItem value;
  _Item(this.id, this.value);
}

class _StructureEditorState extends State<StructureEditor> {
  // Lyrics with no label get one, so they can go in the structure (and in
  // its place in the order they were shown in).
  late final (String, List<StructureItem>) _labelled = ChordPro.relabel(
    widget.raw,
    widget.initial,
    title: widget.title,
  );
  late String _raw = _labelled.$1;
  var _nextId = 0;
  late final List<_Item> _items = [
    for (final i in _labelled.$2) _Item(_nextId++, i),
  ];

  /// Sections that were given a label just now.
  late final List<String> _newLabels = () {
    final before = {
      for (final n in ChordPro.sectionNames(widget.raw)) n.toLowerCase(),
    };
    return [
      for (final n in ChordPro.sectionNames(_raw))
        if (!before.contains(n.toLowerCase())) n,
    ];
  }();

  List<String> get _sections => ChordPro.sectionNames(_raw);

  bool get _hasDuplicates {
    final seen = <String>{};
    return _sections.any((s) => !seen.add(s.toLowerCase()));
  }

  void _add(StructureItem item) =>
      setState(() => _items.add(_Item(_nextId++, item)));

  String _keyLabel(int semitones) {
    final sign = semitones > 0 ? '+$semitones' : '$semitones';
    final key = widget.songKey;
    return key == null ? sign : '${key.transposed(semitones).name} ($sign)';
  }

  String _fromLabel(int index) {
    for (var i = index + 1; i < _items.length; i++) {
      if (!_items[i].value.isModulation) return _items[i].value.name;
    }
    return '';
  }

  Future<void> _editSection(String name) async {
    final text = ChordPro.sectionText(_raw, name);
    if (text == null) return;
    final edited = await showAppDialog<String>(
      context: context,
      builder: (_) => _SectionTextDialog(text: text),
    );
    if (edited == null || edited.trim().isEmpty) return;
    setState(() {
      _raw = ChordPro.replaceSection(_raw, name, edited);
      // If the label was renamed, follow it in the structure.
      final newName = ChordPro.sectionName(edited.split('\n').first);
      if (newName != null && newName != name) {
        for (final item in _items) {
          if (!item.value.isModulation &&
              item.value.name.toLowerCase() == name.toLowerCase()) {
            item.value = StructureItem.section(newName);
          }
        }
      }
    });
  }

  /// Translations come in as linked sections, ready to review and save.
  Future<void> _translate() => TranslateDialog.show(
    context,
    raw: _raw,
    structure: [for (final i in _items) i.value],
    language: widget.translateTo,
    onLanguage: widget.onTranslateTo,
    title: widget.title,
    onChanged: (r) => setState(() {
      _raw = r.raw;
      _items
        ..clear()
        ..addAll([for (final i in r.structure) _Item(_nextId++, i)]);
    }),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sectionTitle = theme.textTheme.titleMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    Widget card(Widget child) => Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(inkR(22)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    );
    Widget removeButton(VoidCallback onTap) => IconButton(
      tooltip: 'Remove',
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: const Icon(
        BrambleIcons.minusCircleFill,
        size: 20,
        color: Color(0xFFE5534B),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Cancel',
                    icon: const Icon(BrambleIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Song structure',
                          style: theme.textTheme.titleLarge,
                        ),
                        if (widget.subtitle != null)
                          Text(
                            widget.subtitle!,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Translate slides',
                    isSelected: translatedLanguages(_raw).isNotEmpty,
                    icon: const Icon(BrambleIcons.globe),
                    onPressed: _translate,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Save',
                    icon: const Icon(BrambleIcons.check),
                    onPressed: () => Navigator.pop(
                      context,
                      StructureResult([for (final i in _items) i.value], _raw),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text('Song structure', style: sectionTitle),
                  const SizedBox(height: 8),
                  card(
                    _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              widget.inSetlist
                                  ? 'Follows the song\'s own order. Tap '
                                        'sections below to make one for this '
                                        'setlist.'
                                  : translatedLanguages(_raw).isNotEmpty
                                  ? 'Played as written, each translation '
                                        'with its section. Tap sections '
                                        'below to build your own order.'
                                  : 'Played as written. Tap sections below '
                                        'to build your own order.',
                            ),
                          )
                        : ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            // Linked sections move together.
                            onReorderItem: (a, b) => setState(() {
                              final groups = _groups;
                              groups.insert(b, groups.removeAt(a));
                              final order = [
                                for (final g in groups)
                                  for (final i in g) _items[i],
                              ];
                              _items
                                ..clear()
                                ..addAll(order);
                            }),
                            children: [
                              for (final (g, group) in _groups.indexed)
                                _group(g, group, removeButton, scheme),
                            ],
                          ),
                  ),
                  const SizedBox(height: 20),
                  Text('Sections', style: sectionTitle),
                  const SizedBox(height: 8),
                  card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        if (_sections.isEmpty)
                          const Text(
                            'This song has no section labels like "Verse 1:" '
                            'or "Chorus:".',
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final name in _sections)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        inkR(8),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _add(StructureItem.section(name)),
                                  child: Text(
                                    '$name:',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        if (_newLabels.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Labelled lyrics that had no label: '
                            '${_newLabels.join(', ')}.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (_hasDuplicates) ...[
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(BrambleIcons.warning, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Song sections don't have unique names.",
                                  style: TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 24),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.secondaryContainer,
                            foregroundColor: scheme.onSecondaryContainer,
                          ),
                          onPressed: () =>
                              _add(const StructureItem.keyChange(0)),
                          icon: const Icon(BrambleIcons.plus),
                          label: const Text('Modulation'),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    child: Text(
                      'Tap a section to add it to the structure. '
                      'Drag ≡ to reorder. Click the chain between two '
                      'sections to link them into one slide (e.g. a verse '
                      'and its translation).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      foregroundColor: const Color(0xFFE5534B),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.all(18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(inkR(22)),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, StructureResult(const [], _raw)),
                    child: Text(
                      widget.inSetlist
                          ? 'Delete this setlist\'s structure (use the '
                                'song\'s own)'
                          : 'Delete structure (play as written)',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Item indexes grouped by links (each group drags as one).
  List<List<int>> get _groups {
    final groups = <List<int>>[];
    for (var i = 0; i < _items.length; i++) {
      if (i > 0 && _items[i - 1].value.linked) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }
    return groups;
  }

  bool _canLink(int i) =>
      i + 1 < _items.length &&
      !_items[i].value.isModulation &&
      !_items[i + 1].value.isModulation;

  void _setLinked(int i, bool linked) =>
      setState(() => _items[i].value = _items[i].value.withLinked(linked));

  void _remove(int i) => setState(() {
    // Taking the end off a linked group mustn't join it to what follows.
    if (i > 0 && !_items[i].value.linked) {
      _items[i - 1].value = _items[i - 1].value.withLinked(false);
    }
    _items.removeAt(i);
  });

  /// One draggable group: its sections with chain links between them, and
  /// the chain to the next group underneath.
  Widget _group(
    int g,
    List<int> group,
    Widget Function(VoidCallback) removeButton,
    ColorScheme scheme,
  ) {
    final last = group.last;
    final linkedGroup = group.length > 1;
    final rows = Column(
      children: [
        for (final i in group) ...[
          _row(i, g, removeButton, scheme),
          if (i != last)
            _LinkToggle(linked: true, onToggle: () => _setLinked(i, false)),
        ],
      ],
    );
    return Column(
      key: ValueKey(_items[group.first].id),
      children: [
        if (linkedGroup)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            // Even space above and below, to balance the chain between.
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              border: Border(
                left: BorderSide(color: scheme.primary, width: inkW(3)),
              ),
            ),
            child: rows,
          )
        else
          rows,
        if (last < _items.length - 1)
          _canLink(last)
              ? _LinkToggle(
                  linked: false,
                  onToggle: () => _setLinked(last, true),
                )
              : const Divider(height: 1, indent: 48),
      ],
    );
  }

  Widget _row(
    int i,
    int group,
    Widget Function(VoidCallback) removeButton,
    ColorScheme scheme,
  ) {
    final item = _items[i];
    final handle = ReorderableDragStartListener(
      index: group,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Icon(BrambleIcons.equals, size: 20),
      ),
    );
    final remove = removeButton(() => _remove(i));
    final Widget body;
    if (item.value.isModulation) {
      final from = _fromLabel(i);
      body = Row(
        children: [
          Icon(BrambleIcons.arrowsDownUp, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _keyLabel(item.value.semitones),
                  style: const TextStyle(fontSize: 16),
                ),
                if (from.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      text: 'From ',
                      children: [
                        TextSpan(
                          text: from,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(inkR(20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Down a semitone',
                  icon: const Icon(BrambleIcons.minus),
                  onPressed: () => setState(
                    () => item.value = StructureItem.keyChange(
                      normalizeTranspose(item.value.semitones - 1),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Up a semitone',
                  icon: const Icon(BrambleIcons.plus),
                  onPressed: () => setState(
                    () => item.value = StructureItem.keyChange(
                      normalizeTranspose(item.value.semitones + 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      final known = _sections.any(
        (s) => s.toLowerCase() == item.value.name.toLowerCase(),
      );
      body = Row(
        children: [
          Expanded(
            child: Text(
              item.value.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (known)
            IconButton(
              tooltip: 'Edit section',
              visualDensity: VisualDensity.compact,
              icon: const Icon(BrambleIcons.pencilSimple, size: 18),
              onPressed: () => _editSection(item.value.name),
            ),
        ],
      );
    }
    return Row(
      children: [
        remove,
        Expanded(child: body),
        handle,
      ],
    );
  }
}

/// The chain between two sections: joined when linked, broken when not.
/// Hovering previews the other state; clicking toggles it.
class _LinkToggle extends StatefulWidget {
  final bool linked;
  final VoidCallback onToggle;
  const _LinkToggle({required this.linked, required this.onToggle});

  @override
  State<_LinkToggle> createState() => _LinkToggleState();
}

class _LinkToggleState extends State<_LinkToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showLinked = widget.linked != _hover;
    final color = widget.linked || _hover ? scheme.primary : scheme.outline;
    final line = Expanded(
      child: Divider(height: 1, color: scheme.outlineVariant),
    );
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          const SizedBox(width: 48),
          line,
          Tooltip(
            message: widget.linked
                ? 'Unlink (separate slides)'
                : 'Link with the next section (one slide)',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _hover = false);
                  widget.onToggle();
                },
                child: Semantics(
                  button: true,
                  label: widget.linked ? 'Unlink sections' : 'Link sections',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: CustomPaint(
                      size: const Size(16, 26),
                      painter: _ChainPainter(linked: showLinked, color: color),
                    ),
                  ),
                ),
              ),
            ),
          ),
          line,
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// An upright chain: two long links joined by a straight line through
/// their inner ends (linked), or the same links, each opened at the end
/// facing the other (unlinked).
class _ChainPainter extends CustomPainter {
  final bool linked;
  final Color color;
  const _ChainPainter({required this.linked, required this.color});

  @override
  void paint(Canvas canvas, Size box) {
    // Drawn on a 26 × 44 grid, scaled to the box.
    canvas.scale(box.height / 44);
    const size = Size(26, 44);
    const cx = 13.0, w = 11.0, h = 17.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    // A link: a rounded rectangle, a little squarer than an oval.
    RRect link(double top) => RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - w / 2, top, w, h),
      const Radius.circular(w * 0.38),
    );
    final upper = link(2), lower = link(25);
    if (linked) {
      canvas.drawRRect(upper, paint);
      canvas.drawRRect(lower, paint);
      canvas.drawLine(const Offset(cx, 13), const Offset(cx, 31), paint);
      return;
    }
    // Each opened where it faces the other.
    for (final (r, y) in [(upper, upper.bottom), (lower, lower.top)]) {
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(
            Rect.fromCenter(center: Offset(cx, y), width: 5, height: 6),
          ),
      );
      canvas.drawRRect(r, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ChainPainter old) =>
      old.linked != linked || old.color != color;
}

class _SectionTextDialog extends StatefulWidget {
  final String text;
  const _SectionTextDialog({required this.text});

  @override
  State<_SectionTextDialog> createState() => _SectionTextDialogState();
}

class _SectionTextDialogState extends State<_SectionTextDialog> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit section'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          maxLines: 14,
          minLines: 6,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
