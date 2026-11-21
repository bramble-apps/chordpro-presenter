import 'package:flutter/material.dart';

import '../music.dart';
import 'chord_db.dart';
import 'chord_diagram.dart';
import 'chord_sound.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// How a chord sheet shows and plays chords (from the settings).
class ChordDiagramsConfig {
  final bool show;
  final Instrument instrument;
  final bool fingers;
  final double zoom;
  final bool collapsed;

  /// Tapping a chord in the song shows its diagrams.
  final bool tappable;
  final ChordPlaySpeed speed;
  final Map<String, String> prefs;
  final List<ChordShape> custom;

  /// The capo: diagrams show the shapes played, sound is the real pitch.
  final int capo;
  final VoidCallback onToggleCollapsed;

  /// Shows a chord's diagrams ([anchor]: where the chord is on screen).
  final void Function(String name, ChordName chord, {Rect? anchor}) onShowChord;

  const ChordDiagramsConfig({
    required this.show,
    required this.instrument,
    required this.fingers,
    required this.zoom,
    required this.collapsed,
    required this.tappable,
    required this.speed,
    required this.prefs,
    required this.custom,
    required this.capo,
    required this.onToggleCollapsed,
    required this.onShowChord,
  });

  ChordShape? shapeFor(ChordName c) => ChordLibrary.pick(
    ChordLibrary.shapesFor(instrument, c, custom: custom),
    prefs[prefKey(instrument, c)],
  );

  void play(ChordName c) {
    final shape = shapeFor(c);
    if (shape != null) playChord(shape, capo: capo, speed: speed);
  }
}

/// Where a chosen shape is remembered.
String prefKey(Instrument i, ChordName c) =>
    '${i.name}|${c.root}|${c.suffix}|${c.bass ?? ''}';

/// The song's chords as diagrams, under its title (one per different
/// chord, in order of first use). Tap one to hear it; long press for all
/// its shapes. The chevron folds the strip away.
class ChordStrip extends StatelessWidget {
  final List<(String, ChordName)> chords;
  final ChordDiagramsConfig config;
  const ChordStrip({super.key, required this.chords, required this.config});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${config.instrument.label} chords',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            IconButton(
              tooltip: config.collapsed
                  ? 'Show chord diagrams'
                  : 'Hide chord diagrams',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                config.collapsed
                    ? BrambleIcons.caretDown
                    : BrambleIcons.caretUp,
              ),
              onPressed: config.onToggleCollapsed,
            ),
          ],
        ),
        if (!config.collapsed)
          Wrap(
            spacing: 4 * config.zoom,
            runSpacing: 4 * config.zoom,
            children: [
              for (final (name, c) in chords)
                Builder(
                  builder: (context) => ChordDiagram(
                    name: name,
                    shape: config.shapeFor(c),
                    instrument: config.instrument,
                    showFingers: config.fingers,
                    zoom: config.zoom,
                    onTap: () => config.play(c),
                    onLongPress: () {
                      final box = context.findRenderObject() as RenderBox;
                      config.onShowChord(
                        name,
                        c,
                        anchor: box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The different chords of a song's lines, in order of first use: (name
/// as shown, chord moved by [transpose]).
List<(String, ChordName)> songChords(
  Iterable<String> chordTexts, {
  required int transpose,
  required String Function(String text) display,
}) {
  final seen = <ChordName>{};
  return [
    for (final t in chordTexts)
      if (ChordName.parse(t, transpose: transpose) case final c?)
        if (seen.add(c)) (display(t), c),
  ];
}

/// A chord's diagrams in a small popover just above the chord (below it
/// when there's no room): every shape, the one in use in gold. Tap one to
/// hear it (and use it from now on); + makes your own. Tapping anywhere
/// else closes it.
Future<void> showChordDiagramsSheet(
  BuildContext context, {
  required String name,
  required ChordName chord,
  required Instrument instrument,
  required List<ChordShape> custom,
  required String? preferred,
  required bool fingers,
  required int capo,
  required ChordPlaySpeed speed,
  required ValueChanged<String> onChoose,
  required VoidCallback onAddShape,
  Rect? anchor,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close chord diagrams',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 120),
  transitionBuilder: (context, a, _, child) =>
      FadeTransition(opacity: a, child: child),
  pageBuilder: (context, _, _) {
    var chosen = preferred;
    return StatefulBuilder(
      builder: (context, setState) {
        final scheme = Theme.of(context).colorScheme;
        final shapes = ChordLibrary.shapesFor(
          instrument,
          chord,
          custom: custom,
        );
        final current = ChordLibrary.pick(shapes, chosen);
        const zoom = 0.9;
        final one = ChordDiagram.sizeOf(instrument, zoom);
        final screen = MediaQuery.sizeOf(context);
        final w = (shapes.length * (one.width + 16) + 24)
            .clamp(160.0, screen.width - 16)
            .toDouble();
        // (No name over each diagram: it's in the header.)
        final h = one.height - 18 * zoom + 12 * zoom + 2 + 40 + 12;
        final at = anchor;
        var left = at == null ? (screen.width - w) / 2 : at.center.dx - w / 2;
        left = left.clamp(8.0, screen.width - w - 8).toDouble();
        var top = at == null ? (screen.height - h) / 2 : at.top - h - 6;
        if (at != null && top < 8) top = at.bottom + 6;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top.clamp(8.0, screen.height - h - 8).toDouble(),
              width: w,
              height: h,
              child: Material(
                elevation: inkE(10),
                color: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(inkR(14)),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (instrument.fretted)
                            IconButton(
                              tooltip: 'Make your own shape',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(BrambleIcons.plus, size: 20),
                              onPressed: () {
                                Navigator.pop(context);
                                onAddShape();
                              },
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    Expanded(
                      child: shapes.isEmpty
                          ? const Center(child: Text('No diagrams yet'))
                          : ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              children: [
                                for (final s in shapes)
                                  ChordDiagram(
                                    name: name,
                                    showName: false,
                                    shape: s,
                                    instrument: instrument,
                                    showFingers: fingers,
                                    zoom: zoom,
                                    // Gold = the one in use (only when
                                    // there's a choice).
                                    selected:
                                        shapes.length > 1 &&
                                        identical(s, current),
                                    onTap: () {
                                      setState(() => chosen = s.id);
                                      onChoose(s.id);
                                      playChord(s, capo: capo, speed: speed);
                                    },
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  },
);

/// A chord's name for the Chord Library and editor ("F#m7", "C/E").
String chordLabel(ChordName c, {bool flats = false}) =>
    '${noteName(c.root, flats: flats)}${suffixLabel(c.suffix)}'
    '${c.bass == null ? '' : '/${noteName(c.bass!, flats: flats)}'}';

/// Spelling helper so callers needn't import music.dart for this.
bool prefersFlats(MusicKey? key) => key?.prefersFlats ?? false;
