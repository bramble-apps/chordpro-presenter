// OpenChords in the app (see openchords.dart): a setlist's ⋯ → "Share
// with OpenChords…" makes a link others open in JustChords, OpenSongApp or
// this app, and keeps it in sync; New… → "Open an OpenChords link…" brings
// in someone else's.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../eink.dart';
import '../openchords.dart';
import '../state.dart';
import 'qr_share.dart';

Future<void> _unavailable(BuildContext context) => showAppDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('OpenChords'),
    content: const Text(
      'This build of ChordPro Presenter has no OpenChords login, so it can\'t '
      'reach the OpenChords server.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  ),
);

/// Share [set] on OpenChords, or (already shared) its link and sync.
Future<void> showOpenChordsShare(
  BuildContext context,
  PresenterModel model,
  Setlist set,
) async {
  if (!openChordsAvailable) return _unavailable(context);
  await showAppDialog<void>(
    context: context,
    builder: (_) => _ShareDialog(model: model, set: set),
  );
}

class _ShareDialog extends StatefulWidget {
  final PresenterModel model;
  final Setlist set;
  const _ShareDialog({required this.model, required this.set});

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  OpenChordsLink? get _link => widget.model.openChordsLinkFor(widget.set.id);
  bool _othersEdit = true;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Already shared: in step right away.
    if (_link != null) _sync();
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await job();
      if (mounted) setState(() => _status = status);
    } on OpenChordsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t reach OpenChords. Check the connection.',
        );
      }
      debugPrint('OpenChords: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
    await shareSetlistOnOpenChords(
      widget.model,
      widget.set,
      readonly: !_othersEdit,
    );
    return 'Shared';
  });

  Future<void> _sync({bool? readonly}) => _run(() async {
    final link = _link;
    if (link == null) return '';
    final merge = await syncOpenChords(widget.model, link, readonly: readonly);
    return merge.summary;
  });

  Future<void> _stop() async {
    final link = _link;
    if (link == null) return;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop syncing?'),
        content: const Text(
          'This setlist stops syncing with OpenChords. The shared copy stays '
          'online for anyone who has the link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop syncing'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.model.removeOpenChordsLink(link);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text(
        link == null ? 'Share with OpenChords' : 'Shared on OpenChords',
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (link == null) ...[
              Text(
                'Puts "${widget.set.name}" and its songs online under a link. '
                'Anyone with the link can open it in JustChords, OpenSongApp '
                'or ChordPro Presenter, and changes sync both ways.',
                style: muted,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Others can edit'),
                subtitle: const Text('Off: they can view and import only'),
                value: _othersEdit,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _othersEdit = v),
              ),
            ] else ...[
              _LinkBox(link: link.link, title: widget.set.name),
              const SizedBox(height: 8),
              if (link.isOwner)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Others can edit'),
                  subtitle: const Text('Off: they can view and import only'),
                  value: !link.readonly,
                  onChanged: _busy ? null : (v) => _sync(readonly: !v),
                )
              else if (link.readonly)
                Text('Read-only: only its owner can change it.', style: muted),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  if (_busy) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: AppSpinner(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(link == null ? 'Sharing…' : 'Syncing…', style: muted),
                  ] else if (_error != null)
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    )
                  else if (_status != null && _status!.isNotEmpty)
                    Expanded(child: Text(_status!, style: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (link == null) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _share,
            child: const Text('Share'),
          ),
        ] else ...[
          TextButton(
            onPressed: _busy ? null : _stop,
            child: const Text('Stop syncing'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _sync(),
            child: const Text('Sync now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ],
    );
  }
}

class _LinkBox extends StatelessWidget {
  final String link, title;
  const _LinkBox({required this.link, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              link,
              maxLines: 1,
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
          IconButton(
            tooltip: 'QR code',
            icon: const Icon(Icons.qr_code_2, size: 20),
            onPressed: () => showTextQr(context, title, link),
          ),
        ],
      ),
    );
  }
}

