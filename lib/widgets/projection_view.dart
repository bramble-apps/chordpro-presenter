import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../chordpro.dart';
import '../fonts.dart';
import '../format.dart';
import '../media.dart';
import '../music.dart';
import '../projection.dart';
import '../state.dart';
import '../themes.dart';
import 'chord_sheet.dart';
import 'dynamic_background.dart';
import 'fitting_slide.dart';
import '../ink.dart';
import 'ink_layer.dart';
import 'live_media.dart';
import '../media_library.dart';

/// What the stage view needs to draw the current song's chord sheet.
class StageData {
  final Song song;
  final String raw;
  final int transpose;
  final MusicKey? displayKey;
  final MusicKey? soundingKey;
  final int capo;
  final SheetFormat format;
  final String sheetFont;
  final String chordFont;
  final String? nextTitle;

  /// Gospelizer chords glow (else they're in brackets).
  final bool passingGlow;

  StageData({
    required this.song,
    required this.raw,
    required this.transpose,
    required this.displayKey,
    required this.soundingKey,
    required this.capo,
    required this.format,
    required this.sheetFont,
    required this.chordFont,
    this.nextTitle,
    this.passingGlow = true,
  });

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'raw': raw,
    'transpose': transpose,
    'displayKey': displayKey?.name,
    'soundingKey': soundingKey?.name,
    'capo': capo,
    'format': format.toJson(),
    'sheetFont': sheetFont,
    'chordFont': chordFont,
    'next': nextTitle,
    if (!passingGlow) 'passingGlow': false,
  };

  static StageData? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    MusicKey? key(Object? v) => v is String ? MusicKey.parse(v) : null;
    return StageData(
      song: Song.fromJson(j['song'] as Map<String, dynamic>),
      raw: j['raw'] as String? ?? '',
      transpose: (j['transpose'] as num?)?.toInt() ?? 0,
      displayKey: key(j['displayKey']),
      soundingKey: key(j['soundingKey']),
      capo: (j['capo'] as num?)?.toInt() ?? 0,
      format: SheetFormat()..updateFrom(j['format'] as Map<String, dynamic>),
      sheetFont: j['sheetFont'] as String? ?? 'default',
      chordFont: j['chordFont'] as String? ?? 'default',
      nextTitle: j['next'] as String?,
      passingGlow: j['passingGlow'] as bool? ?? true,
    );
  }
}

/// Everything the projector shows.
class ProjectionData {
  final ProjectionSettings settings;
  final List<String> slides;
  final ValueListenable<int> selection;
  final double transitionSeconds;
  final String projectorFont;
  final bool blackout;
  final StageData? stage;

  /// The countdown timer (shown when started).
  final CountdownState? countdown;

  /// Running on a TV / Chromecast: skip smooth scrolling animations.
  final bool lowPower;

  /// Annotations drawn on each slide (by slide number), shown over it.
  final List<List<InkStroke>>? ink;

  /// From the media library: played full screen or shown over the lyrics.
  final LiveMedia? live;

  /// The operator's small copy of the screen: videos silent, YouTube as
  /// its still picture (the projector plays the sound).
  final bool preview;

  /// Lyrics with no background behind them (see-through): for a TV that
  /// draws the animated wallpaper itself.
  final bool noBackground;

  const ProjectionData({
    this.live,
    this.preview = false,
    this.noBackground = false,
    this.lowPower = false,
    required this.settings,
    required this.slides,
    required this.selection,
    required this.transitionSeconds,
    required this.projectorFont,
    required this.blackout,
    this.stage,
    this.countdown,
    this.ink,
  });
}

/// The projector screen (lyrics or stage view), drawn at whatever size it
/// is given. The operator's preview draws it at the projector's real size
/// and scales it down.
class ProjectorDisplay extends StatelessWidget {
  final ProjectionData data;

  /// A slide tile (presentation grid): the lyrics look only, still
  /// backgrounds, no blackout or timer.
  final bool tile;

  /// Drawn ahead of time as a picture (Chromecast from the phone): no
  /// live clock, which would be stuck at the moment it was drawn.
  final bool picture;
  const ProjectorDisplay({
    super.key,
    required this.data,
    this.tile = false,
    this.picture = false,
  });

