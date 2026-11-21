// The top toolbar's buttons, which the person can reorder or move into its
// ⋯ menu (Settings → Customize toolbar).

import 'package:flutter/material.dart';

import 'state.dart';
import 'widgets/motion_icon.dart';

class ToolbarItem {
  final String id;
  final String label;
  final Widget icon;
  const ToolbarItem(this.id, this.label, this.icon);
}

// (each icon moves a little on hover: widgets/motion_icon.dart)
const List<ToolbarItem> toolbarItems = [
  ToolbarItem('share', 'Share / export', MotionIcon(IconMotion.share)),
  ToolbarItem('sticky', 'Add sticky note', MotionIcon(IconMotion.sticky)),
  ToolbarItem('insert', 'Insert picture', MotionIcon(IconMotion.insert)),
  ToolbarItem('annotate', 'Annotate', MotionIcon(IconMotion.annotate)),
  ToolbarItem('edit', 'Edit song', MotionIcon(IconMotion.editSong)),
  ToolbarItem('structure', 'Song structure', MotionIcon(IconMotion.structure)),
  ToolbarItem('format', 'Format', MotionIcon(IconMotion.format)),
  ToolbarItem('present', 'Presentation mode', MotionIcon(IconMotion.present)),
  ToolbarItem('preview', 'Projector preview', MotionIcon(IconMotion.preview)),
  ToolbarItem('projector', 'Project', MotionIcon(IconMotion.projector)),
  ToolbarItem('settings', 'Settings', MotionIcon(IconMotion.settings)),
];

ToolbarItem toolbarItem(String id) =>
    toolbarItems.firstWhere((i) => i.id == id);

/// The usual arrangement: everything in the bar; on phones the less-used
/// buttons go in the ⋯ menu.
({List<String> bar, List<String> more}) defaultToolbar({
  required bool compact,
}) => compact
    ? (
        bar: ['edit', 'annotate', 'format', 'present', 'projector'],
        more: ['share', 'sticky', 'insert', 'structure', 'preview', 'settings'],
      )
    : (bar: [for (final i in toolbarItems) i.id], more: <String>[]);

/// The toolbar as the person arranged it (or the usual one). Unknown ids
/// are dropped; buttons added in later versions join the bar.
({List<String> bar, List<String> more}) toolbarLayout(
  AppSettings s, {
  required bool compact,
}) {
  final bar = s.toolbarBar;
  if (bar == null) return defaultToolbar(compact: compact);
  final known = {for (final i in toolbarItems) i.id};
  final seen = <String>{};
  final b = [
    for (final id in bar)
      if (known.contains(id) && seen.add(id)) id,
  ];
  final m = [
    for (final id in s.toolbarMore ?? const <String>[])
      if (known.contains(id) && seen.add(id)) id,
  ];
  for (final i in toolbarItems) {
    if (seen.add(i.id)) b.add(i.id);
  }
  return (bar: b, more: m);
}
