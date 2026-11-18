// Libraries → a library's ⋯ → "Compare & sync…": the open library and
// another side by side (see library_sync.dart), a choice for each
// difference, then both saved.

import 'package:flutter/material.dart';

import '../eink.dart';
import '../library_sync.dart';
import '../state.dart';

Future<void> showLibrarySync(
  BuildContext context,
  PresenterModel model,
  String otherId,
) async {
  final (diff, here, there) = await model.compareWithLibrary(otherId);
  if (!context.mounted) return;
  final result = await showAppDialog<String>(
    context: context,
    builder: (_) => _LibrarySyncDialog(
      model: model,
      otherId: otherId,
      diff: diff,
      here: here,
      there: there,
    ),
  );
  if (result != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(result)));
  }
}

class _LibrarySyncDialog extends StatefulWidget {
  final PresenterModel model;
  final String otherId;
  final LibraryDiff diff;
  final LibrarySide here, there;
  const _LibrarySyncDialog({
    required this.model,
    required this.otherId,
    required this.diff,
    required this.here,
    required this.there,
  });

  @override
  State<_LibrarySyncDialog> createState() => _LibrarySyncDialogState();
}

enum _Direction { both, send, bring }

class _LibrarySyncDialogState extends State<_LibrarySyncDialog> {
  LibraryDiff get d => widget.diff;
  String get hereName => widget.here.name;
  String get thereName => widget.there.name;
  _Direction _direction = _Direction.both;
  bool _busy = false;

  void _setDirection(_Direction v) => setState(() {
    _direction = v;
    d.choose(switch (v) {
      _Direction.both => null,
      _Direction.send => SyncChoice.here,
      _Direction.bring => SyncChoice.there,
    });
  });

  Future<void> _apply() async {
    setState(() => _busy = true);
    final r = await widget.model.syncWithLibrary(
      widget.otherId,
      d,
      widget.here,
      widget.there,
    );
    if (mounted) Navigator.pop(context, r.describe(hereName, thereName));
  }

  /// The choice for a difference that's on one side only: copy or skip.
  Widget _oneSide(Object item, bool isHere) {
    final c = d.choices[item] ?? SyncChoice.skip;
    final copy = isHere ? SyncChoice.here : SyncChoice.there;
    return Checkbox(
      value: c == copy,
      onChanged: (v) =>
          setState(() => d.choices[item] = v == true ? copy : SyncChoice.skip),
    );
  }

  /// The choice for something in both, but different.
  Widget _conflict(Object item, {bool allowBoth = true}) {
    final c = d.choices[item] ?? SyncChoice.skip;
    return AppDropdown<SyncChoice>(
      value: c,
      isDense: true,
      items: [
        for (final (v, label) in [
          (SyncChoice.here, 'Keep $hereName\'s'),
          (SyncChoice.there, 'Take $thereName\'s'),
          if (allowBoth) (SyncChoice.both, 'Keep both'),
          (SyncChoice.skip, 'Leave as is'),
        ])
          DropdownMenuItem(value: v, child: Text(label)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => d.choices[item] = v);
      },
    );
  }

  String _newer(SongDiff s) => switch (s.hereNewer) {
    true => 'edited last in $hereName',
    false => 'edited last in $thereName',
    null => 'different',
  };

  Widget _section(String title, List<Widget> rows) => rows.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(
                '$title (${rows.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ...rows,
          ],
        );

  Widget _row(String title, String? subtitle, Widget choice) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: choice,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final onlyHere = [
      for (final s in d.songs)
        if (s.there == null)
          _row(s.title, s.here!.displayArtist, _oneSide(s, true)),
      for (final s in d.setlists)
        if (s.there == null)
          _row(
            s.name,
            'Setlist · ${s.here!.songCount} songs',
            _oneSide(s, true),
          ),
    ];
    final onlyThere = [
      for (final s in d.songs)
        if (s.here == null)
          _row(s.title, s.there!.displayArtist, _oneSide(s, false)),
      for (final s in d.setlists)
        if (s.here == null)
          _row(
            s.name,
            'Setlist · ${s.there!.songCount} songs',
            _oneSide(s, false),
          ),
    ];
    final both = [
      for (final s in d.songs)
        if (s.changed) _row(s.title, _newer(s), _conflict(s)),
      for (final s in d.setlists)
        if (s.changed)
          _row(s.name, 'Setlist · different', _conflict(s, allowBoth: false)),
    ];
    return AlertDialog(
      title: Text('$hereName ⇄ $thereName'),
      content: SizedBox(
        width: 520,
        child: d.isEmpty
            ? Text(
                'These libraries have the same songs and setlists.',
                style: muted,
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose what goes where. Nothing is deleted; a song '
                      'kept "both" ways comes in as a copy beside the '
                      'other, named after its library.',
                      style: muted,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<_Direction>(
                      segments: [
                        const ButtonSegment(
                          value: _Direction.both,
                          label: Text('Both ways'),
                        ),
                        ButtonSegment(
                          value: _Direction.send,
                          label: Text('Send to $thereName'),
                        ),
                        ButtonSegment(
                          value: _Direction.bring,
                          label: Text('Bring from $thereName'),
                        ),
                      ],
                      selected: {_direction},
                      onSelectionChanged: (v) => _setDirection(v.first),
                    ),
                    _section(
                      'Only in $hereName — send to $thereName',
                      onlyHere,
                    ),
                    _section(
                      'Only in $thereName — bring to $hereName',
                      onlyThere,
                    ),
                    _section('In both, but different', both),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!d.isEmpty)
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: const Text('Sync'),
          ),
      ],
    );
  }
}
