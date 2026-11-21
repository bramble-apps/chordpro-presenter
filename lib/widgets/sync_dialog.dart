import 'package:flutter/material.dart';

import '../cloud_sync.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// The app's backups and sync (set up in main.dart; null in tests).
CloudSync? cloudSync;

/// ☰ → Backup & sync…: folder backups and WebDAV sync.
Future<void> showSyncSettings(BuildContext context) async {
  final sync = cloudSync;
  if (sync == null) return;
  final folderOk = await CloudSync.folderBackupAvailable();
  String? defaultFolder;
  if (folderOk) defaultFolder = (await sync.checkFolder('')).$1;
  if (!context.mounted) return;
  await showAppDialog<void>(
    context: context,
    builder: (_) => _SyncDialog(
      sync: sync,
      folderOk: folderOk,
      defaultFolder: defaultFolder ?? '',
    ),
  );
}

class _SyncDialog extends StatefulWidget {
  final CloudSync sync;
  final bool folderOk;
  final String defaultFolder;
  const _SyncDialog({
    required this.sync,
    required this.folderOk,
    required this.defaultFolder,
  });

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  SyncSettings get s => widget.sync.settings;
  late final _folder = TextEditingController(text: s.backupFolder);
  late final _url = TextEditingController(text: s.davUrl);
  late final _user = TextEditingController(text: s.davUser);
  late final _pass = TextEditingController(text: s.davPassword);
  late final _davFolder = TextEditingController(text: s.davFolder);
  bool _showPass = false;
  String? _test;
  bool _testing = false;

  @override
  void dispose() {
    for (final c in [_folder, _url, _user, _pass, _davFolder]) {
      c.dispose();
    }
    super.dispose();
  }

  void _read() {
    s
      ..backupFolder = _folder.text.trim()
      ..davUrl = _url.text.trim()
      ..davUser = _user.text.trim()
      ..davPassword = _pass.text
      ..davFolder = _davFolder.text.trim().isEmpty
          ? 'ChordPro Presenter'
          : _davFolder.text.trim();
  }

  Future<void> _save() async {
    _read();
    await widget.sync.saveSettings();
  }