/// New… → "Open an OpenChords link…": brings in a shared setlist or song
/// folder. Returns the setlist made, if it was one.
Future<Setlist?> showOpenChordsOpen(
  BuildContext context,
  PresenterModel model,
) async {
  if (!openChordsAvailable) {
    await _unavailable(context);
    return null;
  }
  // A link on the clipboard fills itself in (not in a browser, which
  // asks first).
  String start = '';
  try {
    final clip = kIsWeb
        ? null
        : await Clipboard.getData(Clipboard.kTextPlain)
              .timeout(const Duration(milliseconds: 500));
    if (openChordsFolderId(clip?.text ?? '') != null &&
        (clip?.text ?? '').contains('openchords')) {
      start = clip!.text!.trim();
    }
  } catch (_) {}
  if (!context.mounted) return null;
  final link = await showAppDialog<OpenChordsLink>(
    context: context,
    builder: (_) => _OpenDialog(model: model, start: start),
  );
  if (link == null || link.kind != OpenChordsKind.setlist) return null;
  return model.setlistById(link.localId);
}

class _OpenDialog extends StatefulWidget {
  final PresenterModel model;
  final String start;
  const _OpenDialog({required this.model, required this.start});

  @override
  State<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<_OpenDialog> {
  late final _text = TextEditingController(text: widget.start);
  late final _client = openChordsClient(
    deviceId: widget.model.openChordsUserId,
  );
  bool _busy = false;
  String? _error;
  String? _folderId;
  Map<String, dynamic>? _folder;

  @override
  void initState() {
    super.initState();
    if (widget.start.isNotEmpty) _look();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    final id = openChordsFolderId(_text.text);
    if (id == null) {
      setState(() => _error = 'That isn\'t an OpenChords link.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _folder = null;
    });
    try {
      final f = await _client.getFolder(id, widget.model.openChordsUserId);
      if (!mounted) return;
      setState(() {
        _folderId = id;
        _folder = f;
        if (f == null) _error = 'Nothing is shared under that link.';
      });
    } on OpenChordsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t reach OpenChords. Check the connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _import() {
    final folder = _folder, id = _folderId;
    if (folder == null || id == null) return;
    final m = widget.model;
    // Brought in before: a sync instead of a second copy.
    final had = m.openChordsLinks.where((l) => l.folderId == id).firstOrNull;
    if (had != null) {
      Navigator.pop(context, had);
      syncOpenChords(m, had, client: _client).ignore();
      return;
    }
    final link = m.importOpenChords(
      id,
      folder,
      isOwner: folder['isOwner'] == true,
    );
    Navigator.pop(context, link);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final f = _folder;
    final songs = (f?['songs'] as List?)?.length ?? 0;
    final sets = (f?['setlists'] as List?)?.length ?? 0;
    final isSet = f?['type'] == 'setlist' && sets > 0;
    final known =
        _folderId != null &&
        widget.model.openChordsLinks.any((l) => l.folderId == _folderId);
    return AlertDialog(
      title: const Text('Open an OpenChords link'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a link someone shared from JustChords, OpenSongApp or '
              'ChordPro Presenter.',
              style: muted,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.start.isEmpty,
              decoration: InputDecoration(
                hintText: 'https://openchords.net/?fld=…',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Look',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _busy ? null : _look,
                ),
              ),
              onSubmitted: (_) => _look(),
            ),
            const SizedBox(height: 14),
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: AppSpinner(strokeWidth: 2),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (f != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSet ? Icons.queue_music : Icons.folder_outlined,
                ),
                title: Text(
                  (f['title'] as String?)?.trim().isNotEmpty == true
                      ? f['title'] as String
                      : 'Shared songs',
                ),
                subtitle: Text(
                  [
                    isSet ? 'Setlist' : 'Song folder',
                    '$songs song${songs == 1 ? '' : 's'}',
                    if (!isSet && sets > 0)
                      '$sets setlist${sets == 1 ? '' : 's'}',
                    if (f['readonly'] == true && f['isOwner'] != true)
                      'read-only',
                    if (known) 'already here',
                  ].join(' · '),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: f == null || _busy ? null : _import,
          child: Text(known ? 'Sync' : 'Add to library'),
        ),
      ],
    );
  }
}
