// Pictures placed on a song's chord sheet (Insert → picture): a logo, a
// diagram, a scanned bit of music. Each sits on the page (scrolls with it),
// moves by dragging, resizes from its corners keeping its shape, and when
// tapped shows a toolbar above it: tint (theme, a few colours or any),
// mask (no background behind black-and-white pictures), crop, delete.
// The picture is kept like an attached PDF (so backups carry it); where
// and how it shows is kept with the song.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../browser.dart';
import '../pdfs.dart';
import '../state.dart';
import 'color_picker.dart';
import '../eink.dart';

/// One picture on the sheet.
class SheetImage {
  final String id;

  /// The stored picture (see [PdfStore]) and its file name.
  final String file, name;

  /// Top-left on the sheet, and width (logical pixels).
  double x, y, width;

  /// The full picture's height ÷ width (pixels).
  double aspect;

  /// The part shown: left, top, right, bottom as fractions of the picture.
  List<double> crop;

  /// Tint: null none, 'theme' the theme's text colour, else '#RRGGBB'.
  String? tint;

  /// White becomes see-through (for black-and-white pictures).
  bool mask;

  SheetImage({
    String? id,
    required this.file,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.aspect,
    List<double>? crop,
    this.tint,
    this.mask = false,
  }) : id = id ?? newId(),
       crop = crop ?? [0, 0, 1, 1];

  /// Height ÷ width of the part shown.
  double get shownAspect =>
      aspect * (crop[3] - crop[1]) / math.max(0.001, crop[2] - crop[0]);

  double get height => width * shownAspect;

  Map<String, dynamic> toJson() => {
    'id': id,
    'file': file,
    'name': name,
    'x': x,
    'y': y,
    'w': width,
    'aspect': aspect,
    if (crop.join(',') != '0.0,0.0,1.0,1.0') 'crop': crop,
    'tint': ?tint,
    if (mask) 'mask': true,
  };

  static SheetImage fromJson(Map<String, dynamic> j) => SheetImage(
    id: j['id'] as String?,
    file: j['file'] as String,
    name: j['name'] as String? ?? 'image',
    x: (j['x'] as num?)?.toDouble() ?? 0,
    y: (j['y'] as num?)?.toDouble() ?? 0,
    width: (j['w'] as num?)?.toDouble() ?? 240,
    aspect: (j['aspect'] as num?)?.toDouble() ?? 1,
    crop: [
      for (final v in (j['crop'] as List?) ?? const [0, 0, 1, 1])
        (v as num).toDouble(),
    ],
    tint: j['tint'] as String?,
    mask: j['mask'] == true,
  );
}

List<SheetImage> sheetImages(PresenterModel model, Song song) => [
  for (final j in model.sheetImagesOf(song))
    if (j['file'] is String) SheetImage.fromJson(j),
];

void _store(
  PresenterModel model,
  Song song,
  List<SheetImage> images, {
  bool notify = true,
}) => model.setSheetImages(song, [
  for (final i in images) i.toJson(),
], notify: notify);

/// Picks a picture and puts it on [song]'s sheet, near the top left.
Future<void> insertSheetImage(
  BuildContext context,
  PresenterModel model,
  Song song,
) async {
  final files = await pickBinaryFiles(const [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
  ]);
  if (files.isEmpty) return;
  final (name, bytes) = files.first;
  if (!PdfStore.looksLikeImage(bytes)) return;
  double aspect = 1;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    aspect = img.height / math.max(1, img.width);
    img.dispose();
  } catch (_) {
    return; // not a picture after all
  }
  final ref = await PdfStore.add(name, bytes);
  final images = sheetImages(model, song);
  final n = images.length % 5;
  final width = aspect > 1.5 ? 160.0 : 260.0;
  images.add(
    SheetImage(
      file: ref.id,
      name: name,
      x: 40.0 + n * 24,
      y: 90.0 + n * 24,
      width: width,
      aspect: aspect,
    ),
  );
  _store(model, song, images);
  SheetImageLayer.select(images.last.id);
}

/// Tint presets (besides none, the theme and any colour).
const tintPresets = <(String, int)>[
  ('Black', 0xFF111111),
  ('Red', 0xFFC62828),
  ('Blue', 0xFF1565C0),
  ('Green', 0xFF2E7D32),
  ('Purple', 0xFF6A1B9A),
  ('Orange', 0xFFEF6C00),
];

