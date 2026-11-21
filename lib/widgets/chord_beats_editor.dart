import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chord_beats.dart';
import '../chordpro.dart';
import '../format.dart';
import '../state.dart';
import 'chord_sheet.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// The song editor's "Chord Beats" tab (as in JustChords): the song drawn
/// exactly as the chord sheet will show it, with the chord beats settings
/// on top (Show, Style, Bars per line — for all songs or just this one).
/// Tap a chord, then − / + (⌘↓ / ⌘↑) to change how long it lasts, ‹ / ›
/// (⌘← / ⌘→) to move to the previous / next chord. A chord without its own
/// number lasts a bar; 0 hides its beats.
class ChordBeatsEditor extends StatefulWidget {
  /// The song as being edited (text, time signature, title…).
  final Song Function() song;

  /// Where everyone's settings live (null: defaults, nothing saved).
  final PresenterModel? model;

  /// This song's own chord beats settings (null: it follows everyone's).
  final Map<String, dynamic>? ownSettings;
  final ValueChanged<Map<String, dynamic>?> onOwnSettings;

  /// Beat counts by chord (see chord_beats.dart); changed in place.
  final Map<String, int> beats;

  const ChordBeatsEditor({
    super.key,
    required this.song,
    required this.model,
    required this.ownSettings,
    required this.onOwnSettings,
    required this.beats,
  });

  @override
  State<ChordBeatsEditor> createState() => _ChordBeatsEditorState();
}

class _ChordBeatsEditorState extends State<ChordBeatsEditor> {
  String? _selected;
  final _focus = FocusNode(debugLabel: 'chord beats');
  late final SheetFormat _defaults = SheetFormat();

  SheetFormat get _format => widget.model?.format ?? _defaults;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  BeatSettings get _settings =>
      BeatSettings.of(_format, {'beats': ?widget.ownSettings});

  void _setSettings({bool? show, ChordBeatStyle? style, int? barsPerLine}) {
    final now = _settings;
    if (now.own) {
      widget.onOwnSettings({
        'show': show ?? now.show,
        'style': (style ?? now.style).name,
        'barsPerLine': (barsPerLine ?? now.barsPerLine).clamp(1, 8),
      });
    } else {
      void change(SheetFormat f) {
        if (show != null) f.chordBeats = show;
        if (style != null) f.beatStyle = style;
        if (barsPerLine != null) f.barsPerLine = barsPerLine.clamp(1, 8);
      }

      final model = widget.model;
      model == null ? change(_defaults) : model.updateFormat(change);
    }
    setState(() {});
  }

  void _setOwn(bool own) {
    final now = _settings;
    widget.onOwnSettings(
      own
          ? {
              'show': now.show,
              'style': now.style.name,
              'barsPerLine': now.barsPerLine,
            }
          : null,
    );
    setState(() {});
  }

  /// Every chord in the order the sheet draws them (named as
  /// chord_sheet.dart names them).
  List<String> _order(String raw) {
    final keys = ChordKeys();
    final order = <String>[];
    for (final part in ChordPro.parts(raw)) {
      if (part.isMarker) continue;
      final pieces = part.pieceLines;
      for (var p = 0; p < pieces.length; p++) {
        if (p > 0 && !_format.linked.show) continue;
        for (final line in ChordPro.sheetLines(pieces[p].join('\n'))) {
          keys.line(line);
          if (line.isEmpty ||
              line == pageBreakMarker ||
              line.startsWith(transposeMarker) ||
              line.startsWith(rhythmMarker) ||
              line.startsWith(tabMarker) ||
              ChordPro.isSectionLabel(line)) {
            continue;
          }
          for (final s in ChordPro.segments(line)) {
            if (s.chord?.isNotEmpty ?? false) order.add(keys.next());
          }
        }
      }
    }
    return order;
  }

  void _select(String key) {
    setState(() => _selected = key);
    _focus.requestFocus();
  }

  void _change(int by, int barBeats) {
    final key = _selected;
    if (key == null) return;
    final v = ((widget.beats[key] ?? barBeats) + by).clamp(0, 64);
    setState(() {
      if (v == barBeats) {
        widget.beats.remove(key); // back to a bar
      } else {
        widget.beats[key] = v;
      }
    });
  }

