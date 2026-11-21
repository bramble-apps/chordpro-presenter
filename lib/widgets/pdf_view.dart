import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../pdfs.dart';
import '../state.dart';
import 'scanner_screen.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// A song with PDFs or pictures: tabs at the top for its ChordPro (when it
/// has any) and each file, and the sheet-music view options (cropped, theme
/// colours) beside them while a file is showing.
class SongDocTabs extends StatefulWidget {
  final Song song;

  /// The chord sheet (null: a song that is only sheet music).
  final Widget? chordPro;
  final List<PdfRef> pdfs;

  /// Where the view options live (settings).
  final PresenterModel? model;

  const SongDocTabs({
    super.key,
    required this.song,
    required this.chordPro,
    required this.pdfs,
    this.model,
  });

  @override
  State<SongDocTabs> createState() => _SongDocTabsState();
}

class _SongDocTabsState extends State<SongDocTabs> {
  /// The tab open per song (kept while the app runs).
  static final Map<String, int> _open = {};

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    if (model == null) return _build(context, false, false);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => _build(
        context,
        model.settings.sheetCrop,
        model.settings.sheetThemeColors,
      ),
    );
  }

  Widget _build(BuildContext context, bool crop, bool themed) {
    final scheme = Theme.of(context).colorScheme;
    final tabs = [
      if (widget.chordPro != null) 'ChordPro',
      for (final p in widget.pdfs)
        widget.pdfs.length > 1 ? p.title : (p.isImage ? 'Sheet music' : 'PDF'),
    ];
    final i = (_open[widget.song.id] ?? 0).clamp(0, tabs.length - 1);
    final pdfIndex = widget.chordPro != null ? i - 1 : i;
    final showingFile = !(widget.chordPro != null && i == 0);
    final body = showingFile
        ? PdfPages(
            key: ValueKey(widget.pdfs[pdfIndex].id),
            pdf: widget.pdfs[pdfIndex],
            crop: crop,
            themed: themed,
          )
        : widget.chordPro!;
    final model = widget.model;
    final options = showingFile && model != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: crop ? 'Show whole pages' : 'Crop the margins',
                isSelected: crop,
                icon: const Icon(BrambleIcons.crop),
                onPressed: () =>
                    model.updateSettings((s) => s.sheetCrop = !crop),
              ),
              IconButton(
                tooltip: 'Read the notes (play, export, chords)',
                icon: const Icon(BrambleIcons.scan),
                onPressed: () async {
                  final pdf = widget.pdfs[pdfIndex];
                  final bytes = await PdfStore.bytes(pdf.id);
                  if (bytes == null || !context.mounted) return;
                  await openScanner(
                    context,
                    model,
                    files: [(pdf.name, bytes)],
                    song: widget.song,
                    source: pdf.id,
                  );
                },
              ),
              IconButton(
                tooltip: themed
                    ? 'Show the original colours'
                    : 'Match the theme’s colours',
                isSelected: themed,
                icon: const Icon(BrambleIcons.circleHalf),
                onPressed: () =>
                    model.updateSettings((s) => s.sheetThemeColors = !themed),
              ),
            ],
          )
        : null;
    if (tabs.length < 2 && options == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: tabs.length < 2
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            for (final (k, t) in tabs.indexed)
                              ButtonSegment(
                                value: k,
                                label: Text(t, overflow: TextOverflow.ellipsis),
                                icon: Icon(
                                  k == 0 && widget.chordPro != null
                                      ? BrambleIcons.musicNote
                                      : widget
                                            .pdfs[widget.chordPro != null
                                                ? k - 1
                                                : k]
                                            .isImage
                                      ? BrambleIcons.image
                                      : BrambleIcons.filePdf,
                                  size: 18,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                          selected: {i},
                          onSelectionChanged: (v) =>
                              setState(() => _open[widget.song.id] = v.first),
                        ),
                      ),
              ),
              ?options,
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// One drawn page: the picture, its size, and where the printing is (as
/// fractions of the page; the whole page when it's blank).
class SheetPage {
  final Uint8List png;
  final int width, height;
  final Rect ink;
  const SheetPage(this.png, this.width, this.height, this.ink);
}

