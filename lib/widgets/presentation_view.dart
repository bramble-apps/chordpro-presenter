import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../translation.dart';
import 'translate_dialog.dart';

import 'package:flutter/services.dart';

import '../chordpro.dart';
import '../fonts.dart';
import '../projection.dart';
import '../state.dart';
import '../themes.dart';
import 'bible_pane.dart';
import 'color_picker.dart';
import 'media_pane.dart';
import 'projection_view.dart';
import '../eink.dart';
import '../bramble_icons.dart';
import 'bold_icon.dart';

/// Presentation mode: every slide of the song as a tile (as it looks on
/// the projector), grouped under section headers. Tap a tile to show it.
/// Pinch (or Ctrl/⌘ + scroll) to resize: the grid snaps to 1–5 columns.
/// The live preview and controls are docked beside (or below) the grid.
class PresentationView extends StatefulWidget {
  final PresenterModel model;

  /// Room under the slides and the dock to scroll them out from behind
  /// what floats over the bottom (the toolbar).
  final double bottomClearance;
  const PresentationView({
    super.key,
    required this.model,
    this.bottomClearance = 0,
  });

  @override
  State<PresentationView> createState() => _PresentationViewState();
}

class _PresentationViewState extends State<PresentationView>
    with TickerProviderStateMixin {
  /// Phones: Slides / Functions / Media / Scripture.
  late final _tabs = TabController(length: 4, vsync: this);

  /// Wider windows, under the preview and its controls: Functions /
  /// Scripture.
  late final _dockTabs = TabController(length: 2, vsync: this);

  PresenterModel get model => widget.model;

  /// Columns shown: the chosen number, but never tiles narrower than
  /// about 160 px (phones show fewer).
  int get _columns => model.settings.presentColumns.clamp(1, _maxColumns);
  int _maxColumns = 5;

  /// Fractional column count while a pinch is in progress (null when
  /// idle). The grid re-flows to the nearest whole number as you go.
  double? _cont;

  // Two-finger touch pinch, read directly (the grid's own scrolling would
  // otherwise claim the fingers).
  final Map<int, Offset> _touches = {};
  double? _lastSpan;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    _tabs.dispose();
    _dockTabs.dispose();
    super.dispose();
  }

  void _setColumns(int c) {
    c = c.clamp(1, _maxColumns);
    if (c == _columns) return;
    model.updateSettings((s) => s.presentColumns = c);
  }

  /// Zooms by [factor]: above 1 = bigger tiles (fewer columns).
  void _zoom(double factor) {
    final cont = ((_cont ?? _columns.toDouble()) / factor).clamp(
      0.6,
      _maxColumns + 0.4,
    );
    _cont = cont;
    _setColumns(cont.round());
  }

  void _zoomEnd() {
    _cont = null;
    _lastSpan = null;
  }

  double _span() {
    final p = _touches.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScaleEvent) {
      // Trackpad pinch (some browsers).
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
      _zoom(math.pow(e.scale, 2.5).toDouble());
      _scheduleEnd();
      return;
    }
    if (e is PointerScrollEvent) {
      final keys = HardwareKeyboard.instance;
      if (!keys.isControlPressed && !keys.isMetaPressed) return;
      // Ctrl/⌘ + scroll, and trackpad pinch in most browsers (many small
      // steps). A mouse-wheel notch is capped at about one column.
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
      _zoom(math.exp(-e.scrollDelta.dy.clamp(-40.0, 40.0) * 0.03));
      _scheduleEnd();
    }
  }

  void _scheduleEnd() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 250), () {
      // (A two-finger touch pinch in progress ends on its own.)
      if (mounted && _touches.length < 2) _zoomEnd();
    });
  }

  /// The media button: opens the media pane beside the slides (on phones,
  /// the Media tab).
  void _toggleMedia() {
    if (MediaQuery.sizeOf(context).width < 600) {
      _tabs.animateTo(2);
      return;
    }
    mediaPaneOpen.value = !mediaPaneOpen.value;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: mediaPaneOpen,
      builder: (context, mediaOpen, _) => _layout(mediaOpen),
    );
  }

  /// The timer and the other tools.
  Widget _functions({EdgeInsets padding = EdgeInsets.zero}) => ListView(
    padding: padding,
    children: [
      _TimerPanel(model: model),
      const SizedBox(height: 10),
      UnderscanPanel(model: model),
    ],
  );

  Widget _layout(bool mediaOpen) {
    return LayoutBuilder(
      builder: (context, c) {
        final grid = _grid();
        // Tablets and up: the dock beside the grid: the preview and its
        // controls, then the tools in tabs (Functions / Scripture). (The
        // media pane runs along the bottom of the window.)
        if (c.maxWidth >= 600) {
          final dockWidth = (c.maxWidth * 0.36).clamp(240.0, 540.0);
          final eink = isEink(context);
          final clearance = eink ? 0.0 : widget.bottomClearance;
          final top = [
            _Dock(model: model, onZoom: _zoomBy, part: _DockPart.preview),
            const SizedBox(height: 10),
            _Dock(
              model: model,
              onZoom: _zoomBy,
              part: _DockPart.controls,
              mediaOpen: mediaOpen,
              onMedia: _toggleMedia,
            ),
            TabBar(
              controller: _dockTabs,
              tabs: const [
                _IconTab(BrambleIcons.slidersHorizontal, 'Functions'),
                _IconTab(BrambleIcons.bookOpenText, 'Scripture'),
              ],
            ),
          ];
          final tabs = TabBarView(
            controller: _dockTabs,
            children: [
              _functions(
                padding: EdgeInsets.only(top: 10, bottom: clearance + 12),
              ),
              BiblePane(model: model, bottomClearance: clearance),
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: grid),
              SizedBox(
                width: dockWidth,
                child: Padding(
                  // (E-ink: ends above the toolbar, page arrows in view.)
                  padding: EdgeInsets.fromLTRB(
                    8,
                    8,
                    12,
                    eink ? widget.bottomClearance : 0,
                  ),
                  // Short windows: the dock scrolls, the tools keep a
                  // usable height.
                  child: c.maxHeight < 560
                      ? SingleChildScrollView(
                          child: Column(
                            children: [
                              ...top,
                              SizedBox(height: 420, child: tabs),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            ...top,
                            Expanded(child: tabs),
                          ],
                        ),
                ),
              ),
            ],
          );
        }
        // Phones, like YouTube: the live preview on top, the controls
        // under it, then Slides / Functions tabs.
        return Column(
          children: [
            _Dock(model: model, onZoom: _zoomBy, part: _DockPart.preview),
            const SizedBox(height: 6),
            _Dock(
              model: model,
              onZoom: _zoomBy,
              compact: true,
              part: _DockPart.controls,
              // (No Media button: Media is a tab right under the bar.)
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                _IconTab(BrambleIcons.squaresFour, 'Slides'),
                _IconTab(BrambleIcons.slidersHorizontal, 'Functions'),
                _IconTab(BrambleIcons.images, 'Media'),
                _IconTab(BrambleIcons.bookOpenText, 'Scripture'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  grid,
                  _functions(padding: const EdgeInsets.symmetric(vertical: 10)),
                  MediaPane(model: model),
                  BiblePane(
                    model: model,
                    bottomClearance: widget.bottomClearance,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _zoomBy(int delta) => _setColumns(_columns - delta);

  Widget _grid() {
    final parts = model.parts;
    final slides = model.slides;
    final partIndex = model.slidePartIndex;
    // Section name for every slide (unlabelled parts continue the last one).
    final names = <String?>[];
    final starts = <bool>[];
    String? current;
    for (var i = 0; i < slides.length; i++) {
      // The blank and title slides before the song.
      if (isIntroSlide(slides[i])) {
        starts.add(true);
        names.add(isBlankSlide(slides[i]) ? 'Blank' : 'Title');
        continue;
      }
      final pi = i < partIndex.length ? partIndex[i] : -1;
      final part = pi >= 0 && pi < parts.length ? parts[pi] : null;
      final label = part == null || part.lines.isEmpty
          ? null
          : ChordPro.sectionName(part.lines.first);
      starts.add(label != null);
      if (label != null) current = label;
      names.add(current);
    }
    final size = model.projectorSize;
    final s = model.projection;
    final stage = model.stageData;

    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.touch) return;
        _touches[e.pointer] = e.position;
        if (_touches.length == 2) _lastSpan = _span();
      },
      onPointerMove: (e) {
        if (!_touches.containsKey(e.pointer)) return;
        _touches[e.pointer] = e.position;
        if (_touches.length == 2 && (_lastSpan ?? 0) > 0) {
          final span = _span();
          _zoom(math.pow(span / _lastSpan!, 1.6).toDouble());
          _lastSpan = span;
        }
      },
      onPointerUp: (e) {
        if (_touches.remove(e.pointer) != null && _lastSpan != null) {
          _zoomEnd();
        }
      },
      onPointerCancel: (e) {
        if (_touches.remove(e.pointer) != null && _lastSpan != null) {
          _zoomEnd();
        }
      },
      child: slides.isEmpty
          ? const Center(child: Text('This song has no slides.'))
          : LayoutBuilder(
              builder: (context, c) {
                const pad = 12.0, gap = 10.0;
                _maxColumns = ((c.maxWidth - pad * 2 + gap) / (160 + gap))
                    .floor()
                    .clamp(1, 5);
                final tileWidth =
                    (c.maxWidth - pad * 2 - gap * (_columns - 1)) / _columns;
                final slideHeight = tileWidth * size.height / size.width;
                // E-ink: the grid ends above the toolbar (its page arrows
                // in view) instead of scrolling out from behind it.
                final eink = isEink(context);
                final delegate = SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  // Header strip + a slide with the projector's shape.
                  mainAxisExtent: _SlideTile.headerHeight + 3 + slideHeight,
                );
                // Scripture shown beside the song: its slides after the
                // song's, under a divider.
                final scripture = model.scriptureStart;
                Widget tile(BuildContext context, int i) => _SlideTile(
                  key: ValueKey('tile-$i'),
                  index: i,
                  text: slides[i],
                  section: scripture >= 0 && i >= scripture
                      ? model.scriptureNames[i - scripture]
                      : names[i],
                  startsSection:
                      (scripture >= 0 && i >= scripture) || starts[i],
                  selection: model.selection,
                  settings: s,
                  font: model.projectorFont,
                  projectorSize: size,
                  stage: stage,
                  onTap: () => model.goTo(i),
                );
                // The last row can always scroll clear of the toolbar.
                final bottom = pad + (eink ? 0 : widget.bottomClearance);
                final Widget grid = scripture < 0
                    ? GridView.builder(
                        padding: EdgeInsets.fromLTRB(pad, pad, pad, bottom),
                        gridDelegate: delegate,
                        itemCount: slides.length,
                        itemBuilder: tile,
                      )
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              pad,
                              pad,
                              pad,
                              0,
                            ),
                            sliver: SliverGrid.builder(
                              gridDelegate: delegate,
                              itemCount: scripture,
                              itemBuilder: tile,
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: _ScriptureDivider(model: model),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(pad, 0, pad, bottom),
                            sliver: SliverGrid.builder(
                              gridDelegate: delegate,
                              itemCount: slides.length - scripture,
                              itemBuilder: (context, i) =>
                                  tile(context, scripture + i),
                            ),
                          ),
                        ],
                      );
                return eink
                    ? Padding(
                        padding: EdgeInsets.only(
                          bottom: widget.bottomClearance,
                        ),
                        child: grid,
                      )
                    : grid;
              },
            ),
    );
  }
}

