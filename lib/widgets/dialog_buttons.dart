// The round ✕ and ✓ that close the app's dialogs and editors (song editor,
// song structure, settings…): the same look everywhere, in every style and
// colour theme. ✕ in the surface's neutral tint, ✓ filled with the theme's
// accent; no room round them for touch, so the circle is the edge (the
// padding to it is what's seen).
import 'package:flutter/material.dart';

import '../bramble_icons.dart';

ButtonStyle _round({Color? fill, Color? ink}) => IconButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  backgroundColor: fill,
  foregroundColor: ink,
);

/// ✕: closes without keeping changes.
class DialogCancelButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  const DialogCancelButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: _round(
        fill: scheme.surfaceContainerHighest,
        ink: scheme.onSurface,
      ),
      onPressed: onPressed,
      icon: const Icon(BrambleIcons.x),
    );
  }
}

/// ✓: keeps the changes (Save, Done).
class DialogDoneButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  const DialogDoneButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Done',
  });

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    // (the theme's accent: primary, on primary)
    style: _round(),
    onPressed: onPressed,
    icon: const Icon(BrambleIcons.check),
  );
}
