import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../autoscroll.dart';
import '../chord_beats.dart';
import '../chords/chord_db.dart';
import '../chords/chord_strip.dart';
import '../chordpro.dart';
import '../format.dart';
import '../inline_format.dart';
import 'abc_view.dart';
import 'tab_view.dart';
import '../music.dart';
import '../state.dart';
import '../themes.dart';
import '../bidi.dart';
import 'chord_line.dart';
import 'paged_sheet.dart';
import 'snake_columns.dart';
import '../eink.dart';

/// Formatted chord sheet: title/artist/details on top, sections (tap one to
/// centre it), chords above or inline with the lyrics, key changes from the
/// song structure, notes and a copyright footer — styled by [SheetFormat].
/// Screen pixels a point: the Format pane's sizes are points, drawn at
/// their real size (as a document app does at 100 %).
const pointPixels = 4 / 3;

/// How a [ChordSheet] below sits in its screen: [framed] (a card with a
/// border, the default) or full-bleed under floating toolbars, with its
/// content kept [inset] from the edges (clear of the toolbars) and
/// scrolling up behind them.
class SheetInsets extends InheritedWidget {
  final EdgeInsets inset;
  final bool framed;
  const SheetInsets({
    super.key,
    this.inset = EdgeInsets.zero,
    this.framed = true,
    required super.child,
  });

  static SheetInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetInsets>();

  @override
  bool updateShouldNotify(SheetInsets old) =>
      old.inset != inset || old.framed != framed;
}

class ChordSheet extends StatefulWidget {
  final Song song;

  /// Song text to show (structure already applied).
  final String raw;
  final SheetFormat format;

  /// Semitones to shift the written chords (key change minus capo).
  final int transpose;

  /// Key of the chord shapes shown (used for Roman/Numbers notation).
  final MusicKey? displayKey;

  /// Key the song sounds in, and the capo, for the details line.
  final MusicKey? soundingKey;
  final int capo;

  /// Font families for text and chords (null = app font).
  final String? textFamily;
  final String? chordFamily;
  final void Function(String url)? onOpenUrl;

  /// The song split into parts (see [ChordPro.parts]); each is a tappable
  /// block. [selectedPart] gets a bar on the left and is kept centred.
  final List<SongPart> parts;

  /// Selected slide (listened to directly, so moving the selection doesn't
  /// rebuild the sheet) and slide -> part mapping.
  final ValueListenable<int>? selectedSlide;
  final List<int> slidePartIndex;
  final void Function(int partIndex)? onSelectPart;
  final SelectionStyle selectionStyle;

  /// When set (stage view), every text colour is adjusted to stay readable
  /// on this background.
  final Color? contrastOn;

  /// Smooth scrolling/highlight animations (off on slow TV receivers).
  /// Page mode and columns (null = one long scrolling sheet).
  final SheetLayout? layout;

  /// Drawn over the sheet's content and scrolling with it (pinned sticky
  /// notes).
  final Widget? overlay;

  final bool animate;

  /// Scrolls the sheet down by itself, when it's for this song.
  final Autoscroll? autoscroll;

  /// Draw only part [onlyPart] of [parts] (chords and lyrics, nothing
  /// around it, not scrolling): for the modern stage view's boxes.
  final int? onlyPart;

  /// Chord beats (null or not shown: plain chords).
  final BeatSettings? beats;

  /// Editing chord beats: each chord (or bar) can be tapped, and the one
  /// with key [selectedChord] (see chord_beats.dart) is highlighted.
  final void Function(String chordKey)? onChordTap;
  final String? selectedChord;

  /// Chord diagrams under the title, and chords you can tap (null: none).
  final ChordDiagramsConfig? chords;

  /// Where to start (0–1 of the way down: the same place whatever the
  /// width, e.g. after rotating), and hears where it's scrolled to.
  final double? initialScroll;
  final ValueChanged<double>? onScrolled;

  /// Gospelizer chords (passing chords it added) glow behind; off, or in
  /// e-ink, they're shown in brackets: "(D7)".
  final bool passingGlow;

  const ChordSheet({
    super.key,
    required this.song,
    required this.raw,
    required this.format,
    required this.transpose,
    required this.displayKey,
    this.soundingKey,
    this.capo = 0,
    this.textFamily,
    this.chordFamily,
    this.onOpenUrl,
    required this.parts,
    this.selectedSlide,
    this.slidePartIndex = const [],
    this.onSelectPart,
    this.selectionStyle = SelectionStyle.both,
    this.contrastOn,
    this.animate = true,
    this.layout,
    this.overlay,
    this.autoscroll,
    this.onlyPart,
    this.beats,
    this.onChordTap,
    this.selectedChord,
    this.chords,
    this.initialScroll,
    this.onScrolled,
    this.passingGlow = true,
  });

  @override
  State<ChordSheet> createState() => _ChordSheetState();
}

