import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../browser.dart';
import '../music.dart';
import '../state.dart' show searchKey, searchMatches;
import '../pads/pad_controller.dart';
import '../pads/sf2.dart';
import 'floating_panel.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// The worship pad: twelve keys (the song's key marked; the one playing
/// lit), follow the song's key, octave, volume, and the sound (built in or
/// from a SoundFont) with its tone, reverb and crossfade. A floating panel,
/// or full screen with big keys.
class PadPanel extends StatelessWidget {
  final PadController pads;
  final VoidCallback? onClose;
  final bool fullscreen;
  final VoidCallback? onFullscreen;

  const PadPanel({
    super.key,
    required this.pads,
    this.onClose,
    this.fullscreen = false,
    this.onFullscreen,
  });

  /// Its size as a floating panel.
  static const size = Size(372, 470);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([pads, pads.model]),
      builder: (context, _) => Material(
        color: scheme.surfaceContainerHigh,
        elevation: inkE(fullscreen ? 0 : 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(inkR(fullscreen ? 0 : 18)),
          side: fullscreen
              ? BorderSide.none
              : BorderSide(color: scheme.outline, width: inkW(1.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Title bar: drag it to move the pads.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FloatingDragArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          spacing: 6,
                          children: [
                            Icon(
                              BrambleIcons.dotsSixVertical,
                              color: scheme.outline,
                            ),
                            Text('Pads', style: theme.textTheme.titleMedium),
                            if (pads.busy)
                              const SizedBox.square(
                                dimension: 14,
                                child: AppSpinner(strokeWidth: 2),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: pads.playing ? 'Stop the pad' : 'Play the pad',
                    isSelected: pads.playing,
                    color: pads.playing && !isEink(context)
                        ? scheme.primary
                        : null,
                    icon: const Icon(BrambleIcons.power),
                    onPressed: pads.toggle,
                  ),
                  if (onFullscreen != null)
                    IconButton(
                      tooltip: fullscreen ? 'Exit full screen' : 'Full screen',
                      icon: Icon(
                        fullscreen
                            ? BrambleIcons.cornersIn
                            : BrambleIcons.cornersOut,
                      ),
                      onPressed: onFullscreen,
                    ),
                  if (onClose != null)
                    IconButton(
                      tooltip: 'Close pads (keeps playing)',
                      icon: const Icon(BrambleIcons.x),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                // Full screen: grows with the window, keys big enough to
                // hit from a distance.
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: SizedBox(
                      width: fullscreen
                          ? math.min(box.maxWidth, 900)
                          : box.maxWidth,
                      height: box.maxHeight,
                      child: FittedBox(
                        fit: fullscreen ? BoxFit.contain : BoxFit.scaleDown,
                        child: SizedBox(
                          width: 340,
                          height: 404,
                          child: _PadBody(pads: pads),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PadBody extends StatelessWidget {
  final PadController pads;
  const _PadBody({required this.pads});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = pads.model.settings;
    final song = pads.songKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SoundButton(pads: pads)),
            IconButton(
              tooltip: 'Sound settings',
              icon: const Icon(BrambleIcons.slidersHorizontal),
              onPressed: () => _showSoundSettings(context, pads),
            ),
          ],
        ),
        if (pads.problem case final p?)
          Text(
            p,
            style: TextStyle(color: scheme.error, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 8),
        // The keys: four across.
        Expanded(
          child: Column(
            spacing: 8,
            children: [
              for (var row = 0; row < 3; row++)
                Expanded(
                  child: Row(
                    spacing: 8,
                    children: [
                      for (var col = 0; col < 4; col++)
                        Expanded(
                          child: _KeyButton(
                            name: MusicKey(row * 4 + col, false).name,
                            playing: pads.playing && pads.key == row * 4 + col,
                            chosen: pads.key == row * 4 + col,
                            songKey: song == row * 4 + col,
                            onTap: () => pads.tapKey(row * 4 + col),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: 'Moves to each song’s key as you go through them',
                child: InkWell(
                  borderRadius: BorderRadius.circular(inkR(8)),
                  onTap: () => pads.setFollow(!s.padFollow),
                  child: Row(
                    children: [
                      Checkbox(
                        value: s.padFollow,
                        onChanged: (v) => pads.setFollow(v!),
                      ),
                      Flexible(
                        child: Text(
                          song == null
                              ? 'Follow song key'
                              : 'Follow song key '
                                    '(${pads.model.currentKey?.name ?? MusicKey(song, false).name})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Octave down',
              visualDensity: VisualDensity.compact,
              icon: const Icon(BrambleIcons.minus),
              onPressed: s.padOctave > -1
                  ? () => pads.change((s) => s.padOctave--)
                  : null,
            ),
            Text(
              'Oct ${s.padOctave > 0 ? '+' : ''}${s.padOctave}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Octave up',
              visualDensity: VisualDensity.compact,
              icon: const Icon(BrambleIcons.plus),
              onPressed: s.padOctave < 2
                  ? () => pads.change((s) => s.padOctave++)
                  : null,
            ),
          ],
        ),
        Row(
          children: [
            Icon(BrambleIcons.speakerLow, color: scheme.onSurfaceVariant),
            Expanded(
              child: Slider(
                value: s.padVolume,
                semanticFormatterCallback: (v) =>
                    'Volume ${(v * 100).round()}%',
                onChanged: pads.setVolume,
              ),
            ),
            Icon(BrambleIcons.speakerHigh, color: scheme.onSurfaceVariant),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String name;
  final bool playing, chosen, songKey;
  final VoidCallback onTap;

  const _KeyButton({
    required this.name,
    required this.playing,
    required this.chosen,
    required this.songKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: playing,
      label: '$name${songKey ? ', the song’s key' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: playing ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(inkR(16)),
          border: Border.all(
            color: chosen ? scheme.primary : scheme.outlineVariant,
            width: inkW(chosen ? 2.5 : 1),
          ),
          boxShadow: playing && !isEink(context)
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.45),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(inkR(16)),
            onTap: onTap,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: playing ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
                // A dot under the song's key.
                if (songKey)
                  Align(
                    alignment: const Alignment(0, 0.78),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: playing ? scheme.onPrimary : scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sound in use; tap to choose another (or remove an imported one).
class _SoundButton extends StatelessWidget {
  final PadController pads;
  const _SoundButton({required this.pads});

  @override
  Widget build(BuildContext context) {
    final current = pads.choice;
    return PopupMenuButton<String>(
      tooltip: 'Choose the sound',
      position: PopupMenuPosition.under,
      onSelected: (id) async {
        if (id == 'import') {
          await importSoundFont(context, pads);
        } else {
          pads.change((s) => s.padSound = id);
        }
      },
      itemBuilder: (context) => [
        for (final c in pads.choices)
          PopupMenuItem(
            value: c.id,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: c.id == current.id
                      ? const Icon(BrambleIcons.check, size: 18)
                      : null,
                ),
                Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                if (c.imported)
                  IconButton(
                    tooltip: 'Remove this sound',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(BrambleIcons.trash, size: 18),
                    onPressed: () {
                      Navigator.pop(context);
                      pads.deleteSound(c);
                    },
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(BrambleIcons.folderOpen, size: 18),
              ),
              Text('Import SoundFont (.sf2)…'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              current.imported ? BrambleIcons.vinylRecord : BrambleIcons.waves,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                current.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Icon(BrambleIcons.caretDownFill),
          ],
        ),
      ),
    );
  }
}

/// Tone, reverb and crossfade, in a small sheet.
void _showSoundSettings(BuildContext context, PadController pads) {
  showAppDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: pads,
      builder: (context, _) {
        final s = pads.model.settings;
        Widget slider(
          String label,
          String value,
          double v,
          double max,
          ValueChanged<double> onChange,
          ValueChanged<double> onDone,
        ) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [Text(label), const Spacer(), Text(value)]),
            ),
            Slider(
              value: v,
              max: max,
              onChanged: onChange,
              onChangeEnd: onDone,
            ),
          ],
        );
        return AlertDialog(
          title: Text(pads.choice.name),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                slider(
                  'Tone',
                  s.padTone < 0.35
                      ? 'Dark'
                      : s.padTone > 0.8
                      ? 'Bright'
                      : 'Warm',
                  s.padTone,
                  1,
                  (v) => pads.model.updateSettings((s) => s.padTone = v),
                  (v) => pads.change((s) => s.padTone = v),
                ),
                slider(
                  'Reverb',
                  '${(s.padReverb * 100).round()}%',
                  s.padReverb,
                  1,
                  (v) => pads.model.updateSettings((s) => s.padReverb = v),
                  (v) => pads.change((s) => s.padReverb = v),
                ),
                slider(
                  'Crossfade between keys',
                  '${s.padFade.toStringAsFixed(1)} s',
                  s.padFade,
                  8,
                  (v) => pads.model.updateSettings((s) => s.padFade = v),
                  (_) {},
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
      },
    ),
  );
}

/// Picks a SoundFont, lets the person choose presets from it, and takes
/// them into the app.
Future<void> importSoundFont(BuildContext context, PadController pads) async {
  final files = await pickBinaryFiles(const ['.sf2'], multiple: false);
  if (files.isEmpty || !context.mounted) return;
  final (name, bytes) = files.first;
  final (file, problem) = readSoundFont(bytes);
  if (file == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? 'Couldn’t read that file.')),
    );
    return;
  }
  final chosen = await showAppDialog<List<Sf2Preset>>(
    context: context,
    builder: (context) => _PresetPicker(file: file, fileName: name),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  try {
    await pads.importPresets(file, chosen, name);
  } on Sf2Error catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _PresetPicker extends StatefulWidget {
  final Sf2File file;
  final String fileName;
  const _PresetPicker({required this.file, required this.fileName});

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  late final List<Sf2Preset> _all = widget.file.presets;
  final Set<int> _chosen = {};
  String _filter = '';
  bool _onlyHeld = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _filter.trim();
    final shown = [
      for (final p in _all)
        // (The app's search: accents and word order don't matter.)
        if ((!_onlyHeld || p.sustains) &&
            (q.isEmpty || searchMatches(searchKey(p.name), q)))
          p,
    ];
    return AlertDialog(
      title: Text(
        widget.fileName.replaceFirst(
          RegExp(r'\.sf2$', caseSensitive: false),
          '',
        ),
      ),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(BrambleIcons.magnifyingGlass),
                hintText: 'Find a sound (pad, strings, choir…)',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Only sounds that hold (can be pads)'),
              value: _onlyHeld,
              onChanged: (v) => setState(() => _onlyHeld = v!),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'No sounds',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final p = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(p.name.isEmpty ? 'Untitled' : p.name),
                          secondary: Text(
                            '${p.bank}:${p.program}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          value: _chosen.contains(p.index),
                          onChanged: (v) => setState(
                            () => v!
                                ? _chosen.add(p.index)
                                : _chosen.remove(p.index),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final p in _all)
                    if (_chosen.contains(p.index)) p,
                ]),
          child: Text(
            _chosen.length > 1 ? 'Add ${_chosen.length} sounds' : 'Add sound',
          ),
        ),
      ],
    );
  }
}
