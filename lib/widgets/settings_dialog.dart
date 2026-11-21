import 'package:flutter/material.dart';

import '../format.dart';
import '../gospelizer.dart';
import '../state.dart';
import 'openchords_dialog.dart';
import '../fonts.dart';
import '../themes.dart';
import 'sidebar_icon.dart';
import '../eink.dart';
import '../bramble_icons.dart';
import 'dialog_buttons.dart';

/// Appearance and layout settings.
class SettingsDialog extends StatelessWidget {
  final PresenterModel model;

  /// Opens the toolbar editor (a side pane).
  final VoidCallback? onCustomizeToolbar;
  const SettingsDialog({
    super.key,
    required this.model,
    this.onCustomizeToolbar,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        final scheme = Theme.of(context).colorScheme;
        final dark = Theme.of(context).brightness == Brightness.dark;
        Widget heading(String t) => _Heading(t);

        // Phones: almost the full screen, so two style cards fit a row.
        final screen = MediaQuery.sizeOf(context).width;
        final compact = screen < 600;
        final side = compact ? 16.0 : 24.0;
        return AlertDialog(
          // The list runs to the dialog's foot (scrolling under its rounded
          // edge); done with the round ✓ at the top, as in the song editor.
          clipBehavior: Clip.antiAlias,
          title: Row(
            children: [
              const Expanded(child: Text('Settings')),
              DialogDoneButton(onPressed: () => Navigator.pop(context)),
            ],
          ),
          insetPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 20)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          // (its top and sides the same: the ✓ as far from the corner as the
          // title is from the edge)
          contentPadding: EdgeInsets.fromLTRB(side, 12, side, 0),
          titlePadding: EdgeInsets.fromLTRB(side, side, side, 0),
          content: SizedBox(
            width: compact ? screen - 20 - 32 : 460,
            child: _Sections(
              children: [
                heading('Style'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final style in UiStyle.values)
                      Tooltip(
                        message: style.description,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(inkR(12)),
                          onTap: () =>
                              model.updateSettings((s) => s.uiStyle = style),
                          child: _StylePreview(
                            style: style,
                            theme: themeById(s.themeId),
                            dark: dark,
                            oled: s.oled,
                            selected: s.uiStyle == style,
                            outline: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                heading('Colour'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in appThemes)
                      Tooltip(
                        message: t.name,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(inkR(12)),
                          onTap: () =>
                              model.updateSettings((s) => s.themeId = t.id),
                          child: _Swatch(
                            theme: t,
                            dark: dark,
                            oled: s.oled,
                            style: s.uiStyle,
                            selected: s.themeId == t.id,
                            outline: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                heading('Mode'),
                SegmentedButton<ThemeModeSetting>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeModeSetting.system,
                      label: Text('System'),
                      icon: Icon(BrambleIcons.tbBrightnessAuto),
                    ),
                    ButtonSegment(
                      value: ThemeModeSetting.light,
                      label: Text('Light'),
                      icon: Icon(BrambleIcons.sun),
                    ),
                    ButtonSegment(
                      value: ThemeModeSetting.dark,
                      label: Text('Dark'),
                      icon: Icon(BrambleIcons.moon),
                    ),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (v) =>
                      model.updateSettings((s) => s.mode = v.first),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('OLED black'),
                  subtitle: const Text(
                    'Dark mode uses pure black instead of dark grey',
                  ),
                  value: s.oled,
                  onChanged: (v) => model.updateSettings((s) => s.oled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('E-ink'),
                  subtitle: const Text(
                    'Black and white, no animations; lists turn pages',
                  ),
                  value: s.eink,
                  onChanged: (v) => model.updateSettings((s) => s.eink = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Apply theme to music'),
                  subtitle: const Text(
                    'Off: the chord sheet stays plain light or dark',
                  ),
                  value: s.themeMusic,
                  onChanged: (v) =>
                      model.updateSettings((s) => s.themeMusic = v ?? true),
                ),
                heading('Sidebar'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Fixed'),
                      icon: SidebarIcon(),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Floating'),
                      icon: Icon(BrambleIcons.stack),
                    ),
                  ],
                  selected: {s.floatingSidebar},
                  onSelectionChanged: (v) =>
                      model.updateSettings((s) => s.floatingSidebar = v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  s.floatingSidebar
                      ? 'Floats over the music and hides after you pick a song.'
                      : 'Stays beside the music; hide it with the sidebar button.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                heading('Selected part'),
                SegmentedButton<SelectionStyle>(
                  segments: const [
                    ButtonSegment(
                      value: SelectionStyle.bar,
                      label: Text('Bar'),
                    ),
                    ButtonSegment(
                      value: SelectionStyle.highlight,
                      label: Text('Highlight'),
                    ),
                    ButtonSegment(
                      value: SelectionStyle.both,
                      label: Text('Both'),
                    ),
                  ],
                  selected: {model.format.selectionStyle},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      model.updateFormat((f) => f.selectionStyle = v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  'The selected part is what the projector shows. Tap a '
                  'part, or use ↑ ↓ ← →, Page Up / Page Down or Space — '
                  'the keys most Bluetooth page-turner pedals send. '
                  'Home / End jump to the first / last part.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const _Heading('Buttons', einkOnly: true),
                // Collapsed until opened.
                Card.outlined(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: const Text('Quick buttons'),
                    subtitle: const Text('Shown in the bottom bar'),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(BrambleIcons.timer),
                        title: const Text('Metronome'),
                        value: s.showMetronome,
                        onChanged: (v) =>
                            model.updateSettings((s) => s.showMetronome = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(BrambleIcons.caretDoubleDown),
                        title: const Text('Autoscroll'),
                        subtitle: const Text(
                          "Over the song's duration, or 1:30",
                        ),
                        value: s.showAutoscroll,
                        onChanged: (v) =>
                            model.updateSettings((s) => s.showAutoscroll = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(BrambleIcons.waveform),
                        title: const Text('Tuner and levels'),
                        subtitle: const Text(
                          'Listens through the microphone while open',
                        ),
                        value: s.showTuner,
                        onChanged: (v) =>
                            model.updateSettings((s) => s.showTuner = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(BrambleIcons.waves),
                        title: const Text('Pads'),
                        subtitle: const Text(
                          'A held chord under the music, in the song’s key',
                        ),
                        value: s.showPads,
                        onChanged: (v) =>
                            model.updateSettings((s) => s.showPads = v),
                      ),
                      if (gospelizerEnabled)
                        SwitchListTile(
                          secondary: const Icon(BrambleIcons.sparkle),
                          title: const Text('Gospelizer'),
                          subtitle: const Text(
                            'Gospel passing chords between the song’s own',
                          ),
                          value: s.showGospel,
                          onChanged: (v) =>
                              model.updateSettings((s) => s.showGospel = v),
                        ),
                      SwitchListTile(
                        secondary: const Icon(BrambleIcons.monitorPlay),
                        title: const Text('Play reference recording'),
                        subtitle: const Text(
                          'For songs with a YouTube or audio link',
                        ),
                        value: s.showPlayer,
                        onChanged: (v) =>
                            model.updateSettings((s) => s.showPlayer = v),
                      ),
                    ],
                  ),
                ),
                if (gospelizerEnabled) ...[
                  const SizedBox(height: 8),
                  GospelizerSettings(model: model),
                ],
                // Next to Quick buttons: both arrange the app's buttons.
                if (onCustomizeToolbar != null) ...[
                  const SizedBox(height: 8),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      title: const Text('Customize toolbar'),
                      subtitle: const Text(
                        'Reorder the top buttons, or put some in its ⋯ menu',
                      ),
                      trailing: const Icon(BrambleIcons.caretRight),
                      onTap: () {
                        Navigator.pop(context);
                        onCustomizeToolbar!();
                      },
                    ),
                  ),
                ],
                heading('Sharing'),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(BrambleIcons.shareNetwork),
                    title: const Text('OpenChords'),
                    subtitle: Text(
                      model.openChordsLinks.isEmpty
                          ? 'Share setlists and songs with any '
                                'OpenChords-compatible app'
                          : '${model.openChordsLinks.length} shared · '
                                'links, sync and your OpenChords ID',
                    ),
                    trailing: const Icon(BrambleIcons.caretRight),
                    onTap: () => showOpenChordsSettings(context, model),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  final AppTheme theme;
  final bool dark;
  final bool oled;
  final UiStyle style;
  final bool selected;
  final Color outline;

  const _Swatch({
    required this.theme,
    required this.dark,
    required this.oled,
    required this.style,
    required this.selected,
    required this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = buildTheme(
      theme,
      dark ? Brightness.dark : Brightness.light,
      oled: oled,
      style: style,
    ).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(inkR(12)),
        border: Border.all(
          color: selected ? outline : scheme.outlineVariant,
          width: inkW(selected ? 2.5 : 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 9, backgroundColor: scheme.primary),
              const SizedBox(width: 4),
              CircleAvatar(radius: 9, backgroundColor: scheme.secondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            theme.name,
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Small sample (title bar, button, field) drawn in a desktop style.
class _StylePreview extends StatelessWidget {
  final UiStyle style;
  final AppTheme theme;
  final bool dark;
  final bool oled;
  final bool selected;
  final Color outline;

  const _StylePreview({
    required this.style,
    required this.theme,
    required this.dark,
    required this.oled,
    required this.selected,
    required this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final fontId = style.fontId;
    final data = buildTheme(
      theme,
      dark ? Brightness.dark : Brightness.light,
      oled: oled,
      style: style,
      fontFamily: fontId == null ? null : FontOption(fontId, '').family,
    );
    if (fontId != null) FontService.ensure(fontId);
    final scheme = data.colorScheme;
    return Theme(
      data: data,
      child: Container(
        width: 136,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(inkR(12)),
        ),
        // The outline goes over the contents (the title strip used to
        // cover its top and corners).
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(inkR(12)),
          border: Border.all(
            color: selected ? outline : scheme.outlineVariant,
            width: inkW(selected ? 2.5 : 1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: scheme.surfaceContainerHigh,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                style.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  SizedBox(
                    height: 26,
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Button'),
                    ),
                  ),
                  Text(
                    style.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
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
}

/// A heading in Settings (and on e-ink, where a section starts).
class _Heading extends StatelessWidget {
  final String title;

  /// Only a section on e-ink (the rest of the time it isn't shown).
  final bool einkOnly;
  const _Heading(this.title, {this.einkOnly = false});

  @override
  Widget build(BuildContext context) {
    if (einkOnly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// Settings' contents: one scrolling column, or on e-ink a list of the
/// sections (by [_Heading]), each opening on its own with a way back, so
/// nothing needs scrolling through.
class _Sections extends StatefulWidget {
  final List<Widget> children;
  const _Sections({required this.children});

  @override
  State<_Sections> createState() => _SectionsState();
}

class _SectionsState extends State<_Sections> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    if (!isEink(context)) {
      return SingleChildScrollView(
        // (room at the end, inside the scroll: the last setting clears
        // the dialog's foot)
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.children,
        ),
      );
    }
    final sections = <(String, List<Widget>)>[];
    for (final w in widget.children) {
      if (w is _Heading) {
        sections.add((w.title, []));
      } else if (sections.isNotEmpty) {
        sections.last.$2.add(w);
      }
    }
    final open = sections.where((s) => s.$1 == _open).firstOrNull;
    if (open == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (title, _) in sections)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              trailing: const Icon(BrambleIcons.caretRight),
              onTap: () => setState(() => _open = title),
            ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EinkBackHeader(
          title: open.$1,
          onBack: () => setState(() => _open = null),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: open.$2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Gospelizer's settings (the ✨ toolbar button adds gospel passing
/// chords between a song's own; see gospelizer.dart).
class GospelizerSettings extends StatelessWidget {
  final PresenterModel model;
  const GospelizerSettings({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final s = model.settings;
    final song = model.currentSong;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(BrambleIcons.sparkle),
        title: const Text('Gospelizer'),
        subtitle: const Text('Gospel passing chords between the song’s own'),
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          if (song != null)
            SwitchListTile(
              title: Text('On for “${song.displayTitle}”'),
              subtitle: const Text(
                'Turning it off gives back the song exactly as written',
              ),
              value: song.gospelOn,
              onChanged: model.setGospel,
            ),
          SwitchListTile(
            title: const Text('Glow'),
            subtitle: Text(
              isEink(context)
                  ? 'Not in e-ink: added chords are in brackets, (D7)'
                  : s.gospelGlow
                  ? 'Added chords have a rainbow glow behind them'
                  : 'Added chords look like the others, in brackets: (D7)',
            ),
            value: s.gospelGlow,
            onChanged: (v) => model.updateSettings((s) => s.gospelGlow = v),
          ),
          SwitchListTile(
            title: const Text('Keep the song’s chords'),
            subtitle: const Text(
              'Only adds passing chords between them. Off: a full '
              'reharmonization — colours, secondary dominants, borrowed '
              'chords (Fm6, Ab–Bb–C), tritone subs, F/G',
            ),
            value: s.gospelKeep,
            onChanged: model.setGospelKeep,
          ),
        ],
      ),
    );
  }
}
