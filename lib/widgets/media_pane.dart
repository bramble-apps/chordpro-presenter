// The media pane in presentation mode: the media library (pictures,
// videos, audio, YouTube and other links) in folders, along the bottom of
// the slides. Tap an item to play it on the projector, show it over the
// lyrics or make it the background; drag it onto a setlist to play it
// there. Files dropped on the window while it's open land here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser.dart';
import '../media.dart';
import '../media_library.dart';
import '../state.dart';
import '../themes.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// Whether the media pane is open (presentation mode).
final mediaPaneOpen = ValueNotifier(false);

/// The folder shown ("" = top); files dropped on the window go there.
final mediaPaneFolder = ValueNotifier('');

/// The pane's height along the bottom (drag its top edge).
final mediaPaneHeight = ValueNotifier(240.0);

/// Only this kind of item is shown (null: all).
final mediaPaneFilter = ValueNotifier<MediaKind?>(null);

/// The floating bottom toolbar's size: the pane leaves room to scroll
/// what's under it out from behind it.
final bottomBarSize = ValueNotifier(Size.zero);

/// Adds files dropped on the window (pictures, videos, audio) to the
/// folder shown; returns how many were added.
Future<int> addDroppedMedia(
  PresenterModel model,
  List<(String, Uint8List)> files,
) async {
  await model.loadMedia();
  var n = 0;
  for (final (name, bytes) in files) {
    final mime = mimeOfName(name);
    if (mime.isEmpty) continue;
    final ref = await MediaStore.add(name, mime, bytes);
    model.addMedia(MediaItem.fromFile(ref, folder: mediaPaneFolder.value));
    n++;
  }
  return n;
}

class MediaPane extends StatefulWidget {
  final PresenterModel model;
  final VoidCallback? onClose;

  /// Along the bottom of the window (a panel of its own, its height set
  /// by dragging its top edge). Otherwise it fills its place (phones'
  /// Media tab). Either way the tiles scroll up and down; dragging one
  /// sideways takes it out (onto a setlist or a folder).
  final bool horizontal;
  const MediaPane({
    super.key,
    required this.model,
    this.onClose,
    this.horizontal = false,
  });

  @override
  State<MediaPane> createState() => _MediaPaneState();
}

class _MediaPaneState extends State<MediaPane> {
  PresenterModel get model => widget.model;

