// The top toolbar's buttons, which the person can reorder or move into its
// ⋯ menu (Settings → Customize toolbar).

import 'package:flutter/material.dart';

import 'state.dart';
import 'widgets/edit_song_icon.dart';

class ToolbarItem {
  final String id;
  final String label;
  final Widget icon;
  const ToolbarItem(this.id, this.label, this.icon);
}

const List<ToolbarItem> toolbarItems = [
  ToolbarItem('share', 'Share / export', Icon(Icons.ios_share)),
  ToolbarItem('sticky', 'Add sticky note', Icon(Icons.sticky_note_2_outlined)),
  ToolbarItem(
    'insert',
    'Insert picture',
    Icon(Icons.add_photo_alternate_outlined),
  ),
  ToolbarItem('annotate', 'Annotate', Icon(Icons.draw_outlined)),
  ToolbarItem('edit', 'Edit song', EditSongIcon()),
  ToolbarItem('structure', 'Song structure', Icon(Icons.account_tree_outlined)),
  ToolbarItem('format', 'Format', Icon(Icons.brush_outlined)),
  ToolbarItem('present', 'Presentation mode', Icon(Icons.grid_view_rounded)),
  ToolbarItem(
    'preview',
    'Projector preview',
    Icon(Icons.picture_in_picture_alt_outlined),
  ),
  ToolbarItem('projector', 'Project', Icon(Icons.tv_rounded)),
  ToolbarItem('settings', 'Settings', Icon(Icons.settings_outlined)),
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
