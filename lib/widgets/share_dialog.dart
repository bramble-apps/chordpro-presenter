import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'margin_side.dart';
import '../browser.dart';
import '../export.dart';
import '../justchords.dart';
import '../format.dart';
import '../freeshow.dart';
import '../media.dart';
import '../projection.dart';
import '../slide_export.dart';
import '../state.dart';
import 'dynamic_background.dart';
import 'qr_share.dart';
import 'slide_capture.dart';
import '../eink.dart';
import '../bramble_icons.dart';

enum ShareFormat { pdf, chordPro, text, slides, freeShow, justChords }

enum ShareScope { song, setlist }

/// How slides are saved.
enum SlideFile { pdf, pptx, html }

/// Share / export the open song or a whole setlist: chord sheet PDF,
/// ChordPro, plain text, the slides (PDF, PowerPoint or an HTML page), or
/// FreeShow `.show` files.
class ShareDialog extends StatefulWidget {
  final PresenterModel model;

  /// A setlist to offer ("Whole setlist"); [setlistFirst] starts there.
  final Setlist? setlist;
  final bool setlistFirst;

  const ShareDialog({
    super.key,
    required this.model,
    this.setlist,
    this.setlistFirst = false,
  });

  /// Opens the dialog for the open song (and its setlist, if any).
  static Future<void> show(
    BuildContext context,
    PresenterModel model, {
    Setlist? setlist,
    bool setlistFirst = false,
  }) => showAppDialog<void>(
    context: context,
    builder: (_) => ShareDialog(
      model: model,
      setlist: setlist ?? model.setlistById(model.activeSetlistId),
      setlistFirst: setlistFirst,
    ),
  );

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  PresenterModel get model => widget.model;
  Setlist? get set => widget.setlist;

  late ShareScope _scope =
      (widget.setlistFirst || model.currentSong == null) && set != null
      ? ShareScope.setlist
      : ShareScope.song;
  ShareFormat _format = ShareFormat.pdf;
  SlideFile _slideFile = SlideFile.pdf;

  /// PowerPoint: real text (editable) or pictures (exact look).
  bool _editable = true;

  /// Slides: each song's blank / title slide too (as the projector does),
  /// and PowerPoint fading from slide to slide.
  late bool _withBlank = model.projection.blankSlide;
  late bool _withTitle = model.projection.titleSlide;
  bool _fade = true;
  bool _onePdf = true;
  bool _chords = true;
  // section labels in a margin: 'left' / 'right', '' above as text
  String _margin = '';
  double _scale = 1.0;
  late PaperSize _paper;
  late int _columns;

  // Rendered slides (made when Slides is picked).
  List<SlideImage>? _slides;
  (int, int)? _progress;
  bool _busy = false;

  bool get _isSet => _scope == ShareScope.setlist;

  late final ExportSource? _song = model.currentSong == null
      ? null
      : ExportSource.from(model);
  late final List<ExportSource> _setSongs = set == null
      ? const []
      : [for (final s in model.setlistSpecs(set!)) ExportSource.spec(s, model)];

  List<ExportSource> get _sources => _isSet ? _setSongs : [?_song];