class _ChordSheetState extends State<ChordSheet>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _autoTicker = createTicker(_autoTick);
  Duration _autoLast = Duration.zero;

  /// E-ink: where autoscroll has got to (it turns a page at a time).
  double? _autoAt;

  /// Empty room after the song (not scrolled through by autoscroll).
  double _tail = 0;
  final List<GlobalKey> _sectionKeys = [];

  SheetFormat get format => widget.format;
  Song get song => widget.song;

  @override
  void didUpdateWidget(ChordSheet old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    if (old.selectedSlide != widget.selectedSlide) {
      old.selectedSlide?.removeListener(_onSelection);
      widget.selectedSlide?.addListener(_onSelection);
    }
    if (old.autoscroll != widget.autoscroll) {
      old.autoscroll?.removeListener(_onAutoscroll);
      old.autoscroll?.seek.removeListener(_onSeek);
      widget.autoscroll?.addListener(_onAutoscroll);
      widget.autoscroll?.seek.addListener(_onSeek);
    }
    _onAutoscroll();
  }

  @override
  void initState() {
    super.initState();
    widget.selectedSlide?.addListener(_onSelection);
    widget.autoscroll?.addListener(_onAutoscroll);
    widget.autoscroll?.seek.addListener(_onSeek);
    _scroll.addListener(_onScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Back where it was (rotating, reopening the app).
      final at = widget.initialScroll;
      if (at != null && at > 0 && _scroll.hasClients) {
        final end = _scroll.position.maxScrollExtent;
        _scroll.jumpTo((at * end).clamp(0.0, end));
      }
      _onAutoscroll();
    });
  }

  bool get _isAutoscrollSong {
    final a = widget.autoscroll;
    return a != null && a.songId == widget.song.id;
  }

  /// Reports how far down the sheet is (for Band Sync).
  void _onScrolled() {
    if (widget.onScrolled != null && _scroll.hasClients) {
      final end = _scroll.position.maxScrollExtent;
      widget.onScrolled!(end <= 0 ? 0 : (_scroll.offset / end).clamp(0, 1));
    }
    if (!_isAutoscrollSong || !_scroll.hasClients) return;
    final end = _autoEnd;
    widget.autoscroll!.scrolled.value = end <= 0
        ? 0
        : (_scroll.offset / end).clamp(0.0, 1.0);
  }

  /// Scrolls to where Band Sync's leader is (0–1 of the song).
  void _onSeek() {
    final a = widget.autoscroll;
    final at = a?.seek.value;
    if (at == null || !_isAutoscrollSong || !_scroll.hasClients) return;
    _scroll.jumpTo(at * _autoEnd);
    a!.progress.value = at;
    a.seek.value = null;
  }

  bool get _autoscrolling {
    final a = widget.autoscroll;
    return a != null && a.running && a.songId == widget.song.id;
  }

  /// Where autoscroll stops: the end of the song at the bottom of the view.
  double get _autoEnd {
    final pos = _scroll.position;
    return math.max(0, pos.maxScrollExtent - _tail);
  }

  void _onAutoscroll() {
    if (_autoscrolling) {
      if (_autoTicker.isActive) return;
      // Started again at the bottom: from the top.
      if (_scroll.hasClients && _scroll.offset >= _autoEnd - 1) {
        _scroll.jumpTo(0);
      }
      _autoLast = Duration.zero;
      _autoTicker.start();
    } else if (_autoTicker.isActive) {
      _autoTicker.stop();
    }
  }

  /// One frame of autoscroll: a steady speed that takes the whole song
  /// the chosen time. Holds off while you drag, fling or a part is being
  /// centred, then carries on from wherever that left it.
  void _autoTick(Duration now) {
    final a = widget.autoscroll;
    if (a == null || !_scroll.hasClients) return;
    // (Real time: animations may be sped up, see setEink.)
    final dt = _autoLast == Duration.zero
        ? 0.0
        : ((now - _autoLast).inMicroseconds * timeDilation / 1e6).clamp(
            0.0,
            0.1,
          );
    _autoLast = now;
    final pos = _scroll.position;
    final end = _autoEnd;
    if (end <= 0 || pos.pixels >= end - 0.5) {
      a.finished();
      return;
    }
    // The time left follows the page, even while you scroll it yourself.
    a.progress.value = (pos.pixels / end).clamp(0.0, 1.0);
    if (pos.isScrollingNotifier.value) {
      _autoAt = null;
      return;
    }
    if (einkActive) {
      // A page at a time, when its time is up (no creeping redraws).
      var at = _autoAt ?? pos.pixels;
      if ((at - pos.pixels).abs() > pos.viewportDimension) at = pos.pixels;
      at = math.min(end, at + end / a.seconds * dt);
      _autoAt = at;
      final page = pos.viewportDimension * 0.9;
      if (at - pos.pixels >= page || at >= end) {
        _scroll.jumpTo(math.min(end, pos.pixels + page));
      }
      return;
    }
    final next = math.min(end, pos.pixels + end / a.seconds * dt);
    _scroll.jumpTo(next);
    a.progress.value = next / end;
  }

  int get _selectedPart {
    final slide = widget.selectedSlide?.value ?? -1;
    return slide >= 0 && slide < widget.slidePartIndex.length
        ? widget.slidePartIndex[slide]
        : -1;
  }

  /// Keep the selected part centred (keyboard, pedal, projector window).
  void _onSelection() {
    final part = _selectedPart;
    if (part >= 0) _centre(_keyFor(part));
  }

  @override
  void dispose() {
    widget.selectedSlide?.removeListener(_onSelection);
    widget.autoscroll?.removeListener(_onAutoscroll);
    widget.autoscroll?.seek.removeListener(_onSeek);
    _autoTicker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int i) {
    while (_sectionKeys.length <= i) {
      _sectionKeys.add(GlobalKey());
    }
    return _sectionKeys[i];
  }

  void _centre(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: widget.animate
          ? motion(context, const Duration(milliseconds: 280))
          : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  String _chord(String text, int extra) => renderDualChord(
    text,
    transpose: widget.transpose + extra,
    key: widget.displayKey?.transposed(extra),
    notation: format.notation,
    dual: format.dualNotation,
    minorStyle: format.minorStyle,
    accidentals: SongAccidentals.of(format, song.extra).accidentals,
  );

  String _detailsLine(ChordProHeader header) {
    final tempo = song.tempo.isNotEmpty ? song.tempo : (header.tempo ?? '');
    final time = song.timeSignature.isNotEmpty
        ? song.timeSignature
        : (header.time ?? '');
    final shapes = widget.displayKey;
    return [
      if (widget.soundingKey != null) 'Key ${widget.soundingKey!.name}',
      if (widget.capo > 0)
        'Capo ${widget.capo}${shapes != null ? ' (${shapes.name} shapes)' : ''}',
      if (tempo.isNotEmpty) '${tempo.trim()} BPM',
      if (time.isNotEmpty) time.trim(),
      if (song.duration.isNotEmpty) song.duration,
      for (final e in song.custom.entries)
        if (e.value.trim().isNotEmpty) '${e.key}: ${e.value.trim()}',
    ].join('  ·  ');
  }

  List<String> _footerLines(ChordProHeader header) {
    final copyright = song.copyright.isNotEmpty
        ? song.copyright
        : (header.copyright ?? '');
    return [
      if (song.composer.isNotEmpty) song.composer,
      if (song.lyricist.isNotEmpty && song.lyricist != song.composer)
        song.lyricist,
      if (copyright.isNotEmpty) copyright,
      if (song.ccli.isNotEmpty) 'CCLI Song # ${song.ccli}',
      if (song.ccliLicense.isNotEmpty) 'CCLI License # ${song.ccliLicense}',
      if (song.footer.isNotEmpty && song.footer != copyright) song.footer,
    ];
  }

  /// Building a linked piece (a verse's translation…): styled with
  /// [SheetFormat.linked]. Only set while the blocks are being built.
  bool _inLinked = false;

  TextStyle _style(SheetElement e, {Color? color, bool chord = false}) {
    // (sizes are points, as in a document: 12 is what 12 pt looks like at
    // 100 %, 16 screen pixels)
    var st = format[e]
        .textStyle(
          color: color,
          family: chord ? widget.chordFamily : widget.textFamily,
        )
        .copyWith(fontSize: format[e].size * pointPixels);
    if (_inLinked) {
      st = format.linked.apply(
        st,
        fallbackColor: Theme.of(context).colorScheme.onSurface,
        recolor: !chord,
      );
    }
    final bg = widget.contrastOn;
    if (bg == null || st.color == null) return st;
    return st.copyWith(color: readableOn(st.color!, bg));
  }

  /// Beats in a bar (from the time signature), the song's beat counts and
  /// which chord is which — set while building.
  int _barBeats = 4;
  Map<String, int> _beatMap = const {};
  ChordKeys _keys = ChordKeys();

  /// A line in Hebrew, Arabic… laid out right to left, from the right.
  Widget _directed(String line, Widget child) {
    if (!isRightToLeft(line)) return child;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = scheme.onSurfaceVariant;
    final header = ChordProHeader.parse(widget.raw);
    _barBeats = beatsPerBar(
      song.timeSignature.isNotEmpty ? song.timeSignature : header.time ?? '',
    );
    _beatMap = chordBeatsOf(song);
    _keys = ChordKeys();

    final titleText = song.title.trim().isNotEmpty
        ? song.title
        : (header.titles.isNotEmpty ? header.titles.first : '');
    final artistText = song.artist.isNotEmpty
        ? song.artist
        : (header.artist ?? '');
    final subtitleText = song.subtitle.isNotEmpty
        ? song.subtitle
        : (header.subtitle ?? '');

    final title = format[SheetElement.title];
    final artist = format[SheetElement.artist];
    final details = format[SheetElement.details];
    final headings = format[SheetElement.headings];
    final notes = format[SheetElement.notes];
    final footer = format[SheetElement.footer];
    final detailText = _detailsLine(header);

    final headerTexts = <Widget>[
      if (!title.hidden && titleText.isNotEmpty)
        Text(title.apply(titleText), style: _style(SheetElement.title)),
      if (!artist.hidden)
        for (final t in [artistText, subtitleText])
          if (t.isNotEmpty)
            Text(
              artist.apply(t),
              style: _style(SheetElement.artist, color: secondary),
            ),
      if (!details.hidden && detailText.isNotEmpty)
        Text(
          details.apply(detailText),
          style: _style(SheetElement.details, color: secondary),
        ),
    ];
    final diagrams = widget.chords;
    final stripChords = diagrams != null && diagrams.show && ChordLibrary.loaded
        ? songChords(
            [
              for (final line in ChordPro.sheetLines(widget.raw))
                if (!ChordPro.isSectionLabel(line))
                  for (final seg in ChordPro.segments(line))
                    if (seg.chord?.isNotEmpty ?? false) seg.chord!,
            ],
            transpose: widget.transpose,
            display: (t) => _chord(t, 0),
          )
        : const <(String, ChordName)>[];
    final headerWidgets = <Widget>[
      // (The reference recording plays from the bottom bar.)
      if (headerTexts.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: headerTexts,
        ),
      if (stripChords.isNotEmpty)
        ChordStrip(chords: stripChords, config: diagrams!),
    ];

    // (each line a SeamLine: in columns it fades at the column edges)
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in children)
          SeamLine(
            child: Padding(padding: const EdgeInsets.only(bottom: 6), child: c),
          ),
      ],
    );

    // One block per part. Tapping a part selects it (and projects it).
    final blocks = <Widget?>[];
    // (labels in a margin: each part's label, taken out of its lines)
    final side = format.marginLabels;
    final blockLabels = <String?>[];
    var extra = 0; // semitones added by key changes in the structure
    for (final part in widget.parts) {
      if (part.isMarker) {
        extra = part.keyChange!;
        final key = widget.soundingKey?.transposed(extra);
        blocks.add(
          Row(
            children: [
              Icon(Icons.swap_vert, size: 18, color: scheme.secondary),
              const SizedBox(width: 6),
              Text(
                'Key change → ${key?.name ?? (extra > 0 ? '+$extra' : '$extra')}',
                style: _style(SheetElement.headings, color: scheme.secondary),
              ),
            ],
          ),
        );
        blockLabels.add(null);
        continue;
      }
      final children = <Widget>[];
      String? marginLabel;
      final pieces = part.pieceLines;
      for (var p = 0; p < pieces.length; p++) {
        // Linked pieces (after the first) can be hidden or styled.
        if (p > 0 && !format.linked.show) continue;
        _inLinked = p > 0;
        if (p > 0 && children.isNotEmpty) {
          children.add(const SizedBox(height: 6));
        }
        for (final line in ChordPro.sheetLines(pieces[p].join('\n'))) {
          _keys.line(line);
          if (line == pageBreakMarker || line.startsWith(transposeMarker)) {
            continue;
          } else if (line.startsWith(abcMarker)) {
            // An ABC tune: drawn as music, playable.
            children.add(
              AbcView(
                lines: line.substring(abcMarker.length).split(tabLineBreak),
                style: _style(SheetElement.lyrics),
                ink: scheme.onSurface,
                accent: scheme.primary,
                bpm:
                    int.tryParse(
                      song.tempo.isNotEmpty ? song.tempo : header.tempo ?? '',
                    ) ??
                    100,
              ),
            );
          } else if (line.startsWith(tabMarker)) {
            if (format[SheetElement.chords].hidden) continue;
            children.add(
              TabView(
                lines: line.substring(tabMarker.length).split(tabLineBreak),
                modern: format.tabsModern,
                style: _style(SheetElement.lyrics),
                ink: scheme.onSurface,
                accent: scheme.primary,
                bpm:
                    int.tryParse(
                      song.tempo.isNotEmpty ? song.tempo : header.tempo ?? '',
                    ) ??
                    90,
              ),
            );
          } else if (line.startsWith(rhythmMarker)) {
            if (format[SheetElement.chords].hidden) continue;
            children.add(
              RhythmDiagram(
                strokes: parseRhythm(line.substring(rhythmMarker.length)),
                beats: _barBeats,
                style: _style(
                  SheetElement.chords,
                  color: scheme.primary,
                  chord: true,
                ),
                muted: secondary,
              ),
            );
          } else if (line.isEmpty) {
            if (children.isNotEmpty) children.add(const SizedBox(height: 4));
          } else if (ChordPro.isSectionLabel(line)) {
            // labels in a margin: the part's first label becomes its badge;
            // the rest (a translation's) aren't repeated in the text
            if (side.isNotEmpty) {
              marginLabel ??= ChordPro.sectionName(line);
              continue;
            }
            if (headings.hidden) continue;
            children.add(
              _directed(
                line,
                Text(
                  headings.apply(line),
                  style: _style(SheetElement.headings, color: secondary),
                ),
              ),
            );
          } else {
            final w = _chordedLine(context, line, extra);
            if (w != null) children.add(_directed(line, w));
          }
        }
      }
      _inLinked = false;
      blocks.add(children.isEmpty ? null : column(children));
      blockLabels.add(marginLabel);
    }
    if (widget.onlyPart case final only?) {
      return (only >= 0 && only < blocks.length ? blocks[only] : null) ??
          const SizedBox.shrink();
    }

    final footerLines = _footerLines(header);
    // (the columns after the first show the body again, without the
    // sections' keys, which can be in one place only)
    List<Widget> bodyFor({required bool keyed}) => <Widget>[
      if (!notes.hidden && song.notes.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            // (E-ink: outlined instead of tinted.)
            color: einkActive
                ? null
                : scheme.secondaryContainer.withValues(alpha: 0.4),
            border: einkActive
                ? Border.all(color: scheme.outline, width: einkStroke)
                : null,
            borderRadius: BorderRadius.circular(inkR(8)),
          ),
          child: Text(
            notes.apply(song.notes),
            style: _style(SheetElement.notes),
          ),
        ),
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i] != null)
          _PartBlock(
            key: keyed ? _keyFor(i) : null,
            index: i,
            selection: widget.selectedSlide,
            slidePartIndex: widget.slidePartIndex,
            style: widget.selectionStyle,
            animate: widget.animate,
            selectable: !widget.parts[i].isMarker,
            marginLabel: blockLabels[i],
            marginSide: side,
            onTap: () {
              _centre(_keyFor(i));
              if (!widget.parts[i].isMarker) widget.onSelectPart?.call(i);
            },
            child: blocks[i]!,
          ),
      if (!footer.hidden && footerLines.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            footer.apply(footerLines.join('\n')),
            style: _style(SheetElement.footer, color: secondary),
          ),
        ),
    ];
    final body = bodyFor(keyed: true);

    // Extra space at the end so the last section can reach the centre.
    // Room to scroll the end up the screen (not on e-ink: a song that
    // fits stays one page, no arrows).
    // (its own widget: it reads the window's height, and a window being
    // resized then rebuilds just it, not the whole song)
    final tail = _Tail(
      none: isEink(context),
      onHeight: (h) => _tail = widget.layout?.pageMode == true ? 0 : h,
    );

    final Widget content;
    final layout = widget.layout;
    final placed = SheetInsets.maybeOf(context);
    final inset = placed?.inset ?? EdgeInsets.zero;
    final pad = const EdgeInsets.all(16) + inset;
    if (layout != null && layout.pageMode) {
      // Printed-page view: title across the top of page 1, then the parts
      // flowing down the columns.
      // (true size, as the scroll view's text; pinch, a trackpad pinch or
      // Ctrl + the wheel to zoom)
      content = ColoredBox(
        color: scheme.surfaceContainer,
        child: ZoomablePages(
          controller: _scroll,
          padding: pad,
          paperWidth: layout.paper.width,
          builder: (scale, content, laidOut) => _withOverlay(
            PagedSheet(
              scale: scale,
              onLayout: laidOut,
              // (the content at the scroll view's size: on paper as much
              // larger, margins too)
              paper: layout.paper / content,
              margin: 40 / content,
              columnGap: 20 / content,
              columns: layout.columns,
              spanning: 1,
              pageColor: scheme.surfaceContainerLowest,
              edgeColor: scheme.outlineVariant,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: column(headerWidgets),
                ),
                ...body,
              ],
            ),
          ),
        ),
      );
    } else if (format.pinHeader && headerWidgets.isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 4),
            child: column(headerWidgets),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: pad.copyWith(top: 16),
              child: _withOverlay(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...body, tail],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      final single = SingleChildScrollView(
        controller: _scroll,
        padding: pad,
        child: _withOverlay(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [column(headerWidgets), ...body, tail],
          ),
        ),
      );
      final wanted = layout?.columns ?? 1;
      // Columns: the song running from one to the next, all scrolling
      // together (one when the window is too narrow for them)
      content = wanted < 2
          ? single
          : LayoutBuilder(
              builder: (context, box) {
                // (a window being resized holds the song's layout until it
                // settles: the count doesn't flip back and forth meanwhile)
                final n = snakeColumnsFor(wanted, box.maxWidth);
                if (n < 2) return single;
                return SnakeColumns(
                  controller: _scroll,
                  columns: n,
                  padding: pad,
                  first: _withOverlay(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [column(headerWidgets), ...body, tail],
                    ),
                  ),
                  others: () => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      column(headerWidgets),
                      ...bodyFor(keyed: false),
                      tail,
                    ],
                  ),
                );
              },
            );
    }

    // Full-bleed (under floating toolbars): the page colour edge to edge.
    if (placed != null && !placed.framed) {
      return ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: SelectionArea(child: content),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(
          StyleExtras.of(context).panelRadius,
        ),
        // (E-ink: none; the sheet runs to the bars, whose lines frame it.)
        border: einkActive
            ? null
            : Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                width: inkW(1),
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SelectionArea(child: content),
    );
  }

  /// The sheet's content with [ChordSheet.overlay] over it (scrolling
  /// together).
  Widget _withOverlay(Widget content) {
    final overlay = widget.overlay;
    if (overlay == null) return content;
    return Stack(
      children: [
        content,
        Positioned.fill(child: overlay),
      ],
    );
  }

  /// One lyric line. Returns null when everything on it is hidden.
  Widget? _chordedLine(BuildContext context, String line, int extra) {
    final lyrics = format[SheetElement.lyrics];
    final chords = format[SheetElement.chords];
    final chordStyle = _style(
      SheetElement.chords,
      color: Theme.of(context).colorScheme.primary,
      chord: true,
    );
    final lyricStyle = _style(SheetElement.lyrics);

    // Inline formatting (*bold*, <red>…<): styled runs per segment, and the
    // words without the marks for everything else.
    final parsed = ChordPro.segments(line);
    final runs = parsed.any((s) => hasInlineMarks(s.text))
        ? formatPieces([for (final s in parsed) s.text])
        : null;
    final segments = runs == null
        ? parsed
        : [
            for (final (i, s) in parsed.indexed)
              ChordSegment(
                s.chord,
                runs[i].map((r) => r.text).join(),
                passing: s.passing,
                changed: s.changed,
              ),
          ];
    List<StyledRun>? styledAt(int i) =>
        runs == null || runs[i].every((r) => r.style.isPlain)
        ? null
        : [
            for (final r in runs[i])
              (text: format[SheetElement.lyrics].apply(r.text), style: r.style),
          ];
    final hasChords = segments.any(
      (s) => s.chord != null && s.chord!.isNotEmpty,
    );
    // Each chord's beats (a bar unless the song says otherwise). (The
    // Gospelizer's chords have none: the song's own keep their keys.)
    final keyAt = <int, String>{
      for (var i = 0; i < segments.length; i++)
        if ((segments[i].chord?.isNotEmpty ?? false) && !segments[i].passing)
          i: _keys.next(),
    };
    bool chordAt(int i) => segments[i].chord?.isNotEmpty ?? false;
    final glow = widget.passingGlow && !isEink(context);
    String bracketed(int i) => '(${_chord(segments[i].chord!, extra)})';
    final beatsAt = <int, int>{
      for (final e in keyAt.entries) e.key: _beatMap[e.value] ?? _barBeats,
    };
    final lyricText = segments.map((s) => s.text).join();

    if (!hasChords || chords.hidden) {
      if (lyrics.hidden || lyricText.trim().isEmpty) return null;
      return Text(lyrics.apply(lyricText), style: lyricStyle);
    }

    final beats = widget.beats;
    if (beats != null && beats.show && beats.style.boxed) {
      return _beatBars(
        segments,
        keyAt,
        beatsAt,
        extra,
        beats,
        chordStyle,
        lyricStyle,
      );
    }
    // Dots after each chord, one per beat.
    final showDots = beats != null && beats.show;
    String chordText(int i) {
      final c = _chord(segments[i].chord!, extra);
      if (segments[i].passing) return glow ? c : '($c)';
      if (!showDots) return c;
      return c +
          beatDots(
            beatsAt[i] ?? _barBeats,
            _barBeats,
            hideFull: beats.style == ChordBeatStyle.dotsHideFull,
          );
    }

    final onTap = widget.onChordTap;
    if (onTap != null) {
      // Editing beats: each chord over its words, every chord tappable.
      final scheme = Theme.of(context).colorScheme;
      return Wrap(
        children: [
          for (final (i, seg) in segments.indexed)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (keyAt[i] case final key?)
                  _Tappable(
                    onTap: () => onTap(key),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: key == widget.selectedChord
                            ? _editHighlight.withValues(alpha: 0.22)
                            : scheme.primary.withValues(alpha: 0.06),
                        border: Border.all(
                          color: key == widget.selectedChord
                              ? _editHighlight
                              : Colors.transparent,
                          width: inkW(1.5),
                        ),
                        borderRadius: BorderRadius.circular(inkR(5)),
                      ),
                      child: Text(chordText(i), style: chordStyle),
                    ),
                  )
                else
                  Text(' ', style: chordStyle),
                Text(
                  lyrics.hidden ? '' : lyrics.apply(seg.text),
                  style: lyricStyle,
                ),
              ],
            ),
        ],
      );
    }

    if (lyrics.hidden) {
      final chordLine = [
        for (var i = 0; i < segments.length; i++)
          if (chordAt(i)) segments[i].passing ? bracketed(i) : chordText(i),
      ].join('   ');
      return Text(chordLine, style: chordStyle);
    }

    if (format.chordsInline) {
      return Text.rich(
        TextSpan(
          children: [
            for (final (i, seg) in segments.indexed) ...[
              if (chordAt(i))
                TextSpan(
                  text: '${segments[i].passing ? bracketed(i) : chordText(i)} ',
                  style: chordStyle,
                ),
              if (styledAt(i) case final styled?)
                for (final r in styled)
                  TextSpan(
                    text: r.text,
                    style: r.style.isPlain
                        ? lyricStyle
                        : r.style.on(lyricStyle),
                  )
              else
                TextSpan(text: lyrics.apply(seg.text), style: lyricStyle),
            ],
          ],
        ),
      );
    }

    // Tapping a chord shows its diagrams (when that's on).
    final diagrams = widget.chords;
    void Function(int, Rect)? tapChord;
    if (diagrams != null && diagrams.tappable) {
      tapChord = (i, at) {
        final c = ChordName.parse(
          segments[i].chord!,
          transpose: widget.transpose + extra,
        );
        if (c != null) diagrams.onShowChord(chordText(i), c, anchor: at);
      };
    }

    // One render object for the whole line (fast to resize).
    return ChordLine(
      onChordTap: tapChord,
      glowing: glow
          ? {
              for (var i = 0; i < segments.length; i++)
                if ((segments[i].passing || segments[i].changed) && chordAt(i))
                  i,
            }
          : const {},
      pieces: [
        for (final (i, seg) in segments.indexed)
          (
            // Trailing space keeps neighbouring chords from touching.
            chord: chordAt(i)
                ? '${chordText(i)} '
                : seg.chord == null
                ? ''
                : ' ',
            lyric: lyrics.apply(seg.text),
            runs: styledAt(i),
          ),
      ],
      chordStyle: chordStyle,
      lyricStyle: lyricStyle,
    );
  }

  /// A line as bars (Stacks, Pills, Timeline): each chord lasts a bar,
  /// with the words sung over it. Stacks and Pills wrap after
  /// [BeatSettings.barsPerLine] bars; Timeline keeps the line on one row.
  Widget _beatBars(
    List<ChordSegment> segments,
    Map<int, String> keyAt,
    Map<int, int> beatsAt,
    int extra,
    BeatSettings beats,
    TextStyle chordStyle,
    TextStyle lyricStyle,
  ) {
    final lyrics = format[SheetElement.lyrics];
    final bars = <_Bar>[];
    var before = ''; // words before the first chord go in its bar
    for (final (i, seg) in segments.indexed) {
      final chord = seg.chord;
      if (seg.passing && bars.isNotEmpty && (chord?.isNotEmpty ?? false)) {
        // A Gospelizer chord: in the bar it passes through, "C (D7)".
        final last = bars.removeLast();
        final words = lyrics.hidden ? '' : lyrics.apply(seg.text);
        bars.add((
          key: last.key,
          chord: '${last.chord} (${_chord(chord!, extra)})',
          lyric: '${last.lyric} $words'.trim(),
          beats: last.beats,
        ));
        continue;
      }
      if (chord == null || chord.isEmpty || seg.passing) {
        if (bars.isEmpty) {
          before += seg.text;
        } else {
          final last = bars.removeLast();
          bars.add((
            key: last.key,
            chord: last.chord,
            lyric: '${last.lyric} ${seg.text}'.trim(),
            beats: last.beats,
          ));
        }
        continue;
      }
      bars.add((
        key: keyAt[i]!,
        chord: _chord(chord, extra),
        lyric: lyrics.hidden ? '' : lyrics.apply(before + seg.text).trim(),
        beats: beatsAt[i] ?? _barBeats,
      ));
      before = '';
    }
    final scheme = Theme.of(context).colorScheme;
    final tint = chordStyle.color ?? scheme.primary;
    final tickColor = scheme.onSurfaceVariant.withValues(alpha: 0.55);
    final plainBox = BoxDecoration(
      color: tint.withValues(alpha: 0.08),
      border: Border.all(color: tint.withValues(alpha: 0.22), width: inkW(1)),
      borderRadius: BorderRadius.circular(inkR(8)),
    );
    final pills = beats.style == ChordBeatStyle.pills;

    // Where each chord starts in the line, in beats (for the bar ticks).
    final starts = <int>[];
    var at = 0;
    for (final b in bars) {
      starts.add(at);
      at += math.max(0, b.beats);
    }
    // Width units: four per beat; a 0-beat chord still gets a sliver.
    int units(_Bar b) => b.beats <= 0 ? 1 : b.beats * 4;

    Widget bar(int i) {
      final b = bars[i];
      final chord = Text(b.chord, style: chordStyle, maxLines: 1);
      final words = Text(b.lyric, style: lyricStyle);
      final onTap = widget.onChordTap;
      final selected = onTap != null && b.key == widget.selectedChord;
      final box = selected
          ? BoxDecoration(
              color: _editHighlight.withValues(alpha: 0.16),
              border: Border.all(color: _editHighlight, width: inkW(1.5)),
              borderRadius: BorderRadius.circular(inkR(8)),
            )
          : plainBox;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 10,
            child: CustomPaint(
              painter: _BeatTicks(
                b.beats,
                starts[i] % _barBeats,
                _barBeats,
                tickColor,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: pills
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: box,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: chord,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 4, 0),
                          child: words,
                        ),
                      ],
                    )
                  : Container(
                      decoration: box,
                      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [chord, words],
                      ),
                    ),
            ),
          ),
        ],
      );
      return onTap == null
          ? content
          : _Tappable(onTap: () => onTap(b.key), child: content);
    }

    // Each row is [slots] units wide; chords take their share of it.
    Widget row(List<int> chords, int slots) {
      final used = chords.fold(0, (n, i) => n + units(bars[i]));
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in chords)
              Expanded(flex: units(bars[i]), child: bar(i)),
            if (slots > used) Spacer(flex: slots - used),
          ],
        ),
      );
    }

    final slots = beats.barsPerLine * _barBeats * 4;
    final all = [for (var i = 0; i < bars.length; i++) i];
    if (beats.style == ChordBeatStyle.timeline) {
      final total = all.fold(0, (n, i) => n + units(bars[i]));
      return row(all, math.max(total, slots));
    }
    // Stacks and Pills wrap after "Bars per line".
    final rows = <List<int>>[[]];
    var used = 0;
    for (final i in all) {
      final u = units(bars[i]);
      if (rows.last.isNotEmpty && used + u > slots) {
        rows.add([]);
        used = 0;
      }
      rows.last.add(i);
      used += u;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [for (final r in rows) row(r, math.max(slots, used))],
    );
  }
}

