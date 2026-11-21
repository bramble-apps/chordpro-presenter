import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart' show foldAccents;
import '../abc.dart' show abcStart, abcEnd;
import 'abc_editor.dart';
import '../chordpro.dart';
import '../fonts.dart';
import '../music.dart';
import '../eink.dart';

final _chordOrDirective = RegExp(r'\[[^\]\n]*\]|\{[^}\n]*\}');

/// Text controller that colours ChordPro while you type: [chords] in the
/// accent colour, section labels bold and dimmed, {directives} and
/// # comments dimmed. Matches of [findText] are highlighted (the current
/// one, [findIndex], more strongly). The text itself is never changed.
class ChordProController extends TextEditingController {
  ChordProController({super.text});

  String _find = '';
  bool _matchCase = false;
  int _findIndex = 0;

  /// The current match (highlighted more strongly).
  int get findIndex => _findIndex;
  set findIndex(int value) {
    if (value == _findIndex) return;
    _findIndex = value;
    notifyListeners();
  }

  String get findText => _find;
  bool get matchCase => _matchCase;

  /// What to look for (empty: nothing highlighted).
  void setFind(String text, {bool? matchCase}) {
    if (text == _find && (matchCase ?? _matchCase) == _matchCase) return;
    _find = text;
    _matchCase = matchCase ?? _matchCase;
    _findIndex = 0;
    notifyListeners();
  }

  String? _matchesFor;
  List<TextRange> _matches = const [];

  /// Where [findText] occurs, in order.
  List<TextRange> get matches {
    final key = '$_matchCase\u0000$_find\u0000$text';
    if (key == _matchesFor) return _matches;
    _matchesFor = key;
    if (_find.isEmpty) return _matches = const [];
    // Like the side pane's search, accents don't matter (é finds e and
    // the other way round), unless Match case is on.
    final hay = _matchCase ? text : _fold(text);
    final needle = _matchCase ? _find : _fold(_find);
    final out = <TextRange>[];
    var i = hay.indexOf(needle);
    while (i >= 0) {
      out.add(TextRange(start: i, end: i + needle.length));
      i = hay.indexOf(needle, i + needle.length);
    }
    return _matches = out;
  }

  /// [t] lower-cased with its accents folded, letter for letter (the
  /// same length, so a match's place is its place in the text).
  static String _fold(String t) {
    final out = StringBuffer();
    for (final unit in t.codeUnits) {
      final c = String.fromCharCode(unit);
      final f = foldAccents(c);
      final lower = c.toLowerCase();
      out.write(
        f.length == 1
            ? f
            : lower.length == 1
            ? lower
            : c,
      );
    }
    return out.toString();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chord = TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
      backgroundColor: scheme.primary.withValues(alpha: 0.08),
    );
    final dim = TextStyle(color: scheme.onSurfaceVariant);
    final label = dim.copyWith(fontWeight: FontWeight.w700);

    // The coloured runs, in order.
    final runs = <(String, TextStyle?)>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final nl = i < lines.length - 1 ? '\n' : '';
      final t = line.trim();
      if (t.startsWith('#')) {
        runs.add(('$line$nl', dim));
        continue;
      }
      if (t.isNotEmpty && !t.contains('[') && ChordPro.isSectionLabel(t)) {
        runs.add(('$line$nl', label));
        continue;
      }
      var last = 0;
      for (final m in _chordOrDirective.allMatches(line)) {
        if (m.start > last) runs.add((line.substring(last, m.start), null));
        runs.add((m.group(0)!, m.group(0)!.startsWith('[') ? chord : dim));
        last = m.end;
      }
      runs.add(('${line.substring(last)}$nl', null));
    }

    // Find highlights cut across the runs.
    final found = matches;
    if (found.isEmpty) {
      return TextSpan(
        style: style,
        children: [for (final (t, st) in runs) TextSpan(text: t, style: st)],
      );
    }
    final hit = TextStyle(
      backgroundColor: Colors.amber.withValues(alpha: 0.35),
    );
    final current = TextStyle(
      backgroundColor: Colors.orange.withValues(alpha: 0.85),
      color: Colors.black,
    );
    final at = findIndex.clamp(0, found.length - 1);
    final children = <TextSpan>[];
    var pos = 0;
    var m = 0;
    for (final (t, st) in runs) {
      final end = pos + t.length;
      var from = pos;
      while (from < end) {
        while (m < found.length && found[m].end <= from) {
          m++;
        }
        final inside = m < found.length && found[m].start <= from;
        final to = m >= found.length
            ? end
            : inside
            ? (found[m].end < end ? found[m].end : end)
            : (found[m].start < end ? found[m].start : end);
        final piece = t.substring(from - pos, to - pos);
        children.add(
          TextSpan(
            text: piece,
            style: inside
                ? (st ?? const TextStyle()).merge(m == at ? current : hit)
                : st,
          ),
        );
        from = to;
      }
      pos = end;
    }
    return TextSpan(style: style, children: children);
  }
}