  String get _folder => mediaPaneFolder.value;
  set _folder(String f) => mediaPaneFolder.value = f;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    model.loadMedia();
    mediaPaneFolder.addListener(_refresh);
    mediaPaneFilter.addListener(_refresh);
    bottomBarSize.addListener(_refresh);
  }

  @override
  void dispose() {
    mediaPaneFolder.removeListener(_refresh);
    mediaPaneFilter.removeListener(_refresh);
    bottomBarSize.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _importFiles() async {
    setState(() => _busy = true);
    try {
      final refs = await MediaStore.pickMany();
      for (final ref in refs) {
        model.addMedia(MediaItem.fromFile(ref, folder: _folder));
      }
    } catch (e) {
      _say("Couldn't add that file ($e).");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLink() async {
    // A link already copied is filled in (if the browser lets us read it).
    var clip = '';
    try {
      clip = (await Clipboard.getData('text/plain'))?.text?.trim() ?? '';
    } catch (_) {}
    if (!mounted) return;
    final url = await _askText(
      context,
      'Add a link',
      hint: 'YouTube or any web address',
      initial: Uri.tryParse(clip)?.hasScheme == true ? clip : '',
      action: 'Add',
    );
    if (url == null || url.isEmpty) return;
    final full = url.contains('://') ? url : 'https://$url';
    model.addMedia(MediaItem.fromUrl(full, folder: _folder));
  }

  Future<void> _newFolder() async {
    final name = await _askText(context, 'New folder', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    final clean = name.replaceAll('/', '-').trim();
    model.addMediaFolder(_folder.isEmpty ? clean : '$_folder/$clean');
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        // A folder that's gone (renamed, deleted): back to the top.
        if (_folder.isNotEmpty && !model.mediaFolders.contains(_folder)) {
          mediaPaneFolder.value = '';
        }
        final folders = [
          for (final f in model.mediaFolders)
            if (parentFolder(f) == _folder) f,
        ];
        final filter = mediaPaneFilter.value;
        final items = [
          for (final m in model.mediaItems)
            if (m.folder == _folder && (filter == null || m.kind == filter)) m,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final tiles = [
          for (final f in folders)
            _FolderTile(
              // Keyed, so a tile never keeps another one's picture after
              // a delete, move or filter.
              key: ValueKey('folder:$f'),
              model: model,
              path: f,
              onOpen: () => _folder = f,
            ),
          for (final m in items)
            _ItemTile(key: ValueKey('item:${m.id}'), model: model, item: m),
        ];
        final scheme = Theme.of(context).colorScheme;
        final radius = StyleExtras.of(context).panelRadius;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _filters(),
            if (model.live != null)
              _LiveBar(model: model, inline: widget.horizontal),
            if (_busy) const AppProgressBar(minHeight: 2),
            Expanded(
              child: tiles.isEmpty
                  ? _empty()
                  : Padding(
                      // E-ink: the grid ends above the toolbar (its page
                      // arrows in view), not under it.
                      padding: EdgeInsets.only(
                        bottom: isEink(context) && widget.horizontal
                            ? bottomBarSize.value.height + 14
                            : 0,
                      ),
                      child: GridView.builder(
                        // A new grid per folder and filter; within one, tiles
                        // are found by key, so a removed one never lingers.
                        key: ValueKey('grid:$_folder:${filter?.name}'),
                        // Along the bottom: room at the end to scroll the
                        // last row up from behind the floating toolbar.
                        padding: EdgeInsets.fromLTRB(
                          12,
                          2,
                          12,
                          12 +
                              (widget.horizontal && !isEink(context)
                                  ? bottomBarSize.value.height + 14
                                  : 0),
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 150,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.15,
                            ),
                        itemCount: tiles.length,
                        itemBuilder: (context, i) => tiles[i],
                        findChildIndexCallback: (key) {
                          final i = tiles.indexWhere((t) => t.key == key);
                          return i < 0 ? null : i;
                        },
                      ),
                    ),
            ),
          ],
        );
        if (!widget.horizontal) return body;
        // Along the bottom of the window, edge to edge (the toolbar floats
        // over it); its height set by dragging the handle on top.
        return Material(
          color: scheme.surfaceContainerHigh,
          elevation: inkE(6),
          shadowColor: scheme.shadow,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(inkR(radius)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _resizeHandle(),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }

  Widget _resizeHandle() {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => mediaPaneHeight.value =
            (mediaPaneHeight.value - d.delta.dy).clamp(150.0, 640.0),
        child: SizedBox(
          height: 12,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(inkR(2)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final path = _folder.isEmpty ? <String>[] : _folder.split('/');
    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.horizontal ? 0 : 6, 4, 4),
      child: Row(
        children: [
          // All media › Easter › Backgrounds: each one opens that folder,
          // and items dropped on it move there.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _crumb(
                    '',
                    'Media',
                    icon: BrambleIcons.images,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (var i = 0; i < path.length; i++) ...[
                    Icon(
                      BrambleIcons.caretRight,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    _crumb(
                      path.take(i + 1).join('/'),
                      path[i],
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            // Wide enough that its rows' titles stay on one line.
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 340),
            tooltip: 'Add',
            icon: const Icon(BrambleIcons.plus),
            onSelected: (v) => switch (v) {
              'files' => _importFiles(),
              'link' => _addLink(),
              _ => _newFolder(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'files',
                child: ListTile(
                  leading: Icon(BrambleIcons.images),
                  title: Text('Pictures, videos or audio…'),
                  subtitle: Text('Choose several at once'),
                ),
              ),
              PopupMenuItem(
                value: 'link',
                child: ListTile(
                  leading: Icon(BrambleIcons.monitorPlay),
                  title: Text('YouTube or other link…'),
                ),
              ),
              PopupMenuItem(
                value: 'folder',
                child: ListTile(
                  leading: Icon(BrambleIcons.folderPlus),
                  title: Text('New folder…'),
                ),
              ),
            ],
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Close media',
              icon: const Icon(BrambleIcons.x),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  /// All · Pictures · Videos · Audio · YouTube · Links (only the kinds
  /// there are, and only when there's more than one).
  Widget _filters() {
    final kinds = {for (final m in model.mediaItems) m.kind};
    final filter = mediaPaneFilter.value;
    if (kinds.length < 2 && filter == null) return const SizedBox.shrink();
    Widget chip(MediaKind? kind, String label) {
      final selected = filter == kind;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
          avatar: kind == null ? null : Icon(_iconOf(kind), size: 16),
          label: Text(label),
          selected: selected,
          onSelected: (_) => mediaPaneFilter.value = kind,
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        children: [
          chip(null, 'All'),
          for (final k in MediaKind.values)
            if (kinds.contains(k) || k == filter)
              chip(k, switch (k) {
                MediaKind.image => 'Pictures',
                MediaKind.video => 'Videos',
                MediaKind.audio => 'Audio',
                MediaKind.youtube => 'YouTube',
                MediaKind.link => 'Links',
              }),
        ],
      ),
    );
  }

  /// One step of the folder path.
  Widget _crumb(
    String folder,
    String label, {
    IconData? icon,
    TextStyle? style,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final here = folder == _folder;
    return DragTarget<MediaItem>(
      onWillAcceptWithDetails: (d) => d.data.folder != folder,
      onAcceptWithDetails: (d) => model.moveMedia(d.data, folder),
      builder: (context, over, _) => InkWell(
        borderRadius: BorderRadius.circular(inkR(8)),
        onTap: here ? null : () => _folder = folder,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: over.isEmpty ? null : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(inkR(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: style?.copyWith(
                  color: here ? null : scheme.primary,
                  decoration: here ? null : TextDecoration.underline,
                  decorationColor: scheme.primary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              BrambleIcons.fileArrowDown,
              size: 32,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                mediaPaneFilter.value != null
                    ? 'Nothing of this kind here.'
                    : _folder.isEmpty
                    ? 'No media yet. Drop pictures, videos or audio here, '
                          'or tap + (also for YouTube links).'
                    : 'This folder is empty. Drag media onto its name '
                          'above, drop files here, or tap +.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What's on the projector from the library: play / pause, start again,
/// a scrubber with the time (videos, audio and YouTube), and stop. Along
/// the bottom it's one row ([inline]); on phones the scrubber goes under
/// the buttons.
class _LiveBar extends StatefulWidget {
  final PresenterModel model;
  final bool inline;
  const _LiveBar({required this.model, this.inline = false});

  @override
  State<_LiveBar> createState() => _LiveBarState();
}

class _LiveBarState extends State<_LiveBar> {
  PresenterModel get model => widget.model;

  /// Where the scrubber is being dragged to (seconds).
  double? _drag;

  static String _clock(double s) {
    final t = s.isFinite && s > 0 ? s.round() : 0;
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, ss = (t % 60).toString();
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${ss.padLeft(2, '0')}'
        : '$m:${ss.padLeft(2, '0')}';
  }

  Widget _scrubber() => ValueListenableBuilder<(double, double)>(
    valueListenable: model.liveTime,
    builder: (context, t, _) {
      final (pos, dur) = t;
      final known = dur > 0;
      final at = (_drag ?? pos).clamp(0.0, known ? dur : 0.0);
      final style = Theme.of(context).textTheme.labelSmall
          ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
      return Row(
        children: [
          Text(_clock(at), style: style),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: known ? at : 0,
                max: known ? dur : 1,
                onChanged: known ? (v) => setState(() => _drag = v) : null,
                onChangeEnd: known
                    ? (v) {
                        model.seekLive(v);
                        setState(() => _drag = null);
                      }
                    : null,
              ),
            ),
          ),
          Text(known ? _clock(dur) : '–:––', style: style),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final live = model.live!;
    final scheme = Theme.of(context).colorScheme;
    final timed = switch (live.item.kind) {
      MediaKind.video || MediaKind.audio || MediaKind.youtube => true,
      _ => false,
    };
    final buttons = [
      if (timed) ...[
        IconButton(
          tooltip: live.playing ? 'Pause' : 'Play',
          visualDensity: VisualDensity.compact,
          icon: Icon(live.playing ? BrambleIcons.pause : BrambleIcons.play),
          onPressed: () => model.setLivePlaying(!live.playing),
        ),
        IconButton(
          tooltip: 'Start again',
          visualDensity: VisualDensity.compact,
          icon: const Icon(BrambleIcons.arrowCounterClockwise),
          onPressed: model.restartLive,
        ),
      ],
      IconButton(
        tooltip: 'Stop (back to the lyrics)',
        visualDensity: VisualDensity.compact,
        icon: const Icon(BrambleIcons.stop),
        onPressed: model.stopLive,
      ),
    ];
    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          live.item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Text(
          live.mode == LiveMode.overlay
              ? 'Over the lyrics'
              : 'On the projector',
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
    final icon = Icon(
      _iconOf(live.item.kind),
      size: 18,
      color: scheme.onPrimaryContainer,
    );
    final Widget content = widget.inline
        ? Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: title,
                ),
              ),
              const SizedBox(width: 4),
              ...buttons.take(buttons.length - 1),
              if (timed)
                Expanded(flex: 2, child: _scrubber())
              else
                const Spacer(),
              buttons.last,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Expanded(child: title),
                  ...buttons,
                ],
              ),
              if (timed)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _scrubber(),
                ),
            ],
          );
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(
          StyleExtras.of(context).panelRadius.clamp(6.0, 22.0),
        ),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: scheme.onPrimaryContainer),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onPrimaryContainer),
          child: content,
        ),
      ),
    );
  }
}

IconData _iconOf(MediaKind kind) => switch (kind) {
  MediaKind.image => BrambleIcons.image,
  MediaKind.video => BrambleIcons.filmStrip,
  MediaKind.audio => BrambleIcons.musicNote,
  MediaKind.youtube => BrambleIcons.monitorPlay,
  MediaKind.link => BrambleIcons.linkSimple,
};

class _FolderTile extends StatelessWidget {
  final PresenterModel model;
  final String path;
  final VoidCallback onOpen;
  const _FolderTile({
    super.key,
    required this.model,
    required this.path,
    required this.onOpen,
  });

  Future<void> _menu(BuildContext context, Offset at) async {
    final v = await _showMenuAt(context, at, const [
      PopupMenuItem(value: 'rename', child: Text('Rename…')),
      PopupMenuItem(value: 'delete', child: Text('Delete folder')),
    ]);
    if (!context.mounted) return;
    switch (v) {
      case 'rename':
        final name = await _askText(
          context,
          'Rename folder',
          initial: folderName(path),
          action: 'Rename',
        );
        if (name != null) model.renameMediaFolder(path, name);
      case 'delete':
        model.deleteMediaFolder(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = model.mediaItems
        .where((m) => m.folder == path || m.folder.startsWith('$path/'))
        .length;
    return DragTarget<MediaItem>(
      onAcceptWithDetails: (d) => model.moveMedia(d.data, path),
      builder: (context, over, _) => _Tile(
        highlight: over.isNotEmpty,
        onTap: onOpen,
        onMenu: (at) => _menu(context, at),
        picture: ColoredBox(
          color: scheme.primaryContainer,
          child: Center(
            child: Icon(
              BrambleIcons.folder,
              size: 52,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        name: folderName(path),
        tooltip: '$count item${count == 1 ? '' : 's'}',
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PresenterModel model;
  final MediaItem item;

  const _ItemTile({super.key, required this.model, required this.item});

  Future<void> _menu(BuildContext context, Offset at) async {
    final scheme = Theme.of(context).colorScheme;
    PopupMenuItem<String> entry(String v, IconData icon, String text) =>
        PopupMenuItem(
          value: v,
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(text),
            ],
          ),
        );
    final v = await _showMenuAt(context, at, [
      if (item.canProject)
        entry(
          'play',
          item.kind == MediaKind.audio
              ? BrambleIcons.play
              : BrambleIcons.presentation,
          item.kind == MediaKind.audio
              ? 'Play'
              : item.kind == MediaKind.image
              ? 'Show full screen'
              : 'Play full screen',
        ),
      if (item.canProject && item.kind != MediaKind.audio)
        entry('overlay', BrambleIcons.stack, 'Show over the lyrics'),
      if (item.canBeBackground)
        entry('background', BrambleIcons.imageSquare, 'Set as background'),
      if (item.url.isNotEmpty)
        entry('open', BrambleIcons.arrowSquareOut, 'Open in browser'),
      if (model.setlists.isNotEmpty)
        entry('setlist', BrambleIcons.listPlus, 'Add to setlist…'),
      const PopupMenuDivider(),
      entry('rename', BrambleIcons.pencilSimple, 'Rename…'),
      if (model.mediaFolders.isNotEmpty || item.folder.isNotEmpty)
        entry('move', BrambleIcons.folderSimpleDashed, 'Move to folder…'),
      entry(
        'export',
        BrambleIcons.downloadSimple,
        item.file == null ? 'Save link' : 'Save a copy',
      ),
      entry('delete', BrambleIcons.trash, 'Delete'),
    ]);
    if (!context.mounted || v == null) return;
    switch (v) {
      case 'play':
        model.showMedia(item, LiveMode.play);
      case 'overlay':
        model.showMedia(item, LiveMode.overlay);
      case 'background':
        model.showMedia(item, LiveMode.background);
      case 'open':
        openUrl(item.url);
      case 'setlist':
        await _addToSetlist(context);
      case 'rename':
        final name = await _askText(
          context,
          'Rename',
          initial: item.name,
          action: 'Rename',
        );
        if (name != null) model.renameMedia(item, name);
      case 'move':
        final to = await _pickFolder(context, model, item.folder);
        if (to != null) model.moveMedia(item, to);
      case 'export':
        await _export();
      case 'delete':
        await model.deleteMedia(item);
    }
  }

  Future<void> _addToSetlist(BuildContext context) async {
    final sets = [...model.setlists];
    final set = await showAppDialog<Setlist>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Add "${item.name}" to'),
        children: [
          for (final s in sets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (set != null) model.addMediaToSetlist(set, item);
  }

  Future<void> _export() async {
    final ref = item.file;
    if (ref == null) {
      downloadTextFile(
        item.exportName,
        '[InternetShortcut]\nURL=${item.url}\n',
        mime: 'text/plain',
      );
      return;
    }
    final bytes = await MediaStore.bytes(ref);
    if (bytes == null || bytes.isEmpty) return;
    downloadBytes(item.exportName, bytes, ref.mime);
  }

  @override
  Widget build(BuildContext context) {
    final live = model.live?.item.id == item.id;
    final tile = _Tile(
      highlight: live,
      onTap: null,
      onMenu: (at) => _menu(context, at),
      picture: _Thumb(item: item),
      kind: item.kind,
      name: item.name,
      tooltip: live ? 'On the projector' : item.kind.label,
    );
    return Draggable<MediaItem>(
      data: item,
      // Sideways drags take it out; up and down scroll the pane.
      affinity: Axis.horizontal,
      feedback: Material(
        elevation: inkE(8),
        borderRadius: BorderRadius.circular(inkR(10)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: 128, height: 72, child: _Thumb(item: item)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}

/// One tile: a picture with the name under it. Tapping (or right-clicking
/// / long-pressing) opens its menu; a folder's tap opens it.
class _Tile extends StatelessWidget {
  final bool highlight;
  final VoidCallback? onTap;
  final void Function(Offset at) onMenu;
  final Widget picture;
  final String name;
  final String tooltip;

  /// Shown as a small badge on the picture (items, not folders).
  final MediaKind? kind;

  const _Tile({
    required this.highlight,
    required this.onTap,
    required this.onMenu,
    required this.picture,
    required this.name,
    required this.tooltip,
    this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Follows the theme's corners (square themes stay square).
    final r = (StyleExtras.of(context).panelRadius * 0.6).clamp(0.0, 12.0);
    final radius = BorderRadius.circular(inkR(r));
    final tile = Material(
      color: highlight ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: highlight ? scheme.primary : scheme.outlineVariant,
          width: inkW(highlight ? 2 : 1),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTapUp: (d) => onTap == null ? onMenu(d.globalPosition) : onTap!(),
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          onMenu(box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: picture,
                  ),
                  if (kind != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(inkR(6)),
                        ),
                        child: Icon(
                          _iconOf(kind!),
                          size: 14,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: highlight
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: tile,
    );
  }
}

/// A media item's little picture: the picture itself, YouTube's still, or
/// an icon.
class _Thumb extends StatefulWidget {
  final MediaItem item;
  const _Thumb({required this.item});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Thumb old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _bytes = null;
      _load();
    }
  }

  void _load() {
    final item = widget.item;
    final ref = item.file;
    if (item.kind != MediaKind.image || ref == null) return;
    MediaStore.bytes(ref).then((b) {
      // Still showing this item (not another one by now)?
      if (!mounted || widget.item.id != item.id) return;
      if (b != null && b.isNotEmpty) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (widget.item.kind) {
      MediaKind.video || MediaKind.youtube => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      MediaKind.audio => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    final icon = ColoredBox(
      color: bg,
      child: Center(
        child: Icon(_iconOf(widget.item.kind), size: 40, color: fg),
      ),
    );
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 300,
        errorBuilder: (_, _, _) => icon,
      );
    }
    // A picture from a link.
    if (widget.item.kind == MediaKind.image && widget.item.file == null) {
      return Image.network(
        pictureSource(widget.item.url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => icon,
      );
    }
    final thumb = widget.item.thumbnailUrl;
    if (thumb != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            pictureSource(thumb),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
          const Center(
            child: Icon(BrambleIcons.playCircle, color: Colors.white, size: 36),
          ),
        ],
      );
    }
    return icon;
  }
}

Future<String?> _showMenuAt(
  BuildContext context,
  Offset at,
  List<PopupMenuEntry<String>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      // The overlay may not start at the window's corner.
      overlay.globalToLocal(at) & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

Future<String?> _pickFolder(
  BuildContext context,
  PresenterModel model,
  String current,
) => showAppDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Move to'),
    children: [
      for (final f in ['', ...model.mediaFolders])
        if (f != current)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, f),
            child: Row(
              children: [
                SizedBox(width: 16.0 * '/'.allMatches(f).length),
                Icon(f.isEmpty ? BrambleIcons.images : BrambleIcons.folder),
                const SizedBox(width: 10),
                Text(f.isEmpty ? 'All media (top)' : folderName(f)),
              ],
            ),
          ),
    ],
  ),
);

Future<String?> _askText(
  BuildContext context,
  String title, {
  String initial = '',
  String hint = '',
  String action = 'OK',
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showAppDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint.isEmpty ? null : hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}