/// A tab shown as an icon (its name as the tooltip).
class _IconTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _IconTab(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Tab(
    icon: Tooltip(message: label, child: Icon(icon)),
  );
}

/// Between the song's slides and the scripture shown beside it: a rule,
/// the passage, and a button that takes its slides away again.
class _ScriptureDivider extends StatelessWidget {
  final PresenterModel model;
  const _ScriptureDivider({required this.model});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = model.currentPassage;
    final rule = Expanded(
      child: Divider(color: scheme.outlineVariant, thickness: inkW(1)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 2),
      child: Row(
        children: [
          Icon(
            BrambleIcons.bookOpenText,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 0,
            child: Text(
              p == null
                  ? 'Scripture'
                  : 'Scripture · ${p.reference} · ${p.versions}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          rule,
          IconButton(
            tooltip: 'Remove the scripture slides',
            visualDensity: VisualDensity.compact,
            icon: const Icon(BrambleIcons.x, size: 18),
            onPressed: model.closeScripture,
          ),
        ],
      ),
    );
  }
}

/// One slide: number and section header, then the slide as projected.
class _SlideTile extends StatelessWidget {
  final int index;
  final String text;
  final String? section;
  final bool startsSection;
  final ValueListenable<int> selection;
  final ProjectionSettings settings;
  final String font;
  final Size projectorSize;
  final StageData? stage;
  final VoidCallback onTap;

