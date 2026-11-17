import 'package:flutter/material.dart';

import '../state.dart';
import '../eink.dart';

/// Asks how to import [batch]: restore the whole library from a backup, or
/// add to it, with what to do about songs and setlists it already has.
/// Null: cancelled. Nothing to ask (all new, not a backup): the defaults
/// without a dialog.
Future<ImportOptions?> askImportOptions(
  BuildContext context,
  PresenterModel model,
  ImportBatch batch,
) async {
  final sameSongs = batch.songs.where((s) => model.matchingSong(s) != null);
  final sameSets = batch.setlists.where(
    (s) => model.matchingSetlist(s) != null,
  );
  final nSongs = sameSongs.length, nSets = sameSets.length;
  if (!batch.isBackup && nSongs == 0 && nSets == 0) {
    return const ImportOptions();
  }
  var restore = false;
  var songs = ImportSongs.newer;
  var setlists = ImportSetlists.merge;
  String count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
  return showAppDialog<ImportOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) {
        final text = Theme.of(context).textTheme;
        Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: text.titleSmall),
        );
        return AlertDialog(
          title: const Text('Import'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [
                      count(batch.songs.length, 'song'),
                      if (batch.setlists.isNotEmpty)
                        count(batch.setlists.length, 'setlist'),
                      if (batch.trash.isNotEmpty)
                        '${batch.trash.length} in Trash',
                    ].join(' · '),
                  ),
                  if (batch.isBackup) ...[
                    heading('How'),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Add to library'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Restore completely'),
                        ),
                      ],
                      selected: {restore},
                      onSelectionChanged: (v) =>
                          setLocal(() => restore = v.first),
                    ),
                    if (restore)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Replaces every song, setlist, tag and the Trash '
                          'in “${model.currentLibrary.name}” with the '
                          'backup’s.',
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                  if (!restore && nSongs > 0) ...[
                    heading('${count(nSongs, 'song')} already in the library'),
                    SegmentedButton<ImportSongs>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ImportSongs.skip,
                          label: Text('Skip'),
                        ),
                        ButtonSegment(
                          value: ImportSongs.newer,
                          label: Text('If newer'),
                        ),
                        ButtonSegment(
                          value: ImportSongs.replace,
                          label: Text('Replace'),
                        ),
                      ],
                      selected: {songs},
                      onSelectionChanged: (v) =>
                          setLocal(() => songs = v.first),
                    ),
                  ],
                  if (!restore && nSets > 0) ...[
                    heading(
                      '${count(nSets, 'setlist')} already in the library',
                    ),
                    SegmentedButton<ImportSetlists>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ImportSetlists.merge,
                          label: Text('Merge'),
                        ),
                        ButtonSegment(
                          value: ImportSetlists.replace,
                          label: Text('Replace'),
                        ),
                        ButtonSegment(
                          value: ImportSetlists.skip,
                          label: Text('Skip'),
                        ),
                      ],
                      selected: {setlists},
                      onSelectionChanged: (v) =>
                          setLocal(() => setlists = v.first),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                ImportOptions(
                  restore: restore,
                  songs: songs,
                  setlists: setlists,
                ),
              ),
              child: Text(restore ? 'Restore' : 'Import'),
            ),
          ],
        );
      },
    ),
  );
}
