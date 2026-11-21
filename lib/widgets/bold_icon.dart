// The Bold button's icon: a heavy "B" (the icon sets have only outlined or
// boxed ones), in the interface font, sized and coloured like the icons
// beside it.
import 'package:flutter/material.dart';

class BoldIcon extends StatelessWidget {
  final double? size;
  const BoldIcon({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: Center(
        child: Text(
          'B',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            // (about the icons' height: their drawings fill ~3/4 of the box)
            fontSize: s * .82,
            height: 1,
            fontWeight: FontWeight.w900,
            color: theme.color,
          ),
        ),
      ),
    );
  }
}

/// The All caps button's icon: "AA" in the interface font, at the line
/// weight of the icons beside it (the icon sets' capitals are rounded).
class CapsIcon extends StatelessWidget {
  final double? size;
  const CapsIcon({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: Center(
        child: Text(
          'AA',
          textScaler: TextScaler.noScaling,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontSize: s * .62,
            height: 1,
            letterSpacing: s * .02,
            fontWeight: FontWeight.w500,
            color: theme.color,
          ),
        ),
      ),
    );
  }
}
