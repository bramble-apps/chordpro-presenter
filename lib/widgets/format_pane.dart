import 'package:flutter/material.dart';

import '../browser.dart';
import '../dynamic_bg.dart';
import '../fonts.dart';
import '../media.dart';
import '../projection.dart';
import 'color_picker.dart';
import 'dynamic_background.dart';
import 'projection_view.dart';
import '../format.dart';
import '../music.dart';
import '../state.dart';
import '../chords/chord_db.dart';
import '../chords/chord_library.dart';
import '../chords/chord_sound.dart';
import '../eink.dart';

/// Right-hand "Format" panel with Projection and Page tabs.
class FormatPane extends StatefulWidget {
  final PresenterModel model;
  final VoidCallback onClose;

  const FormatPane({super.key, required this.model, required this.onClose});

  @override
  State<FormatPane> createState() => _FormatPaneState();
}

enum _Tab { page, projection }

class _FormatPaneState extends State<FormatPane> {
  PresenterModel get model => widget.model;

  /// Opens on what's on screen: projection formatting in presentation
  /// view (the slide grid), page formatting with the chord sheet.
  late bool _presenting = model.settings.presentationMode;
  late _Tab tab = _presenting ? _Tab.projection : _Tab.page;

  /// E-ink: the one section shown (null = the list of sections).
  String? _einkSection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final presenting = model.settings.presentationMode;
        if (presenting != _presenting) {
          _presenting = presenting;
          tab = presenting ? _Tab.projection : _Tab.page;
        }
        return _content(context);
      },
    );
  }

  Widget _content(BuildContext context) {
    return Builder(
      builder: (context) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Text('Format', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<_Tab>(
            segments: const [
              ButtonSegment(value: _Tab.page, label: Text('Page')),
              ButtonSegment(value: _Tab.projection, label: Text('Projection')),
            ],
            selected: {tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              tab = s.first;
              _einkSection = null;
            }),
          ),
          const SizedBox(height: 12),
          ..._einkPaged(context, switch (tab) {
            _Tab.page => _page(),
            _Tab.projection => _projection(context),
          }),
        ],
      ),
    );
  }

  /// On e-ink, [items]' sections become a list of their titles, each
  /// opening on its own (with a way back) instead of one long scroll.
  List<Widget> _einkPaged(BuildContext context, List<Widget> items) {
    if (!isEink(context)) return items;
    final sections = [
      for (final w in items)
        if (w is _Section) w,
    ];
    final open = sections.where((w) => w.title == _einkSection).firstOrNull;
    if (open != null) {
      return [
        EinkBackHeader(
          title: open.title,
          onBack: () => setState(() => _einkSection = null),
        ),
        open.child,
      ];
    }
    return [
      // What isn't in a section (e.g. the projector view cards) stays.
      for (final w in items)
        if (w is! _Section) w,
      for (final w in sections)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(w.title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _einkSection = w.title),
        ),
    ];
  }

  List<Widget> _projection(BuildContext context) {
    final p = model.projection;
    void set(void Function(ProjectionSettings p) f) =>
        model.updateProjection(f);
    final lyrics = p.view == ProjectionView.lyrics;
    return [
      // Which view the projector window shows.
      Row(
        spacing: 10,
        children: [
          Expanded(
            child: _ViewCard(
              label: 'Lyrics view',
              selected: lyrics,
              onTap: () => set((p) => p.view = ProjectionView.lyrics),
              preview: const _LyricsThumb(),
            ),
          ),
          Expanded(
            child: _ViewCard(
              label: 'Stage view',
              selected: !lyrics,
              onTap: () => set((p) => p.view = ProjectionView.stage),
              preview: const _StageThumb(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (lyrics) ..._lyricsSettings(p, set) else ..._stageSettings(p, set),
    ];
  }

  List<Widget> _lyricsSettings(
    ProjectionSettings p,
    void Function(void Function(ProjectionSettings p)) set,
  ) {
    return [
      _Section(
        title: 'Text',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            _Labeled(
              'Mode',
              SegmentedButton<TextMode>(
                segments: const [
                  ButtonSegment(
                    value: TextMode.section,
                    label: Text('Section'),
                  ),
                  ButtonSegment(value: TextMode.song, label: Text('Song')),
                ],
                selected: {p.textMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set((p) => p.textMode = v.first),
              ),
            ),
            _Hint(
              p.textMode == TextMode.section
                  ? 'One part at a time.'
                  : 'The whole song, current part highlighted.',
            ),
            _Labeled(
              'Size',
              _Stepper(
                value: '${p.textSize}',
                onMinus: p.textSize > 20
                    ? () => set((p) => p.textSize -= 5)
                    : null,
                onPlus: p.textSize < 200
                    ? () => set((p) => p.textSize += 5)
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            _FontPicker(
              label: 'Font',
              model: model,
              value: model.settings.projectorFont,
              onChanged: (id) =>
                  model.updateSettings((s) => s.projectorFont = id),
            ),
            const SizedBox(height: 6),
            _Labeled(
              'Style',
              Wrap(
                spacing: 2,
                children: [
                  _Toggle(
                    'Bold',
                    Icons.format_bold,
                    p.textBold,
                    (v) => set((p) => p.textBold = v),
                  ),
                  _Toggle(
                    'Italic',
                    Icons.format_italic,
                    p.textItalic,
                    (v) => set((p) => p.textItalic = v),
                  ),
                  _Toggle(
                    'All caps',
                    Icons.text_fields,
                    p.textCaps,
                    (v) => set((p) => p.textCaps = v),
                  ),
                  _Toggle(
                    'Shadow',
                    Icons.blur_on,
                    p.textShadow,
                    (v) => set((p) => p.textShadow = v),
                  ),
                ],
              ),
            ),
            _Labeled(
              'Colour',
              ColorField(
                value: p.textColor,
                onChanged: (c) => set((p) => p.textColor = c),
              ),
            ),
            _Labeled(
              'Align',
              SegmentedButton<HAlign>(
                segments: const [
                  ButtonSegment(
                    value: HAlign.left,
                    icon: Icon(Icons.format_align_left),
                  ),
                  ButtonSegment(
                    value: HAlign.center,
                    icon: Icon(Icons.format_align_center),
                  ),
                  ButtonSegment(
                    value: HAlign.right,
                    icon: Icon(Icons.format_align_right),
                  ),
                ],
                selected: {p.textAlign},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set((p) => p.textAlign = v.first),
              ),
            ),
            _Labeled(
              'Position',
              SegmentedButton<VAlign>(
                segments: const [
                  ButtonSegment(
                    value: VAlign.top,
                    icon: Icon(Icons.vertical_align_top),
                  ),
                  ButtonSegment(
                    value: VAlign.center,
                    icon: Icon(Icons.vertical_align_center),
                  ),
                  ButtonSegment(
                    value: VAlign.bottom,
                    icon: Icon(Icons.vertical_align_bottom),
                  ),
                ],
                selected: {p.textPosition},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set((p) => p.textPosition = v.first),
              ),
            ),
            _Labeled(
              'Transition',
              _Stepper(
                value: '${model.transitionDuration.toStringAsFixed(2)}s',
                onMinus: model.transitionDuration > 0
                    ? () => model.setTransitionDuration(
                        (model.transitionDuration - 0.25).clamp(0, 3),
                        persist: true,
                      )
                    : null,
                onPlus: model.transitionDuration < 3
                    ? () => model.setTransitionDuration(
                        (model.transitionDuration + 0.25).clamp(0, 3),
                        persist: true,
                      )
                    : null,
              ),
            ),
            _Labeled(
              'Line spacing',
              _Stepper(
                value: '${p.textLineSpacing}%',
                onMinus: p.textLineSpacing > 70
                    ? () => set((p) => p.textLineSpacing -= 10)
                    : null,
                onPlus: p.textLineSpacing < 200
                    ? () => set((p) => p.textLineSpacing += 10)
                    : null,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Tidy lyrics'),
              subtitle: const Text("Remove ' - ', lone '-' and double spaces"),
              value: p.tidyLyrics,
              onChanged: (v) => set((p) => p.tidyLyrics = v),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Before each song',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Blank slide'),
              subtitle: const Text(
                'Just the background: no words, logo or footer',
              ),
              value: p.blankSlide,
              onChanged: (v) => set((p) => p.blankSlide = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Title slide'),
              subtitle: const Text('The song\'s title and artist, centred'),
              value: p.titleSlide,
              onChanged: (v) => set((p) => p.titleSlide = v),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Linked Section (Song Structure)',
        collapsible: true,
        child: _LinkedControls(
          look: model.projection.linked,
          projector: true,
          onChange: (f) => model.updateProjection((p) => f(p.linked)),
        ),
      ),
      _Section(
        title: 'Background',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            SegmentedButton<BackgroundType>(
              segments: const [
                ButtonSegment(
                  value: BackgroundType.color,
                  label: Text('Colour'),
                ),
                ButtonSegment(
                  value: BackgroundType.media,
                  label: Text('Image & Video'),
                ),
                ButtonSegment(
                  value: BackgroundType.dynamic,
                  label: Text('Dynamic'),
                ),
              ],
              selected: {p.bgType},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
              onSelectionChanged: (v) => set((p) => p.bgType = v.first),
            ),
            const SizedBox(height: 4),
            if (p.bgType == BackgroundType.color)
              _Labeled(
                'Colour',
                ColorField(
                  value: p.bgColor,
                  onChanged: (c) => set((p) => p.bgColor = c),
                ),
              )
            else if (p.bgType == BackgroundType.dynamic)
              _DynamicControls(
                bg: p.bgDynamic,
                previewMotion: p.bgDynamicPreview,
                onPreviewMotion: (v) => set((p) => p.bgDynamicPreview = v),
                onPreset: (preset) =>
                    set((p) => p.bgDynamic = DynamicBg(preset)),
                onChange: (f) => set((p) => f(p.bgDynamic)),
              )
            else ...[
              _MediaRow(
                media: p.bgMedia,
                onChanged: (m) => set((p) => p.bgMedia = m),
              ),
              _Labeled(
                'Scaling',
                SegmentedButton<MediaFit>(
                  segments: const [
                    ButtonSegment(value: MediaFit.fill, label: Text('Fill')),
                    ButtonSegment(value: MediaFit.fit, label: Text('Fit')),
                  ],
                  selected: {p.bgFit},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => set((p) => p.bgFit = v.first),
                ),
              ),
            ],
            _Labeled(
              'Dim',
              ColorField(
                value: p.bgDimColor,
                tooltip: 'Dim colour',
                onChanged: (c) => set((p) => p.bgDimColor = c),
              ),
            ),
            _PercentSlider(
              value: p.bgDim,
              onChanged: (v) => set((p) => p.bgDim = v),
            ),
            _Labeled(
              'Transition',
              _Stepper(
                value: '${p.bgTransition.toStringAsFixed(1)}s',
                onMinus: p.bgTransition > 0
                    ? () => set(
                        (p) =>
                            p.bgTransition = (p.bgTransition - 0.5).clamp(0, 5),
                      )
                    : null,
                onPlus: p.bgTransition < 5
                    ? () => set(
                        (p) =>
                            p.bgTransition = (p.bgTransition + 0.5).clamp(0, 5),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Overlays',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Gradient'),
              subtitle: const Text('Shade part of the screen behind the words'),
              value: p.gradient,
              onChanged: (v) => set((p) => p.gradient = v),
            ),
            if (p.gradient) ...[
              _Labeled(
                'Colours',
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('One')),
                    ButtonSegment(value: true, label: Text('Two')),
                  ],
                  selected: {p.gradientTwoColors},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      set((p) => p.gradientTwoColors = v.first),
                ),
              ),
              _Labeled(
                p.gradientTwoColors ? 'From' : 'Colour',
                ColorField(
                  value: p.gradientColor1,
                  onChanged: (c) => set((p) => p.gradientColor1 = c),
                ),
              ),
              _PercentSlider(
                value: p.gradientOpacity1,
                onChanged: (v) => set((p) => p.gradientOpacity1 = v),
              ),
              if (p.gradientTwoColors) ...[
                _Labeled(
                  'To',
                  ColorField(
                    value: p.gradientColor2,
                    onChanged: (c) => set((p) => p.gradientColor2 = c),
                  ),
                ),
                _PercentSlider(
                  value: p.gradientOpacity2,
                  onChanged: (v) => set((p) => p.gradientOpacity2 = v),
                ),
              ] else
                const _Hint('Fades to transparent.'),
              _Labeled(
                'Angle',
                AngleField(
                  value: p.gradientAngle,
                  onChanged: (v) => set((p) => p.gradientAngle = v),
                ),
              ),
              const Divider(height: 16),
            ],
            const Text('Logo'),
            _MediaRow(
              media: p.logo,
              imagesOnly: true,
              onChanged: (m) => set((p) => p.logo = m),
            ),
            if (p.logo != null) ...[
              _Labeled(
                'Corner',
                SegmentedButton<Corner>(
                  segments: const [
                    ButtonSegment(
                      value: Corner.topLeft,
                      icon: Icon(Icons.north_west),
                    ),
                    ButtonSegment(
                      value: Corner.topRight,
                      icon: Icon(Icons.north_east),
                    ),
                    ButtonSegment(
                      value: Corner.bottomLeft,
                      icon: Icon(Icons.south_west),
                    ),
                    ButtonSegment(
                      value: Corner.bottomRight,
                      icon: Icon(Icons.south_east),
                    ),
                  ],
                  selected: {p.logoCorner},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => set((p) => p.logoCorner = v.first),
                ),
              ),
              _Labeled(
                'Size',
                _Stepper(
                  value: '${p.logoSize}%',
                  onMinus: p.logoSize > 4
                      ? () => set((p) => p.logoSize -= 2)
                      : null,
                  onPlus: p.logoSize < 40
                      ? () => set((p) => p.logoSize += 2)
                      : null,
                ),
              ),
            ],
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Footer'),
              subtitle: const Text('Song info along the bottom'),
              value: p.footer,
              onChanged: (v) => set((p) => p.footer = v),
            ),
            if (p.footer) ...[
              for (final (label, value, change) in [
                ('Title', p.footerTitle, (OnSlides v) => p.footerTitle = v),
                (
                  'Copyright',
                  p.footerCopyright,
                  (OnSlides v) => p.footerCopyright = v,
                ),
                ('CCLI', p.footerCcli, (OnSlides v) => p.footerCcli = v),
                ('Song footer', p.footerText, (OnSlides v) => p.footerText = v),
              ])
                _Labeled(
                  label,
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SegmentedButton<OnSlides>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      showSelectedIcon: false,
                      segments: [
                        for (final o in OnSlides.values)
                          ButtonSegment(value: o, label: Text(o.label)),
                      ],
                      selected: {value},
                      onSelectionChanged: (v) => set((_) => change(v.first)),
                    ),
                  ),
                ),
              const _Hint(
                'On which slides of each song: the first, the last or every '
                'one. Song footer is the footer text in the song\'s details.',
              ),
            ],
          ],
        ),
      ),
      _blackoutSection(p, set),
    ];
  }

  Widget _blackoutSection(
    ProjectionSettings p,
    void Function(void Function(ProjectionSettings p)) set,
  ) => _Section(
    title: 'Blackout',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        _MediaRow(
          media: p.blackoutMedia,
          emptyLabel: 'Black screen',
          onChanged: (m) => set((p) => p.blackoutMedia = m),
        ),
        const _Hint(
          'Blackout hides the lyrics: press B or the blackout button while '
          'projecting.',
        ),
      ],
    ),
  );

  List<Widget> _stageSettings(
    ProjectionSettings p,
    void Function(void Function(ProjectionSettings p)) set,
  ) {
    return [
      _Section(
        title: 'Stage view',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            const _Hint(
              'Chords and lyrics for musicians, following the selected part. '
              'Uses your Page formatting.',
            ),
            _Labeled(
              'Layout',
              SegmentedButton<StageLayout>(
                segments: const [
                  ButtonSegment(
                    value: StageLayout.classic,
                    label: Text('Classic'),
                    tooltip: 'The whole chord sheet, following along',
                  ),
                  ButtonSegment(
                    value: StageLayout.modern,
                    label: Text('Modern'),
                    tooltip:
                        'This part large, the next one beside it, the '
                        'song\'s parts down the side, and the time',
                  ),
                ],
                selected: {p.stageLayout},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set((p) => p.stageLayout = v.first),
              ),
            ),
            if (p.stageLayout == StageLayout.modern) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Fade between parts'),
                value: p.stageFade,
                onChanged: (v) => set((p) => p.stageFade = v),
              ),
              _PercentSlider(
                label: 'Parts list',
                value: p.stagePartsWidth,
                min: 0,
                max: 200,
                onChanged: (v) => set((p) => p.stagePartsWidth = v),
              ),
              const _Hint(
                'Narrower gives the song more room; all the way down hides '
                'the list.',
              ),
              _Labeled(
                'Part colours',
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Colour'),
                      tooltip: 'Each kind of part in its own colour',
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Mono'),
                      tooltip: 'Black and white',
                    ),
                  ],
                  selected: {p.stageColourLabels},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      set((p) => p.stageColourLabels = v.first),
                ),
              ),
            ],
            _Labeled(
              'Colour scheme',
              SegmentedButton<StageScheme>(
                segments: const [
                  ButtonSegment(value: StageScheme.dark, label: Text('Dark')),
                  ButtonSegment(value: StageScheme.light, label: Text('Light')),
                ],
                selected: {p.stageScheme},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set((p) => p.stageScheme = v.first),
              ),
            ),
            _Labeled(
              'Text size',
              _Stepper(
                value: '${p.stageTextSize}%',
                onMinus: p.stageTextSize > 30
                    ? () => set((p) => p.stageTextSize -= 5)
                    : null,
                onPlus: p.stageTextSize < 300
                    ? () => set((p) => p.stageTextSize += 5)
                    : null,
              ),
            ),
            if (p.stageLayout == StageLayout.classic)
              _Labeled(
                'Side margins',
                _Stepper(
                  value: '${p.stageMargin}%',
                  onMinus: p.stageMargin > 0
                      ? () => set((p) => p.stageMargin -= 1)
                      : null,
                  onPlus: p.stageMargin < 30
                      ? () => set((p) => p.stageMargin += 1)
                      : null,
                ),
              ),
          ],
        ),
      ),
      if (p.stageLayout == StageLayout.classic)
        _Section(
          title: 'Header & footer',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Header'),
                subtitle: const Text('Title, key, capo, tempo'),
                value: p.stageHeader,
                onChanged: (v) => set((p) => p.stageHeader = v),
              ),
              if (p.stageHeader)
                _PercentSlider(
                  label: 'Header size',
                  value: p.stageHeaderSize,
                  min: 50,
                  max: 250,
                  onChanged: (v) => set((p) => p.stageHeaderSize = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Footer'),
                subtitle: const Text('Section chips and the next song'),
                value: p.stageFooter,
                onChanged: (v) => set((p) => p.stageFooter = v),
              ),
              if (p.stageFooter)
                _PercentSlider(
                  label: 'Footer size',
                  value: p.stageFooterSize,
                  min: 50,
                  max: 250,
                  onChanged: (v) => set((p) => p.stageFooterSize = v),
                ),
            ],
          ),
        ),
      _blackoutSection(p, set),
    ];
  }

  List<Widget> _page() {
    final f = model.format;
    return [
      _Section(
        title: 'Layout',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Labeled(
              'Guitar tabs',
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: true, label: Text('Modern')),
                  ButtonSegment(value: false, label: Text('Classic')),
                ],
                selected: {f.tabsModern},
                onSelectionChanged: (v) =>
                    model.updateFormat((f) => f.tabsModern = v.first),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Pin header'),
              subtitle: const Text(
                'Title and artist stay visible while scrolling',
              ),
              value: f.pinHeader,
              onChanged: (v) => model.updateFormat((f) => f.pinHeader = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Follow arrangement'),
              subtitle: const Text(
                'Play sections in the song\'s or setlist\'s arrangement order',
              ),
              value: f.followArrangement,
              onChanged: (v) =>
                  model.updateFormat((f) => f.followArrangement = v),
            ),
            const SizedBox(height: 4),
            _SheetLayoutControls(model: model),
            const SizedBox(height: 10),
            const Text('Chord position'),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Above')),
                ButtonSegment(value: true, label: Text('Inline')),
              ],
              selected: {f.chordsInline},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  model.updateFormat((f) => f.chordsInline = s.first),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Fonts',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            _FontPicker(
              label: 'Lyrics & headings',
              model: model,
              value: model.settings.sheetFont,
              onChanged: (id) => model.updateSettings((s) => s.sheetFont = id),
            ),
            _FontPicker(
              label: 'Chords',
              model: model,
              value: model.settings.chordFont,
              onChanged: (id) => model.updateSettings((s) => s.chordFont = id),
            ),
            _CustomFonts(model: model),
          ],
        ),
      ),
      _Section(
        title: 'Chord notation',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdownField<ChordNotation>(
              initialValue: f.notation,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final n in ChordNotation.values)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      '${n.label}  ·  ${n.example}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) model.updateFormat((f) => f.notation = v);
              },
            ),
            const SizedBox(height: 12),
            const Text('Dual chords: also show'),
            const SizedBox(height: 6),
            AppDropdownField<ChordNotation?>(
              // (Rebuilt when the main notation changes: it leaves the list.)
              key: ValueKey(f.notation),
              initialValue: f.dualNotation == f.notation
                  ? null
                  : f.dualNotation,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nothing')),
                for (final n in ChordNotation.values)
                  if (n != f.notation)
                    DropdownMenuItem(
                      value: n,
                      child: Text(
                        '${n.label}  ·  e.g. G (${switch (n) {
                          ChordNotation.standard => 'G',
                          ChordNotation.solfege => 'Sol',
                          ChordNotation.roman => 'I',
                          ChordNotation.numbers => '1',
                        }})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (v) => model.updateFormat((f) => f.dualNotation = v),
            ),
            if ((f.notation == ChordNotation.roman ||
                    f.notation == ChordNotation.numbers ||
                    f.dualNotation == ChordNotation.roman ||
                    f.dualNotation == ChordNotation.numbers) &&
                model.currentKey == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'This song has no key or chords, so standard names are shown.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            const Text('Minor chords'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in MinorStyle.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: f.minorStyle == m,
                    onSelected: (_) =>
                        model.updateFormat((f) => f.minorStyle = m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _AccidentalsControls(model: model),
          ],
        ),
      ),
      _Section(
        title: 'Chord diagrams',
        child: _ChordDiagramControls(model: model),
      ),
      _Section(
        title: 'Linked Section (Song Structure)',
        collapsible: true,
        child: _LinkedControls(
          look: model.format.linked,
          projector: false,
          onChange: (f) => model.updateFormat((fmt) => f(fmt.linked)),
        ),
      ),
      // (E-ink: a section of its own, like the others.)
      if (einkActive)
        _Section(
          title: 'Text styles',
          child: Column(
            children: [
              for (final e in SheetElement.values)
                _ElementEditor(model: model, element: e),
            ],
          ),
        )
      else ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text('Text styles'),
        ),
        for (final e in SheetElement.values)
          _ElementEditor(model: model, element: e),
      ],
    ];
  }
}