/// Chords to offer as shortcuts: those used in the song, in the order they
/// first appear; for a song without chords yet, the chords of its key.
List<String> chordSuggestions(String raw, {MusicKey? key}) {
  final seen = <String>{};
  final found = <String>[];
  for (final m in RegExp(r'\[([^\]\n]+)\]').allMatches(raw)) {
    final c = m.group(1)!.trim();
    if (Chord.parse(c) != null && seen.add(c)) found.add(c);
  }
  if (found.isNotEmpty) return found;
  // Diatonic chords: I ii iii IV V vi (major) or i III iv v VI VII (minor).
  final k = key ?? const MusicKey(0, false);
  final degrees = k.minor
      ? const [
          (0, true),
          (3, false),
          (5, true),
          (7, true),
          (8, false),
          (10, false),
        ]
      : const [
          (0, false),
          (2, true),
          (4, true),
          (5, false),
          (7, false),
          (9, true),
        ];
  final names = k.prefersFlats
      ? const ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']
      : const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return [
    for (final (d, minor) in degrees)
      '${names[(k.root + d) % 12]}${minor ? 'm' : ''}',
  ];
}

/// The ChordPro text box plus a shortcut bar of chord buttons.
class ChordProField extends StatefulWidget {
  final ChordProController controller;
  final MusicKey? songKey;

  const ChordProField({super.key, required this.controller, this.songKey});

  @override
  State<ChordProField> createState() => _ChordProFieldState();
}

class _ChordProFieldState extends State<ChordProField> {
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  final _findField = TextEditingController();
  final _replaceField = TextEditingController();
  final _findFocus = FocusNode();

  /// "Replaced 4" after Replace all, until the search changes.
  String? _note;

  /// Find & replace is hidden until asked for (the Find button, ⌘F /
  /// Ctrl+F), and so is its replace row.
  bool _findOpen = false, _replaceOpen = false;