  @override
  Widget build(BuildContext context) {
    // Annotations on the slide shown (over the whole screen).
    final ink = data.ink == null
        ? null
        : ValueListenableBuilder<int>(
            valueListenable: data.selection,
            builder: (context, i, _) => i >= 0 && i < data.ink!.length
                ? InkCanvas(strokes: data.ink![i])
                : const SizedBox.shrink(),
          );
    if (tile) {
      return LayoutBuilder(
        builder: (context, c) {
          final view = _LyricsView(data: data, size: c.biggest, still: true);
          if (ink == null) return view;
          return Stack(fit: StackFit.expand, children: [view, ink]);
        },
      );
    }
    final screen = LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final view = data.settings.view == ProjectionView.stage
            ? _StageView(data: data, size: size, clock: !picture)
            : _LyricsView(data: data, size: size, motion: !picture);
        return Stack(
          fit: StackFit.expand,
          children: [
            view,
            ?ink,
            if (data.live case final live?)
              LiveMediaView(
                key: ValueKey('live-${live.started}'),
                live: live,
                preview: data.preview || picture,
              ),
            // Blackout: fade to black (or the blackout picture/video).
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: data.blackout ? 1 : 0,
                child: data.settings.blackoutMedia == null
                    ? const ColoredBox(color: Colors.black)
                    : MediaBackground(
                        media: data.settings.blackoutMedia!,
                        fit: MediaFit.fill,
                        play: data.blackout,
                      ),
              ),
            ),
            // The countdown sits above everything (also over blackout, so
            // a pre-service countdown can run on a black screen).
            if (data.countdown case final c?
                when c.active && data.settings.timerShow)
              CountdownOverlay(
                countdown: c,
                settings: data.settings,
                size: size,
                fontFamily: FontOption(
                  data.settings.timerFont.isEmpty
                      ? data.projectorFont
                      : data.settings.timerFont,
                  '',
                ).family,
              ),
          ],
        );
      },
    );
    return underscanned(data.settings, screen);
  }
}

/// [screen] shrunk and placed inside the screen as the underscan settings
/// say (black around it), or as it is when underscan is off.
Widget underscanned(ProjectionSettings s, Widget screen) {
  if (!s.underscan) return screen;
  return ColoredBox(
    color: Colors.black,
    child: Align(
      alignment: Alignment(s.underscanX, s.underscanY),
      child: FractionallySizedBox(
        widthFactor: s.underscanW / 100,
        heightFactor: (s.underscanLocked ? s.underscanW : s.underscanH) / 100,
        child: ClipRect(child: screen),
      ),
    ),
  );
}