  static final _firstSlide = ValueNotifier<int>(0);

  const _SlideTile({
    super.key,
    required this.index,
    required this.text,
    required this.section,
    required this.startsSection,
    required this.selection,
    required this.settings,
    required this.font,
    required this.projectorSize,
    required this.onTap,
    this.stage,
  });

  static const headerHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // (E-ink: black and white, so no section colours.)
    final color = section == null || isEink(context)
        ? scheme.outline
        : sectionColor(section!);
    // Drawn exactly like the projector (background, dim, gradient, text,
    // alignment, position, logo, footer), just smaller.
    final slide = FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: projectorSize.width,
        height: projectorSize.height,
        child: ProjectorDisplay(
          tile: true,
          data: ProjectionData(
            settings: settings,
            slides: [text],
            selection: _firstSlide,
            transitionSeconds: 0,
            projectorFont: font,
            blackout: false,
            stage: stage,
          ),
        ),
      ),
    );
    final header = SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              section ?? '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: startsSection ? color : color.withValues(alpha: 0.55),
                fontWeight: startsSection ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Slide ${index + 1}${section == null ? '' : ', $section'}',
      child: ValueListenableBuilder<int>(
        valueListenable: selection,
        builder: (context, selected, child) {
          final on = selected == index;
          return Material(
            color: scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              // Follows the style (Material rounder, desktop styles squarer).
              borderRadius: BorderRadius.circular(
                StyleExtras.of(context).panelRadius * 0.6,
              ),
              side: BorderSide(
                color: on ? scheme.onSurface : Colors.transparent,
                width: inkW(2),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: child),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Container(height: 3, color: color),
            Expanded(child: RepaintBoundary(child: slide)),
          ],
        ),
      ),
    );
  }
}