  void _step(List<String> order, int by) {
    if (order.isEmpty) return;
    final at = _selected == null ? -1 : order.indexOf(_selected!);
    final next = at < 0
        ? (by > 0 ? 0 : order.length - 1)
        : (at + by).clamp(0, order.length - 1);
    _select(order[next]);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song();
    final raw = song.raw;
    final barBeats = beatsPerBar(
      song.timeSignature.isNotEmpty
          ? song.timeSignature
          : ChordProHeader.parse(raw).time ?? '',
    );
    final settings = _settings;
    final order = _order(raw);
    if (_selected != null && !order.contains(_selected)) _selected = null;
    final selected = _selected;
    final n = selected == null ? null : widget.beats[selected] ?? barBeats;
    final cmd = Theme.of(context).platform == TargetPlatform.macOS
        ? '⌘'
        : 'Ctrl+';

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Show beats'),
              const SizedBox(width: 6),
              Switch(
                value: settings.show,
                onChanged: (v) => _setSettings(show: v),
              ),
            ],
          ),
          AppDropdown<ChordBeatStyle>(
            value: settings.style,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: settings.show
                ? (v) {
                    if (v != null) _setSettings(style: v);
                  }
                : null,
            items: [
              for (final st in ChordBeatStyle.values)
                DropdownMenuItem(value: st, child: Text(st.label)),
            ],
          ),
          if (settings.style.boxed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Bars per line  ${settings.barsPerLine}'),
                IconButton(
                  tooltip: 'Fewer bars per line',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(BrambleIcons.minus),
                  onPressed: settings.show && settings.barsPerLine > 1
                      ? () =>
                            _setSettings(barsPerLine: settings.barsPerLine - 1)
                      : null,
                ),
                IconButton(
                  tooltip: 'More bars per line',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(BrambleIcons.plus),
                  onPressed: settings.show && settings.barsPerLine < 8
                      ? () =>
                            _setSettings(barsPerLine: settings.barsPerLine + 1)
                      : null,
                ),
              ],
            ),
          Tooltip(
            message: settings.own
                ? 'These settings apply to this song only'
                : 'These settings apply to all songs',
            child: InkWell(
              borderRadius: BorderRadius.circular(inkR(6)),
              onTap: () => _setOwn(!settings.own),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: settings.own,
                    onChanged: (v) => _setOwn(v == true),
                  ),
                  const Text('Only this song'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        for (final meta in [true, false]) ...{
          SingleActivator(
            LogicalKeyboardKey.arrowUp,
            meta: meta,
            control: !meta,
          ): () =>
              _change(1, barBeats),
          SingleActivator(
            LogicalKeyboardKey.arrowDown,
            meta: meta,
            control: !meta,
          ): () =>
              _change(-1, barBeats),
          SingleActivator(
            LogicalKeyboardKey.arrowRight,
            meta: meta,
            control: !meta,
          ): () =>
              _step(order, 1),
          SingleActivator(
            LogicalKeyboardKey.arrowLeft,
            meta: meta,
            control: !meta,
          ): () =>
              _step(order, -1),
        },
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolbar,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ChordSheet(
                  song: song,
                  raw: raw,
                  format: _format,
                  transpose: 0,
                  displayKey: song.writtenKey,
                  soundingKey: song.writtenKey,
                  parts: ChordPro.parts(raw),
                  beats: settings,
                  animate: false,
                  onChordTap: _select,
                  selectedChord: selected,
                ),
              ),
            ),
            if (!settings.show)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Beats are hidden. Turn on “Show beats” to see them on '
                  'the chord sheet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous chord ($cmd←)',
                    icon: const Icon(BrambleIcons.caretLeft),
                    onPressed: order.isEmpty ? null : () => _step(order, -1),
                  ),
                  Expanded(
                    child: Text(
                      order.isEmpty
                          ? 'This song has no chords yet.'
                          : n == null
                          ? 'Tap a chord to set its beats'
                          : n == 0
                          ? 'No beats shown'
                          : '$n beat${n == 1 ? '' : 's'}'
                                '${n == barBeats ? ' (a bar)' : ''}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fewer beats ($cmd↓)',
                    icon: const Icon(BrambleIcons.minus),
                    onPressed: n == null || n <= 0
                        ? null
                        : () => _change(-1, barBeats),
                  ),
                  IconButton(
                    tooltip: 'More beats ($cmd↑)',
                    icon: const Icon(BrambleIcons.plus),
                    onPressed: n == null ? null : () => _change(1, barBeats),
                  ),
                  IconButton(
                    tooltip: 'Next chord ($cmd→)',
                    icon: const Icon(BrambleIcons.caretRight),
                    onPressed: order.isEmpty ? null : () => _step(order, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