/// One bar of a line in chord-beat view: its chord, the words sung over
/// it and how many beats it lasts.
typedef _Bar = ({String key, String chord, String lyric, int beats});

/// The selected chord while editing chord beats.
const _editHighlight = Color(0xFFF59E0B);

/// Something to tap while editing chord beats (a pointer cursor on it).
class _Tappable extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _Tappable({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    ),
  );
}

/// Beat marks over a bar: a taller tick where the bar starts, a short one
/// on each other beat.
class _BeatTicks extends CustomPainter {
  final int beats;

  /// The chord's first beat within its bar (0 = it starts the bar).
  final int start;
  final int barBeats;
  final Color color;
  const _BeatTicks(this.beats, this.start, this.barBeats, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (beats <= 0) return;
    final step = size.width / beats;
    for (var i = 0; i < beats; i++) {
      final x = 1 + i * step;
      final barStart = (start + i) % barBeats == 0;
      canvas.drawLine(
        Offset(x, barStart ? 1 : size.height * 0.5),
        Offset(x, size.height - 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BeatTicks old) =>
      old.beats != beats ||
      old.start != start ||
      old.barBeats != barBeats ||
      old.color != color;
}

/// A song part on the sheet. Only this widget's decoration listens to the
/// selection; its contents are built once and cached in a RepaintBoundary.
class _PartBlock extends StatelessWidget {
  final int index;
  final ValueListenable<int>? selection;
  final List<int> slidePartIndex;
  final SelectionStyle style;
  final bool animate;
  final bool selectable;
  final VoidCallback onTap;
  final Widget child;

  /// The part's name for a badge in a margin, and which margin ('left',
  /// 'right'; '' none).
  final String? marginLabel;
  final String marginSide;

  const _PartBlock({
    this.marginLabel,
    this.marginSide = '',
    this.animate = true,
    super.key,
    required this.index,
    required this.selection,
    required this.slidePartIndex,
    required this.style,
    required this.selectable,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = RepaintBoundary(child: child);
    final bar = style != SelectionStyle.highlight;
    final tint = style != SelectionStyle.bar;
    final margin = marginSide.isNotEmpty && marginLabel != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ValueListenableBuilder<int>(
        valueListenable: selection ?? ValueNotifier(-1),
        child: content,
        builder: (context, slide, content) {
          final selected =
              selectable &&
              slide >= 0 &&
              slide < slidePartIndex.length &&
              slidePartIndex[slide] == index;
          final d = animate ? const Duration(milliseconds: 160) : Duration.zero;
          // Two plain layers (a tint with evenly rounded corners and a
          // separate bar) — a left-only border with rounded corners leaves
          // faint hairline arcs at the corners.
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Stack(
              children: [
                if (tint)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: d,
                      opacity: selected ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(
                            alpha: bar ? 0.07 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(inkR(6)),
                        ),
                      ),
                    ),
                  ),
                if (bar && !margin)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 4,
                    child: AnimatedOpacity(
                      duration: d,
                      opacity: selected ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(inkR(2)),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16 + (margin && marginSide == 'left' ? _MarginBadge.width : 0),
                    6,
                    8 + (margin && marginSide == 'right' ? _MarginBadge.width : 0),
                    2,
                  ),
                  child: content,
                ),
                // (selected: its rail is the selection bar, its badge filled)
                if (margin)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: marginSide == 'left' ? 8 : null,
                    right: marginSide == 'right' ? 4 : null,
                    width: _MarginBadge.width - 4,
                    child: _MarginBadge(
                      name: marginLabel!,
                      selected: selected,
                      bar: bar,
                      duration: d,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A section's name in a margin: a short badge ("V1", "C") riding a thin
/// rail as tall as the section. Choruses in the accent colour.
class _MarginBadge extends StatelessWidget {
  static const width = 44.0;
  final String name;

  /// The section shown: the rail becomes the selection bar (when the
  /// selection style has one) and the badge is filled.
  final bool selected;
  final bool bar;
  final Duration duration;
  const _MarginBadge({
    required this.name,
    this.selected = false,
    this.bar = true,
    this.duration = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final short = ChordPro.sectionAbbreviation(name);
    final chorus = short.startsWith('C') && !short.startsWith('Co');
    final ink = einkActive;
    final line = ink ? scheme.onSurface : (chorus ? scheme.primary : scheme.outline);
    final on = selected;
    final railOn = on && bar;
    final fill = on
        ? (ink ? scheme.onSurface : scheme.primary)
        : (ink ? scheme.surface : (chorus ? scheme.primaryContainer : scheme.surfaceContainerHighest));
    final text = on
        ? (ink ? scheme.surface : scheme.onPrimary)
        : (ink ? scheme.onSurface : (chorus ? scheme.onPrimaryContainer : scheme.onSurfaceVariant));
    return Tooltip(
      message: name,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // the rail, the section's height
          Positioned(
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: railOn ? 4 : (ink ? einkStroke : 1),
              decoration: BoxDecoration(
                color: railOn
                    ? (ink ? scheme.onSurface : scheme.primary)
                    : line.withValues(alpha: ink ? 1 : .6),
                borderRadius: BorderRadius.circular(railOn ? inkR(2) : 0),
              ),
            ),
          ),
          // the badge, centred on it
          AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: on ? fill : line, width: ink ? einkStroke : 1),
              borderRadius: BorderRadius.circular(inkR(5)),
            ),
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: text),
              child: Text(short, maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// A strum pattern (`{rhythm: D>-DU-UDU}`): one slot per stroke on the
/// beat grid, ↓ down, ↑ up, × muted, · nothing; an accent mark above
/// accented strokes, "pm" under palm-muted ones, the count ("1 + 2 +")
/// under each slot, and a bar line between bars.
class RhythmDiagram extends StatelessWidget {
  final List<Stroke> strokes;
  final int beats;
  final TextStyle style;
  final Color muted;
  const RhythmDiagram({
    super.key,
    required this.strokes,
    required this.beats,
    required this.style,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final counts = rhythmCounts(strokes.length, beats);
    final bar = rhythmBarLength(strokes.length, beats);
    final size = style.fontSize ?? 16;
    final small = TextStyle(fontSize: size * 0.62, color: muted, height: 1.1);
    Widget slot(int i) {
      final s = strokes[i];
      final onBeat = counts[i].isNotEmpty && int.tryParse(counts[i]) != null;
      return SizedBox(
        width: size * 1.35,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.accent ? '>' : ' ',
              style: small.copyWith(
                color: style.color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              s.symbol,
              style: style.copyWith(
                fontSize: size * (s.accent ? 1.25 : 1.05),
                fontWeight: s.accent ? FontWeight.w900 : FontWeight.w600,
                color: s.rest || s.soft
                    ? style.color?.withValues(alpha: 0.45)
                    : style.color,
                height: 1.1,
              ),
            ),
            Text(
              [if (s.palmMute) 'pm', if (s.bass) 'b'].join(' ').isEmpty
                  ? counts[i]
                  : [if (s.palmMute) 'pm', if (s.bass) 'b'].join(' '),
              style: small.copyWith(
                fontWeight: onBeat ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label:
          'Strum pattern: ${strokes.map((s) => switch (s.action) {
            'D' => 'down',
            'U' => 'up',
            'X' => 'mute',
            '-' => 'rest',
            _ => s.action,
          }).join(', ')}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < strokes.length; i++) ...[
                if (bar > 0 && i > 0 && i % bar == 0)
                  Container(
                    width: 1.5,
                    height: size * 2.6,
                    margin: EdgeInsets.symmetric(horizontal: size * 0.3),
                    color: muted.withValues(alpha: 0.6),
                  ),
                slot(i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Room at the end of the sheet so the last section can reach the middle
/// of the screen (0.4 of the window's height; none on e-ink, where a song
/// that fits stays one page).
class _Tail extends StatelessWidget {
  final bool none;
  final ValueChanged<double> onHeight;
  const _Tail({required this.none, required this.onHeight});

  @override
  Widget build(BuildContext context) {
    final h = none ? 0.0 : MediaQuery.sizeOf(context).height * 0.4;
    onHeight(h);
    return SizedBox(height: h);
  }
}
