import 'package:flutter/material.dart';

import '../state.dart';
import '../toolbar_items.dart';
import '../eink.dart';

/// Settings → Customize toolbar, in a side pane: the top toolbar's buttons
/// as one list in two parts, the toolbar and its ⋯ menu. Drag a button up
/// or down (across the "⋯ menu" heading to put it away or bring it back),
/// or use its arrow to move it to the other part.
class ToolbarEditor extends StatelessWidget {
  final PresenterModel model;
  final VoidCallback onClose;

  /// Phones (the usual arrangement differs).
  final bool compact;

  const ToolbarEditor({
    super.key,
    required this.model,
    required this.onClose,
    this.compact = false,
  });

  /// Stands for the "⋯ menu" heading in the list.
  static const _divider = '|';

  void _save(List<String> list) {
    final at = list.indexOf(_divider);
    model.updateSettings((s) {
      s.toolbarBar = list.sublist(0, at);
      s.toolbarMore = list.sublist(at + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final layout = toolbarLayout(model.settings, compact: compact);
        final list = [...layout.bar, _divider, ...layout.more];
        final at = list.indexOf(_divider);

        Widget heading(String text, String hint) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(text, style: theme.textTheme.titleSmall),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Customize toolbar',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            heading('Toolbar', 'Drag to reorder; drag below “⋯ menu” to hide'),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: list.length,
                onReorderItem: (from, to) {
                  if (from == at) return; // the heading stays put
                  final next = [...list];
                  next.insert(to, next.removeAt(from));
                  _save(next);
                },
                itemBuilder: (context, i) {
                  final id = list[i];
                  if (id == _divider) {
                    return Container(
                      key: const ValueKey(_divider),
                      child: heading(
                        '⋯ menu',
                        'Buttons here are in the toolbar’s ⋯ menu',
                      ),
                    );
                  }
                  final item = toolbarItem(id);
                  final shown = i < at;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(id),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Material(
                        color: scheme.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(inkR(10)),
                          side: BorderSide(
                            color: scheme.outlineVariant,
                            width: inkW(1),
                          ),
                        ),
                        child: SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.grab,
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: scheme.outline,
                                    ),
                                  ),
                                ),
                              ),
                              IconTheme.merge(
                                data: IconThemeData(
                                  color: shown
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                                child: item.icon,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: shown
                                      ? null
                                      : TextStyle(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: shown
                                    ? 'Move to the ⋯ menu'
                                    : 'Move to the toolbar',
                                icon: Icon(
                                  shown
                                      ? Icons.keyboard_double_arrow_down
                                      : Icons.keyboard_double_arrow_up,
                                ),
                                onPressed: () {
                                  final next = [...list]..remove(id);
                                  final div = next.indexOf(_divider);
                                  // To the end of the toolbar, or the top
                                  // of the menu.
                                  next.insert(shown ? div + 1 : div, id);
                                  _save(next);
                                },
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset to default'),
                onPressed: model.settings.toolbarBar == null
                    ? null
                    : () => model.updateSettings((s) {
                        s.toolbarBar = null;
                        s.toolbarMore = null;
                      }),
              ),
            ),
          ],
        );
      },
    );
  }
}