/// Accidentals: for all songs, or overridden for the open song only.
class _AccidentalsControls extends StatelessWidget {
  final PresenterModel model;
  const _AccidentalsControls({required this.model});

  @override
  Widget build(BuildContext context) {
    final f = model.format;
    final song = model.currentSong;
    final own = song != null && model.songOwnsAccidentals(song);
    final current = song == null ? f.accidentals : model.accidentalsFor(song);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Accidentals'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in Accidentals.values)
              ChoiceChip(
                label: Text(a.label),
                selected: current == a,
                onSelected: (_) => own
                    ? model.setSongAccidentals(a)
                    : model.updateFormat((f) => f.accidentals = a),
              ),
          ],
        ),
        if (song != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Only this song'),
            subtitle: Text(
              own
                  ? '“${song.displayTitle}” ignores the global setting'
                  : 'Uses the same setting as all songs',
            ),
            value: own,
            onChanged: (v) => v == true
                ? model.setSongAccidentals(current)
                : model.clearSongAccidentals(),
          ),
      ],
    );
  }
}

class _Section extends StatefulWidget {
  final String title;
  final Widget child;

  /// Starts closed; the title opens and closes it.
  final bool collapsible;
  const _Section({
    required this.title,
    required this.child,
    this.collapsible = false,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = !widget.collapsible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Text(
      widget.title,
      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
    );
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.collapsible)
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  children: [
                    Expanded(child: title),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              )
            else
              title,
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: widget.child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bold / italic / caps / underline / size / highlight / hide for one element.
class _ElementEditor extends StatelessWidget {
  final PresenterModel model;
  final SheetElement element;

  const _ElementEditor({required this.model, required this.element});

  @override
  Widget build(BuildContext context) {
    final s = model.format[element];
    final scheme = Theme.of(context).colorScheme;

    void update(void Function(ElementStyle s) change) =>
        model.updateFormat((f) => change(f[element]));

    Widget toggle(
      String tooltip,
      Widget icon,
      bool value,
      void Function(bool) set, {
      bool enabled = true,
    }) {
      return IconButton(
        tooltip: tooltip,
        isSelected: value,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: value ? scheme.secondaryContainer : null,
        ),
        icon: icon,
        onPressed: enabled ? () => update((s) => set(!value)) : null,
      );
    }

    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    element.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.hidden ? scheme.outline : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: s.hidden ? 'Show' : 'Hide',
                  icon: Icon(
                    s.hidden ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => update((s) => s.hidden = !s.hidden),
                ),
              ],
            ),
            if (!s.hidden) ...[
              Wrap(
                spacing: 2,
                children: [
                  toggle(
                    'Bold',
                    const Icon(Icons.format_bold),
                    s.bold,
                    (v) => s.bold = v,
                  ),
                  toggle(
                    'Italic',
                    const Icon(Icons.format_italic),
                    s.italic,
                    (v) => s.italic = v,
                  ),
                  toggle(
                    'Underline',
                    const Icon(Icons.format_underline),
                    s.underline,
                    (v) => s.underline = v,
                  ),
                  if (element.allowsCaps)
                    toggle(
                      'All caps',
                      const Text(
                        'AA',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      s.caps,
                      (v) => s.caps = v,
                    ),
                ],
              ),
              Row(
                children: [
                  const Text('Size'),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle),
                    onPressed: s.size > 8
                        ? () => update((s) => s.size -= 1)
                        : null,
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${s.size.round()}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle),
                    onPressed: s.size < 60
                        ? () => update((s) => s.size += 1)
                        : null,
                  ),
                ],
              ),
              _SwatchRow(
                label: 'Colour',
                swatches: [
                  for (final name in [null, ...namedColors.keys])
                    _Swatch(
                      tooltip: name ?? 'Default',
                      color: namedColors[name] ?? scheme.onSurface,
                      selected: s.color == name,
                      onTap: () => update((s) => s.color = name),
                    ),
                ],
                custom: namedColors.containsKey(s.color)
                    ? null
                    : colorFromHex(s.color),
                onCustom: (c) => update((s) => s.color = hexOf(c)),
              ),
              const SizedBox(height: 6),
              _SwatchRow(
                label: 'Highlight',
                swatches: [
                  for (var i = 0; i < highlightColors.length; i++)
                    _Swatch(
                      tooltip: const [
                        'None',
                        'Yellow',
                        'Green',
                        'Blue',
                        'Pink',
                        'Orange', //
                      ][i],
                      color: highlightColors[i] ?? scheme.surface,
                      selected: s.highlightHex == null && s.highlight == i,
                      icon: i == 0 ? Icons.block : null,
                      onTap: () => update((s) {
                        s.highlight = i;
                        s.highlightHex = null;
                      }),
                    ),
                ],
                custom: colorFromHex(s.highlightHex),
                onCustom: (c) => update((s) => s.highlightHex = hexOf(c)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Swatch {
  final String tooltip;
  final Color color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _Swatch({
    required this.tooltip,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });
}

/// One scrollable row of colour circles; the + at the end opens the full
/// colour picker. A custom colour shows as its own (selected) circle.
class _SwatchRow extends StatelessWidget {
  final String label;
  final List<_Swatch> swatches;
  final Color? custom;
  final ValueChanged<Color> onCustom;

  const _SwatchRow({
    required this.label,
    required this.swatches,
    required this.custom,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget circle({
      required String tooltip,
      required Color color,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) => Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              width: inkW(selected ? 2.5 : 1),
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: icon == null
              ? null
              : Icon(icon, size: 14, color: scheme.outline),
        ),
      ),
    );

    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              children: [
                for (final sw in [
                  ...swatches.map(
                    (sw) => circle(
                      tooltip: sw.tooltip,
                      color: sw.color,
                      selected: sw.selected,
                      onTap: sw.onTap,
                      icon: sw.icon,
                    ),
                  ),
                  if (custom != null)
                    circle(
                      tooltip: 'Custom ${hexOf(custom!)}',
                      color: custom!,
                      selected: true,
                      onTap: () async {
                        final c = await pickColor(context, custom!);
                        if (c != null) onCustom(c);
                      },
                    ),
                  Tooltip(
                    message: 'Custom colour…',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final c = await pickColor(
                          context,
                          custom ?? scheme.primary,
                        );
                        if (c != null) onCustom(c);
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.outline,
                            width: inkW(1),
                          ),
                        ),
                        child: Icon(Icons.add, size: 16, color: scheme.primary),
                      ),
                    ),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Center(child: sw),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Dropdown of built-in and uploaded fonts.
class _FontPicker extends StatelessWidget {
  final String? label;
  final PresenterModel model;
  final String value;
  final void Function(String id) onChanged;

  const _FontPicker({
    this.label,
    required this.model,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = model.settings.fontOptions;
    final current = options.any((f) => f.id == value) ? value : 'default';
    return AppDropdownField<String>(
      initialValue: current,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final f in options)
          DropdownMenuItem(
            value: f.id,
            child: Text(f.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) async {
        if (id == null) return;
        await FontService.ensure(id);
        onChanged(id);
      },
    );
  }
}

/// Upload / remove your own .ttf or .otf fonts.
class _CustomFonts extends StatelessWidget {
  final PresenterModel model;
  const _CustomFonts({required this.model});

  @override
  Widget build(BuildContext context) {
    final fonts = model.settings.customFonts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in fonts)
          Row(
            children: [
              const Icon(Icons.font_download_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(f.name, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Remove font',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await FontService.removeCustom(f);
                  model.updateSettings((s) {
                    s.customFonts.remove(f);
                    if (s.sheetFont == f.id) s.sheetFont = 'default';
                    if (s.chordFont == f.id) s.chordFont = 'default';
                    if (s.projectorFont == f.id) s.projectorFont = 'default';
                  });
                },
              ),
            ],
          ),
        TextButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Add your own font (.ttf / .otf)…'),
          onPressed: () async {
            final files = await pickFontFiles();
            for (final (name, bytes) in files) {
              final font = await FontService.addCustom(name, bytes);
              model.updateSettings((s) => s.customFonts.add(font));
            }
          },
        ),
      ],
    );
  }
}