/// Live preview with the slide controls, docked beside / under the grid.
/// Which piece of the dock to show (phones lay them out separately).
enum _DockPart { all, preview, controls }

class _Dock extends StatelessWidget {
  final PresenterModel model;
  final bool compact;
  final void Function(int delta) onZoom;
  final _DockPart part;
  final bool mediaOpen;
  final VoidCallback? onMedia;

  const _Dock({
    required this.model,
    required this.onZoom,
    this.compact = false,
    this.part = _DockPart.all,
    this.mediaOpen = false,
    this.onMedia,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = model.projectorSize;
    final radius = StyleExtras.of(context).panelRadius;
    final preview = AspectRatio(
      aspectRatio: size.width / size.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(inkR(radius)),
        child: ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ProjectorDisplay(data: model.projectionData),
            ),
          ),
        ),
      ),
    );
    // Narrow docks: tighter buttons, and no zoom buttons (pinch or
    // Ctrl/⌘ + scroll still zoom).
    final controls = Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(inkR(radius)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: LayoutBuilder(
          builder: (context, c) {
            final tight = c.maxWidth < 320;
            final density = tight
                ? VisualDensity.compact
                : VisualDensity.standard;
            // Too many buttons for a narrow dock: they wrap onto a
            // second line rather than run off the edge.
            final wrap = c.maxWidth < 300;
            final items = <Widget>[
              IconButton(
                tooltip: 'Previous slide',
                visualDensity: density,
                icon: const Icon(BrambleIcons.caretLeft),
                onPressed: model.previous,
              ),
              // Shrinks rather than overflow (narrow dock, large text).
              if (wrap)
                ValueListenableBuilder<int>(
                  valueListenable: model.selection,
                  builder: (context, i, _) => Text(
                    model.slides.isEmpty
                        ? '–'
                        : '${i + 1} / ${model.slides.length}',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ValueListenableBuilder<int>(
                      valueListenable: model.selection,
                      builder: (context, i, _) => Text(
                        model.slides.isEmpty
                            ? '–'
                            : '${i + 1} / ${model.slides.length}',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Next slide',
                visualDensity: density,
                icon: const Icon(BrambleIcons.caretRight),
                onPressed: model.next,
              ),
              IconButton(
                tooltip: 'Translate slides',
                visualDensity: density,
                isSelected:
                    model.currentSong != null &&
                    translatedLanguages(model.currentSong!.raw).isNotEmpty,
                icon: const Icon(BrambleIcons.globe),
                onPressed: model.currentSong == null
                    ? null
                    : () => translateCurrentSong(context, model),
              ),
              IconButton(
                tooltip: model.blackout ? 'Show slides again' : 'Blackout',
                visualDensity: density,
                isSelected: model.blackout,
                icon: const Icon(BrambleIcons.circleHalf),
                onPressed: model.toggleBlackout,
              ),
              if (model.live != null)
                IconButton(
                  tooltip: 'Stop the media (back to the lyrics)',
                  visualDensity: density,
                  icon: const Icon(BrambleIcons.stopCircle),
                  onPressed: model.stopLive,
                )
              else if (onMedia != null)
                IconButton(
                  tooltip: mediaOpen ? 'Hide media' : 'Media',
                  visualDensity: density,
                  isSelected: mediaOpen,
                  icon: const Icon(BrambleIcons.images),
                  onPressed: onMedia,
                ),
              if (!compact && !tight) ...[
                IconButton(
                  tooltip: 'Bigger tiles (fewer columns)',
                  icon: const Icon(BrambleIcons.magnifyingGlassPlus),
                  onPressed: () => onZoom(1),
                ),
                IconButton(
                  tooltip: 'Smaller tiles (more columns)',
                  icon: const Icon(BrambleIcons.magnifyingGlassMinus),
                  onPressed: () => onZoom(-1),
                ),
              ],
            ];
            // Beside the grid: two rows (moving through the slides, then
            // the tools), so nothing is cramped.
            if (!compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: items.sublist(0, 3),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: items.sublist(3),
                  ),
                ],
              );
            }
            return wrap
                ? Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: items,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: items,
                  );
          },
        ),
      ),
    );
    if (part == _DockPart.preview) return preview;
    if (part == _DockPart.controls) return controls;
    final timer = _TimerPanel(model: model, compact: compact);
    if (compact) {
      return LayoutBuilder(
        builder: (context, c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: math.min(220, c.maxWidth * 0.4),
                  child: preview,
                ),
                const SizedBox(width: 8),
                Expanded(child: controls),
              ],
            ),
            const SizedBox(height: 8),
            timer,
            const SizedBox(height: 8),
            UnderscanPanel(model: model),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        preview,
        const SizedBox(height: 10),
        controls,
        const SizedBox(height: 10),
        timer,
        const SizedBox(height: 10),
        UnderscanPanel(model: model),
      ],
    );
  }
}