/// The colour filter for a picture's tint and mask (null: as it is).
ColorFilter? imageFilter(SheetImage img, Color themeInk) {
  Color? tint;
  if (img.tint == 'theme') {
    tint = themeInk;
  } else if (img.tint != null) {
    tint = parseHex(img.tint!);
  }
  // Dark parts: the tint; light parts: white (or see-through with mask).
  const lum = [0.299, 0.587, 0.114];
  final alpha = img.mask
      ? [-lum[0] * 2, -lum[1] * 2, -lum[2] * 2, 0.0, 510.0]
      : [0.0, 0.0, 0.0, 1.0, 0.0];
  if (tint == null) {
    if (!img.mask) return null;
    return ColorFilter.matrix([
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      ...alpha,
    ]);
  }
  List<double> row(double c) {
    // With a mask the colour is the tint everywhere (alpha does the rest).
    if (img.mask) return [0, 0, 0, 0, c];
    final k = (255 - c) / 255;
    return [k * lum[0], k * lum[1], k * lum[2], 0, c];
  }

  return ColorFilter.matrix([
    ...row(tint.r * 255),
    ...row(tint.g * 255),
    ...row(tint.b * 255),
    ...alpha,
  ]);
}

/// The pictures on a song's sheet (in the sheet's own stack, so they
/// scroll with it).
class SheetImageLayer extends StatefulWidget {
  final PresenterModel model;
  final Song song;
  const SheetImageLayer({super.key, required this.model, required this.song});

  /// The picture chosen (one at a time, app-wide).
  static final selected = ValueNotifier<String?>(null);
  static void select(String? id) => selected.value = id;

  @override
  State<SheetImageLayer> createState() => _SheetImageLayerState();
}

class _SheetImageLayerState extends State<SheetImageLayer> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.model, SheetImageLayer.selected]),
      builder: (context, _) {
        final images = sheetImages(widget.model, widget.song);
        if (images.isEmpty) return const SizedBox.shrink();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final img in images)
              _ImageOnSheet(
                key: ValueKey(img.id),
                image: img,
                selected: SheetImageLayer.selected.value == img.id,
                onChanged: (notify) {
                  final all = sheetImages(widget.model, widget.song);
                  final i = all.indexWhere((e) => e.id == img.id);
                  if (i >= 0) all[i] = img;
                  _store(widget.model, widget.song, all, notify: notify);
                },
                onDelete: () {
                  _store(widget.model, widget.song, [
                    for (final e in sheetImages(widget.model, widget.song))
                      if (e.id != img.id) e,
                  ]);
                  SheetImageLayer.select(null);
                },
              ),
          ],
        );
      },
    );
  }
}

