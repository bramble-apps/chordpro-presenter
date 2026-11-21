import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bramble_icons.dart';
import '../eink.dart';
import '../format.dart' show namedColors;
import 'dialog_buttons.dart';

/// A colour swatch that opens a picker (saturation/brightness square, hue
/// slider, hex code) when tapped.
class ColorField extends StatelessWidget {
  final Color value;
  final ValueChanged<Color> onChanged;
  final String? tooltip;

  /// Show the #RRGGBB code beside the swatch.
  final bool showHex;

  const ColorField({
    super.key,
    required this.value,
    required this.onChanged,
    this.tooltip,
    this.showHex = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? 'Choose colour',
      child: InkWell(
        borderRadius: BorderRadius.circular(inkR(8)),
        onTap: () async {
          final picked = await pickColor(context, value);
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: showHex
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
              : const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(inkR(8)),
            border: Border.all(color: scheme.outlineVariant, width: inkW(1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: showHex ? 8 : 0,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value.withValues(alpha: 1),
                  borderRadius: BorderRadius.circular(inkR(5)),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: inkW(1),
                  ),
                ),
              ),
              if (showHex)
                Text(
                  hexOf(value),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the colour picker; returns the chosen colour (null if cancelled).
Future<Color?> pickColor(BuildContext context, Color initial) async =>
    (await showAppDialog<ColorPick>(
      context: context,
      builder: (_) => _PickerDialog(initial: initial),
    ))?.color;

/// What a picker with a "Default" / "None" choice returns: a colour, or
/// null for that choice.
class ColorPick {
  final Color? color;
  const ColorPick(this.color);
}

/// The picker with a first swatch for no colour of its own ([clearLabel]:
/// "Default", drawn split white and black when [splitClear]; or "None")
/// and its own [presets]. A swatch is chosen at once.
Future<ColorPick?> pickColorOrClear(
  BuildContext context,
  Color initial, {
  required String clearLabel,
  bool splitClear = false,
  Map<String, Color>? presets,
}) => showAppDialog<ColorPick>(
  context: context,
  builder: (_) => _PickerDialog(
    initial: initial,
    clearLabel: clearLabel,
    splitClear: splitClear,
    presets: presets,
  ),
);

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? parseHex(String text) {
  final t = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

class _PickerDialog extends StatefulWidget {
  final Color initial;
  final String? clearLabel;
  final bool splitClear;
  final Map<String, Color>? presets;
  const _PickerDialog({
    required this.initial,
    this.clearLabel,
    this.splitClear = false,
    this.presets,
  });

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial.withValues(alpha: 1));
  late final _hex = TextEditingController(text: hexOf(widget.initial));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor c) {
    setState(() => _hsv = c);
    _hex.text = hexOf(c.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final scheme = Theme.of(context).colorScheme;
    // On top: the colour and its hex code, then ✕ and ✓ (as the app's
    // other dialogs); the preset colours along the bottom.
    return AlertDialog(
      title: Row(
        spacing: 12,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(inkR(8)),
              border: Border.all(color: scheme.outlineVariant, width: inkW(1)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _hex,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(
                labelText: 'Hex',
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (t) {
                final c = parseHex(t);
                if (c != null) setState(() => _hsv = HSVColor.fromColor(c));
              },
            ),
          ),
          DialogCancelButton(onPressed: () => Navigator.pop(context)),
          DialogDoneButton(
            tooltip: 'Use colour',
            onPressed: () => Navigator.pop(context, ColorPick(color)),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            // Saturation (x) × brightness (y) for the current hue.
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                const h = 180.0;
                void at(Offset p) => _set(
                  _hsv
                      .withSaturation((p.dx / w).clamp(0, 1))
                      .withValue(1 - (p.dy / h).clamp(0, 1)),
                );
                return GestureDetector(
                  onPanDown: (d) => at(d.localPosition),
                  onPanUpdate: (d) => at(d.localPosition),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(inkR(8)),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  HSVColor.fromAHSV(
                                    1,
                                    _hsv.hue,
                                    1,
                                    1,
                                  ).toColor(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(inkR(8)),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _hsv.saturation * w - 9,
                          top: (1 - _hsv.value) * h - 9,
                          child: _Knob(color: color),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Hue.
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                void at(Offset p) =>
                    _set(_hsv.withHue((p.dx / w).clamp(0, 1) * 359.9));
                return GestureDetector(
                  onPanDown: (d) => at(d.localPosition),
                  onPanUpdate: (d) => at(d.localPosition),
                  child: SizedBox(
                    height: 22,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(inkR(11)),
                              gradient: LinearGradient(
                                colors: [
                                  for (var h = 0; h <= 360; h += 60)
                                    HSVColor.fromAHSV(
                                      1,
                                      h % 360.0,
                                      1,
                                      1,
                                    ).toColor(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _hsv.hue / 360 * w - 9,
                          top: 2,
                          child: _Knob(
                            color: HSVColor.fromAHSV(
                              1,
                              _hsv.hue,
                              1,
                              1,
                            ).toColor(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // The preset colours (as the Format pane's swatches), from the
            // left edge.
            Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.clearLabel case final clear?)
                  Tooltip(
                    message: clear,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(inkR(6)),
                      onTap: () =>
                          Navigator.pop(context, const ColorPick(null)),
                      child: ColorTile(
                        color: null,
                        split: widget.splitClear,
                        size: 28,
                      ),
                    ),
                  ),
                for (final MapEntry(key: name, value: c)
                    in (widget.presets ?? namedColors).entries)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(inkR(6)),
                      // (a swatch: chosen at once, its exact colour)
                      onTap: () => Navigator.pop(context, ColorPick(c)),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(inkR(6)),
                          border: Border.all(
                            width: inkW(c == color ? 2.5 : 1),
                            color: c == color
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  final Color color;
  const _Knob({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: inkW(3)),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
    ),
  );
}

/// Angle control: a wheel you drag around (snaps to 15°) plus a number box.
class AngleField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const AngleField({super.key, required this.value, required this.onChanged});

  @override
  State<AngleField> createState() => _AngleFieldState();
}

class _AngleFieldState extends State<AngleField> {
  late final _text = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(AngleField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _text.text != '${widget.value}') {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _drag(Offset p, double size) {
    final c = Offset(size / 2, size / 2);
    final v = p - c;
    if (v.distance < 4) return;
    // 0° = up, clockwise; snap to 15° steps.
    var deg = (math.atan2(v.dx, -v.dy) * 180 / math.pi + 360) % 360;
    final snapped = ((deg / 15).round() * 15) % 360;
    if (snapped != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged(snapped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 64.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        Tooltip(
          message: 'Drag to set the direction (snaps to 15°)',
          child: GestureDetector(
            onPanDown: (d) => _drag(d.localPosition, size),
            onPanUpdate: (d) => _drag(d.localPosition, size),
            child: CustomPaint(
              size: const Size(size, size),
              painter: _WheelPainter(
                angle: widget.value,
                ring: scheme.outlineVariant,
                hand: scheme.primary,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _text,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(isDense: true, suffixText: '°'),
            onSubmitted: (t) => widget.onChanged((int.tryParse(t) ?? 0) % 360),
            onChanged: (t) {
              final v = int.tryParse(t);
              if (v != null) widget.onChanged(v % 360);
            },
          ),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final int angle;
  final Color ring;
  final Color hand;
  _WheelPainter({required this.angle, required this.ring, required this.hand});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Tick marks every 45°.
    for (var a = 0; a < 360; a += 45) {
      final t = a * math.pi / 180;
      final dir = Offset(math.sin(t), -math.cos(t));
      canvas.drawLine(c + dir * (r - 5), c + dir * r, Paint()..color = ring);
    }
    final t = angle * math.pi / 180;
    final tip = c + Offset(math.sin(t), -math.cos(t)) * (r - 2);
    canvas.drawLine(
      c,
      tip,
      Paint()
        ..color = hand
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 5, Paint()..color = hand);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.angle != angle;
}

/// A colour as a small rounded tile; null: no colour of its own, drawn
/// split white and black ([split]: follows light or dark mode) or with a
/// "no" sign (none).
class ColorTile extends StatelessWidget {
  final Color? color;
  final bool split;
  final double size;
  final double? width;
  const ColorTile({
    super.key,
    required this.color,
    this.split = false,
    this.size = 24,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(inkR(6));
    return Container(
      width: width ?? size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: color ?? (split ? null : scheme.surface),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant, width: inkW(1)),
      ),
      child: color != null
          ? null
          : split
          ? const CustomPaint(painter: _SplitPainter())
          : Icon(BrambleIcons.prohibit, size: size * .6, color: scheme.outline),
    );
  }
}

/// White above the diagonal, black below: light mode's text, dark mode's.
class _SplitPainter extends CustomPainter {
  const _SplitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawPath(
        Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = const Color(0xFF000000),
      );
  }

  @override
  bool shouldRepaint(_SplitPainter old) => false;
}

/// A colour setting as Letters' inspector shows one: its colour in a tile
/// and a colour wheel, together in a pill; either opens the picker (the
/// colour square, hue, hex and swatches).
class ColorWell extends StatelessWidget {
  final String label;

  /// The colour; null: [clearLabel] (the default, or none).
  final Color? value;
  final String clearLabel;
  final bool splitClear;
  final Map<String, Color>? presets;
  final ValueChanged<Color?> onChanged;

  const ColorWell({
    super.key,
    required this.label,
    required this.value,
    required this.clearLabel,
    required this.onChanged,
    this.splitClear = false,
    this.presets,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Future<void> open() async {
      final pick = await pickColorOrClear(
        context,
        value ?? scheme.primary,
        clearLabel: clearLabel,
        splitClear: splitClear,
        presets: presets,
      );
      if (pick != null) onChanged(pick.color);
    }

    return Row(
      children: [
        Expanded(child: Text(label)),
        Tooltip(
          message: value == null ? clearLabel : hexOf(value!),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(inkR(10)),
            child: InkWell(
              borderRadius: BorderRadius.circular(inkR(10)),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    ColorTile(
                      color: value,
                      split: splitClear,
                      size: 24,
                      width: 44,
                    ),
                    const _Wheel(size: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small colour wheel (the hues round a circle, white at its middle).
class _Wheel extends StatelessWidget {
  final double size;
  const _Wheel({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ),
    ),
    foregroundDecoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
        stops: [0, 1],
      ),
    ),
  );
}
