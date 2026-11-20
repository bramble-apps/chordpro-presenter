// Which margin the section labels go in: two small icon buttons (a rail on
// the left, a rail on the right), compact enough for a phone.
import 'package:flutter/material.dart';

/// Picks 'left' or 'right' for labels in margins.
class MarginSidePicker extends StatelessWidget {
  final String side;
  final ValueChanged<String> onChanged;
  const MarginSidePicker({super.key, required this.side, required this.onChanged});

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(
        value: 'left',
        icon: Icon(Icons.border_left, size: 20),
        tooltip: 'Left margin',
      ),
      ButtonSegment(
        value: 'right',
        icon: Icon(Icons.border_right, size: 20),
        tooltip: 'Right margin',
      ),
    ],
    selected: {side == 'right' ? 'right' : 'left'},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}