class _ImageOnSheet extends StatefulWidget {
  final SheetImage image;
  final bool selected;
  final void Function(bool notify) onChanged;
  final VoidCallback onDelete;
  const _ImageOnSheet({
    super.key,
    required this.image,
    required this.selected,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ImageOnSheet> createState() => _ImageOnSheetState();
}

class _ImageOnSheetState extends State<_ImageOnSheet> {
  Uint8List? _bytes;
  bool _cropping = false;

  /// While cropping: the crop being set (fractions), shown over the whole
  /// picture.
  late List<double> _crop;

  SheetImage get img => widget.image;

  static const _handle = 30.0; // touch-sized

  @override
  void initState() {
    super.initState();
    _crop = [...img.crop];
    PdfStore.bytes(img.file).then((b) {
      if (mounted) setState(() => _bytes = b);
    });
  }

  @override
  void didUpdateWidget(_ImageOnSheet old) {
    super.didUpdateWidget(old);
    if (!widget.selected && _cropping) _cropping = false;
  }

  /// The whole picture's size at the current scale.
  Size get _full {
    final w = img.width / math.max(0.001, img.crop[2] - img.crop[0]);
    return Size(w, w * img.aspect);
  }

  Widget _picture(Size size, Color themeInk) {
    final bytes = _bytes;
    if (bytes == null) return SizedBox.fromSize(size: size);
    Widget pic = Image.memory(
      bytes,
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
    final f = imageFilter(img, themeInk);
    if (f != null) pic = ColorFiltered(colorFilter: f, child: pic);
    return pic;
  }

  void _startCrop() => setState(() {
    _crop = [...img.crop];
    _cropping = true;
  });

  void _finishCrop() {
    final full = _full;
    // Keep the shown part where it was on the page.
    final oldLeft = img.x - img.crop[0] * full.width;
    final oldTop = img.y - img.crop[1] * full.height;
    img
      ..crop = [..._crop]
      ..x = oldLeft + _crop[0] * full.width
      ..y = oldTop + _crop[1] * full.height
      ..width = full.width * (_crop[2] - _crop[0]);
    setState(() => _cropping = false);
    widget.onChanged(true);
  }

  /// Room above the picture for its toolbar, and around it for handles
  /// (all inside the picture's own box, so they take taps).
  static const _room = 54.0, _pad = _handle / 2;

  /// The picture's box on the page: [content] at [left], [top] (sheet
  /// coordinates) sized [width] × [height]; [toolbar] above it; [handles]
  /// positioned in the box's coordinates (see [_at]).
  /// A handle centred on ([x], [y]) of the content, in the box.
  Widget _at(double x, double y, Widget child) => Positioned(
    left: _pad + x - _handle / 2,
    top: _room + _pad + y - _handle / 2,
    child: child,
  );

  Widget _framed({
    required double left,
    required double top,
    required double width,
    required double height,
    required Widget content,
    Widget? toolbar,
    List<Widget> handles = const [],
    VoidCallback? onTapOutside,
  }) {
    return Positioned(
      left: left - _pad,
      top: top - _room - _pad,
      child: TapRegion(
        groupId: SheetImageLayer,
        onTapOutside: onTapOutside == null ? null : (_) => onTapOutside(),
        child: SizedBox(
          width: math.max(width + 2 * _pad, 230),
          height: height + _room + 2 * _pad,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _pad,
                top: _room + _pad,
                width: width,
                height: height,
                child: content,
              ),
              ?(toolbar == null
                  ? null
                  : Positioned(left: _pad, top: 2, child: toolbar)),
              ...handles,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeInk = scheme.onSurface;
    if (_cropping) return _cropView(scheme, themeInk);
    final w = img.width, h = img.height;
    final full = _full;
    final shown = ClipRect(
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -img.crop[0] * full.width,
              top: -img.crop[1] * full.height,
              child: _picture(full, themeInk),
            ),
          ],
        ),
      ),
    );
    return _framed(
      left: img.x,
      top: img.y,
      width: w,
      height: h,
      onTapOutside: widget.selected ? () => SheetImageLayer.select(null) : null,
      toolbar: widget.selected ? _toolbar(scheme) : null,
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => SheetImageLayer.select(img.id),
        onPanStart: (_) => SheetImageLayer.select(img.id),
        onPanUpdate: (d) => setState(() {
          img
            ..x += d.delta.dx
            ..y += d.delta.dy;
        }),
        onPanEnd: (_) => widget.onChanged(false),
        child: Stack(
          children: [
            shown,
            if (widget.selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.primary, width: inkW(2)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      handles: widget.selected
          ? [
              for (final corner in const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                _resizeHandle(corner, scheme),
            ]
          : const [],
    );
  }

  /// A corner handle: resizes keeping the picture's shape (no skinny
  /// pictures), the opposite corner staying put.
  Widget _resizeHandle(Alignment corner, ColorScheme scheme) {
    final right = corner.x > 0, bottom = corner.y > 0;
    return _at(
      right ? img.width : 0,
      bottom ? img.height : 0,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setState(() {
          // How much wider: along the diagonal, by the larger move.
          final dx = right ? d.delta.dx : -d.delta.dx;
          final dy = (bottom ? d.delta.dy : -d.delta.dy) / img.shownAspect;
          final grow = dx.abs() > dy.abs() ? dx : dy;
          final w = (img.width + grow).clamp(40.0, 2000.0);
          final dw = w - img.width, dh = dw * img.shownAspect;
          if (!right) img.x -= dw;
          if (!bottom) img.y -= dh;
          img.width = w;
        }),
        onPanEnd: (_) => widget.onChanged(false),
        child: SizedBox.square(
          dimension: _handle,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.primary, width: inkW(2)),
                borderRadius: BorderRadius.circular(inkR(3)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cropping: the whole picture, the part kept bright, handles on its
  /// corners and edges.
  Widget _cropView(ColorScheme scheme, Color themeInk) {
    final full = _full;
    final left = img.x - img.crop[0] * full.width;
    final top = img.y - img.crop[1] * full.height;
    Rect keep() => Rect.fromLTRB(
      _crop[0] * full.width,
      _crop[1] * full.height,
      _crop[2] * full.width,
      _crop[3] * full.height,
    );

    Widget handle(double fx, double fy, void Function(Offset d) move) {
      final r = keep();
      return _at(
        r.left + r.width * fx,
        r.top + r.height * fy,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => setState(() => move(d.delta)),
          child: SizedBox.square(
            dimension: _handle,
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: scheme.primary, width: inkW(2)),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    const minPart = 0.05;
    void edge(int i, double delta, double size) {
      final v = (_crop[i] + delta / size).clamp(0.0, 1.0);
      if (i == 0) _crop[0] = math.min(v, _crop[2] - minPart);
      if (i == 1) _crop[1] = math.min(v, _crop[3] - minPart);
      if (i == 2) _crop[2] = math.max(v, _crop[0] + minPart);
      if (i == 3) _crop[3] = math.max(v, _crop[1] + minPart);
    }

    return _framed(
      left: left,
      top: top,
      width: full.width,
      height: full.height,
      toolbar: _bar(scheme, [
        _button('Done cropping', Icons.check, _finishCrop, scheme, on: true),
        _button(
          'Show the whole picture',
          Icons.crop_free,
          () => setState(() => _crop = [0, 0, 1, 1]),
          scheme,
        ),
        _button(
          'Cancel',
          Icons.close,
          () => setState(() => _cropping = false),
          scheme,
        ),
      ]),
      content: Stack(
        children: [
          _picture(full, themeInk),
          // Outside the part kept: dimmed.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DimOutside(keep())),
            ),
          ),
        ],
      ),
      handles: [
        // Corners move two edges; edges one.
        handle(0, 0, (d) {
          edge(0, d.dx, full.width);
          edge(1, d.dy, full.height);
        }),
        handle(1, 0, (d) {
          edge(2, d.dx, full.width);
          edge(1, d.dy, full.height);
        }),
        handle(0, 1, (d) {
          edge(0, d.dx, full.width);
          edge(3, d.dy, full.height);
        }),
        handle(1, 1, (d) {
          edge(2, d.dx, full.width);
          edge(3, d.dy, full.height);
        }),
        handle(0.5, 0, (d) => edge(1, d.dy, full.height)),
        handle(0.5, 1, (d) => edge(3, d.dy, full.height)),
        handle(0, 0.5, (d) => edge(0, d.dx, full.width)),
        handle(1, 0.5, (d) => edge(2, d.dx, full.width)),
      ],
    );
  }

  Widget _button(
    String tip,
    IconData icon,
    VoidCallback onTap,
    ColorScheme scheme, {
    bool on = false,
  }) => SizedBox.square(
    dimension: 40,
    child: IconButton(
      tooltip: tip,
      isSelected: on,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        backgroundColor: on ? scheme.primary.withValues(alpha: 0.18) : null,
        foregroundColor: on ? scheme.primary : null,
      ),
      icon: Icon(icon, size: 21),
      onPressed: onTap,
    ),
  );

  Widget _bar(ColorScheme scheme, List<Widget> children) => Material(
    elevation: inkE(6),
    color: scheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(inkR(24)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _toolbar(ColorScheme scheme) {
    Widget swatch(Color c, {bool selected = false}) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : Colors.black26,
          width: inkW(selected ? 2.5 : 1),
        ),
      ),
    );
    return _bar(scheme, [
      SizedBox.square(
        dimension: 40,
        child: PopupMenuButton<String>(
          tooltip: 'Tint',
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          icon: Icon(
            Icons.format_color_fill,
            size: 21,
            color: img.tint == null ? null : scheme.primary,
          ),
          onSelected: (v) async {
            if (v == 'custom') {
              final c = await pickColor(
                context,
                img.tint != null && img.tint != 'theme'
                    ? parseHex(img.tint!) ?? Colors.black
                    : Colors.black,
              );
              if (c == null) return;
              v = hexOf(c);
            }
            setState(() => img.tint = v == 'none' ? null : v);
            widget.onChanged(true);
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'none',
              checked: img.tint == null,
              child: const Text('No tint'),
            ),
            CheckedPopupMenuItem(
              value: 'theme',
              checked: img.tint == 'theme',
              child: const Text('Theme colour'),
            ),
            for (final (name, c) in tintPresets)
              PopupMenuItem(
                value: hexOf(Color(c)),
                child: Row(
                  spacing: 12,
                  children: [
                    swatch(Color(c), selected: img.tint == hexOf(Color(c))),
                    Text(name),
                  ],
                ),
              ),
            const PopupMenuItem(value: 'custom', child: Text('Custom colour…')),
          ],
        ),
      ),
      _button(
        img.mask
            ? 'Mask on: no white background'
            : 'Mask (remove the white background)',
        Icons.layers_clear_outlined,
        () {
          setState(() => img.mask = !img.mask);
          widget.onChanged(true);
        },
        scheme,
        on: img.mask,
      ),
      _button('Crop', Icons.crop, _startCrop, scheme),
      _button('Delete picture', Icons.delete_outline, widget.onDelete, scheme),
    ]);
  }
}

class _DimOutside extends CustomPainter {
  final Rect keep;
  _DimOutside(this.keep);

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(keep);
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawRect(
      keep,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DimOutside old) => old.keep != keep;
}