/// Countdown timer. Top: time left, play/pause and a timeline of the
/// whole timer (drag to jump). Below: +1 / −1 minute, stop, format.
class _TimerPanel extends StatefulWidget {
  final PresenterModel model;
  final bool compact;
  const _TimerPanel({required this.model, this.compact = false});

  @override
  State<_TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends State<_TimerPanel> {
  PresenterModel get model => widget.model;

  /// Seconds into the timer while the timeline is dragged (applied on
  /// release).
  double? _drag;

  /// The format options are open (below the timer).
  bool _format = false;

  static final _tight = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 36),
  );

  /// Square icon buttons with the icon centred (an even hover shape).
  static final _iconStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size.square(36),
    fixedSize: const Size.square(36),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = StyleExtras.of(context).panelRadius;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(inkR(radius)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        child: ValueListenableBuilder<int>(
          valueListenable: model.timerSeconds,
          builder: (context, left, _) {
            final total = model.timerTotalSeconds;
            final elapsed = _drag ?? (total - left).clamp(0, total).toDouble();
            final shownLeft = total - elapsed.round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      formatCountdown(shownLeft * 1000),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: model.timerRunning
                            ? scheme.primary
                            : scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: model.timerRunning
                          ? 'Pause timer'
                          : 'Start timer',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        model.timerRunning
                            ? BrambleIcons.pause
                            : BrambleIcons.play,
                      ),
                      onPressed: left == 0 && !model.timerRunning
                          ? null
                          : model.timerToggle,
                    ),
                    Expanded(
                      child: Slider(
                        value: elapsed.clamp(0, math.max(total, 1)).toDouble(),
                        max: math.max(total, 1).toDouble(),
                        semanticFormatterCallback: (v) =>
                            '${formatCountdown((total - v.round()) * 1000)} left',
                        onChanged: total == 0
                            ? null
                            : (v) => setState(() => _drag = v),
                        onChangeEnd: (v) {
                          model.timerSeek(v.round());
                          setState(() => _drag = null);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Shrinks a little rather than overflow in a narrow dock.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => model.timerAdd(60),
                              style: _tight,
                              child: const Text('+1 min'),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: total == 0
                                  ? null
                                  : () => model.timerAdd(-60),
                              style: _tight,
                              child: const Text('−1 min'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: model.projection.timerShow
                          ? 'Hide timer on the projector'
                          : 'Show timer on the projector',
                      visualDensity: VisualDensity.compact,
                      style: _iconStyle,
                      icon: Icon(
                        model.projection.timerShow
                            ? BrambleIcons.eye
                            : BrambleIcons.eyeSlash,
                      ),
                      onPressed: () => model.updateProjection(
                        (p) => p.timerShow = !p.timerShow,
                      ),
                    ),
                    IconButton(
                      tooltip:
                          'Stop timer (back to the start, off the '
                          'projector)',
                      visualDensity: VisualDensity.compact,
                      style: _iconStyle,
                      icon: const Icon(BrambleIcons.stop),
                      onPressed: model.timerStop,
                    ),
                    IconButton(
                      tooltip: _format ? 'Hide timer format' : 'Timer format',
                      isSelected: _format,
                      visualDensity: VisualDensity.compact,
                      style: _iconStyle,
                      icon: const Icon(BrambleIcons.textAa),
                      onPressed: () => setState(() => _format = !_format),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _format
                      ? _TimerFormat(model: model)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How the countdown looks on the projector (opens under the timer).
class _TimerFormat extends StatelessWidget {
  final PresenterModel model;
  const _TimerFormat({required this.model});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = model.projection;
    void set(void Function(ProjectionSettings p) f) =>
        model.updateProjection(f);
    Widget toggle(String tip, Widget icon, bool on, VoidCallback onTap) =>
        IconButton(
          tooltip: tip,
          isSelected: on,
          visualDensity: VisualDensity.compact,
          // On = a tint of the accent colour (clear in every style).
          style: IconButton.styleFrom(
            backgroundColor: on
                ? scheme.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            foregroundColor: on ? scheme.primary : scheme.onSurfaceVariant,
          ),
          icon: icon,
          onPressed: onTap,
        );
    final fonts = model.settings.fontOptions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 8),
          const SizedBox(height: 6),
          // Room permitting: placement beside the style buttons and colour.
          // Otherwise (narrow dock, large text) stacked, never squeezed.
          LayoutBuilder(
            builder: (context, c) {
              final picker = _PlacementPicker(
                value: p.timerPlace,
                onChanged: (t) => set((p) => p.timerPlace = t),
              );
              final styles = Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  toggle(
                    'Bold',
                    const BoldIcon(),
                    p.timerBold,
                    () => set((p) => p.timerBold = !p.timerBold),
                  ),
                  toggle(
                    'Italic',
                    const Icon(BrambleIcons.textItalic),
                    p.timerItalic,
                    () => set((p) => p.timerItalic = !p.timerItalic),
                  ),
                  toggle(
                    'Shadow',
                    const Icon(BrambleIcons.tbBlur),
                    p.timerShadow,
                    () => set((p) => p.timerShadow = !p.timerShadow),
                  ),
                ],
              );
              final colour = ColorField(
                tooltip: 'Timer colour',
                showHex: false,
                value: p.timerColor,
                onChanged: (c) => set((p) => p.timerColor = c),
              );
              const label = Text(
                'Colour',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              );
              if (c.maxWidth - 132 - 10 >= 150) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    picker,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          styles,
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(width: 6),
                              const Expanded(child: label),
                              colour,
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: picker),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(child: styles),
                      const SizedBox(width: 8),
                      colour,
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          AppDropdownField<String>(
            initialValue: fonts.any((f) => f.id == p.timerFont)
                ? p.timerFont
                : '',
            isExpanded: true,
            isDense: true,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Font',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Same as slides')),
              for (final f in fonts)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(f.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) async {
              if (id == null) return;
              if (id.isNotEmpty) await FontService.ensure(id);
              set((p) => p.timerFont = id);
            },
          ),
          Row(
            children: [
              Tooltip(
                message: 'Size',
                child: Icon(
                  BrambleIcons.textAa,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: p.timerSize.toDouble(),
                  min: 4,
                  max: 40,
                  divisions: 36,
                  label: '${p.timerSize}%',
                  semanticFormatterCallback: (v) => 'Size ${v.round()}%',
                  onChanged: (v) => set((p) => p.timerSize = v.round()),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${p.timerSize}%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A little screen with nine dots (corners, sides, centre): tap one to
/// put the timer there.
class _PlacementPicker extends StatelessWidget {
  final TimerPlace value;
  final ValueChanged<TimerPlace> onChanged;
  const _PlacementPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = StyleExtras.of(context).panelRadius * 0.5;
    return Container(
      width: 132,
      height: 76,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outline, width: inkW(1)),
        borderRadius: BorderRadius.circular(inkR(radius)),
      ),
      child: Stack(
        children: [
          for (final t in TimerPlace.values)
            Align(
              alignment: t.alignment,
              child: Tooltip(
                message: t.label,
                child: InkResponse(
                  onTap: () => onChanged(t),
                  radius: 16,
                  child: SizedBox(
                    width: 28,
                    height: 24,
                    child: Center(
                      child: Container(
                        width: t == value ? 12 : 8,
                        height: t == value ? 12 : 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Underscan: shrinks the picture inside the screen, for projectors and
/// TVs that cut off the edges. The size (the screen's shape, or any shape
/// once unlocked), and where it sits: drag the box in the little screen; it
/// snaps to a corner, the middle of an edge or the centre.
class UnderscanPanel extends StatefulWidget {
  final PresenterModel model;
  const UnderscanPanel({super.key, required this.model});

  @override
  State<UnderscanPanel> createState() => _UnderscanPanelState();
}

class _UnderscanPanelState extends State<UnderscanPanel> {
  /// Where the box is while being dragged (-1…1 each way).
  Offset? _drag;

  PresenterModel get model => widget.model;

  void _set(void Function(ProjectionSettings p) f) => model.updateProjection(f);

  static String _place(double x, double y) {
    const rows = ['Top', '', 'Bottom'];
    const cols = ['left', '', 'right'];
    final r = rows[(y.round() + 1).clamp(0, 2)];
    final c = cols[(x.round() + 1).clamp(0, 2)];
    if (r.isEmpty && c.isEmpty) return 'Centre';
    if (r.isEmpty) return c == 'left' ? 'Left' : 'Right';
    return c.isEmpty ? r : '$r $c';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = StyleExtras.of(context).panelRadius;
    final p = model.projection;
    final w = p.underscanW;
    final h = p.underscanLocked ? p.underscanW : p.underscanH;
    Widget slider(String label, int value, ValueChanged<int> onChanged) => Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 50,
            max: 100,
            divisions: 50,
            label: '$value%',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value%',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(inkR(radius)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(BrambleIcons.frameCorners, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                const Expanded(child: Text('Underscan')),
                Switch(
                  value: p.underscan,
                  onChanged: (v) => _set((p) => p.underscan = v),
                ),
              ],
            ),
            if (p.underscan) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _UnderscanPicker(
                  screen: model.projectorSize,
                  width: w / 100,
                  height: h / 100,
                  at: _drag ?? Offset(p.underscanX, p.underscanY),
                  onDrag: (o) => setState(() => _drag = o),
                  onPick: (o) => _set(
                    (p) => p
                      ..underscanX = o.dx
                      ..underscanY = o.dy,
                  ),
                  onDrop: () {
                    // Snaps to the nearest of the nine places.
                    final o = _drag;
                    setState(() => _drag = null);
                    if (o == null) return;
                    _set(
                      (p) => p
                        ..underscanX = o.dx.clamp(-1.0, 1.0).roundToDouble()
                        ..underscanY = o.dy.clamp(-1.0, 1.0).roundToDouble(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              if (p.underscanLocked)
                slider('Size', w, (v) => _set((p) => p.underscanW = v))
              else ...[
                slider('Width', w, (v) => _set((p) => p.underscanW = v)),
                slider('Height', h, (v) => _set((p) => p.underscanH = v)),
              ],
              Row(
                children: [
                  IconButton(
                    tooltip: p.underscanLocked
                        ? 'Unlock the shape (width and height apart)'
                        : 'Keep the screen\'s shape',
                    isSelected: p.underscanLocked,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      p.underscanLocked
                          ? BrambleIcons.lock
                          : BrambleIcons.lockOpen,
                      size: 20,
                    ),
                    onPressed: () => _set((p) {
                      if (!p.underscanLocked) {
                        p.underscanW = math.max(p.underscanW, p.underscanH);
                      }
                      p.underscanH = p.underscanW;
                      p.underscanLocked = !p.underscanLocked;
                    }),
                  ),
                  Expanded(
                    child: Text(
                      '$w% × $h%  ·  '
                      '${_place(p.underscanX, p.underscanY)}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _set(
                      (p) => p
                        ..underscanW = 90
                        ..underscanH = 90
                        ..underscanLocked = true
                        ..underscanX = 0
                        ..underscanY = 0,
                    ),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A little screen with the underscanned picture in it: drag the picture;
/// let go and it snaps to the nearest of the nine places (corners, edge
/// middles, centre), shown as dots.
class _UnderscanPicker extends StatefulWidget {
  final Size screen;

  /// The picture's size, as a fraction of the screen's.
  final double width, height;

  /// Where it is (-1…1 each way).
  final Offset at;
  final ValueChanged<Offset> onDrag;

  /// Let go (the last [onDrag] place snaps).
  final VoidCallback onDrop;

  /// One of the nine places tapped.
  final ValueChanged<Offset> onPick;

  const _UnderscanPicker({
    required this.screen,
    required this.width,
    required this.height,
    required this.at,
    required this.onDrag,
    required this.onDrop,
    required this.onPick,
  });

  @override
  State<_UnderscanPicker> createState() => _UnderscanPickerState();
}

class _UnderscanPickerState extends State<_UnderscanPicker> {
  /// The box's top-left while dragging (moves add up between frames).
  Offset? _pos;

  void _drop() {
    if (_pos == null) return;
    setState(() => _pos = null);
    widget.onDrop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (screen, width, height, at) = (
      widget.screen,
      widget.width,
      widget.height,
      widget.at,
    );
    // A margin around the screen, so the dots on its edges can be tapped.
    const m = 12.0;
    return LayoutBuilder(
      builder: (context, c) {
        final ow = c.maxWidth - 2 * m;
        final outer = Size(ow, ow * screen.height / screen.width);
        final inner = Size(outer.width * width, outer.height * height);
        final free = Size(
          outer.width - inner.width,
          outer.height - inner.height,
        );
        Offset topLeft(Offset a) =>
            Offset(free.width * (a.dx + 1) / 2, free.height * (a.dy + 1) / 2);
        final box = (topLeft(at) & inner).shift(const Offset(m, m));
        return SizedBox(
          width: c.maxWidth,
          height: outer.height + 2 * m,
          child: Stack(
            children: [
              // The screen.
              Positioned(
                left: m,
                top: m,
                width: outer.width,
                height: outer.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(inkR(6)),
                    border: Border.all(color: scheme.outline, width: inkW(1)),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: box,
                child: MouseRegion(
                  key: const ValueKey('underscan-box'),
                  cursor: SystemMouseCursors.move,
                  // Takes the drag from the dock's scrolling as soon as
                  // it moves (a tap still goes to a dot on top).
                  child: RawGestureDetector(
                    gestures: {
                      _QuickPan:
                          GestureRecognizerFactoryWithHandlers<_QuickPan>(
                            _QuickPan.new,
                            (r) {
                              r.onStart = (_) => setState(
                                () => _pos = box.topLeft - const Offset(m, m),
                              );
                              r.onUpdate = (d) {
                                final now = _pos =
                                    (_pos ?? box.topLeft - const Offset(m, m)) +
                                    d.delta;
                                widget.onDrag(
                                  Offset(
                                    free.width <= 0
                                        ? 0
                                        : now.dx / free.width * 2 - 1,
                                    free.height <= 0
                                        ? 0
                                        : now.dy / free.height * 2 - 1,
                                  ).clamp(),
                                );
                              };
                              r.onEnd = (_) => _drop();
                              // (Let go outside the window, or taken over.)
                              r.onCancel = _drop;
                            },
                          ),
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.28),
                        border: Border.all(
                          color: scheme.primary,
                          width: inkW(2),
                        ),
                        borderRadius: BorderRadius.circular(inkR(3)),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              // The nine places, on the screen's edges and centre: tap one
              // to put the picture there (the one in use filled; the
              // nearest while dragging).
              for (final y in const [-1.0, 0.0, 1.0])
                for (final x in const [-1.0, 0.0, 1.0])
                  Positioned(
                    left: m + outer.width * (x + 1) / 2 - 12,
                    top: m + outer.height * (y + 1) / 2 - 12,
                    // (Not a tooltip: that would keep a drag starting on
                    // the dot from reaching the picture under it.)
                    child: Semantics(
                      button: true,
                      label: _UnderscanPanelState._place(x, y),
                      child: GestureDetector(
                        // A tap picks the dot; a drag that starts on it
                        // still moves the picture underneath.
                        behavior: HitTestBehavior.translucent,
                        onTap: () => widget.onPick(Offset(x, y)),
                        child: IgnorePointer(
                          child: SizedBox.square(
                            dimension: 24,
                            child: Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      at.dx.roundToDouble() == x &&
                                          at.dy.roundToDouble() == y
                                      ? scheme.primary
                                      : scheme.surface,
                                  border: Border.all(
                                    color: scheme.primary,
                                    width: inkW(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

extension on Offset {
  Offset clamp() => Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
}

/// A pan that wins as soon as the pointer moves a little (before a
/// scrolling parent can take it), so small drags still move the box.
class _QuickPan extends PanGestureRecognizer {
  Offset? _down;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (event is PointerMoveEvent &&
        down != null &&
        (event.position - down).distance > 3) {
      _down = null;
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }
}