/// Where the printing is on an RGBA page: the box around every pixel that
/// isn't (nearly) white, with a little air around it, as fractions of the
/// page. The whole page when nothing is printed.
Rect inkBounds(Uint8List rgba, int width, int height) {
  var left = width, top = height, right = -1, bottom = -1;
  const step = 2;
  for (var y = 0; y < height; y += step) {
    final row = y * width * 4;
    for (var x = 0; x < width; x += step) {
      final i = row + x * 4;
      if (rgba[i + 3] < 32) continue; // see-through
      if (rgba[i] > 232 && rgba[i + 1] > 232 && rgba[i + 2] > 232) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < 0) return const Rect.fromLTWH(0, 0, 1, 1);
  final pad = 0.02 * math.max(width, height);
  return Rect.fromLTRB(
    math.max(0, left - pad) / width,
    math.max(0, top - pad) / height,
    math.min(width, right + step + pad) / width,
    math.min(height, bottom + step + pad) / height,
  );
}

/// Paper to [paper], ink to [ink]: each pixel by how light it is (so grey
/// stays in between and the page reads in any theme).
ColorFilter themeColorFilter(Color paper, Color ink) {
  List<double> row(double p, double k) {
    final d = (p - k) / 255;
    return [d * 0.2126, d * 0.7152, d * 0.0722, 0, k];
  }

  final p = [paper.r * 255, paper.g * 255, paper.b * 255];
  final k = [ink.r * 255, ink.g * 255, ink.b * 255];
  return ColorFilter.matrix([
    ...row(p[0], k[0]),
    ...row(p[1], k[1]),
    ...row(p[2], k[2]),
    0,
    0,
    0,
    1,
    0,
  ]);
}

/// A PDF's pages (or one picture), one under the other, as wide as there
/// is room: [crop] trims each page to its printing, [themed] recolours it
/// to the theme.
class PdfPages extends StatefulWidget {
  final PdfRef pdf;
  final bool crop;
  final bool themed;
  const PdfPages({
    super.key,
    required this.pdf,
    this.crop = false,
    this.themed = false,
  });

  @override
  State<PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<PdfPages> {
  final List<SheetPage> _pages = [];
  String? _problem;
  bool _done = false;

  /// Pages drawn per file (kept while the app runs).
  static final Map<String, List<SheetPage>> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.pdf.id];
    if (cached != null) {
      setState(() {
        _pages.addAll(cached);
        _done = true;
      });
      return;
    }
    try {
      final bytes = await PdfStore.bytes(widget.pdf.id);
      if (bytes == null) {
        setState(() => _problem = 'This file isn’t on this device.');
        return;
      }
      if (!PdfStore.looksLikePdf(bytes)) {
        // A picture: decoded once to find its printing.
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final page = SheetPage(
          bytes,
          image.width,
          image.height,
          data == null
              ? const Rect.fromLTWH(0, 0, 1, 1)
              : inkBounds(data.buffer.asUint8List(), image.width, image.height),
        );
        image.dispose();
        _cache[widget.pdf.id] = [page];
        if (mounted) {
          setState(() {
            _pages.add(page);
            _done = true;
          });
        }
        return;
      }
      await for (final raster in Printing.raster(bytes, dpi: 144)) {
        final png = await raster.toPng();
        final page = SheetPage(
          png,
          raster.width,
          raster.height,
          inkBounds(raster.pixels, raster.width, raster.height),
        );
        if (!mounted) return;
        setState(() => _pages.add(page));
      }
      _cache[widget.pdf.id] = [..._pages];
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _problem = 'Couldn’t show this file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_problem case final p?) return Center(child: Text(p));
    final filter = widget.themed
        ? themeColorFilter(scheme.surface, scheme.onSurface)
        : null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final page in _pages)
          Padding(
            padding: EdgeInsets.only(bottom: widget.crop ? 6 : 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.themed ? scheme.surface : Colors.white,
                border: widget.crop
                    ? null
                    : Border.all(color: scheme.outlineVariant, width: inkW(1)),
                boxShadow: widget.crop || widget.themed || isEink(context)
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: _PageImage(page: page, crop: widget.crop, filter: filter),
            ),
          ),
        if (!_done)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppSpinner()),
          ),
      ],
    );
  }
}

/// A page as wide as there is room: all of it, or only its printing.
class _PageImage extends StatelessWidget {
  final SheetPage page;
  final bool crop;
  final ColorFilter? filter;
  const _PageImage({required this.page, required this.crop, this.filter});

  @override
  Widget build(BuildContext context) {
    final r = crop ? page.ink : const Rect.fromLTWH(0, 0, 1, 1);
    Widget image(double w, double h) {
      final img = Image.memory(
        page.png,
        width: w,
        height: h,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
      return filter == null
          ? img
          : ColorFiltered(colorFilter: filter!, child: img);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final fullW = w / r.width;
        final fullH = fullW * page.height / page.width;
        return SizedBox(
          width: w,
          height: fullH * r.height,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: fullW,
              maxWidth: fullW,
              minHeight: fullH,
              maxHeight: fullH,
              child: Transform.translate(
                offset: Offset(-r.left * fullW, -r.top * fullH),
                child: image(fullW, fullH),
              ),
            ),
          ),
        );
      },
    );
  }
}
