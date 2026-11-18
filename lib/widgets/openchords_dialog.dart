// OpenChords in the app (see openchords.dart). Settings → OpenChords (also
// ☰ → OpenChords…) has all of it: what's shared and its links, sharing a
// setlist or the songs with a tag (a link others open in any OpenChords
// app, kept in sync), opening someone else's link,
// syncing, and this device's OpenChords ID. + → "Add from OpenChords
// link…" opens a link too.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../eink.dart';
import '../openchords.dart';
import '../state.dart';
import 'qr_share.dart';

/// [text] with "{apps}" as a small (i) listing the apps that open
/// OpenChords links.
Widget openChordsAppsText(String text, TextStyle? style) {
  final parts = text.split('{apps}');
  return Text.rich(
    TextSpan(
      style: style,
      children: [
        for (final (i, p) in parts.indexed) ...[
          TextSpan(text: p),
          if (i < parts.length - 1)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Tooltip(
                message:
                    'OpenChords-compatible apps: ChordPro Presenter, '
                    'JustChords, OpenSongApp',
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: style?.color,
                  semanticLabel: 'Apps that open OpenChords links',
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

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
    builder: (_) => _ShareDialog(
      model: model,
      localId: set.id,
      name: set.name,
      what: 'setlist',
      intro:
          'Puts "${set.name}" and its songs online under a link that opens '
          'in any OpenChords-compatible app {apps}. Changes sync both ways.',
      share: (readonly) =>
          shareSetlistOnOpenChords(model, set, readonly: readonly),
    ),
  );
}

/// Share the open library (all its songs, setlists and tags), or (already
/// shared) its link and sync.
Future<void> showOpenChordsShareLibrary(
  BuildContext context,
  PresenterModel model,
) async {
  if (!openChordsAvailable) return _unavailable(context);
  final name = model.currentLibrary.name;
  await showAppDialog<void>(
    context: context,
    builder: (_) => _ShareDialog(
      model: model,
      localId: model.libraryId,
      name: name,
      what: 'library',
      intro:
          'Puts the whole "$name" library online: its ${model.songs.length} '
          'songs, ${model.setlists.length} setlists and tags. Others join it '
          'with the link in any OpenChords-compatible app {apps}. Changes '
          'sync both ways.',
      share: (readonly) => shareLibraryOnOpenChords(model, readonly: readonly),
    ),
  );
}

/// Share the songs with [tag] as an OpenChords song folder, or (already
/// shared) its link and sync.
Future<void> showOpenChordsShareTag(
  BuildContext context,
  PresenterModel model,
  Tag tag,
) async {
  if (!openChordsAvailable) return _unavailable(context);
  final count = model.songs.where((s) => s.tags.contains(tag.id)).length;
  await showAppDialog<void>(
    context: context,
    builder: (_) => _ShareDialog(
      model: model,
      localId: tag.id,
      name: tag.name,
      what: 'song folder',
      intro:
          'Puts the $count song${count == 1 ? '' : 's'} tagged "${tag.name}" '
          'online as a song folder that opens in any OpenChords-compatible '
          'app {apps}. Songs you tag later are added, and edits sync both '
          'ways.',
      share: (readonly) => shareTagOnOpenChords(model, tag, readonly: readonly),
    ),
  );
}

class _ShareDialog extends StatefulWidget {
  final PresenterModel model;
  final String localId, name, what, intro;
  final Future<OpenChordsLink> Function(bool readonly) share;
  const _ShareDialog({
    required this.model,
    required this.localId,
    required this.name,
    required this.what,
    required this.intro,
    required this.share,
  });

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  OpenChordsLink? get _link => widget.model.openChordsLinkFor(widget.localId);
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
    await widget.share(!_othersEdit);
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
        content: Text(
          'This ${widget.what} stops syncing with OpenChords. The shared '
          'copy stays online for anyone who has the link.',
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
              openChordsAppsText(widget.intro, muted),
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
              _LinkBox(link: link.link, title: widget.name),
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
///
/// [newLibrary]: offered as its own library first (Libraries → Join a
/// shared library…).
Future<Setlist?> showOpenChordsOpen(
  BuildContext context,
  PresenterModel model, {
  bool newLibrary = false,
  String? linkText,
}) async {
  if (!openChordsAvailable) {
    await _unavailable(context);
    return null;
  }
  // A link on the clipboard fills itself in (not in a browser, which
  // asks first).
  String start = linkText ?? '';
  if (start.isEmpty) {
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
  }
  if (!context.mounted) return null;
  final link = await showAppDialog<OpenChordsLink>(
    context: context,
    builder: (_) =>
        _OpenDialog(model: model, start: start, newLibrary: newLibrary),
  );
  if (link == null || link.kind != OpenChordsKind.setlist) return null;
  return model.setlistById(link.localId);
}

class _OpenDialog extends StatefulWidget {
  final PresenterModel model;
  final String start;
  final bool newLibrary;
  const _OpenDialog({
    required this.model,
    required this.start,
    this.newLibrary = false,
  });

  @override
  State<_OpenDialog> createState() => _OpenDialogState();
}

class _OpenDialogState extends State<_OpenDialog> {
  late final _text = TextEditingController(text: widget.start);
  late bool _asLibrary = widget.newLibrary;
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

  Future<void> _import() async {
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
    if (_asLibrary) {
      // A library of its own, joined to the whole folder.
      final title = (folder['title'] as String?)?.trim() ?? '';
      setState(() => _busy = true);
      await m.createLibrary(title.isEmpty ? 'Shared library' : title);
      final link = m.importOpenChords(
        id,
        folder,
        isOwner: folder['isOwner'] == true,
        asLibrary: true,
      );
      if (mounted) Navigator.pop(context, link);
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
      title: Text(
        _asLibrary ? 'Join a shared library' : 'Open an OpenChords link',
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste the OpenChords link someone sent you.', style: muted),
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
            if (f != null && !known && !_busy) ...[
              const SizedBox(height: 4),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.library_add_outlined, size: 18),
                    label: Text('Into this library'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text('As a new library'),
                  ),
                ],
                selected: {_asLibrary},
                onSelectionChanged: (v) => setState(() => _asLibrary = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                _asLibrary
                    ? 'A library of its own, kept in sync with the shared '
                          'one: songs, setlists and tags.'
                    : isSet
                    ? 'Added to "${widget.model.currentLibrary.name}" as a '
                          'setlist, kept in sync.'
                    : 'Added to "${widget.model.currentLibrary.name}", its '
                          'songs tagged "${(f['title'] as String?)?.trim() ?? 'OpenChords'}", '
                          'kept in sync.',
                style: muted,
              ),
            ],
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
          child: Text(
            known
                ? 'Sync'
                : _asLibrary
                ? 'Join as new library'
                : 'Add to library',
          ),
        ),
      ],
    );
  }
}

// ---- Settings → OpenChords ----

/// Everything OpenChords: what's shared (links, sync, read-only, stop),
/// sharing a setlist or a tag, opening a link, syncing on its own, and
/// this device's OpenChords ID.
Future<void> showOpenChordsSettings(
  BuildContext context,
  PresenterModel model,
) => showAppDialog<void>(
  context: context,
  builder: (_) => _OpenChordsPage(model: model),
);

class _OpenChordsPage extends StatefulWidget {
  final PresenterModel model;
  const _OpenChordsPage({required this.model});

  @override
  State<_OpenChordsPage> createState() => _OpenChordsPageState();
}

class _OpenChordsPageState extends State<_OpenChordsPage> {
  PresenterModel get m => widget.model;
  bool _busy = false;
  String? _status;
  String? _error;

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final status = await job();
      if (mounted) setState(() => _status = status);
    } on OpenChordsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('OpenChords: $e');
      if (mounted) {
        setState(
          () => _error = 'Couldn\'t reach OpenChords. Check the connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncAll() => _run(() async {
    final problem = await syncAllOpenChords(m);
    if (problem != null) throw OpenChordsException(problem);
    return 'Everything is in sync';
  });

  Future<void> _syncOne(OpenChordsLink link, {bool? readonly}) => _run(
    () async => (await syncOpenChords(m, link, readonly: readonly)).summary,
  );

  Future<void> _stop(OpenChordsLink link) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop syncing?'),
        content: const Text(
          'It stops syncing with OpenChords and stays here as it is. The '
          'shared copy stays online for anyone who has the link.',
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
    if (ok == true) m.removeOpenChordsLink(link);
  }

  Future<void> _changeId() async {
    final text = TextEditingController(text: m.openChordsUserId);
    final id = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OpenChords ID'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Give your other devices the same ID to make them owners of '
                'what you shared, too. Copy it from the device that shared '
                'and paste it here.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
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
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    if (id == null) return;
    final ok = openChordsFolderId(id);
    if (ok == null) {
      if (mounted) setState(() => _error = 'That isn\'t an OpenChords ID.');
      return;
    }
    m.openChordsUserId = ok;
  }

  String _ago(DateTime? t) {
    if (t == null) return 'not synced yet';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'synced just now';
    if (d.inMinutes < 60) return 'synced ${d.inMinutes} min ago';
    if (d.inHours < 24) return 'synced ${d.inHours} h ago';
    return 'synced ${d.inDays} d ago';
  }

  Widget _row(OpenChordsLink link) {
    final name = openChordsLocalName(m, link);
    final role = link.isOwner
        ? (link.readonly ? 'yours, others view only' : 'yours, others can edit')
        : (link.readonly ? 'read-only' : 'shared with you');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (link.kind) {
        OpenChordsKind.setlist => Icons.queue_music,
        OpenChordsKind.folder => Icons.sell_outlined,
        OpenChordsKind.library => Icons.library_music_outlined,
      }),
      title: Text(name ?? '${link.title} (removed here)'),
      subtitle: Text(
        [
          switch (link.kind) {
            OpenChordsKind.setlist => 'Setlist',
            OpenChordsKind.folder => 'Songs tagged "${name ?? link.title}"',
            OpenChordsKind.library => 'This whole library',
          },
          role,
          _ago(link.lastSync),
        ].join(' · '),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Options',
        enabled: !_busy,
        onSelected: (v) async {
          switch (v) {
            case 'copy':
              await Clipboard.setData(ClipboardData(text: link.link));
              if (mounted) setState(() => _status = 'Link copied');
            case 'qr':
              await showTextQr(context, name ?? link.title, link.link);
            case 'sync':
              await _syncOne(link);
            case 'edit':
              await _syncOne(link, readonly: !link.readonly);
            case 'stop':
              await _stop(link);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'copy', child: Text('Copy link')),
          const PopupMenuItem(value: 'qr', child: Text('QR code')),
          if (name != null)
            const PopupMenuItem(value: 'sync', child: Text('Sync now')),
          if (link.isOwner && name != null)
            CheckedPopupMenuItem(
              value: 'edit',
              checked: !link.readonly,
              child: const Text('Others can edit'),
            ),
          const PopupMenuItem(value: 'stop', child: Text('Stop syncing')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final available = openChordsAvailable;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final links = m.openChordsLinks;
        return AlertDialog(
          title: const Text('OpenChords settings'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  openChordsAppsText(
                    'Share setlists and songs with a link that opens in any '
                    'OpenChords-compatible app {apps}. Changes sync both '
                    'ways. Share from a library\'s, setlist\'s or tag\'s '
                    'menu.',
                    muted,
                  ),
                  if (!available) ...[
                    const SizedBox(height: 12),
                    Text(
                      'This build has no OpenChords login, so it can\'t reach '
                      'the OpenChords server.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Shared and joined in this library',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (links.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('Sync all now'),
                            onPressed: _busy ? null : _syncAll,
                          ),
                      ],
                    ),
                    if (links.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text('Nothing shared yet.', style: muted),
                      )
                    else
                      for (final l in links) _row(l),
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          if (_busy) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: AppSpinner(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text('Syncing…', style: muted),
                          ] else if (_error != null)
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            )
                          else if (_status != null)
                            Expanded(child: Text(_status!, style: muted)),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sync automatically'),
                      subtitle: const Text(
                        'When the app opens, then every few minutes',
                      ),
                      value: m.settings.openChordsAutoSync,
                      onChanged: (v) =>
                          m.updateSettings((s) => s.openChordsAutoSync = v),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('This device\'s OpenChords ID'),
                      subtitle: SelectableText(
                        m.openChordsUserId,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: m.openChordsUserId),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Use another device\'s ID',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _changeId,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

// ---- Libraries → New library ----

/// New library: a personal one, or an OpenChords one (started here and
/// shared, or joined with someone's link).
Future<void> showNewLibrary(BuildContext context, PresenterModel model) async {
  // (What comes next opens here, once the dialog is gone.)
  final next = await showAppDialog<String>(
    context: context,
    builder: (_) => _NewLibraryDialog(model: model),
  );
  if (next == null || !context.mounted) return;
  if (next == 'shared') {
    // Its link, to send to the others.
    await showOpenChordsShareLibrary(context, model);
  } else if (next.startsWith('join:')) {
    await showOpenChordsOpen(
      context,
      model,
      newLibrary: true,
      linkText: next.substring(5),
    );
  }
}

class _NewLibraryDialog extends StatefulWidget {
  final PresenterModel model;
  const _NewLibraryDialog({required this.model});

  @override
  State<_NewLibraryDialog> createState() => _NewLibraryDialogState();
}

class _NewLibraryDialogState extends State<_NewLibraryDialog> {
  final _name = TextEditingController();
  final _link = TextEditingController();
  bool _openChords = false;
  bool _join = false;
  bool _othersEdit = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  bool get _ready => _openChords && _join
      ? openChordsFolderId(_link.text) != null
      : _name.text.trim().isNotEmpty;

  Future<void> _create() async {
    final m = widget.model;
    final nav = Navigator.of(context);
    if (_openChords && _join) {
      nav.pop('join:${_link.text.trim()}');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await m.createLibrary(_name.text.trim());
    if (!_openChords) {
      nav.pop();
      return;
    }
    try {
      await shareLibraryOnOpenChords(m, readonly: !_othersEdit);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'The library is made, but OpenChords couldn\'t be reached. '
              'Share it later from its ⋮ menu.';
        });
      }
      return;
    }
    nav.pop('shared');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final available = openChordsAvailable;
    return AlertDialog(
      title: const Text('New library'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                  value: false,
                  icon: Icon(Icons.folder_outlined, size: 18),
                  label: Text('Personal'),
                ),
                ButtonSegment(
                  value: true,
                  enabled: available,
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: const Text('OpenChords'),
                ),
              ],
              selected: {_openChords},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() => _openChords = v.first),
            ),
            const SizedBox(height: 12),
            if (!_openChords)
              Text('Only on this device (and your backups).', style: muted)
            else ...[
              openChordsAppsText(
                'Shared online and kept in sync with anyone who has its '
                'link, in any OpenChords-compatible app {apps}.',
                muted,
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.add, size: 18),
                    label: Text('Start one'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.link, size: 18),
                    label: Text('Join with a link'),
                  ),
                ],
                selected: {_join},
                onSelectionChanged: _busy
                    ? null
                    : (v) => setState(() => _join = v.first),
              ),
            ],
            const SizedBox(height: 12),
            if (_openChords && _join)
              TextField(
                controller: _link,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://openchords.net/?fld=…',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _ready ? _create() : null,
              )
            else
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'e.g. French songs',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _ready && !_busy ? _create() : null,
              ),
            if (_openChords && !_join)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Others can edit'),
                subtitle: const Text('Off: they can view and import only'),
                value: _othersEdit,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _othersEdit = v),
              ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: AppSpinner(strokeWidth: 2),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_error == null ? 'Cancel' : 'Close'),
        ),
        if (_error == null)
          FilledButton(
            onPressed: _ready && !_busy ? _create : null,
            child: Text(_openChords && _join ? 'Join' : 'Create'),
          ),
      ],
    );
  }
}