  void _closeFind() {
    _findField.clear();
    _note = null;
    c.setFind('');
    setState(() {
      _findOpen = false;
      _replaceOpen = false;
    });
    _focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    // A search left from before (e.g. the tab was switched away) is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.setFind('');
    });
    FontService.ensure('cousine').then((_) {
      if (mounted) setState(() {});
    });
  }

  ChordProController get c => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    _findField.dispose();
    _replaceField.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  // ---- Find & replace ----

  void _search(String text) {
    _note = null;
    c.setFind(text);
    // Start from the first match after the cursor.
    final cursor = c.selection.isValid ? c.selection.start : 0;
    final i = c.matches.indexWhere((r) => r.start >= cursor);
    _show(i < 0 ? 0 : i);
  }

  /// Makes match [i] (wrapping round) the current one and scrolls to it.
  void _show(int i) {
    final found = c.matches;
    if (found.isEmpty) {
      setState(() {});
      return;
    }
    c.findIndex = i % found.length;
    final r = found[c.findIndex];
    setState(() {});
    final state = _fieldKey.currentState;
    if (state is TextSelectionGestureDetectorBuilderDelegate) {
      final editable = (state as TextSelectionGestureDetectorBuilderDelegate)
          .editableTextKey
          .currentState;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editable?.bringIntoView(TextPosition(offset: r.end));
      });
    }
  }

  void _next() => _show(c.findIndex + 1);
  void _previous() => _show(c.findIndex - 1);

  /// Replaces the current match, then moves on to the next.
  void _replace() {
    final found = c.matches;
    if (found.isEmpty) return;
    final r = found[c.findIndex.clamp(0, found.length - 1)];
    final by = _replaceField.text;
    c.value = TextEditingValue(
      text: c.text.replaceRange(r.start, r.end, by),
      selection: TextSelection.collapsed(offset: r.start + by.length),
    );
    final after = c.matches.indexWhere((m) => m.start >= r.start + by.length);
    _show(after < 0 ? 0 : after);
  }

  void _replaceAll() {
    final found = c.matches;
    if (found.isEmpty) return;
    final by = _replaceField.text;
    var text = c.text;
    for (final r in found.reversed) {
      text = text.replaceRange(r.start, r.end, by);
    }
    c.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() => _note = 'Replaced ${found.length}');
  }

  /// ⌘F / Ctrl+F or the Find button: Find & replace opens, the find box
  /// ready with the selected text in it.
  void _openFind() {
    if (!_findOpen) setState(() => _findOpen = true);
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(c.text);
      if (!picked.contains('\n')) {
        _findField.text = picked;
        _search(picked);
      }
    }
    // (Once the box is built.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _findFocus.requestFocus();
      _findField.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findField.text.length,
      );
    });
  }

  /// The pieces of Find & replace: the find box (with "2 of 5" in it),
  /// the arrows and Match case, the replace box and its buttons.
  ({
    Widget find,
    Widget arrows,
    Widget matchCase,
    Widget replace,
    Widget buttons,
  })
  _findParts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = c.matches;
    final searching = c.findText.isNotEmpty;
    final count =
        _note ??
        (!searching
            ? ''
            : found.isEmpty
            ? 'No results'
            : '${c.findIndex.clamp(0, found.length - 1) + 1} of ${found.length}');
    // Compact: a 36 px high box.
    const dense = InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
    );
    final find = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): _previous,
        const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
      },
      child: TextField(
        key: const Key('find-text'),
        controller: _findField,
        focusNode: _findFocus,
        onChanged: _search,
        style: const TextStyle(fontSize: 14),
        decoration: dense.copyWith(
          hintText: 'Find',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixText: count,
          suffixStyle: TextStyle(
            fontSize: 12,
            color: searching && found.isEmpty
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    final arrows = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous match (Shift+Enter)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: found.isEmpty ? null : _previous,
        ),
        IconButton(
          tooltip: 'Next match (Enter)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: found.isEmpty ? null : _next,
        ),
      ],
    );
    final matchCase = IconButton(
      tooltip: 'Match case',
      visualDensity: VisualDensity.compact,
      isSelected: c.matchCase,
      icon: const Icon(Icons.text_fields_rounded, size: 20),
      onPressed: () {
        c.setFind(c.findText, matchCase: !c.matchCase);
        _search(_findField.text);
      },
    );
    final replace = TextField(
      key: const Key('replace-text'),
      controller: _replaceField,
      onSubmitted: (_) => _replace(),
      style: const TextStyle(fontSize: 14),
      decoration: dense.copyWith(
        hintText: 'Replace with',
        prefixIcon: const Icon(Icons.find_replace_rounded, size: 18),
      ),
    );
    final small = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: small,
          onPressed: found.isEmpty ? null : _replace,
          child: const Text('Replace'),
        ),
        TextButton(
          style: small,
          onPressed: found.isEmpty ? null : _replaceAll,
          child: const Text('All'),
        ),
      ],
    );
    return (
      find: find,
      arrows: arrows,
      matchCase: matchCase,
      replace: replace,
      buttons: buttons,
    );
  }

  /// Desktop: one row over the text (Find, arrows, Match case, the
  /// replace toggle, close); replace on a second row only when wanted.
  Widget _findBar(BuildContext context) {
    final p = _findParts(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        spacing: 4,
        children: [
          Row(
            children: [
              Expanded(child: p.find),
              p.arrows,
              p.matchCase,
              IconButton(
                tooltip: _replaceOpen ? 'Hide replace' : 'Replace…',
                visualDensity: VisualDensity.compact,
                isSelected: _replaceOpen,
                icon: const Icon(Icons.find_replace_rounded, size: 20),
                onPressed: () => setState(() => _replaceOpen = !_replaceOpen),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                onPressed: _closeFind,
              ),
            ],
          ),
          if (_replaceOpen)
            Row(
              children: [
                Expanded(child: p.replace),
                p.buttons,
                // (In line with the buttons above.)
                const SizedBox(width: 40),
              ],
            ),
        ],
      ),
    );
  }

  /// Inserts [text] at the cursor (replacing any selection). [caretBack]
  /// moves the cursor left afterwards, e.g. to land inside "[]".
  void _insert(String text, {int caretBack = 0}) {
    final v = c.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    c.value = TextEditingValue(
      text: v.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(
        offset: sel.start + text.length - caretBack,
      ),
    );
    _focus.requestFocus();
  }

  /// Writes a melody in ABC with the music drawn as you type: the tune the
  /// cursor is in (edited in place), or a new one at the cursor.
  Future<void> _melody() async {
    final text = c.text;
    final at = c.selection.isValid ? c.selection.start : text.length;
    // The {start_of_abc}…{end_of_abc} block around the cursor, if any.
    final lines = text.split('\n');
    var pos = 0;
    int? blockStart, innerStart, innerEnd, blockEnd;
    for (final line in lines) {
      final end = pos + line.length;
      if (abcStart.hasMatch(line.trim())) {
        blockStart = pos;
        innerStart = end + 1;
        innerEnd = null;
      } else if (abcEnd.hasMatch(line.trim()) && blockStart != null) {
        innerEnd = pos;
        blockEnd = end;
        if (blockStart <= at && at <= blockEnd) break;
        blockStart = innerStart = innerEnd = blockEnd = null;
      }
      pos = end + 1;
    }
    final inside = blockStart != null && blockEnd != null;
    final initial = inside
        ? text.substring(innerStart!.clamp(0, innerEnd!), innerEnd).trimRight()
        : abcTemplateTune;
    final tune = await editAbc(context, initial);
    if (tune == null || !mounted) return;
    final block = '{start_of_abc}\n$tune\n{end_of_abc}';
    if (inside) {
      c.value = TextEditingValue(
        text: text.replaceRange(blockStart, blockEnd, block),
        selection: TextSelection.collapsed(offset: blockStart + block.length),
      );
      _focus.requestFocus();
    } else {
      _insert(block);
    }
  }

  /// Wraps the selection in [ ], or inserts [] with the cursor inside.
  void _bracket() {
    final v = c.value;
    final sel = v.selection;
    if (sel.isValid && !sel.isCollapsed) {
      _insert('[${sel.textInside(v.text)}]');
    } else {
      _insert('[]', caretBack: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themed = Theme.of(context).chipTheme.backgroundColor != null;
    Widget chip(String label, VoidCallback onTap, {String? tooltip}) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip ?? 'Insert [$label]',
        // Keep the text box focused so the cursor stays where it was.
        child: ExcludeFocus(
          // Touch-sized: at least 44 wide and 38 tall.
          child: ActionChip(
            // (floating over the text area: lifted off it)
            elevation: 2,
            shadowColor: Colors.black,
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            label: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 20),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            // Seen on any colour theme: a solid fill set off from the
            // editor's tinted surface with a hairline (Material); the
            // desktop styles' own bordered buttons otherwise.
            backgroundColor: themed ? null : scheme.surfaceContainerLowest,
            side: themed ? null : BorderSide(color: scheme.outlineVariant),
            shape: themed ? null : const StadiumBorder(),
            onPressed: onTap,
          ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
      },
      child: Column(
        children: [
          if (_findOpen)
            ListenableBuilder(
              listenable: c,
              builder: (context, _) => _findBar(context),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _field()),
                // The text fades into the background under the bar (as the
                // tags do at their edge).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _barHeight + _barInset + 24,
                  child: IgnorePointer(child: _fade(context)),
                ),
                // The bar floats over the text area's foot.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _bar(context, chip),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The text area's background (its fill over the surface it's on), clear
  /// at the top to solid at the foot.
  Widget _fade(BuildContext context) {
    final theme = Theme.of(context);
    final surface =
        theme.dialogTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerHigh;
    final fill = Color.alphaBlend(
      theme.inputDecorationTheme.fillColor ??
          theme.colorScheme.surfaceContainerHighest,
      surface,
    );
    if (isEink(context)) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill.withValues(alpha: 0), fill.withValues(alpha: .9), fill],
          stops: const [0, .45, 1],
        ),
      ),
    );
  }

  /// The bar's height, and how far it sits up from the bottom.
  static const _barHeight = 48.0, _barInset = 6.0;

  /// The text, edge to edge: no box around it. Scrolled as a whole (its
  /// gaps with it), so lines go right up to the tabs' line and pass under
  /// the bar floating over its foot; at the end, room to bring the last
  /// line up above the bar. At least as tall as the room (all of it takes
  /// a tap).
  Widget _field() => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: _text(),
      ),
    ),
  );

  Widget _text() => TextField(
    key: _fieldKey,
    controller: c,
    focusNode: _focus,
    maxLines: null,
    // The caret is kept clear of the bar.
    scrollPadding: const EdgeInsets.fromLTRB(
      20,
      20,
      20,
      _barHeight + _barInset + 20,
    ),
    textAlignVertical: TextAlignVertical.top,
    // Bundled monospaced font so chords and lyrics line up.
    style: TextStyle(
      fontFamily: FontOption('cousine', '').family,
      fontFamilyFallback: const ['monospace'],
      fontSize: 14,
      height: 1.5,
    ),
    decoration: const InputDecoration(
      alignLabelWithHint: true,
      hintText:
          'Verse 1:\n[G]Lyrics with [D]chords\n\nChorus:\n…\n\n'
          '{section_break} or a blank line starts a new slide.',
      filled: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      // (20 from the edge to the text, as the title field above:
      // the field adds 4 of its own)
      contentPadding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        _barHeight + _barInset + 8,
      ),
    ),
  );

  Widget _bar(
    BuildContext context,
    Widget Function(String, VoidCallback, {String? tooltip}) chip,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: _barInset),
      child: SizedBox(
        height: _barHeight,
        // Scrolling the bar never flips the ChordPro / Details tabs: it
        // claims wheel / trackpad scrolls over it even at its ends, and
        // touch drags stop at its edges.
        child: Row(
          children: [
            // Find & replace: hidden until wanted (also ⌘F /
            // Ctrl+F).
            const SizedBox(width: 12),
            ExcludeFocus(
              child: IconButton.filledTonal(
                style: IconButton.styleFrom(
                  elevation: 2,
                  shadowColor: Colors.black,
                  backgroundColor: scheme.surfaceContainerLowest,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                tooltip: 'Find & replace',
                visualDensity: VisualDensity.compact,
                isSelected: _findOpen,
                icon: const Icon(Icons.search),
                onPressed: _findOpen ? _closeFind : _openFind,
              ),
            ),
            Expanded(
              child: Listener(
                onPointerSignal: (event) => GestureBinding
                    .instance
                    .pointerSignalResolver
                    .register(event, (_) {}),
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) {
                    final chords = chordSuggestions(
                      c.text,
                      key: widget.songKey,
                    );
                    return ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                      children: [
                        for (final ch in chords)
                          chip(ch, () => _insert('[$ch]')),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '|',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        chip(
                          '[chord]',
                          _bracket,
                          tooltip: 'Insert [ ] (wraps the selection)',
                        ),
                        chip('#', () => _insert('#'), tooltip: 'Sharp'),
                        chip(
                          '♭',
                          () => _insert('b'),
                          tooltip: 'Flat (types b)',
                        ),
                        chip('/', () => _insert('/'), tooltip: 'Slash chord'),
                        chip(
                          'Tab',
                          () => _insert(
                            '{start_of_tab}\n'
                            'e|----------------|\n'
                            'B|----------------|\n'
                            'G|----------------|\n'
                            'D|----------------|\n'
                            'A|----------------|\n'
                            'E|----------------|\n'
                            '{end_of_tab}',
                          ),
                          tooltip:
                              'A guitar tab: type fret numbers on the strings '
                              '(drawn as strings, playable)',
                        ),
                        chip(
                          'Melody (ABC)',
                          _melody,
                          tooltip:
                              'A melody in ABC notation, drawn as sheet music '
                              'and playable (edits the tune the cursor is in)',
                        ),
                        chip(
                          'Strum pattern',
                          () => _insert('{rhythm: D-DU-UDU}'),
                          tooltip:
                              'A strum pattern drawn on the beat grid: D down, U '
                              'up, X muted, - rest, > accent (JustChords syntax)',
                        ),
                        chip(
                          'Projected text',
                          () => _insert(lyricsOverrideBlock),
                          tooltip:
                              'Text the projector shows for this section instead '
                              'of its lyrics (JustChords’ lyrics override)',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