  String get _stem {
    final name = _isSet ? set!.name : _song?.song.displayTitle ?? 'song';
    final t = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '').trim();
    return t.isEmpty ? (_isSet ? 'setlist' : 'song') : t;
  }

  @override
  void initState() {
    super.initState();
    // Start from the song's page layout (Format → Page).
    final first = _song ?? (_setSongs.isEmpty ? null : _setSongs.first);
    final layout = first == null
        ? SheetLayout.of(model.format, const {})
        : SheetLayout.of(first.format, first.song.extra);
    _paper = layout.paperA4 ? PaperSize.a4 : PaperSize.letter;
    _columns = layout.columns;
    _margin = (first?.format ?? model.format).marginLabels;
  }

  // ---- Building the files ----

  String get _text {
    if (!_isSet) {
      return _format == ShareFormat.chordPro
          ? exportChordPro(_song!, includeChords: _chords)
          : exportText(_song!, includeChords: _chords);
    }
    if (_format == ShareFormat.text) {
      return exportSetlistText(set!.name, _setSongs, includeChords: _chords);
    }
    // ChordPro: each file, one after another (they download as a zip).
    final names = setlistFileNames(_setSongs, 'cho');
    return [
      for (var i = 0; i < _setSongs.length; i++)
        '# ── ${names[i]} ──\n'
            '${exportChordPro(_setSongs[i], includeChords: _chords)}',
    ].join('\n\n');
  }

  Future<Uint8List> _pdfOf(List<ExportSource> songs) async {
    final doc = pw.Document(title: _stem);
    for (final s in songs) {
      await addPdfPages(
        doc,
        s,
        includeChords: _chords,
        scale: _scale,
        paper: _paper,
        columns: _columns,
        marginLabels: _margin,
      );
    }
    return doc.save();
  }

  /// Every slide being shared: each song's blank and title slides (if
  /// chosen), then its lyrics.
  List<String> get _slideTexts => [
    for (final spec
        in _isSet ? model.setlistSpecs(set!) : [?model.currentSpec]) ...[
      if (_withBlank) blankSlide,
      if (_withTitle)
        titleSlide(spec.song.displayTitle, spec.song.displayArtist),
      for (final s in model.slidesOf(spec))
        if (!isIntroSlide(s)) s,
    ],
  ];

  /// The fade between PowerPoint slides (the projector's transition time).
  double? get _fadeSeconds =>
      _fade ? math.max(model.transitionDuration, 0.3) : null;

  /// A slide option changed: the pictures are drawn again.
  void _slidesChanged(VoidCallback change) {
    setState(() {
      change();
      _slides = null;
    });
    if (_progress == null) _renderSlides();
  }

  /// The projector's look, for an editable deck.
  Future<TextSlideLook> _textLook() async {
    final p = model.projection;
    final media = p.bgType == BackgroundType.media ? p.bgMedia : null;
    final ext = switch (media?.mime) {
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpeg',
      'image/gif' => 'gif',
      _ => null,
    };
    final size = model.projectorSize;
    // A dynamic background can't move in a deck: its still.
    final image = p.bgType == BackgroundType.dynamic
        ? await dynamicStillPng(p.bgDynamic, aspect: size.width / size.height)
        : media == null || ext == null
        ? null
        : await MediaStore.bytes(media);
    return TextSlideLook(
      background: p.bgColor,
      backgroundImage: image != null && image.isNotEmpty ? image : null,
      backgroundExt: p.bgType == BackgroundType.dynamic ? 'png' : ext ?? 'png',
      dimColor: p.bgDimColor,
      dim: p.bgDim / 100,
      color: p.textColor,
      bold: p.textBold,
      italic: p.textItalic,
      caps: p.textCaps,
      shadow: p.textShadow,
      align: p.textAlign,
      position: p.textPosition,
      maxSize: p.textSize.toDouble(),
      linked: p.linked,
      lineSpacing: p.textLineSpacing,
      font: model.settings.pptxFont,
    );
  }

  /// Slides of everything being shared, rendered as the projector shows
  /// them.
  Future<void> _renderSlides() async {
    final texts = _slideTexts;
    setState(() {
      _slides = null;
      _progress = (0, texts.length);
    });
    final images = await captureSlides(
      context,
      slides: texts,
      settings: model.projection,
      font: model.projectorFont,
      projectorSize: model.projectorSize,
      stage: model.stageData,
      onProgress: (d, t) {
        if (mounted) setState(() => _progress = (d, t));
      },
    );
    if (!mounted) return;
    // A slide option changed meanwhile: draw them again.
    if (!listEquals(texts, _slideTexts)) {
      _progress = null;
      _renderSlides();
      return;
    }
    setState(() {
      _slides = images;
      _progress = null;
    });
  }

  void _pick({ShareFormat? format, ShareScope? scope}) {
    setState(() {
      _format = format ?? _format;
      if (scope != null && scope != _scope) {
        _scope = scope;
        _slides = null;
      }
    });
    if (_format == ShareFormat.slides && _slides == null && _progress == null) {
      _renderSlides();
    }
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      await _save();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final stem = _stem;
    final songs = _sources;
    switch (_format) {
      case ShareFormat.pdf:
        if (!_isSet || _onePdf) {
          downloadBytes('$stem.pdf', await _pdfOf(songs), 'application/pdf');
        } else {
          final names = setlistFileNames(songs, 'pdf');
          downloadBytes(
            '$stem (PDFs).zip',
            zipFiles({
              for (var i = 0; i < songs.length; i++)
                names[i]: await _pdfOf([songs[i]]),
            }),
            'application/zip',
          );
        }
      case ShareFormat.chordPro:
        if (!_isSet) {
          downloadTextFile('$stem.cho', _text, mime: 'text/plain');
        } else {
          final names = setlistFileNames(songs, 'cho');
          downloadBytes(
            '$stem (ChordPro).zip',
            zipFiles({
              for (var i = 0; i < songs.length; i++)
                names[i]: utf8.encode(
                  exportChordPro(songs[i], includeChords: _chords),
                ),
            }),
            'application/zip',
          );
        }
      case ShareFormat.text:
        downloadTextFile('$stem.txt', _text, mime: 'text/plain');
      case ShareFormat.freeShow:
        if (!_isSet) {
          downloadTextFile(
            '$stem.show',
            exportFreeShow(songs.single),
            mime: 'application/json',
          );
        } else {
          final names = setlistFileNames(songs, 'show');
          downloadBytes(
            '$stem (FreeShow).zip',
            zipFiles({
              for (var i = 0; i < songs.length; i++)
                names[i]: utf8.encode(exportFreeShow(songs[i])),
            }),
            'application/zip',
          );
        }
      case ShareFormat.justChords:
        downloadBytes(
          '$stem.jcarchive',
          _isSet
              ? justChordsSetlistArchive(set!, model.songs)
              : justChordsSongArchive(_song!.song),
          'application/zip',
        );
      case ShareFormat.slides:
        final slides = _slides ?? const <SlideImage>[];
        final size = model.projectorSize;
        if (slides.isEmpty && !(_slideFile == SlideFile.pptx && _editable)) {
          return;
        }
        switch (_slideFile) {
          case SlideFile.pdf:
            downloadBytes(
              '$stem (slides).pdf',
              await slidesPdf(
                slides,
                width: size.width,
                height: size.height,
                title: stem,
              ),
              'application/pdf',
            );
          case SlideFile.pptx when _editable:
            downloadBytes(
              '$stem.pptx',
              slidesPptxText(
                _slideTexts,
                width: size.width,
                height: size.height,
                look: await _textLook(),
                title: stem,
                fade: _fadeSeconds,
              ),
              'application/vnd.openxmlformats-officedocument.'
                  'presentationml.presentation',
            );
          case SlideFile.pptx:
            downloadBytes(
              '$stem.pptx',
              slidesPptx(
                slides,
                width: size.width,
                height: size.height,
                title: stem,
                fade: _fadeSeconds,
              ),
              'application/vnd.openxmlformats-officedocument.'
                  'presentationml.presentation',
            );
          case SlideFile.html:
            downloadTextFile(
              '$stem (slides).html',
              slidesHtml(slides, title: stem),
              mime: 'text/html',
            );
        }
    }
  }

  // ---- Layout ----

  String get _downloadLabel => switch (_format) {
    ShareFormat.pdf =>
      _isSet && !_onePdf ? 'Download PDFs (.zip)' : 'Download PDF',
    ShareFormat.chordPro => _isSet ? 'Download .zip' : 'Download .cho',
    ShareFormat.text => 'Download .txt',
    ShareFormat.freeShow => _isSet ? 'Download .zip' : 'Download .show',
    ShareFormat.justChords => 'Download .jcarchive',
    ShareFormat.slides => switch (_slideFile) {
      SlideFile.pdf => 'Download PDF',
      SlideFile.pptx => 'Download .pptx',
      SlideFile.html => 'Download .html',
    },
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isSet
        ? 'Share setlist "${set!.name}"'
        : 'Share "${_song?.song.displayTitle ?? ''}"';
    final usesChords =
        _format == ShareFormat.pdf ||
        _format == ShareFormat.chordPro ||
        _format == ShareFormat.text;
    final canDownload =
        _sources.isNotEmpty &&
        !_busy &&
        (_format != ShareFormat.slides ||
            (_slides?.isNotEmpty ?? false) ||
            (_slideFile == SlideFile.pptx && _editable));
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 880),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(BrambleIcons.x),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (set != null && _song != null)
                SegmentedButton<ShareScope>(
                  segments: [
                    const ButtonSegment(
                      value: ShareScope.song,
                      label: Text('This song'),
                      icon: Icon(BrambleIcons.musicNote),
                    ),
                    ButtonSegment(
                      value: ShareScope.setlist,
                      label: Text('Whole setlist (${_setSongs.length})'),
                      icon: const Icon(BrambleIcons.playlist),
                    ),
                  ],
                  selected: {_scope},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _pick(scope: v.first),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ShareFormat>(
                  segments: const [
                    ButtonSegment(
                      value: ShareFormat.pdf,
                      label: Text('PDF'),
                      icon: Icon(BrambleIcons.filePdf),
                    ),
                    ButtonSegment(
                      value: ShareFormat.chordPro,
                      label: Text('ChordPro'),
                      icon: Icon(BrambleIcons.musicNote),
                    ),
                    ButtonSegment(
                      value: ShareFormat.text,
                      label: Text('Text'),
                      icon: Icon(BrambleIcons.textAlignLeft),
                    ),
                    ButtonSegment(
                      value: ShareFormat.slides,
                      label: Text('Slides'),
                      icon: Icon(BrambleIcons.presentation),
                    ),
                    ButtonSegment(
                      value: ShareFormat.freeShow,
                      label: Text('FreeShow'),
                      icon: Icon(BrambleIcons.broadcast),
                    ),
                    ButtonSegment(
                      value: ShareFormat.justChords,
                      label: Text('JustChords'),
                      icon: Icon(BrambleIcons.vinylRecord),
                    ),
                  ],
                  selected: {_format},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _pick(format: v.first),
                ),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (usesChords)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _chords,
                          onChanged: (v) => setState(() => _chords = v),
                        ),
                        const SizedBox(width: 6),
                        const Text('Include chords'),
                      ],
                    ),
                  if (_format == ShareFormat.pdf)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _margin.isNotEmpty,
                          onChanged: (v) =>
                              setState(() => _margin = v ? 'left' : ''),
                        ),
                        const SizedBox(width: 6),
                        const Text('Labels in margins'),
                      ],
                    ),
                  // (its own item: on a narrow screen it goes to the next line)
                  if (_format == ShareFormat.pdf && _margin.isNotEmpty)
                    MarginSidePicker(
                      side: _margin,
                      onChanged: (v) => setState(() => _margin = v),
                    ),
                  if (_format == ShareFormat.pdf && _isSet)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('One PDF')),
                        ButtonSegment(
                          value: false,
                          label: Text('A PDF per song (.zip)'),
                        ),
                      ],
                      selected: {_onePdf},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _onePdf = v.first),
                    ),
                  if (_format == ShareFormat.slides)
                    SegmentedButton<SlideFile>(
                      segments: const [
                        ButtonSegment(value: SlideFile.pdf, label: Text('PDF')),
                        ButtonSegment(
                          value: SlideFile.pptx,
                          label: Text('PowerPoint'),
                        ),
                        ButtonSegment(
                          value: SlideFile.html,
                          label: Text('HTML page'),
                        ),
                      ],
                      selected: {_slideFile},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _slideFile = v.first),
                    ),
                  if (_format == ShareFormat.slides)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final (label, value, set) in [
                          (
                            'Title slides',
                            _withTitle,
                            (bool v) => _withTitle = v,
                          ),
                          (
                            'Blank slides',
                            _withBlank,
                            (bool v) => _withBlank = v,
                          ),
                          if (_slideFile == SlideFile.pptx)
                            (
                              'Fade between slides',
                              _fade,
                              (bool v) => _fade = v,
                            ),
                        ])
                          FilterChip(
                            label: Text(label),
                            selected: value,
                            onSelected: (v) => label.startsWith('Fade')
                                ? setState(() => set(v))
                                : _slidesChanged(() => set(v)),
                          ),
                      ],
                    ),
                  if (_format == ShareFormat.slides &&
                      _slideFile == SlideFile.pptx) ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Editable text'),
                          icon: Icon(BrambleIcons.textT),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Pictures'),
                          icon: Icon(BrambleIcons.image),
                        ),
                      ],
                      selected: {_editable},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) =>
                          setState(() => _editable = v.first),
                    ),
                    if (_editable)
                      DropdownMenu<String>(
                        key: const Key('pptx-font'),
                        label: const Text('Font'),
                        width: 220,
                        initialSelection:
                            pptxFonts.contains(model.settings.pptxFont)
                            ? model.settings.pptxFont
                            : pptxFonts.first,
                        dropdownMenuEntries: [
                          for (final f in pptxFonts)
                            DropdownMenuEntry(
                              value: f,
                              label: f,
                              labelWidget: Text(
                                f,
                                style: TextStyle(fontFamily: f),
                              ),
                            ),
                        ],
                        onSelected: (f) {
                          if (f == null) return;
                          model.updateSettings((s) => s.pptxFont = f);
                          setState(() {});
                        },
                      ),
                  ],
                ],
              ),
              if (_format == ShareFormat.pdf) _pdfOptions(),
              Expanded(child: _preview(theme)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  if ((_format == ShareFormat.chordPro ||
                          _format == ShareFormat.text) &&
                      !_isSet)
                    OutlinedButton.icon(
                      icon: const Icon(BrambleIcons.qrCode, size: 18),
                      label: const Text('QR code'),
                      onPressed: () => showTextQr(
                        context,
                        _song?.song.displayTitle ?? 'Song',
                        _text,
                      ),
                    ),
                  if (_format == ShareFormat.chordPro && !_isSet ||
                      _format == ShareFormat.text)
                    OutlinedButton.icon(
                      icon: const Icon(BrambleIcons.copy, size: 18),
                      label: const Text('Copy'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied')),
                          );
                        }
                      },
                    ),
                  FilledButton.icon(
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: AppSpinner(strokeWidth: 2),
                          )
                        : const Icon(BrambleIcons.downloadSimple, size: 18),
                    label: Text(_downloadLabel),
                    onPressed: canDownload ? _download : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // (narrow, e.g. a phone: the size slider on a line of its own, the paper
  // and columns under it)
  Widget _pdfOptions() => LayoutBuilder(
    builder: (context, c) {
      final size = _sizeSlider();
      final rest = _pageChoices();
      if (c.maxWidth >= 520) {
        return Row(children: [Expanded(child: size), const SizedBox(width: 12), ...rest]);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          size,
          Row(children: [rest[0], const SizedBox(width: 12), rest[2]]),
        ],
      );
    },
  );

  Widget _sizeSlider() => Row(
    children: [
      const Text('Size'),
      Expanded(
        child: Slider(
          value: _scale,
          min: 0.5,
          max: 1.5,
          divisions: 20,
          label: '${(_scale * 100).round()}%',
          onChanged: (v) => setState(() => _scale = v),
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '${(_scale * 100).round()}%',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    ],
  );

  List<Widget> _pageChoices() => [
      AppDropdown<PaperSize>(
        value: _paper,
        items: const [
          DropdownMenuItem(value: PaperSize.letter, child: Text('Letter')),
          DropdownMenuItem(value: PaperSize.a4, child: Text('A4')),
        ],
        onChanged: (v) => setState(() => _paper = v!),
      ),
      const SizedBox(width: 12),
      Tooltip(
        message: 'Columns',
        child: AppDropdown<int>(
          value: _columns,
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 column')),
            DropdownMenuItem(value: 2, child: Text('2 columns')),
            DropdownMenuItem(value: 3, child: Text('3 columns')),
          ],
          onChanged: (v) => setState(() => _columns = v!),
        ),
      ),
  ];

  Widget _preview(ThemeData theme) {
    final scheme = theme.colorScheme;
    Widget box(Widget child) => Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(inkR(8)),
        border: Border.all(color: scheme.outlineVariant, width: inkW(1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (_sources.isEmpty) {
      return box(const Center(child: Text('Nothing to share.')));
    }
    switch (_format) {
      case ShareFormat.pdf:
        return box(
          PdfPreview(
            key: ValueKey(
              '$_scope|$_chords|$_scale|$_paper|$_columns|$_margin',
            ),
            build: (_) => _pdfOf(_sources),
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            maxPageWidth: 560,
            // A soft, subtle page shadow.
            pdfPreviewPageDecoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            pdfFileName: '$_stem.pdf',
            loadingWidget: const AppSpinner(),
            onError: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Preview unavailable ($error). Download still works.',
                ),
              ),
            ),
          ),
        );
      case ShareFormat.chordPro:
      case ShareFormat.text:
        return box(
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        );
      case ShareFormat.freeShow:
        final names = _isSet
            ? setlistFileNames(_sources, 'show')
            : ['$_stem.show'];
        return box(
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'FreeShow songs: each section becomes a slide group, the '
                'song structure the layout, chords stay on their lines and '
                'linked translations become FreeShow translations. In '
                'FreeShow: Import → FreeShow (.show).',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final n in names)
                ListTile(
                  dense: true,
                  leading: const Icon(BrambleIcons.fileText),
                  title: Text(n),
                ),
            ],
          ),
        );
      case ShareFormat.justChords:
        final songs = _isSet
            ? {for (final s in _sources) s.song.id: s.song}.length
            : 1;
        return box(
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'A JustChords archive: open it with JustChords to add '
                '${_isSet ? 'the setlist and its songs' : 'the song'} '
                '(key, tempo, YouTube link and song structure included; '
                'translations come right after their section).',
                style: theme.textTheme.bodyMedium,
              ),
              if (_isSet && songs < 2) ...[
                const SizedBox(height: 12),
                Text(
                  'With only one song, JustChords adds just the song, not '
                  'the setlist.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                dense: true,
                leading: const Icon(BrambleIcons.fileText),
                title: Text('$_stem.jcarchive'),
              ),
            ],
          ),
        );
      case ShareFormat.slides:
        final slides = _slides;
        if (slides == null) {
          final p = _progress;
          return box(
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 12,
                children: [
                  const AppSpinner(),
                  Text(
                    p == null || p.$2 == 0
                        ? 'Drawing the slides…'
                        : 'Drawing slide ${p.$1} of ${p.$2}…',
                  ),
                ],
              ),
            ),
          );
        }
        if (slides.isEmpty) {
          return box(const Center(child: Text('No slides to share.')));
        }
        final size = model.projectorSize;
        final note = _slideFile == SlideFile.pptx && _editable
            ? 'Editable: real text in ${model.settings.pptxFont} over the '
                  'projector background. Spacing can differ a little from '
                  'these pictures; PowerPoint shrinks text that overflows.'
            : null;
        return box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Text(note, style: theme.textTheme.bodySmall),
                ),
              Expanded(child: _slideGrid(slides, size)),
            ],
          ),
        );
    }
  }

  Widget _slideGrid(List<SlideImage> slides, Size size) => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 240,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: size.width / size.height,
    ),
    itemCount: slides.length,
    itemBuilder: (context, i) => ClipRRect(
      borderRadius: BorderRadius.circular(inkR(4)),
      child: Image.memory(
        slides[i].png,
        key: Key('slide-preview-$i'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    ),
  );
}