/// Label on the left, control on the right.
class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(
          flex: 3,
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// "value  − | +" control.
class _Stepper extends StatelessWidget {
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _Stepper({required this.value, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(inkR(20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Less',
                icon: const Icon(Icons.remove, size: 18),
                onPressed: onMinus,
              ),
              Container(width: 1, height: 18, color: scheme.outlineVariant),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'More',
                icon: const Icon(Icons.add, size: 18),
                onPressed: onPlus,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool value;
  final void Function(bool) onChanged;
  const _Toggle(this.tooltip, this.icon, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: value,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: value
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
    ),
    icon: Icon(icon),
    onPressed: () => onChanged(!value),
  );
}

/// Thumbnail + choose / remove for a background, logo or blackout file.
class _MediaRow extends StatelessWidget {
  final MediaRef? media;
  final bool imagesOnly;
  final String emptyLabel;
  final void Function(MediaRef?) onChanged;

  const _MediaRow({
    required this.media,
    required this.onChanged,
    this.imagesOnly = false,
    this.emptyLabel = 'None',
  });

  @override
  Widget build(BuildContext context) {
    final m = media;
    return Row(
      spacing: 8,
      children: [
        Container(
          width: 64,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(inkR(4)),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: inkW(1),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: m == null
              ? null
              : m.isVideo
              ? const Icon(Icons.movie_outlined, color: Colors.white70)
              : MediaBackground(media: m, fit: MediaFit.fill),
        ),
        Expanded(
          child: Text(
            m?.name ?? emptyLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () async {
            MediaRef? picked;
            try {
              picked = await MediaStore.pick(videos: !imagesOnly);
            } catch (e) {
              debugLog('pick failed: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Couldn\'t add that file: $e')),
                );
              }
              return;
            }
            debugLog('picked: ${picked?.name}');
            if (picked == null) return;
            if (m != null) await MediaStore.delete(m);
            onChanged(picked);
          },
          child: Text(m == null ? 'Choose…' : 'Change…'),
        ),
        if (m != null)
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () async {
              await MediaStore.delete(m);
              onChanged(null);
            },
          ),
      ],
    );
  }
}