/// A song's title slide: the title large, the artist under it, centred.
class _TitleSlide extends StatelessWidget {
  final String title, artist;
  final double unit;
  final ProjectionSettings settings;
  final String? fontFamily;
  const _TitleSlide({
    required this.title,
    required this.artist,
    required this.unit,
    required this.settings,
    required this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final shadows = s.textShadow
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 12 * unit,
              offset: Offset(0, 3 * unit),
            ),
          ]
        : null;
    TextStyle style(double size, FontWeight weight, double alpha) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      fontStyle: s.textItalic ? FontStyle.italic : FontStyle.normal,
      color: s.textColor.withValues(alpha: alpha),
      shadows: shadows,
      height: 1.15,
    );
    return Padding(
      padding: EdgeInsets.all(96 * unit),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1600 * unit),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.textCaps ? title.toUpperCase() : title,
                  textAlign: TextAlign.center,
                  style: style(s.textSize * 1.3 * unit, FontWeight.w700, 1),
                ),
                if (artist.trim().isNotEmpty) ...[
                  SizedBox(height: 28 * unit),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    style: style(s.textSize * 0.6 * unit, FontWeight.w400, 0.8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsView extends StatelessWidget {
  final ProjectionData data;
  final Size size;

  /// No moving pictures (tiles): videos show as the background colour.
  final bool still;

  /// A dynamic background moves (off for a picture of the screen: its
  /// first moment, as a still).
  final bool motion;
  const _LyricsView({
    required this.data,
    required this.size,
    this.still = false,
    this.motion = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = data.settings;
    final unit = size.height / 1080; // sizes are given for a 1080p screen
    var media = s.bgType == BackgroundType.media ? s.bgMedia : null;
    if (still && media != null && media.mime.startsWith('video/')) media = null;
    final dynamicBg = s.bgType == BackgroundType.dynamic ? s.bgDynamic : null;
    final song = data.stage?.song;

    // The footer on slide [index]: each item on its chosen slides. None on
    // the blank slide; on the title slide, everything but the title (it's
    // already there, large). "First" / "last" count the title slide and
    // the lyrics (the title item: the lyrics only).
    final slides = data.slides;
    final lyricSlides = [
      for (var k = 0; k < slides.length; k++)
        if (!isIntroSlide(slides[k])) k,
    ];
    final titleAt = slides.indexWhere((t) => titleSlideOf(t) != null);
    String footerOn(int index) {
      if (song == null || index < 0 || index >= slides.length) return '';
      if (isBlankSlide(slides[index])) return '';
      bool on(OnSlides w, {bool title = false}) {
        final pool = [if (!title && titleAt >= 0) titleAt, ...lyricSlides];
        if (!pool.contains(index)) return false;
        return w.shows(pool.indexOf(index), pool.length);
      }

      return [
        if (on(s.footerTitle, title: true)) song.displayTitle,
        if (on(s.footerCopyright) && song.copyright.isNotEmpty)
          '© ${song.copyright}',
        if (on(s.footerCcli) && song.ccli.isNotEmpty)
          'CCLI Song # ${song.ccli}',
        if (on(s.footerCcli) && song.ccliLicense.isNotEmpty)
          'CCLI License # ${song.ccliLicense}',
        if (on(s.footerText) && song.footer.trim().isNotEmpty)
          song.footer.trim(),
      ].join('   ·   ');
    }

    // Room is kept for it on every slide (so the lyrics don't jump), as
    // long as some slide shows it.
    final footerText = song == null
        ? ''
        : [
            for (var k = 0; k < data.slides.length; k++)
              if (footerOn(k).isNotEmpty) 'x',
          ].join();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!data.noBackground) ColoredBox(color: s.bgColor),
        if (!data.noBackground)
          AnimatedSwitcher(
            duration: Duration(milliseconds: (s.bgTransition * 1000).round()),
            child: media != null
                ? MediaBackground(
                    key: ValueKey(media.id),
                    media: media,
                    fit: s.bgFit,
                  )
                : dynamicBg != null
                ? DynamicBackground(
                    key: ValueKey('dynamic ${dynamicBg.name}'),
                    bg: dynamicBg,
                    // The operator's small copy moves only if asked to.
                    animate:
                        !still &&
                        motion &&
                        (!data.preview || s.bgDynamicPreview),
                    // Fewer pixels for the small copy and on slow devices
                    // (a still is drawn once, and may be cast or exported).
                    pixels: !still && (data.preview || data.lowPower)
                        ? 320
                        : 480,
                  )
                : const SizedBox.expand(key: ValueKey('none')),
          ),
        if (s.bgDim > 0)
          ColoredBox(color: s.bgDimColor.withValues(alpha: s.bgDim / 100)),
        if (overlayGradient(s) case final g?)
          DecoratedBox(decoration: BoxDecoration(gradient: g)),
        Padding(
          // Leave room for the footer line when it is shown.
          padding: EdgeInsets.only(
            bottom: s.footer && footerText.isNotEmpty ? 50 * unit : 0,
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: data.selection,
            builder: (context, index, _) {
              final text = index < slides.length ? slides[index] : '';
              // The blank slide: only the background.
              if (isBlankSlide(text)) return const SizedBox.expand();
              if (titleSlideOf(text) case (final title, final artist)) {
                return _TitleSlide(
                  title: title,
                  artist: artist,
                  unit: unit,
                  settings: s,
                  fontFamily: FontOption(data.projectorFont, '').family,
                );
              }
              final intro = introCount(slides);
              return FittingSlide(
                text: text,
                allSlides: s.textMode == TextMode.song
                    ? slides.sublist(intro)
                    : null,
                current: index - intro,
                linked: s.linked,
                lineHeight: 1.2 * s.textLineSpacing / 100,
                maxFontSize: s.textSize * unit,
                padding: 48 * unit,
                transitionSeconds: data.transitionSeconds,
                fontFamily: FontOption(data.projectorFont, '').family,
                color: s.textColor,
                bold: s.textBold,
                italic: s.textItalic,
                caps: s.textCaps,
                shadow: s.textShadow,
                align: switch (s.textAlign) {
                  HAlign.left => TextAlign.left,
                  HAlign.center => TextAlign.center,
                  HAlign.right => TextAlign.right,
                },
                position: Alignment(
                  switch (s.textAlign) {
                    HAlign.left => -1,
                    HAlign.center => 0,
                    HAlign.right => 1,
                  },
                  switch (s.textPosition) {
                    VAlign.top => -1,
                    VAlign.center => 0,
                    VAlign.bottom => 1,
                  },
                ),
              );
            },
          ),
        ),
        // (Not on the blank slide.)
        if (s.logo != null)
          ValueListenableBuilder<int>(
            valueListenable: data.selection,
            builder: (context, index, child) =>
                index < slides.length && isBlankSlide(slides[index])
                ? const SizedBox.shrink()
                : child!,
            child: Align(
              alignment: switch (s.logoCorner) {
                Corner.topLeft => Alignment.topLeft,
                Corner.topRight => Alignment.topRight,
                Corner.bottomLeft => Alignment.bottomLeft,
                Corner.bottomRight => Alignment.bottomRight,
              },
              child: Padding(
                padding: EdgeInsets.all(28 * unit),
                child: SizedBox(
                  height: size.height * s.logoSize / 100,
                  child: MediaBackground(media: s.logo!, fit: MediaFit.fit),
                ),
              ),
            ),
          ),
        if (s.footer && footerText.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16 * unit),
              child: ValueListenableBuilder<int>(
                valueListenable: data.selection,
                builder: (context, index, _) => Text(
                  footerOn(index),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: s.textColor.withValues(alpha: 0.75),
                    fontSize: 22 * unit,
                    fontFamily: FontOption(data.projectorFont, '').family,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Musicians' monitor: header, the chord sheet following the selected part,
/// and a footer of section chips plus the next song.
class _StageView extends StatelessWidget {
  final ProjectionData data;
  final Size size;
  final bool clock;
  const _StageView({required this.data, required this.size, this.clock = true});

  @override
  Widget build(BuildContext context) {
    final s = data.settings;
    final stage = data.stage;
    final dark = s.stageScheme == StageScheme.dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = neutralScheme(brightness);
    final bg = dark ? Colors.black : Colors.white;
    final fg = dark ? Colors.white : Colors.black;
    final unit = size.height / 1080;
    final textScale = s.stageTextSize / 100 * size.height / 600;

    if (stage == null) return ColoredBox(color: bg);
    final parts = _partsFor(stage.raw);
    // (The blank / title slides first: no part.)
    final slidePartIndex = [
      for (var k = 0; k < introCount(data.slides); k++) -1,
      for (var i = 0; i < parts.length; i++)
        if (!parts[i].isMarker) i,
    ];
    // The header replaces the sheet's own title block.
    final format = SheetFormat()..updateFrom(stage.format.toJson());
    if (s.stageHeader) {
      for (final e in [
        SheetElement.title,
        SheetElement.artist,
        SheetElement.details,
      ]) {
        format[e].hidden = true;
      }
    }
    final headerSize = 34 * unit * s.stageHeaderSize / 100;
    final details = [
      if (stage.soundingKey != null) 'Key ${stage.soundingKey!.name}',
      if (stage.capo > 0) 'Capo ${stage.capo}',
      if (stage.song.tempo.isNotEmpty) '${stage.song.tempo} BPM',
      if (stage.song.timeSignature.isNotEmpty) stage.song.timeSignature,
    ].join('  ·  ');

    // Strong, readable colours on the stage screen.
    final stageTheme = ThemeData(
      colorScheme: scheme.copyWith(
        surfaceContainerLowest: bg,
        onSurface: fg,
        onSurfaceVariant: dark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF303030),
        primary: dark ? const Color(0xFF8AB4F8) : const Color(0xFF0B57D0),
        secondary: dark ? const Color(0xFFFFB74D) : const Color(0xFFB45309),
      ),
    );
    if (s.stageLayout == StageLayout.modern) {
      return Theme(
        data: stageTheme,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: ColoredBox(
            color: bg,
            child: _ModernStage(
              key: ValueKey('modern-${stage.song.id}'),
              data: data,
              stage: stage,
              parts: parts,
              slidePartIndex: slidePartIndex,
              format: format,
              size: size,
              textScale: textScale,
              dark: dark,
              live: clock,
            ),
          ),
        ),
      );
    }
    return Theme(
      data: stageTheme,
      // Text without its own colour (lyrics, notes…) must follow the stage
      // scheme, not the window it happens to be shown in (the projector
      // window is dark, the operator preview light).
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: ColoredBox(
          color: bg,
          child: Column(
            children: [
              if (s.stageHeader)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24 * unit,
                    vertical: 12 * unit,
                  ),
                  color: dark
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFEDEDED),
                  child: Row(
                    children: [
                      // Clock · centred title · key / tempo details.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: clock
                              ? StageClock(
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: headerSize * 0.8,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          stage.song.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontSize: headerSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              details,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.7),
                                fontSize: headerSize * 0.7,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: size.width * s.stageMargin / 100,
                  ),
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: ChordSheet(
                      key: ValueKey(stage.song.id),
                      song: stage.song,
                      raw: stage.raw,
                      format: format,
                      transpose: stage.transpose,
                      displayKey: stage.displayKey,
                      soundingKey: stage.soundingKey,
                      capo: stage.capo,
                      textFamily: FontOption(stage.sheetFont, '').family,
                      chordFamily: FontOption(stage.chordFont, '').family,
                      parts: parts,
                      selectedSlide: data.selection,
                      slidePartIndex: slidePartIndex,
                      selectionStyle: stage.format.selectionStyle,
                      contrastOn: bg,
                      passingGlow: stage.passingGlow,
                      // Scroll smoothly on every screen (parts are cached layers,
                      // so this stays cheap even on a Chromecast).
                      animate: true,
                    ),
                  ),
                ),
              ),
              if (s.stageFooter)
                _StageFooter(
                  parts: parts,
                  slidePartIndex: slidePartIndex,
                  selection: data.selection,
                  nextTitle: stage.nextTitle,
                  unit: unit * s.stageFooterSize / 100,
                  dark: dark,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour for a section by its name (verse green, chorus amber…).
/// A colour for each kind of song part (every verse the same colour, every
/// chorus another…), in English and French.
Color sectionColor(String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  // Checked before "chorus" / "refrain", which these names contain.
  if (has(['pre-chorus', 'prechorus', 'pre chorus', 'pré-refrain', 'pre'])) {
    return const Color(0xFFA855F7); // purple
  }
  if (has(['post-chorus', 'postchorus', 'post chorus'])) {
    return const Color(0xFFEC4899); // pink
  }
  if (has(['chorus', 'refrain'])) return const Color(0xFFF59E0B); // amber
  if (has(['verse', 'couplet'])) return const Color(0xFF22C55E); // green
  if (has(['bridge', 'pont'])) return const Color(0xFF3B82F6); // blue
  if (has(['intro'])) return const Color(0xFF06B6D4); // cyan
  if (has(['outro', 'ending', 'end', 'fin', 'coda'])) {
    return const Color(0xFFEF4444); // red
  }
  if (has(['instrumental', 'interlude', 'solo', 'break'])) {
    return const Color(0xFF14B8A6); // teal
  }
  if (has(['tag'])) return const Color(0xFFEAB308); // yellow
  if (has(['vamp', 'turnaround'])) return const Color(0xFF8B5CF6); // violet
  return const Color(0xFF94A3B8); // slate
}

String? _partsRaw;
List<SongPart> _partsCache = const [];

/// Song parts for the stage view, reused while the song text is unchanged.
List<SongPart> _partsFor(String raw) {
  if (raw != _partsRaw) {
    _partsRaw = raw;
    _partsCache = ChordPro.parts(raw);
  }
  return _partsCache;
}

/// Each slide's name, after the section it belongs to.
List<String> _slideNames(List<SongPart> parts, List<int> slidePartIndex) {
  final names = <String>[];
  var current = '';
  for (final i in slidePartIndex) {
    if (i < 0) {
      names.add('•');
      continue;
    }
    final first = parts[i].lines.isEmpty ? '' : parts[i].lines.first;
    current = ChordPro.sectionName(first) ?? current;
    names.add(current.isEmpty ? '•' : current);
  }
  return names;
}

/// The modern stage view (a 16:9 screen, laid out in 1920×1080 units):
/// the song's parts down the left, this part large in the middle, the next
/// part smaller on the right with "Up next" under it, and the title, key,
/// time signature, clock and time elapsed above it.
class _ModernStage extends StatefulWidget {
  final ProjectionData data;
  final StageData stage;
  final List<SongPart> parts;
  final List<int> slidePartIndex;
  final SheetFormat format;
  final Size size;
  final double textScale;
  final bool dark;

  /// Clock and time elapsed (not in pictures drawn ahead of time).
  final bool live;

  const _ModernStage({
    super.key,
    required this.data,
    required this.stage,
    required this.parts,
    required this.slidePartIndex,
    required this.format,
    required this.size,
    required this.textScale,
    required this.dark,
    required this.live,
  });

  @override
  State<_ModernStage> createState() => _ModernStageState();
}

class _ModernStageState extends State<_ModernStage> {
  /// When this song came up (for "time elapsed").
  final DateTime _start = DateTime.now();

  /// The screen behind everything, in both colour schemes.
  static const _screen = Color(0xFF262626);
  static const _onScreen = Colors.white;
  static const _onScreenDim = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final s = w.data.settings;
    final size = w.size;
    final unit = size.height / 1080;
    // The windows with chords and lyrics follow the colour scheme.
    final window = w.dark ? Colors.black : Colors.white;
    // One subtle outline for every window and part.
    final edge = Colors.white.withValues(alpha: 0.16);
    final radius = BorderRadius.circular(10 * unit);
    final names = _slideNames(w.parts, w.slidePartIndex);
    final stage = w.stage;
    final details = [
      if (stage.soundingKey != null) 'Key ${stage.soundingKey!.name}',
      if (stage.capo > 0) 'Capo ${stage.capo}',
      if (stage.song.timeSignature.isNotEmpty) stage.song.timeSignature,
      if (stage.song.tempo.isNotEmpty) '${stage.song.tempo} BPM',
    ].join('  ·  ');
    final fade = s.stageFade
        ? Duration(
            milliseconds: (math.max(w.data.transitionSeconds, 0.2) * 1000)
                .round(),
          )
        : Duration.zero;

    Widget part(int? partIndex, {required double scale}) {
      if (partIndex == null || partIndex < 0) return const SizedBox.shrink();
      return ClipRect(
        // As large as it can be: full size if it fits, otherwise the wrap
        // width that lets it shrink the least.
        child: _FitPart(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(w.textScale * scale)),
            child: ChordSheet(
              song: stage.song,
              raw: stage.raw,
              format: w.format,
              transpose: stage.transpose,
              displayKey: stage.displayKey,
              soundingKey: stage.soundingKey,
              capo: stage.capo,
              textFamily: FontOption(stage.sheetFont, '').family,
              chordFamily: FontOption(stage.chordFont, '').family,
              parts: w.parts,
              onlyPart: partIndex,
              contrastOn: window,
              passingGlow: stage.passingGlow,
              animate: false,
            ),
          ),
        ),
      );
    }

    /// A window with chords and lyrics; [content] fades when [id] changes.
    Widget textWindow(Object id, Widget content, {required double pad}) =>
        Container(
          decoration: BoxDecoration(
            color: window,
            border: Border.all(color: edge, width: 1.5 * unit),
            borderRadius: radius,
          ),
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(pad * unit),
          child: AnimatedSwitcher(
            duration: fade,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: KeyedSubtree(key: ValueKey(id), child: content),
          ),
        );

    // Layout (in pixels of this screen). Everything is sized from the
    // screen's height, then made narrower if the screen is narrower than
    // 16:9, so nothing ever overlaps; on wider screens it's centred.
    const shape = 600 / 686; // width / height of both windows
    final margin = 40 * unit;
    final gap = 36 * unit;
    final headH = 150 * unit; // title, key… clock
    final upNextH = 78 * unit; // "Up next" heading
    // The parts list (narrower, or hidden, gives the song more room).
    final fullLabelsW = 230 * unit;
    var labelsW = fullLabelsW * s.stagePartsWidth.clamp(0, 200) / 100;
    final labelsGap = labelsW > 0 ? gap : 0.0;
    final bigH = size.height - 2 * margin;
    var bigW = bigH * shape + (fullLabelsW - labelsW);
    final nextH = bigH - headH - upNextH;
    var nextW = nextH * shape;
    var rightW = math.max(nextW, 560 * unit);
    final room = size.width - 2 * margin - gap - labelsGap;
    final want = labelsW + bigW + rightW;
    if (want > room) {
      // Narrower than 16:9: the windows get narrower but keep the full
      // height (no empty band along the bottom).
      final k = math.max(room, 0) / want;
      labelsW *= k;
      bigW *= k;
      rightW *= k;
      nextW = rightW;
    }
    final left = margin + math.max(0, (room - (labelsW + bigW + rightW)) / 2);
    final bigLeft = left + labelsW + labelsGap;
    final rightLeft = bigLeft + bigW + gap;

    return ColoredBox(
      color: _screen,
      child: ValueListenableBuilder<int>(
        valueListenable: w.data.selection,
        builder: (context, raw, _) {
          final n = w.slidePartIndex.length;
          final index = n == 0 ? 0 : raw.clamp(0, n - 1);
          final hasNext = index + 1 < n;
          return Stack(
            children: [
              // The song's parts, top to bottom; this one highlighted.
              if (labelsW > 0)
                Positioned(
                  key: const ValueKey('modern-parts'),
                  left: left,
                  top: margin,
                  width: labelsW,
                  bottom: margin,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final gap = 18 * unit;
                      final h = n == 0
                          ? 0.0
                          : ((c.maxHeight - gap * (n - 1)) / n).clamp(
                              0.0,
                              95 * unit,
                            );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < n; i++) ...[
                            if (i > 0)
                              SizedBox(height: h < 30 * unit ? 4 * unit : gap),
                            _PartLabel(
                              name: names[i],
                              current: i == index,
                              colour: s.stageColourLabels,
                              height: h,
                              unit: unit,
                              edge: edge,
                              radius: radius,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              // This part, large (same shape as the "up next" window).
              Positioned(
                key: const ValueKey('modern-now'),
                left: bigLeft,
                top: margin,
                width: bigW,
                height: bigH,
                child: textWindow(
                  'now-$index',
                  part(n == 0 ? null : w.slidePartIndex[index], scale: 1.7),
                  pad: 34,
                ),
              ),
              // Title, key, time signature · clock, time elapsed.
              Positioned(
                key: const ValueKey('modern-head'),
                left: rightLeft,
                top: margin,
                width: rightW,
                height: headH,
                // Shrinks rather than running into anything.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: math.max(rightW, 560 * unit),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stage.song.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 46 * unit,
                                  fontWeight: FontWeight.bold,
                                  color: _onScreen,
                                ),
                              ),
                              SizedBox(height: 6 * unit),
                              Text(
                                details,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 32 * unit,
                                  color: _onScreenDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (w.live) ...[
                          SizedBox(width: 24 * unit),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StageClock(
                                style: TextStyle(
                                  fontSize: 46 * unit,
                                  fontWeight: FontWeight.bold,
                                  color: _onScreen,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              SizedBox(height: 6 * unit),
                              _Elapsed(
                                since: _start,
                                style: TextStyle(
                                  fontSize: 32 * unit,
                                  color: _onScreenDim,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey('modern-upnext'),
                left: rightLeft,
                top: margin + headH,
                child: Text(
                  'Up next',
                  style: TextStyle(
                    fontSize: 44 * unit,
                    fontWeight: FontWeight.w600,
                    color: _onScreenDim,
                  ),
                ),
              ),
              // The next part, smaller (or the next song / the end).
              Positioned(
                key: const ValueKey('modern-next'),
                left: rightLeft,
                top: margin + headH + upNextH,
                width: nextW,
                height: nextH,
                child: textWindow(
                  'next-$index',
                  hasNext
                      ? part(w.slidePartIndex[index + 1], scale: 0.75)
                      : Center(
                          child: Text(
                            stage.nextTitle ?? 'End',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 48 * unit,
                              color: (w.dark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                  pad: 26,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One part in the list down the left of the modern stage view.
class _PartLabel extends StatelessWidget {
  final String name;
  final bool current;

  /// Each kind of part in its own colour (otherwise black and white).
  final bool colour;
  final double height;
  final double unit;
  final Color edge;
  final BorderRadius radius;

  const _PartLabel({
    required this.name,
    required this.current,
    required this.colour,
    required this.height,
    required this.unit,
    required this.edge,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final kind = sectionColor(name);
    final Color fill;
    final Color text;
    if (colour) {
      // This part in full colour; the others in a quieter shade of theirs.
      fill = current
          ? kind
          : Color.alphaBlend(
              kind.withValues(alpha: 0.32),
              const Color(0xFF262626),
            );
      text = current ? Colors.black : Colors.white;
    } else {
      fill = current ? Colors.white : const Color(0xFF383838);
      text = current ? Colors.black : const Color(0xFFE6E6E6);
    }
    return Container(
      height: height,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 10 * unit),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: current ? Colors.white : edge,
          width: (current ? 3 : 1.5) * unit,
        ),
        borderRadius: radius,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          style: TextStyle(
            fontSize: (height * 0.42).clamp(10 * unit, 40 * unit),
            fontWeight: current ? FontWeight.bold : FontWeight.w500,
            color: text,
          ),
        ),
      ),
    );
  }
}

/// Shows its child (a song part) as large as possible within the space
/// given, never larger than its own size: it tries different widths to
/// wrap the lines at, and keeps the one that needs the least shrinking
/// (wrapping at the box's width makes a part too tall when its lines are
/// long; not wrapping at all makes it too wide).
class _FitPart extends SingleChildRenderObjectWidget {
  const _FitPart({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFitPart();
}

class _RenderFitPart extends RenderProxyBox {
  double _scale = 1;

  @override
  void performLayout() {
    final child = this.child;
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    size = constraints.biggest;
    if (child == null || !maxW.isFinite || !maxH.isFinite || maxW <= 0) {
      child?.layout(constraints, parentUsesSize: true);
      _scale = 1;
      return;
    }
    double heightAt(double width) {
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      return math.max(child.size.height, 1);
    }

    // Shrink needed when laid out [width] wide.
    double fit(double width, double height) =>
        math.min(1, math.min(maxW / width, maxH / height));

    var bestWidth = maxW;
    var best = fit(maxW, heightAt(maxW));
    if (best < 1) {
      // Too tall at the box's width: wider lines make it shorter. Find
      // where "too wide" and "too tall" balance.
      var lo = maxW, hi = maxW * 6;
      for (var i = 0; i < 12; i++) {
        final mid = (lo + hi) / 2;
        final h = heightAt(mid);
        final s = fit(mid, h);
        if (s > best) {
          best = s;
          bestWidth = mid;
        }
        if (maxW / mid > maxH / h) {
          lo = mid; // still limited by height: go wider
        } else {
          hi = mid;
        }
      }
    }
    heightAt(bestWidth);
    _scale = best;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset);
      return;
    }
    context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.diagonal3Values(_scale, _scale, 1),
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.scaleByDouble(_scale, _scale, 1, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;
}

/// Time since [since], as m:ss (h:mm:ss after an hour), ticking each
/// second.
class _Elapsed extends StatefulWidget {
  final DateTime since;
  final TextStyle style;
  const _Elapsed({required this.since, required this.style});

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _timer; // start ticking
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    String two(int v) => v.toString().padLeft(2, '0');
    final text = d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${d.inMinutes}:${two(d.inSeconds % 60)}';
    return Text('Elapsed $text', style: widget.style);
  }
}

/// Coloured chips for each section (current one solid) and the next song.
class _StageFooter extends StatelessWidget {
  final List<SongPart> parts;
  final List<int> slidePartIndex;
  final ValueListenable<int> selection;
  final String? nextTitle;
  final double unit;
  final bool dark;

  const _StageFooter({
    required this.parts,
    required this.slidePartIndex,
    required this.selection,
    required this.nextTitle,
    required this.unit,
    required this.dark,
  });

  static Color _colorFor(String name) => sectionColor(name);

  @override
  Widget build(BuildContext context) {
    final names = _slideNames(parts, slidePartIndex);
    final fontSize = 18 * unit;
    return Container(
      width: double.infinity,
      color: dark ? const Color(0xFF1A1A1A) : const Color(0xFFEDEDED),
      padding: EdgeInsets.symmetric(horizontal: 16 * unit, vertical: 10 * unit),
      child: ValueListenableBuilder<int>(
        valueListenable: selection,
        builder: (context, index, _) => Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6 * unit,
                runSpacing: 6 * unit,
                children: [
                  for (var i = 0; i < names.length; i++)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * unit,
                        vertical: 4 * unit,
                      ),
                      decoration: BoxDecoration(
                        color: i == index
                            ? _colorFor(names[i])
                            : _colorFor(names[i]).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6 * unit),
                      ),
                      child: Text(
                        names[i],
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: i == index
                              ? Colors.black
                              : (dark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (nextTitle != null) ...[
              SizedBox(width: 16 * unit),
              Text(
                'Next: $nextTitle',
                style: TextStyle(
                  fontSize: fontSize,
                  color: dark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An uploaded image or (muted, looping) video filling its box.
class MediaBackground extends StatefulWidget {
  final MediaRef media;
  final MediaFit fit;
  final bool play;

  const MediaBackground({
    super.key,
    required this.media,
    required this.fit,
    this.play = true,
  });

  @override
  State<MediaBackground> createState() => _MediaBackgroundState();
}

class _MediaBackgroundState extends State<MediaBackground> {
  Uint8List? _image;
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaBackground old) {
    super.didUpdateWidget(old);
    if (old.media.id != widget.media.id) {
      _video?.dispose();
      _video = null;
      _image = null;
      _load();
    } else if (old.play != widget.play && _video != null) {
      widget.play ? _video!.play() : _video!.pause();
    }
  }

  Future<void> _load() async {
    final media = widget.media;
    if (media.isVideo) {
      final url = await MediaStore.url(media);
      if (url == null || !mounted) return;
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize();
        await c.setVolume(0);
        await c.setLooping(true);
        if (widget.play) await c.play();
      } catch (e) {
        debugPrint('Video failed: $e');
      }
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _video = c);
    } else {
      final bytes = await MediaStore.bytes(media);
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() => _image = bytes);
      }
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fit = widget.fit == MediaFit.fill ? BoxFit.cover : BoxFit.contain;
    final video = _video;
    if (video != null && video.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: video.value.size.width,
            height: video.value.size.height,
            child: VideoPlayer(video),
          ),
        ),
      );
    }
    if (_image != null) {
      return Image.memory(
        _image!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        // A file that isn't a readable image just shows nothing.
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      );
    }
    return const SizedBox.expand();
  }
}

/// The current time (updates on the minute) for the stage header.
class StageClock extends StatefulWidget {
  final TextStyle style;
  const StageClock({super.key, required this.style});

  @override
  State<StageClock> createState() => _StageClockState();
}

class _StageClockState extends State<StageClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// Wakes once at the start of each minute (no constant redraws).
  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        _schedule();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Text(time, maxLines: 1, style: widget.style);
  }
}

/// The countdown timer on the projector. Counts down by itself between
/// messages (one repaint a second of just the digits).
class CountdownOverlay extends StatefulWidget {
  final CountdownState countdown;
  final ProjectionSettings settings;
  final Size size;
  final String? fontFamily;

  const CountdownOverlay({
    super.key,
    required this.countdown,
    required this.settings,
    required this.size,
    this.fontFamily,
  });

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(CountdownOverlay old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    _tick?.cancel();
    if (!widget.countdown.running) return;
    // Wake just after the next whole second changes.
    final left = widget.countdown.remainingMs;
    if (left <= 0) return;
    final wait = left % 1000 == 0 ? 1000 : left % 1000;
    _tick = Timer(Duration(milliseconds: wait + 15), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final h = widget.size.height;
    final fontSize = h * s.timerSize / 100;
    return IgnorePointer(
      child: Align(
        alignment: s.timerPlace.alignment,
        child: Padding(
          padding: EdgeInsets.all(h * 0.035),
          child: RepaintBoundary(
            child: Text(
              formatCountdown(widget.countdown.remainingMs),
              style: TextStyle(
                color: s.timerColor,
                fontSize: fontSize,
                fontFamily: widget.fontFamily,
                fontWeight: s.timerBold ? FontWeight.bold : FontWeight.normal,
                fontStyle: s.timerItalic ? FontStyle.italic : FontStyle.normal,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1,
                shadows: s.timerShadow
                    ? [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: fontSize * 0.12,
                          offset: Offset(0, fontSize * 0.04),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