  Future<void> _force(SyncForce force) async {
    final push = force == SyncForce.push;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(push ? 'Re-upload everything?' : 'Re-download everything?'),
        content: Text(
          push
              ? 'Every song, setlist and tag on this device is sent again, '
                    'replacing the service’s copy (other devices get this '
                    'version on their next sync). Songs only on the service '
                    'still come here.'
              : 'Every song, setlist and tag is fetched from the service '
                    'again, replacing this device’s copy. Songs only on '
                    'this device that were never sent are sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(push ? 'Re-upload' : 'Re-download'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save();
    await widget.sync.syncNow(force: force);
  }

  String _when(DateTime? t) {
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return ' · ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget status(String text, bool failed, DateTime? at) => text.isEmpty
        ? const SizedBox.shrink()
        : Text(
            '$text${_when(at)}',
            style: small?.copyWith(color: failed ? scheme.error : null),
          );
    Widget heading(IconData icon, String text) => Row(
      spacing: 8,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        Text(text, style: theme.textTheme.titleMedium),
      ],
    );

    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) => AlertDialog(
        title: const Text('Backup & sync'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                // ---- Folder backup ----
                heading(BrambleIcons.folders, 'Folder backup'),
                if (!widget.folderOk)
                  Text(
                    'Saving backups to a folder works in the computer app. '
                    'Here, use sync below (it keeps a copy online too), or '
                    '☰ → Export for a backup file.',
                    style: small,
                  )
                else ...[
                  Text(
                    'The whole library (songs, setlists, PDFs) as a backup '
                    'file, saved after changes. Choose a folder that’s '
                    'synced (Drime, Dropbox, Nextcloud, Syncthing…) and the '
                    'backups go online too.',
                    style: small,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Back up automatically'),
                    value: s.backupOn,
                    onChanged: (v) async {
                      setState(() => s.backupOn = v);
                      await _save();
                      if (v) widget.sync.backupNow();
                    },
                  ),
                  TextField(
                    controller: _folder,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: 'Folder',
                      hintText: widget.defaultFolder,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  Row(
                    spacing: 10,
                    children: [
                      const Text('Keep'),
                      AppDropdown<int>(
                        value: s.keep,
                        items: [
                          for (final n in [5, 10, 20, 50])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: (v) {
                          setState(() => s.keep = v ?? 10);
                          _save();
                        },
                      ),
                      const Text('newest backups'),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: widget.sync.backingUp
                            ? null
                            : () async {
                                await _save();
                                await widget.sync.backupNow();
                              },
                        child: const Text('Back up now'),
                      ),
                    ],
                  ),
                  status(
                    widget.sync.backupStatus,
                    widget.sync.backupFailed,
                    widget.sync.lastBackup,
                  ),
                ],
                const Divider(height: 24),

                // ---- WebDAV sync ----
                heading(BrambleIcons.arrowsClockwise, 'Sync (WebDAV)'),
                Text(
                  'Keeps the library the same on every device signed in to '
                  'the same account, song by song. Works with Koofr '
                  '(free), Nextcloud, Box, a NAS… Where the service has app '
                  'passwords (Koofr: Preferences → Password → App '
                  'passwords), make one for this app and use it here.',
                  style: small,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync this library'),
                  value: s.davOn,
                  onChanged: (v) async {
                    _read();
                    if (v && !s.davReady) {
                      setState(
                        () => _test =
                            'Fill in the address and user name '
                            'first.',
                      );
                      return;
                    }
                    setState(() => s.davOn = v);
                    await _save();
                    if (v) widget.sync.syncNow();
                  },
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in davPresets.entries)
                      ActionChip(
                        label: Text(e.key),
                        onPressed: () => setState(() => _url.text = e.value),
                      ),
                  ],
                ),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV address',
                    hintText: 'https://…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(
                    labelText: 'User name (often your email)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: _pass,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: 'Password (or app password)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: _showPass ? 'Hide' : 'Show',
                      icon: Icon(
                        _showPass ? BrambleIcons.eyeSlash : BrambleIcons.eye,
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
                TextField(
                  controller: _davFolder,
                  decoration: const InputDecoration(
                    labelText: 'Folder on the service',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                Row(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _testing
                          ? null
                          : () async {
                              _read();
                              setState(() {
                                _testing = true;
                                _test = null;
                              });
                              final err = await widget.sync.testConnection();
                              if (!mounted) return;
                              setState(() {
                                _testing = false;
                                _test = err ?? 'Connected.';
                              });
                              if (err == null) await _save();
                            },
                      child: const Text('Test'),
                    ),
                    FilledButton.tonal(
                      onPressed: widget.sync.syncing || !s.davOn
                          ? null
                          : () async {
                              await _save();
                              await widget.sync.syncNow();
                            },
                      child: const Text('Sync now'),
                    ),
                    if (widget.sync.syncing)
                      const SizedBox.square(
                        dimension: 18,
                        child: AppSpinner(strokeWidth: 2),
                      ),
                  ],
                ),
                // When the two sides seem out of step: one side's version
                // everywhere.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      icon: const Icon(BrambleIcons.cloudArrowUp, size: 18),
                      label: const Text('Re-upload everything'),
                      onPressed: widget.sync.syncing || !s.davOn
                          ? null
                          : () => _force(SyncForce.push),
                    ),
                    TextButton.icon(
                      icon: const Icon(BrambleIcons.cloudArrowDown, size: 18),
                      label: const Text('Re-download everything'),
                      onPressed: widget.sync.syncing || !s.davOn
                          ? null
                          : () => _force(SyncForce.pull),
                    ),
                  ],
                ),
                if (_test != null)
                  Text(
                    _test!,
                    style: small?.copyWith(
                      color: _test == 'Connected.' ? null : scheme.error,
                    ),
                  ),
                status(
                  widget.sync.syncStatus,
                  widget.sync.syncFailed,
                  widget.sync.lastSync,
                ),
                Text('The password is kept on this device only.', style: small),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await _save();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