class _ViewCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  const _ViewCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(inkR(10)),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(inkR(10)),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: inkW(selected ? 2.5 : 1),
          ),
        ),
        child: Column(
          spacing: 6,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(inkR(4)),
                child: preview,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsThumb extends StatelessWidget {
  const _LyricsThumb();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFF3949AB),
    child: Center(
      child: Text(
        'Amazing grace,\nhow sweet the sound',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

class _StageThumb extends StatelessWidget {
  const _StageThumb();

  @override
  Widget build(BuildContext context) {
    const chord = TextStyle(
      fontSize: 9,
      color: Color(0xFF1E88E5),
      fontWeight: FontWeight.bold,
    );
    const lyric = TextStyle(fontSize: 9, color: Colors.black87);
    // Drawn at a fixed size, then scaled to fit the card.
    return const FittedBox(
      child: SizedBox(
        width: 160,
        height: 90,
        child: ColoredBox(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(5),
            child: Stack(
              children: [
                // Sheet text, clipped to the thumbnail.
                Positioned.fill(
                  bottom: 10,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ColoredBox(
                            color: Color(0xFFF59E0B),
                            child: Text(
                              ' Chorus ',
                              style: TextStyle(fontSize: 7),
                            ),
                          ),
                          Text('   G          D       Em', style: chord),
                          Text('Amazing grace, how sweet', style: lyric),
                          Text('   C          G', style: chord),
                          Text('the sound that saved', style: lyric),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Row(
                    spacing: 3,
                    children: [
                      _Chip(Color(0xFF22C55E)),
                      _Chip(Color(0xFFF59E0B)),
                      _Chip(Color(0xFF3B82F6)),
                    ],
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

class _Chip extends StatelessWidget {
  final Color color;
  const _Chip(this.color);

  @override
  Widget build(BuildContext context) =>
      Container(width: 14, height: 5, color: color);
}

/// The dynamic background's controls, as in Keydeck (Format > Slide >
/// Background > Dynamic): the presets six to a page, Preview Motion, the
/// colours and the chosen kind's sliders.
class _DynamicControls extends StatefulWidget {
  final DynamicBg bg;
  final bool previewMotion;
  final ValueChanged<bool> onPreviewMotion;
  final ValueChanged<DynamicPreset> onPreset;
  final void Function(void Function(DynamicBg bg) change) onChange;

  const _DynamicControls({
    required this.bg,
    required this.previewMotion,
    required this.onPreviewMotion,
    required this.onPreset,
    required this.onChange,
  });

  @override
  State<_DynamicControls> createState() => _DynamicControlsState();
}

class _DynamicControlsState extends State<_DynamicControls> {
  static const _perPage = 6;

  /// Opens on the page of the preset in use.
  late int _page = dynamicPresets.indexOf(widget.bg.preset) ~/ _perPage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = widget.bg;
    final pages = (dynamicPresets.length / _perPage).ceil();
    final page = _page.clamp(0, pages - 1);
    final shown = dynamicPresets.skip(page * _perPage).take(_perPage).toList();

    Widget arrow(IconData icon, String tooltip, int to) => IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 40),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: to >= 0 && to < pages
          ? () => setState(() => _page = to)
          : null,
    );

    Widget thumb(DynamicPreset preset) {
      final on = preset == bg.preset;
      return Tooltip(
        message: preset.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(inkR(6)),
          onTap: () => widget.onPreset(preset),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(inkR(6)),
              border: Border.all(
                color: on ? scheme.primary : Colors.transparent,
                width: inkW(2),
              ),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(inkR(4)),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(inkR(4)),
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: inkW(1),
                    ),
                  ),
                  child: DynamicBackground(
                    bg: DynamicBg(preset),
                    animate: false,
                    pixels: 96,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final stops = bg.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          children: [
            arrow(Icons.chevron_left, 'Previous backgrounds', page - 1),
            Expanded(
              child: Column(
                spacing: 4,
                children: [
                  for (var row = 0; row < 2; row++)
                    Row(
                      spacing: 4,
                      children: [
                        for (var col = 0; col < 3; col++)
                          Expanded(
                            child: row * 3 + col < shown.length
                                ? thumb(shown[row * 3 + col])
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            arrow(Icons.chevron_right, 'More backgrounds', page + 1),
          ],
        ),
        // Page dots.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages; i++)
              InkResponse(
                radius: 10,
                onTap: () => setState(() => _page = i),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == page
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Preview Motion'),
          value: widget.previewMotion,
          onChanged: widget.onPreviewMotion,
        ),
        const Text('Colours'),
        // The colours in a bar, then a well for each.
        Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(inkR(3)),
            gradient: LinearGradient(
              colors: [for (final s in stops) s.color],
              stops: [for (final s in stops) s.at],
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var i = 0; i < stops.length; i++)
              ColorField(
                value: stops[i].color,
                showHex: false,
                tooltip: 'Colour ${i + 1}',
                onChanged: (c) => widget.onChange((b) => b.setColor(i, c)),
              ),
          ],
        ),
        if (bg.hasBackground)
          _Labeled(
            'Background Colour',
            ColorField(
              value: bg.background ?? const Color(0xFF000000),
              onChanged: (c) => widget.onChange((b) => b.setBackground(c)),
            ),
          ),
        for (final c in dynamicControls(bg.family)) ...[
          _Labeled(
            c.label,
            _Stepper(
              value: c.format(bg.value(c)),
              onMinus: bg.value(c) > c.min
                  ? () => widget.onChange(
                      (b) => b.setValue(c, b.value(c) - c.step),
                    )
                  : null,
              onPlus: bg.value(c) < c.max
                  ? () => widget.onChange(
                      (b) => b.setValue(c, b.value(c) + c.step),
                    )
                  : null,
            ),
          ),
          Slider(
            value: bg.value(c).clamp(c.min, c.max).toDouble(),
            min: c.min,
            max: c.max,
            divisions: c.decimals == 0 ? (c.max - c.min).round() : null,
            onChanged: (v) => widget.onChange((b) => b.setValue(c, v)),
          ),
        ],
      ],
    );
  }
}

/// "label  [slider]  42%" — opacity / size in percent.
class _PercentSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _PercentSlider({
    this.label = 'Opacity',
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 88, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ 5,
          label: '$value%',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '$value%',
          textAlign: TextAlign.end,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    ],
  );
}

/// Scroll or pages, columns and paper — for all songs, or just this one.
class _SheetLayoutControls extends StatelessWidget {
  final PresenterModel model;
  const _SheetLayoutControls({required this.model});

  @override
  Widget build(BuildContext context) {
    final song = model.currentSong;
    final layout = song == null
        ? SheetLayout.of(model.format, const {})
        : model.layoutFor(song);
    final own = layout.own;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('View'),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Scroll'),
              icon: Icon(Icons.view_day_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Pages'),
              icon: Icon(Icons.auto_stories_outlined),
            ),
          ],
          selected: {layout.pageMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              model.setLayout(pageMode: s.first, thisSong: own),
        ),
        if (layout.pageMode) ...[
          const SizedBox(height: 10),
          const Text('Columns'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {layout.columns},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                model.setLayout(columns: s.first, thisSong: own),
          ),
          const SizedBox(height: 10),
          const Text('Paper'),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Letter')),
              ButtonSegment(value: true, label: Text('A4')),
            ],
            selected: {model.format.paperA4},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                model.updateFormat((f) => f.paperA4 = s.first),
          ),
        ],
        if (song != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Only this song'),
            subtitle: Text(
              own
                  ? 'View and columns above apply to “${song.displayTitle}” only'
                  : 'View and columns above apply to all songs',
            ),
            value: own,
            onChanged: (v) => v == true
                ? model.setLayout(thisSong: true)
                : model.clearSongLayout(),
          ),
      ],
    );
  }
}

/// The look of linked sections (a verse's translation…): on the projector,
/// or on the chord sheet (which the stage view and PDF follow). Built from
/// the same controls as the Text section.
class _LinkedControls extends StatelessWidget {
  final LinkedStyle look;
  final bool projector;
  final void Function(void Function(LinkedStyle l) change) onChange;

  const _LinkedControls({
    required this.look,
    required this.projector,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        _Hint(
          projector
              ? 'The second of two linked sections (e.g. a translation) '
                    'on the projector.'
              : 'The second of two linked sections (e.g. a translation) '
                    'on the chord sheet, stage view and PDF.',
        ),
        _Labeled(
          'Show',
          Switch(
            value: look.show,
            onChanged: (v) => onChange((l) => l.show = v),
          ),
        ),
        if (look.show) ...[
          if (projector)
            _Labeled(
              'Layout',
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    tooltip: 'Top & bottom',
                    icon: Icon(Icons.view_agenda_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    tooltip: 'Side by side',
                    // The top & bottom icon turned: two panels side by side.
                    icon: RotatedBox(
                      quarterTurns: 1,
                      child: Icon(Icons.view_agenda_outlined),
                    ),
                  ),
                ],
                selected: {look.sideBySide},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    onChange((l) => l.sideBySide = s.first),
              ),
            ),
          _Labeled(
            'Size',
            _Stepper(
              value: '${look.size}%',
              onMinus: look.size > 40
                  ? () => onChange((l) => l.size -= 10)
                  : null,
              onPlus: look.size < 160
                  ? () => onChange((l) => l.size += 10)
                  : null,
            ),
          ),
          _Labeled(
            'Style',
            Wrap(
              spacing: 2,
              children: [
                _Toggle(
                  'Bold',
                  Icons.format_bold,
                  look.bold,
                  (v) => onChange((l) => l.bold = v),
                ),
                _Toggle(
                  'Italic',
                  Icons.format_italic,
                  look.italic,
                  (v) => onChange((l) => l.italic = v),
                ),
                _Toggle(
                  'Dimmed',
                  Icons.opacity,
                  look.dim,
                  (v) => onChange((l) => l.dim = v),
                ),
                if (projector)
                  _Toggle(
                    'Shadow',
                    Icons.blur_on,
                    look.shadow,
                    (v) => onChange((l) => l.shadow = v),
                  ),
              ],
            ),
          ),
          _Labeled(
            'Colour',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (look.color != null)
                  IconButton(
                    tooltip: 'Same colour as the main section',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.format_color_reset_outlined),
                    onPressed: () => onChange((l) => l.color = null),
                  ),
                ColorField(
                  tooltip: 'Linked section colour',
                  value:
                      look.color ??
                      (projector ? Colors.white : scheme.onSurface),
                  onChanged: (c) => onChange((l) => l.color = c),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Chord diagrams under the song's title, and what tapping a chord does.
class _ChordDiagramControls extends StatelessWidget {
  final PresenterModel model;
  const _ChordDiagramControls({required this.model});

  @override
  Widget build(BuildContext context) {
    final s = model.settings;
    void set(void Function(AppSettings s) f) => model.updateSettings(f);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show chord diagrams'),
          subtitle: const Text('The song’s chords, under its title'),
          value: s.showChordDiagrams,
          onChanged: (v) => set((s) => s.showChordDiagrams = v),
        ),
        const SizedBox(height: 4),
        SegmentedButton<Instrument>(
          showSelectedIcon: false,
          segments: [
            for (final i in Instrument.values)
              ButtonSegment(value: i, label: Text(i.label)),
          ],
          selected: {s.chordInstrument},
          onSelectionChanged: (v) => set((s) => s.chordInstrument = v.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show fingers'),
          value: s.showDiagramFingers,
          onChanged: (v) => set((s) => s.showDiagramFingers = v),
        ),
        Row(
          children: [
            const Text('Size'),
            Expanded(
              child: Slider(
                value: s.diagramZoom,
                min: 0.6,
                max: 2.0,
                divisions: 14,
                label: '${(s.diagramZoom * 100).round()}%',
                onChanged: (v) => set((s) => s.diagramZoom = v),
              ),
            ),
          ],
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Tap a chord to see its diagrams'),
          subtitle: const Text('Then tap a diagram to hear it'),
          value: s.tapChords,
          onChanged: (v) => set((s) => s.tapChords = v),
        ),
        const Text('Play speed'),
        const SizedBox(height: 6),
        SegmentedButton<ChordPlaySpeed>(
          showSelectedIcon: false,
          segments: [
            for (final p in ChordPlaySpeed.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {s.chordPlaySpeed},
          onSelectionChanged: (v) => set((s) => s.chordPlaySpeed = v.first),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.library_music_outlined, size: 18),
          label: const Text('Chord Library…'),
          onPressed: () => showChordLibrary(context, model),
        ),
      ],
    );
  }
}
