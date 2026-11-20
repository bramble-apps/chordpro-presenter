import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'sidebar_icon.dart';
import '../band_sync/band_sync.dart';
import '../browser.dart';
import '../chords/chord_library.dart';
import '../eink.dart';
import '../format.dart';
import '../justchords.dart';
import '../pdfs.dart';
import '../song_icons.dart';
import '../media_library.dart';
import '../state.dart';
import '../themes.dart';
import 'alpha_scrubber.dart';
import 'find_songs.dart';
import 'scanner_screen.dart';
import 'library_sync_dialog.dart';
import 'openchords_dialog.dart';
import 'share_dialog.dart';
import 'edit_link.dart';
import 'sync_dialog.dart';
import 'song_usage.dart';

enum _Mode { songs, setlists, trash, find, libraries, bandSync }

enum _Sort { title, artist, key, newest }

extension on _Sort {
  String get label => switch (this) {
    _Sort.title => 'Title',
    _Sort.artist => 'Artist',
    _Sort.key => 'Key',
    _Sort.newest => 'Recently added',
  };
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
  'Nov', 'Dec', //
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// Left column: ☰ menu, then the song library, setlists or trash.
class Sidebar extends StatefulWidget {
  final PresenterModel model;
  final Future<bool> Function(Song) onEditSong;
  final Future<void> Function(Song) onDeleteSong;
  final Future<void> Function() onImport;
  final VoidCallback onEditStructure;
  final VoidCallback onOpenSettings;

  /// Called after a song is opened (closes the drawer on small screens).
  final VoidCallback onOpened;

  const Sidebar({
    super.key,
    required this.model,
    required this.onEditSong,
    required this.onDeleteSong,
    required this.onImport,
    required this.onEditStructure,
    required this.onOpenSettings,
    required this.onOpened,
    this.toggleRoom,
    this.trailing,
  });

  /// A button at the right of the top row (the phone drawer's own sidebar
  /// button, which closes it).
  final Widget? trailing;

  /// Room kept at the right of the top row for the sidebar button (its
  /// size as drawn), which rides there while the sidebar is open.
  final ValueListenable<Size>? toggleRoom;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _search = TextEditingController();

  // ---- A–Z scrubber: jumping the grouped list to a letter ----
  final _listScroll = ScrollController();
  final _tagScroll = ScrollController();

  /// Natural heights of the three kinds of row (letter header, song, song
  /// with an artist line), measured from hidden samples. With these the
  /// list knows every row's height, so jumping far is instant (nothing in
  /// between has to be laid out) and lands exactly.
  final Map<String, double> _kindHeight = {};

  String _kind(Object row) => row is String
      ? 'header'
      : ((row as Song).artist.isNotEmpty ? 'song2' : 'song1');

  void _measured(String kind, double h) {
    if (_kindHeight[kind] == h) return;
    _kindHeight[kind] = h;
    // (After this frame: we're in the middle of layout.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  bool get _heightsKnown => _kindHeight.length == 3;

  void _jumpTo(String letter, List<Object> rows) {
    final index = rows.indexOf(letter);
    if (index < 0 || !_listScroll.hasClients || !_heightsKnown) return;
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _kindHeight[_kind(rows[i])]!;
    }
    _listScroll.jumpTo(offset.clamp(0, _listScroll.position.maxScrollExtent));
  }

  _Mode _mode = _Mode.songs;
  _Sort _sort = _Sort.title;
  final Set<String> _tagFilter = {};

  /// E-ink: the letter the song list is filtered to (null = all).
  String? _letter;
  bool _grouped = true;

  /// Only show songs played in this key (e.g. "G", "Em").
  String? _keyFilter;
  String? _openSetlistId;

  /// Find songs: open with the paste box ready.
  bool _findPaste = false;
  _Mode _beforeFind = _Mode.songs;

  void _openFind({bool paste = false}) => setState(() {
    if (_mode != _Mode.find) _beforeFind = _mode;
    _mode = _Mode.find;
    _findPaste = paste;
  });

  PresenterModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    // Back where it was left (after closing the app, or rotating, which
    // rebuilds the pane as a drawer or docked).
    final m = model;
    final mode = _Mode.values.asNameMap()[m.uiValue<String>('sidebar.mode')];
    if (mode != null && mode != _Mode.find) _mode = mode;
    _sort =
        _Sort.values.asNameMap()[m.uiValue<String>('sidebar.sort')] ?? _sort;
    _grouped = m.uiValue<bool>('sidebar.grouped') ?? _grouped;
    _keyFilter = m.uiValue<String>('sidebar.key');
    _letter = m.uiValue<String>('sidebar.letter');
    _openSetlistId = m.uiValue<String>('sidebar.setlist');
    _tagFilter.addAll(
      m.uiValue<List<dynamic>>('sidebar.tags')?.whereType<String>() ?? [],
    );
    _search.text = m.uiValue<String>('sidebar.search') ?? '';
    _einkFor = m.uiValue<String>('sidebar.einkFor');
    _einkPage = m.uiValue<int>('sidebar.einkPage') ?? 0;
    final scrolled = m.uiValue<num>('sidebar.scroll')?.toDouble();
    if (scrolled != null && scrolled > 0) {
      // Once laid out, and again when the rows' heights are measured.
      void restore([int tries = 2]) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_listScroll.hasClients) return;
          final p = _listScroll.position;
          _listScroll.jumpTo(scrolled.clamp(0, p.maxScrollExtent));
          if (tries > 1) restore(tries - 1);
        });
      }

      restore();
    }
    _listScroll.addListener(() {
      if (_listScroll.positions.length == 1) {
        model.setUi('sidebar.scroll', _listScroll.offset.roundToDouble());
      }
    });
  }

  /// Notes where the pane is (see initState); only what changed is saved.
  void _remember() {
    final m = model;
    m.setUi('sidebar.mode', (_mode == _Mode.find ? _beforeFind : _mode).name);
    m.setUi('sidebar.sort', _sort.name);
    m.setUi('sidebar.grouped', _grouped);
    m.setUi('sidebar.key', _keyFilter);
    m.setUi('sidebar.letter', _letter);
    m.setUi('sidebar.setlist', _openSetlistId);
    m.setUi('sidebar.tags', [..._tagFilter]..sort());
    m.setUi('sidebar.search', _search.text.isEmpty ? null : _search.text);
    m.setUi('sidebar.einkFor', _einkFor);
    m.setUi('sidebar.einkPage', _einkPage == 0 ? null : _einkPage);
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _tagScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([model, _search]),
      builder: (context, _) {
        final openSet = model.setlistById(_openSetlistId);
        // (After this build: e-ink pages are worked out while building.)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _remember();
        });
        return Column(
          children: [
            Container(
              // Same height as the header bar in desktop styles.
              constraints: BoxConstraints(
                minHeight: StyleExtras.of(context).headerBar ? 46 : 0,
                // E-ink: exactly the header bar's height.
                maxHeight: isEink(context) ? 46 : double.infinity,
              ),
              // E-ink: the header bar's height and line, so the two
              // read as one bar.
              decoration: isEink(context)
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: einkStroke,
                        ),
                      ),
                    )
                  : null,
              // (The 2 px line counts towards the 46: 2 + 40 + 2 + 2.)
              padding: isEink(context)
                  ? const EdgeInsets.fromLTRB(_einkSide, 2, _einkSide, 2)
                  : StyleExtras.of(context).headerBar
                  ? const EdgeInsets.fromLTRB(4, 3, 4, 3)
                  : const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Row(
                spacing: 6,
                children: [
                  _menu(),
                  Expanded(child: _topBar(openSet)),
                  if (widget.trailing case final t?)
                    t
                  else if (widget.toggleRoom case final room?)
                    ValueListenableBuilder<Size>(
                      valueListenable: room,
                      builder: (context, size, _) =>
                          SizedBox(width: size.width),
                    ),
                ],
              ),
            ),
            if (model.remoteEdit) RemoteEditStrip(model: model),
            // (E-ink: in the filter menu, all at once.)
            if (_mode == _Mode.songs && !isEink(context)) _tagBar(),
            Expanded(
              child: switch (_mode) {
                _Mode.songs => _songList(),
                _Mode.setlists when openSet != null => _SetlistDetail(
                  model: model,
                  setlist: openSet,
                  onOpened: widget.onOpened,
                  onEditStructure: widget.onEditStructure,
                ),
                _Mode.setlists => _setlistList(),
                _Mode.trash => _trashList(),
                _Mode.libraries => _libraryList(),
                _Mode.bandSync => _BandSyncPane(
                  model: model,
                  onOpenSetlist: (id) => setState(() {
                    _mode = _Mode.setlists;
                    _openSetlistId = id;
                  }),
                ),
                _Mode.find => FindSongsPane(
                  key: ValueKey('find-$_findPaste'),
                  model: model,
                  paste: _findPaste,
                  onEdit: widget.onEditSong,
                ),
              },
            ),
            if (_mode == _Mode.bandSync)
              const SizedBox.shrink()
            else if (_mode == _Mode.libraries)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 18,
                        ),
                        label: const Text('New library'),
                        onPressed: _newLibrary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'OpenChords settings',
                      icon: const Icon(Icons.cloud_sync_outlined, size: 20),
                      onPressed: () => showOpenChordsSettings(context, model),
                    ),
                  ],
                ),
              )
            else if (_mode != _Mode.find)
              Padding(
                padding: isEink(context)
                    ? const EdgeInsets.fromLTRB(
                        _einkSide,
                        8,
                        _einkSide,
                        _einkSide,
                      )
                    : const EdgeInsets.all(8),
                child: _bottomBar(openSet),
              ),
          ],
        );
      },
    );
  }

  // ---- Top ----

  /// ☰: what to look at, organising, working with others, tools, the
  /// library in and out, then settings.
  Widget _menu() {
    MenuItemButton item(
      String value,
      IconData icon,
      String title, {
      String? subtitle,
      Widget? badge,
    }) => MenuItemButton(
      leadingIcon: Icon(icon, size: 20),
      onPressed: () => _menuAction(value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              badge == null
                  ? Text(title)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [Text(title), badge],
                    ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    MenuItemButton view(_Mode mode, String value, String label) =>
        MenuItemButton(
          leadingIcon: Icon(_mode == mode ? Icons.check : null, size: 20),
          onPressed: () => _menuAction(value),
          child: Text(label),
        );

    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        tooltip: 'Menu',
        icon: const Icon(Icons.menu),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        view(_Mode.songs, 'songs', 'Songs (${model.songs.length})'),
        view(_Mode.setlists, 'setlists', 'Setlists (${model.setlists.length})'),
        view(_Mode.trash, 'trash', 'Trash (${model.trash.length})'),
        const Divider(height: 1),
        // Organising.
        // (A window editing another computer's library edits that one.)
        if (!model.remoteEdit)
          item(
            'libraries',
            Icons.folder_outlined,
            'Libraries…',
            subtitle: model.currentLibrary.name,
          ),
        item('tags', Icons.sell_outlined, 'Manage tags…'),
        const Divider(height: 1),
        // With others.
        item(
          'bandsync',
          Icons.groups_outlined,
          'Band Sync…',
          subtitle: switch (model.bandSync.role) {
            BandSyncRole.leading => 'Leading a session',
            BandSyncRole.following => 'Following a session',
            BandSyncRole.idle => null,
          },
        ),
        if (!model.remoteEdit)
          item('remote-edit', Icons.devices_outlined, 'Remote…'),
        SubmenuButton(
          leadingIcon: const Icon(Icons.handyman_outlined, size: 20),
          menuChildren: [
            item('chords', Icons.library_music_outlined, 'Chord Library…'),
            item(
              'scanner',
              Icons.document_scanner_outlined,
              'Sheet music scanner…',
              subtitle: 'Read printed music, play it, get its chords',
            ),
            item(
              'usage',
              Icons.bar_chart_outlined,
              'Song usage…',
              subtitle: 'Which songs were projected, and how often',
              badge: const ReportingBadge(),
            ),
          ],
          child: const Text('Tools'),
        ),
        const Divider(height: 1),
        // The library in and out.
        item('import', Icons.file_upload_outlined, 'Import…'),
        SubmenuButton(
          leadingIcon: const Icon(Icons.file_download_outlined, size: 20),
          menuChildren: [
            item(
              'export',
              Icons.inventory_2_outlined,
              'Backup of everything',
              subtitle: 'Songs, setlists and PDFs, to import here later',
            ),
            item(
              'export-justchords',
              Icons.ios_share,
              'For JustChords (.json)',
              subtitle: 'Restore in JustChords (replaces its library)',
            ),
          ],
          child: const Text('Export'),
        ),
        if (!model.remoteEdit) ...[
          item('sync', Icons.cloud_sync_outlined, 'Backup & sync…'),
        ],
        const Divider(height: 1),
        item('settings', Icons.settings_outlined, 'Settings…'),
        item('donate', Icons.favorite_outline, 'Support development…'),
      ],
    );
  }

  Future<void> _menuAction(String v) async {
    switch (v) {
      case 'songs':
        setState(() => _mode = _Mode.songs);
      case 'setlists':
        setState(() {
          _mode = _Mode.setlists;
          _openSetlistId = null;
        });
      case 'trash':
        setState(() => _mode = _Mode.trash);
      case 'libraries':
        setState(() => _mode = _Mode.libraries);
      case 'bandsync':
        setState(() => _mode = _Mode.bandSync);
      case 'chords':
        showChordLibrary(context, model);
      case 'scanner':
        openScanner(context, model);
      case 'usage':
        showSongUsage(context, model);
      case 'remote-edit':
        showEditLink(context);
      case 'sync':
        showSyncSettings(context);
      case 'tags':
        _openTagManager();
      case 'import':
        widget.onImport();
      case 'export':
        // With PDFs: a zip (songs.json + the PDFs), which Import reads.
        if (libraryPdfs(model).isEmpty) {
          downloadTextFile('songs.json', model.toJsonString());
        } else {
          downloadBytes(
            'ChordPro Presenter backup.zip',
            await libraryBackupZip(model),
            'application/zip',
          );
        }
      case 'export-justchords':
        final d = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        final stamp = '${d.year}-${two(d.month)}-${two(d.day)}';
        // JustChords takes ChordPro only: the PDFs can come as a zip.
        var withPdfs = false;
        if (libraryPdfs(model).isNotEmpty) {
          final go = await showAppDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, setLocal) => AlertDialog(
                title: const Text('Export for JustChords'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Also download the PDFs (.zip)'),
                      value: withPdfs,
                      onChanged: (v) => setLocal(() => withPdfs = v!),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Export'),
                  ),
                ],
              ),
            ),
          );
          if (go != true) return;
        }
        downloadTextFile('library_$stamp.json', justChordsLibraryJson(model));
        if (withPdfs) {
          downloadBytes(
            'library_${stamp}_pdfs.zip',
            await pdfsZip(model),
            'application/zip',
          );
        }
      case 'settings':
        widget.onOpenSettings();
      case 'donate':
        openUrl(donateUrl);
    }
  }

  void _openTagManager() => showAppDialog<void>(
    context: context,
    builder: (_) => _TagManager(model: model),
  );

  Future<void> _newTag() async {
    final n = await _askName(context, 'New tag', '', hint: 'e.g. Communion');
    if (n != null) model.addTag(n, color: 'blue');
  }

  /// Key a song is played in, as shown in the list.
  String? _songKey(Song s) => s.writtenKey?.transposed(s.transpose).name;

  Widget _filterMenu() {
    // Songs per key, ordered C, C#, D... with major before minor.
    final counts = <String, (int, int)>{}; // name -> (order, count)
    for (final s in model.songs) {
      final k = s.writtenKey?.transposed(s.transpose);
      final name = k?.name ?? 'No key';
      final order = k == null ? 999 : k.root * 2 + (k.minor ? 1 : 0);
      counts[name] = (order, (counts[name]?.$2 ?? 0) + 1);
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[a]!.$1.compareTo(counts[b]!.$1));
    final eink = isEink(context);
    final active =
        _sort != _Sort.title ||
        _grouped ||
        _keyFilter != null ||
        (eink && _tagFilter.isNotEmpty);
    final tags = [...model.tags]..sort((a, b) => a.name.compareTo(b.name));

    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      // (inside the search bar, drawn like its magnifying glass; a dot
      // while sorting or filtering)
      builder: (context, controller, _) => IconButton(
        tooltip: 'Sort & filter',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        style: hoverOnlyHighlight(context),
        color: scheme.onSurfaceVariant,
        icon: Badge(
          isLabelVisible: active,
          smallSize: 6,
          backgroundColor: eink ? scheme.onSurface : scheme.primary,
          child: const Icon(Icons.filter_list),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final s in _Sort.values)
          MenuItemButton(
            leadingIcon: Icon(
              s == _sort ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
            ),
            onPressed: () => setState(() => _sort = s),
            child: Text('Sort by ${s.label}'),
          ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: Icon(
            _grouped ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
          ),
          onPressed: () => setState(() => _grouped = !_grouped),
          child: const Text('Group by letter'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.music_note, size: 18),
          menuChildren: [
            MenuItemButton(
              leadingIcon: Icon(
                _keyFilter == null ? Icons.check : null,
                size: 18,
              ),
              onPressed: () => setState(() => _keyFilter = null),
              child: Text('All keys (${model.songs.length})'),
            ),
            const Divider(height: 1),
            for (final k in keys)
              MenuItemButton(
                leadingIcon: Icon(
                  _keyFilter == k ? Icons.check : null,
                  size: 18,
                ),
                onPressed: () => setState(() => _keyFilter = k),
                child: Text('$k (${counts[k]!.$2})'),
              ),
          ],
          child: Text(_keyFilter == null ? 'Key' : 'Key: $_keyFilter'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.visibility_off_outlined, size: 18),
          menuChildren: [
            for (final t in model.tags)
              MenuItemButton(
                closeOnActivate: false,
                leadingIcon: Icon(
                  t.hidden ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                ),
                onPressed: () => model.updateTag(t, hidden: !t.hidden),
                child: Text(t.name),
              ),
          ],
          child: const Text('Hide from All Songs'),
        ),
        // E-ink: the tags here, all at once (no strip to scroll).
        if (eink) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SizedBox(
              width: 280,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tag.name),
                      selected: _tagFilter.contains(tag.id),
                      onSelected: (on) => setState(
                        () => on
                            ? _tagFilter.add(tag.id)
                            : _tagFilter.remove(tag.id),
                      ),
                    ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('New tag'),
                    onPressed: _newTag,
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text('Manage tags'),
                    onPressed: _openTagManager,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _topBar(Setlist? openSet) {
    final style = Theme.of(context).textTheme.titleMedium;
    switch (_mode) {
      case _Mode.songs:
        return Row(
          spacing: 6,
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  // Same height as the buttons beside it, in every style
                  // (icons otherwise make the field 48 px tall).
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  constraints: const BoxConstraints(maxHeight: 40),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  // clear (while searching), and sort & filter
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _search.clear,
                        ),
                      _filterMenu(),
                    ],
                  ),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(inkR(8)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        );
      case _Mode.trash:
        return Text('Trash', style: style);
      case _Mode.bandSync:
        return Row(
          children: [
            IconButton(
              tooltip: 'Back to songs',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _mode = _Mode.songs),
            ),
            Expanded(child: Text('Band Sync', style: style)),
          ],
        );
      case _Mode.libraries:
        return Row(
          children: [
            IconButton(
              tooltip: 'Back to songs',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _mode = _Mode.songs),
            ),
            Expanded(child: Text('Libraries', style: style)),
          ],
        );
      case _Mode.find:
        return Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _mode = _beforeFind),
            ),
            Expanded(child: Text('Find songs', style: style)),
          ],
        );
      case _Mode.setlists:
        if (openSet == null) return Text('Setlists', style: style);
        return Row(
          children: [
            IconButton(
              tooltip: 'All setlists',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _openSetlistId = null),
            ),
            Expanded(
              child: Text(
                openSet.name,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Setlist options',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) async {
                if (v == 'edit') {
                  await showAppDialog<void>(
                    context: context,
                    builder: (_) =>
                        _SetlistDetailsDialog(model: model, setlist: openSet),
                  );
                } else if (v == 'duplicate') {
                  final copy = model.duplicateSetlist(openSet);
                  setState(() => _openSetlistId = copy.id);
                } else if (v == 'openchords') {
                  await showOpenChordsShare(context, model, openSet);
                } else if (v == 'export') {
                  await ShareDialog.show(
                    context,
                    model,
                    setlist: openSet,
                    setlistFirst: true,
                  );
                } else if (v == 'delete') {
                  final ok = await _confirm(
                    context,
                    'Delete setlist?',
                    '"${openSet.name}" will be removed. '
                        'The songs stay in your library.',
                  );
                  if (ok) {
                    setState(() => _openSetlistId = null);
                    model.deleteSetlist(openSet);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Name, date & notes…'),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate setlist'),
                ),
                PopupMenuItem(
                  value: 'openchords',
                  child: Text(
                    model.openChordsLinkFor(openSet.id) == null
                        ? 'Share on OpenChords…'
                        : 'OpenChords link & sync…',
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Text('Export setlist…'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete setlist'),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _tagBar() {
    final sorted = [...model.tags]..sort((a, b) => a.name.compareTo(b.name));
    return SizedBox(
      height: 40,
      // Tags fade out at the right edge instead of being cut off.
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          colors: isEink(context)
              ? const [Colors.white, Colors.white]
              : const [Colors.white, Colors.white, Colors.transparent],
          stops: isEink(context)
              ? null
              : [0, ((rect.width - 32) / rect.width).clamp(0.0, 1.0), 1],
        ).createShader(rect),
        child: Listener(
          onPointerSignal: _scrollTags,
          child: ListView(
            controller: _tagScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 8, right: 32),
            children: [
              IconButton(
                tooltip: 'Manage tags',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.sell_outlined, size: 20),
                onPressed: _openTagManager,
              ),
              const SizedBox(width: 6),
              for (final tag in sorted)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor:
                          colorNamed(tag.color) ?? Colors.grey.shade500,
                    ),
                    label: Text(tag.name),
                    tooltip: tag.hidden ? 'Hidden tag' : null,
                    selected: _tagFilter.contains(tag.id),
                    onSelected: (on) => setState(
                      () => on
                          ? _tagFilter.add(tag.id)
                          : _tagFilter.remove(tag.id),
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'New tag',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 20),
                onPressed: _newTag,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Two-finger scrolling over the tags: sideways or up / down, both move
  /// them sideways (a scroll the list didn't take itself).
  void _scrollTags(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_tagScroll.hasClients) return;
    final d = event.scrollDelta;
    final by = d.dx.abs() > d.dy.abs() ? d.dx : d.dy;
    final pos = _tagScroll.position;
    final to = (pos.pixels + by).clamp(0.0, pos.maxScrollExtent);
    if (by == 0 || to == pos.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _tagScroll.jumpTo(to),
    );
  }

  /// Opens library [id] and shows its songs.
  Future<void> _openLibrary(String id) async {
    setState(() {
      _tagFilter.clear();
      _openSetlistId = null;
      _mode = _Mode.songs;
    });
    await model.switchLibrary(id);
  }

  /// New library: personal, or OpenChords (started here or joined).
  Future<void> _newLibrary() async {
    final before = model.libraryId;
    await showNewLibrary(context, model);
    if (!mounted || model.libraryId == before) return;
    setState(() {
      _tagFilter.clear();
      _openSetlistId = null;
      _mode = _Mode.songs;
    });
  }

  /// The libraries (in the side pane): tap one to open it; rename or
  /// delete from its menu. Each has its own songs, tags, setlists and
  /// trash; backups and imports cover the open one.
  Widget _libraryList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: [
        for (final lib in model.libraries)
          _Row(
            leading: Icon(
              lib.id == model.libraryId
                  ? Icons.folder_open
                  : Icons.folder_outlined,
            ),
            title: lib.name,
            subtitle: lib.id == model.libraryId
                ? [
                    'Open · ${model.songs.length} songs',
                    if (model.openChordsLinkFor(lib.id) != null)
                      'Shared on OpenChords',
                  ].join(' · ')
                : null,
            selected: lib.id == model.libraryId,
            onTap: lib.id == model.libraryId
                ? () => setState(() => _mode = _Mode.songs)
                : () => _openLibrary(lib.id),
            menu: {
              'Rename': () async {
                final name = await _askName(
                  context,
                  'Rename library',
                  lib.name,
                );
                if (name != null) model.renameLibrary(lib.id, name);
              },
              if (!model.remoteEdit)
                lib.id == model.libraryId &&
                        model.openChordsLinkFor(lib.id) != null
                    ? 'OpenChords link & sync…'
                    : 'Share on OpenChords…': () async {
                  // (A library is shared from inside it.)
                  if (lib.id != model.libraryId) {
                    await _openLibrary(lib.id);
                  }
                  if (mounted) {
                    await showOpenChordsShareLibrary(context, model);
                  }
                },
              if (lib.id != model.libraryId && !model.remoteEdit)
                'Compare & sync with ${model.currentLibrary.name}…': () =>
                    showLibrarySync(context, model, lib.id),
              if (lib.id != model.libraryId)
                'Delete': () async {
                  final ok = await _confirm(
                    context,
                    'Delete “${lib.name}”?',
                    'Its songs, setlists, tags and trash are deleted for '
                        'good. Export a backup first if you may want them '
                        'back.',
                    action: 'Delete',
                  );
                  if (ok) await model.deleteLibrary(lib.id);
                },
            },
          ),
      ],
    );
  }

  /// Each chosen PDF becomes a song of its own (attach PDFs to an existing
  /// song in its editor).
  Future<void> _addPdfSongs() async {
    final files = await pickBinaryFiles(sheetMusicExtensions);
    var n = 0;
    for (final (name, bytes) in files) {
      if (!PdfStore.looksLikeSheetMusic(bytes)) continue;
      await addPdfSong(model, name, bytes);
      n++;
    }
    if (n > 0 && mounted) {
      setState(() => _mode = _Mode.songs);
      widget.onOpened();
    }
  }

  Future<void> _newSetlist() async {
    final name = await _askName(context, 'New setlist', '');
    if (name == null) return;
    final set = model.createSetlist(name);
    setState(() {
      _mode = _Mode.setlists;
      _openSetlistId = set.id;
    });
  }

  Future<void> _addMarker(Setlist set, EntryType type) async {
    final title = await _askName(
      context,
      'New ${_entryTypeName(type).toLowerCase()}',
      '',
      hint: switch (type) {
        EntryType.divider => 'e.g. After Sermon',
        EntryType.label => 'e.g. Maybe',
        _ => 'e.g. Prayer time',
      },
    );
    if (title != null) model.addMarker(set, type, title);
  }

  Widget _bottomBar(Setlist? openSet) {
    // + and Setlists share one size so the bar looks even.
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    final plus = MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: 'New…',
        child: FilledButton.tonal(
          style: buttonStyle,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: const Icon(Icons.add, size: 20),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.music_note, size: 18),
          onPressed: () => widget.onEditSong(Song(title: '', raw: '')),
          child: const Text('New song'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.playlist_add, size: 18),
          onPressed: _newSetlist,
          child: const Text('New setlist'),
        ),
        if (openSet != null) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.library_add, size: 18),
            onPressed: () async {
              final ids = await _pickSongs(context, model);
              if (ids != null && ids.isNotEmpty) {
                model.addSongsToSetlist(openSet, ids);
              }
            },
            child: Text('Add songs to "${openSet.name}"'),
          ),
          for (final t in [EntryType.divider, EntryType.label, EntryType.event])
            MenuItemButton(
              leadingIcon: Icon(switch (t) {
                EntryType.divider => Icons.horizontal_rule,
                EntryType.label => Icons.label_outline,
                _ => Icons.event,
              }, size: 18),
              onPressed: () => _addMarker(openSet, t),
              child: Text('Add ${_entryTypeName(t).toLowerCase()}'),
            ),
          const Divider(height: 1),
        ],
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          onPressed: _addPdfSongs,
          child: const Text('PDF or picture as a song…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.travel_explore, size: 18),
          onPressed: _openFind,
          child: const Text('Find songs online'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.content_paste, size: 18),
          onPressed: () => _openFind(paste: true),
          child: const Text('Paste a song'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.cloud_download_outlined, size: 18),
          onPressed: () async {
            final set = await showOpenChordsOpen(context, model);
            if (set != null && mounted) {
              setState(() {
                _mode = _Mode.setlists;
                _openSetlistId = set.id;
              });
            }
          },
          child: const Text('Add from OpenChords link…'),
        ),
      ],
    );

    final inSongs = _mode == _Mode.songs;
    final toggle = FilledButton.tonalIcon(
      style: buttonStyle,
      icon: Icon(inSongs ? Icons.queue_music : Icons.library_music, size: 18),
      label: Text(inSongs ? 'Setlists' : 'Songs'),
      onPressed: () => setState(() {
        _mode = inSongs ? _Mode.setlists : _Mode.songs;
        _openSetlistId = null;
      }),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(child: plus),
            Expanded(child: toggle),
          ],
        ),
        if (_mode == _Mode.trash)
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Empty Trash'),
            onPressed: model.trash.isEmpty
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      'Empty Trash?',
                      '${model.trash.length} songs will be deleted for '
                          'good. This cannot be undone.',
                      action: 'Empty Trash',
                    );
                    if (ok) model.emptyTrash();
                  },
          ),
      ],
    );
  }

  // ---- Songs ----

  List<Song> _sorted(Iterable<Song> songs) {
    final list = songs.toList();
    int byTitle(Song a, Song b) => a.sortKey.compareTo(b.sortKey);
    switch (_sort) {
      case _Sort.title:
        list.sort(byTitle);
      case _Sort.artist:
        list.sort((a, b) {
          final c = foldAccents(a.artist).compareTo(foldAccents(b.artist));
          return c != 0 ? c : byTitle(a, b);
        });
      case _Sort.key:
        list.sort((a, b) {
          final ka = a.writtenKey?.transposed(a.transpose).root ?? 99;
          final kb = b.writtenKey?.transposed(b.transpose).root ?? 99;
          return ka != kb ? ka.compareTo(kb) : byTitle(a, b);
        });
      case _Sort.newest:
        list.sort((a, b) {
          final da = a.date ?? DateTime(1970);
          final db = b.date ?? DateTime(1970);
          return db.compareTo(da);
        });
    }
    return list;
  }

  Widget _songList() {
    // Accents don't matter: "eleve" finds "Élevé".
    final q = _search.text.trim();
    final hiddenTags = {
      for (final t in model.tags)
        if (t.hidden && !_tagFilter.contains(t.id)) t.id,
    };
    final matches = <Song>[];
    for (final s in model.songs) {
      if (!_tagFilter.every(s.tags.contains)) continue;
      if (_keyFilter != null && (_songKey(s) ?? 'No key') != _keyFilter) {
        continue;
      }
      if (q.isNotEmpty && s.searchRank(q) == null) {
        continue;
      }
      // (Songs with a hidden tag show when that tag is picked.)
      if (s.tags.any(hiddenTags.contains)) continue;
      matches.add(s);
    }
    var songs = _sorted(matches);
    // Searching: best matches first (the exact title on top), then the
    // usual order.
    final ranked = q.isNotEmpty;
    if (ranked) {
      final order = {for (final (i, s) in songs.indexed) s.id: i};
      final rank = {for (final s in songs) s.id: s.searchRank(q)!};
      songs = [...songs]
        ..sort((a, b) {
          final c = rank[a.id]!.compareTo(rank[b.id]!);
          return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
        });
    }
    model.libraryOrder = [for (final s in songs) s.id];

    return Column(
      children: [
        Expanded(
          child: songs.isEmpty
              ? const Center(child: Text('No matching songs.'))
              : _grouped && !ranked
              ? _groupedList(songs)
              // E-ink: whole rows to a page.
              : isEink(context)
              ? _einkPages(songs, 'p:$q:$_sort:${songs.length}')
              : ListView.builder(
                  // (Its place is remembered too, see initState.)
                  controller: _listScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: songs.length,
                  itemBuilder: (context, i) => _songRow(songs[i]),
                ),
        ),
      ],
    );
  }

  /// Letter used for grouping: by artist when sorted by artist, by key
  /// when sorted by key, otherwise by title.
  String _groupOf(Song s) {
    if (_sort == _Sort.key) return _songKey(s) ?? 'No key';
    // Accents folded (É → E) so French titles group with their letter.
    final text = _sort == _Sort.artist ? foldAccents(s.artist) : s.sortKey;
    if (text.isEmpty) return '#';
    final letter = text.characters.first.toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(letter) ? letter : '#';
  }

  Widget _groupedList(List<Song> songs) {
    final rows = <Object>[]; // String header or Song
    String? current;
    for (final s in songs) {
      final g = _groupOf(s);
      if (g != current) {
        rows.add(g);
        current = g;
      }
      rows.add(s);
    }
    final headerStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    final groups = [
      for (final r in rows)
        if (r is String) r,
    ];
    // By key: the keys there are. Otherwise # and A–Z (dim when empty).
    final letters = _sort == _Sort.key
        ? groups
        : ['#', for (var c = 65; c <= 90; c++) String.fromCharCode(c)];
    if (isEink(context)) return _einkList(rows, letters, groups.toSet());
    final list = ListView.builder(
      controller: _listScroll,
      padding: EdgeInsets.only(
        left: 6,
        right: AlphaScrubber.widthFor(context) + 4,
      ),
      itemCount: rows.length,
      itemExtentBuilder: _heightsKnown
          ? (i, _) => i < rows.length ? _kindHeight[_kind(rows[i])] : null
          : null,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) return _header(row, headerStyle);
        return _songRow(row as Song);
      },
    );
    // Hidden samples of each kind of row, measured at the list's width.
    final samples = Offstage(
      child: Padding(
        padding: EdgeInsets.only(
          left: 6,
          right: AlphaScrubber.widthFor(context) + 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MeasureHeight(
              onHeight: (h) => _measured('header', h),
              child: _header('A', headerStyle),
            ),
            _MeasureHeight(
              onHeight: (h) => _measured('song1', h),
              child: _songRow(Song(title: 'Sample', raw: '')),
            ),
            _MeasureHeight(
              onHeight: (h) => _measured('song2', h),
              child: _songRow(Song(title: 'Sample', raw: '', artist: 'Artist')),
            ),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Positioned(left: 0, right: 0, top: 0, child: samples),
        list,
        Positioned(
          right: 2,
          top: 4,
          bottom: 4,
          width: AlphaScrubber.widthFor(context),
          child: AlphaScrubber(
            letters: letters,
            available: groups.toSet(),
            onLetter: (l) => _jumpTo(l, rows),
          ),
        ),
      ],
    );
  }

  /// E-ink: the songs of one letter at a time (or all), turned by page
  /// arrows, with a grid of letters underneath instead of the scrubber.
  Widget _einkList(List<Object> rows, List<String> letters, Set<String> have) {
    final letter = have.contains(_letter) ? _letter : null;
    final shown = <Object>[];
    String? group;
    for (final r in rows) {
      if (r is String) group = r;
      if (letter == null || group == letter) shown.add(r);
    }
    final scheme = Theme.of(context).colorScheme;
    // Seven to a row, as wide as there is room for: All, #, A–Z fill four
    // rows exactly.
    final keys = ['All', ...letters];
    final grid = LayoutBuilder(
      builder: (context, c) {
        const cols = 7, gap = 4.0;
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in keys)
              _letterKey(
                k,
                k == 'All' ? null : k,
                width: w,
                on: (k == 'All' ? null : k) == letter,
                enabled: k == 'All' || have.contains(k),
              ),
          ],
        );
      },
    );
    return Column(
      children: [
        Expanded(child: _einkPages(shown, 'g:$letter:$_sort')),
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.onSurface, width: einkStroke),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(_einkSide, 8, _einkSide, 0),
          child: grid,
        ),
      ],
    );
  }

  /// E-ink: the side pane's edges (list, letters, buttons line up).
  static const _einkSide = 10.0;

  /// E-ink: which page of the song list shows, and how many there are,
  /// for the list as it was ([_einkFor]); a different list starts at 1.
  int _einkPage = 0, _einkPageCount = 1;
  String? _einkFor;

  /// [rows] (letter headings and songs) as pages of whole rows, with
  /// the page strip under them.
  Widget _einkPages(List<Object> rows, String signature) {
    if (_einkFor != signature) {
      _einkFor = signature;
      _einkPage = 0;
    }
    final page = _einkPage.clamp(0, _einkPageCount - 1);
    final headerStyle = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _einkSide - 6),
            child: EinkPagedRows(
              page: page,
              onPages: (n) {
                if (mounted && n != _einkPageCount) {
                  setState(() => _einkPageCount = n);
                }
              },
              children: [
                for (final row in rows)
                  row is String
                      ? _header(row, headerStyle)
                      : _songRow(row as Song),
              ],
            ),
          ),
        ),
        if (_einkPageCount > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EinkPageBar(
              page: page + 1,
              pages: _einkPageCount,
              onPrevious: page > 0
                  ? () => setState(() => _einkPage = page - 1)
                  : null,
              onNext: page < _einkPageCount - 1
                  ? () => setState(() => _einkPage = page + 1)
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _letterKey(
    String label,
    String? value, {
    required double width,
    required bool on,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: 36,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: on ? scheme.onSurface : null,
          foregroundColor: on ? scheme.surface : scheme.onSurface,
          // No songs under it: faint, without a box.
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            side: enabled
                ? BorderSide(color: scheme.onSurface, width: einkStroke)
                : BorderSide.none,
          ),
        ),
        onPressed: enabled ? () => setState(() => _letter = value) : null,
        child: FittedBox(child: Text(label, maxLines: 1)),
      ),
    );
  }

  Widget _header(String letter, TextStyle? style) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Text(letter, style: style, maxLines: 1),
  );

  Widget _songRow(Song song) {
    final key = song.writtenKey?.transposed(song.transpose).name;
    final dots = [
      for (final id in song.tags)
        if (model.tagById(id) case final tag? when !tag.hidden)
          colorNamed(tag.color) ?? Colors.grey.shade500,
    ];
    // Found in the lyrics: show where.
    final q = _search.text.trim();
    return _Row(
      title: song.displayTitle,
      icon: songIconOf(song),
      subtitle: song.artist.isNotEmpty ? song.artist : null,
      snippet: q.isEmpty ? null : song.searchSnippet(q),
      query: q,
      dots: dots,
      trailingText: key,
      selected: song.id == model.selectedSongId && model.activeEntryId == null,
      onTap: () {
        model.selectSong(song.id);
        widget.onOpened();
      },
      menu: {
        'Edit': () => widget.onEditSong(song),
        'Song icon…': () => _chooseSongIcon(context, model, song),
        if (model.setlists.isNotEmpty)
          'Add to setlist…': () async {
            final set = await _pickSetlist(context, model);
            if (set != null) model.addSongsToSetlist(set, [song.id]);
          },
        'Move to Trash': () => widget.onDeleteSong(song),
      },
    );
  }

  // ---- Setlists ----

  Widget _setlistList() {
    final band = model.bandSetlist;
    if (model.setlists.isEmpty && band == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No setlists yet.\nTap "New Setlist" to make one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Newest first (by event date, else creation date).
    final sets = [...model.setlists]
      ..sort((a, b) {
        final da = a.eventDate ?? a.date ?? DateTime(1970);
        final db = b.eventDate ?? b.date ?? DateTime(1970);
        return db.compareTo(da);
      });
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: [
        // Following a Band Sync session: the leader's setlist.
        if (band != null)
          _Row(
            leading: const Icon(Icons.groups_outlined),
            title: band.name,
            subtitle:
                'Band Sync · ${band.songCount} '
                'song${band.songCount == 1 ? '' : 's'}',
            selected: band.id == model.activeSetlistId,
            onTap: () => setState(() => _openSetlistId = band.id),
            menu: const {},
          ),
        for (final set in sets)
          _Row(
            title: set.name,
            subtitle: [
              if (set.eventDate != null) formatDate(set.eventDate!),
              '${set.songCount} song${set.songCount == 1 ? '' : 's'}',
              if (model.openChordsLinkFor(set.id) != null) 'OpenChords',
            ].join(' · '),
            selected: set.id == model.activeSetlistId,
            onTap: () => setState(() => _openSetlistId = set.id),
            menu: {
              'Name, date & notes…': () => showAppDialog<void>(
                context: context,
                builder: (_) =>
                    _SetlistDetailsDialog(model: model, setlist: set),
              ),
              'Duplicate setlist': () => model.duplicateSetlist(set),
              'Delete': () async {
                final ok = await _confirm(
                  context,
                  'Delete setlist?',
                  '"${set.name}" will be removed. '
                      'The songs stay in your library.',
                );
                if (ok) model.deleteSetlist(set);
              },
            },
          ),
      ],
    );
  }

  // ---- Trash ----

  Widget _trashList() {
    if (model.trash.isEmpty) {
      return const Center(child: Text('Trash is empty.'));
    }
    final songs = [...model.trash]
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final song = songs[i];
        return _Row(
          title: song.displayTitle,
          subtitle: song.artist.isNotEmpty ? song.artist : null,
          selected: false,
          onTap: null,
          menu: {
            'Restore': () => model.restoreSong(song),
            'Delete forever': () async {
              final ok = await _confirm(
                context,
                'Delete forever?',
                '"${song.displayTitle}" will be deleted for good.',
              );
              if (ok) model.deleteForever(song);
            },
          },
        );
      },
    );
  }
}

String _entryTypeName(EntryType t) => switch (t) {
  EntryType.song => 'Song',
  EntryType.divider => 'Divider',
  EntryType.label => 'Label',
  EntryType.event => 'Event',
  EntryType.media => 'Media',
  EntryType.bible => 'Bible',
};

String? _nonEmpty(String s) => s.isEmpty ? null : s;

class _SetlistDetail extends StatefulWidget {
  final PresenterModel model;
  final Setlist setlist;
  final VoidCallback onOpened;
  final VoidCallback onEditStructure;

  const _SetlistDetail({
    required this.model,
    required this.setlist,
    required this.onOpened,
    required this.onEditStructure,
  });

  @override
  State<_SetlistDetail> createState() => _SetlistDetailState();
}

class _SetlistDetailState extends State<_SetlistDetail> {
  PresenterModel get model => widget.model;
  Setlist get setlist => widget.setlist;
  VoidCallback get onOpened => widget.onOpened;
  VoidCallback get onEditStructure => widget.onEditStructure;

  // ---- Dragging a row by its handle (as Keydeck's slides): up and down
  // moves it, right nests it under the song above, left brings it out. ----

  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _rowKeys = <String, GlobalKey>{};
  List<SetlistRow> _rows = const [];
  int? _dragFrom;
  Offset _dragStart = Offset.zero, _dragAt = Offset.zero;
  Timer? _autoScroll;

  /// How far right a drag goes for one level deeper.
  static const _step = 24.0;

  /// Where a nested row's tree line runs (from the left of the row).
  static const _lineX = 21.0;
  static const _indent = 24.0;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String _rowId(SetlistRow r) =>
      r.isSub ? '${r.entry.id}/${r.sub}' : r.entry.id;
  GlobalKey _keyOf(SetlistRow r) =>
      _rowKeys.putIfAbsent(_rowId(r), GlobalKey.new);

  /// The rows [from] carries along (its nested songs).
  int _blockEnd(int from) {
    var end = from + 1;
    if (!_rows[from].isSub) {
      while (end < _rows.length && _rows[end].isSub) {
        end++;
      }
    }
    return end;
  }

  bool _isSongRow(SetlistRow r) =>
      r.isSub || (r.entry.type == EntryType.song && r.entry.songId != null);

  /// Where the held row lands now: before row `to`, at `depth`.
  ({int to, int depth})? _target() {
    final from = _dragFrom;
    if (from == null) return null;
    final end = _blockEnd(from);
    var to = _rows.length;
    for (var i = 0; i < _rows.length; i++) {
      final box =
          _keyOf(_rows[i]).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final mid = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      if (_dragAt.dy < mid) {
        to = i;
        break;
      }
    }
    // Inside itself: where it is.
    if (to > from && to <= end) to = from;
    final above = [
      for (var i = to - 1; i >= 0; i--)
        if (i < from || i >= end) i,
    ].firstOrNull;
    final canNest =
        above != null && _isSongRow(_rows[above]) && _isSongRow(_rows[from]);
    final own = _rows[from].isSub ? 1 : 0;
    final depth = (own + ((_dragAt.dx - _dragStart.dx) / _step).round()).clamp(
      0,
      canNest ? 1 : 0,
    );
    return (to: to, depth: depth);
  }

  Drag _startDrag(int row, Offset at) {
    setState(() {
      _dragFrom = row;
      _dragStart = _dragAt = at;
    });
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_dragAt).dy;
      const edge = 48.0;
      final by = y < edge
          ? -(edge - y) / 4
          : y > box.size.height - edge
          ? (y - box.size.height + edge) / 4
          : 0.0;
      if (by == 0) return;
      final p = _scroll.position;
      _scroll.jumpTo((p.pixels + by).clamp(0.0, p.maxScrollExtent));
      setState(() {});
    });
    return _RowDrag(
      onUpdate: (d) => setState(() => _dragAt = d.globalPosition),
      onEnd: _endDrag,
      onCancel: () => _endDrag(cancelled: true),
    );
  }

  void _endDrag({bool cancelled = false}) {
    _autoScroll?.cancel();
    final from = _dragFrom;
    final t = _target();
    setState(() => _dragFrom = null);
    if (cancelled || from == null || t == null) return;
    final own = _rows[from].isSub ? 1 : 0;
    if (t.to == from && t.depth == own) return;
    model.moveSetlistRow(setlist, from, t.to, t.depth);
  }

  /// A row's ≡ handle: held, the row follows the finger or mouse.
  Widget _handle(int row) => RawGestureDetector(
    gestures: {
      ImmediateMultiDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<
            ImmediateMultiDragGestureRecognizer
          >(
            ImmediateMultiDragGestureRecognizer.new,
            (r) => r.onStart = (at) => _startDrag(row, at),
          ),
    },
    child: const MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Padding(
        padding: EdgeInsets.only(right: 8),
        child: Icon(Icons.drag_indicator, size: 18),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    var songNumber = 0;
    final numbers = [
      for (final e in setlist.entries)
        e.type == EntryType.song ? ++songNumber : 0,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (setlist.eventDate != null || setlist.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              [
                if (setlist.eventDate != null) formatDate(setlist.eventDate!),
                if (setlist.notes.isNotEmpty) setlist.notes,
              ].join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        SwitchListTile(
          dense: true,
          title: const Text('Set-specific edits'),
          subtitle: Text(
            setlist.setSpecific
                ? 'Key & capo changes apply to this setlist only'
                : 'Key & capo changes update the song everywhere',
          ),
          value: setlist.setSpecific,
          onChanged: (v) => model.setSetSpecific(setlist, v),
        ),
        const Divider(height: 1),
        Expanded(
          // Media dragged from the media pane: dropped below the last
          // entry, it goes at the end.
          child: DragTarget<MediaItem>(
            onAcceptWithDetails: (d) =>
                model.addMediaToSetlist(setlist, d.data),
            builder: (context, over, _) => DecoratedBox(
              decoration: BoxDecoration(
                border: over.isEmpty
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: inkW(3),
                        ),
                      ),
              ),
              child: _entries(context, numbers),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entries(BuildContext context, List<int> numbers) {
    if (setlist.entries.isEmpty) {
      return const Center(child: Text('Tap "Add Songs" to fill this set.'));
    }
    _rows = model.setlistRows(setlist);
    final from = _dragFrom;
    final end = from == null ? 0 : _blockEnd(from);
    final target = _target();
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      key: _stackKey,
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          itemCount: _rows.length,
          itemBuilder: (context, i) {
            final r = _rows[i];
            final entryIndex = setlist.entries.indexOf(r.entry);
            Widget row = r.isSub
                ? _subRow(context, r.entry, r.sub!, r.songId!, i)
                : _entryRow(context, numbers, entryIndex, i);
            final subs = r.isSub ? 0 : r.entry.subSongIds.length;
            row = CustomPaint(
              foregroundPainter: _TreeLines(
                color: scheme.outline,
                width: inkW(1.5),
                x: _lineX + (r.isSub ? 0 : _accentWidth(r.entry)),
                indent: _indent,
                kind: r.isSub
                    ? (r.sub! == r.entry.subSongIds.length - 1
                          ? _Tree.last
                          : _Tree.middle)
                    : subs > 0
                    ? _Tree.parent
                    : _Tree.none,
              ),
              child: row,
            );
            return KeyedSubtree(
              key: _keyOf(r),
              child: Opacity(
                opacity: from != null && i >= from && i < end ? 0.35 : 1,
                child: row,
              ),
            );
          },
        ),
        if (target != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DropLine(
                  y: _lineY(target.to),
                  x: 6 + 12 + target.depth * _indent,
                  color: scheme.primary,
                  width: inkW(3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _accentWidth(SetEntry e) => colorNamed(e.color) == null ? 0 : inkW(3);

  /// Where the drop line goes, before row [to], in the list's box.
  double _lineY(int to) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || _rows.isEmpty) return 0;
    final last = to >= _rows.length;
    final box =
        _keyOf(_rows[last ? _rows.length - 1 : to]).currentContext
                ?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.attached) return last ? stack.size.height - 4 : 0;
    final g = box.localToGlobal(Offset(0, last ? box.size.height : 0));
    return stack.globalToLocal(g).dy;
  }

  Widget _entryRow(
    BuildContext context,
    List<int> numbers,
    int i,
    int rowIndex,
  ) {
    final entry = setlist.entries[i];
    final handle = _handle(rowIndex);
    if (entry.type == EntryType.bible) {
      return _BibleEntryRow(
        model: model,
        setlist: setlist,
        entry: entry,
        handle: handle,
        onOpened: onOpened,
      );
    }
    if (entry.type == EntryType.media) {
      return _MediaDrop(
        onDrop: (item) => model.addMediaToSetlist(setlist, item, at: i + 1),
        child: _MediaEntryRow(
          model: model,
          setlist: setlist,
          entry: entry,
          handle: handle,
          onOpened: onOpened,
        ),
      );
    }
    if (entry.type != EntryType.song) {
      return _MediaDrop(
        onDrop: (item) => model.addMediaToSetlist(setlist, item, at: i + 1),
        child: _MarkerRow(
          model: model,
          setlist: setlist,
          entry: entry,
          handle: handle,
        ),
      );
    }
    final song = model.songById(entry.songId);
    final inTrash =
        song == null && model.trash.any((s) => s.id == entry.songId);
    final key = song?.writtenKey
        ?.transposed(model.transposeFor(song, entry: entry, setlist: setlist))
        .name;
    final capo = song == null
        ? 0
        : model.capoFor(song, entry: entry, setlist: setlist);
    final name =
        song?.displayTitle ?? (inTrash ? 'Song in Trash' : 'Missing song');
    final background = entry.background;
    final previous = i > 0 ? setlist.entries[i - 1] : null;
    return _MediaDrop(
      onDrop: (item) => _droppedOnSong(context, entry, i, item),
      child: _Row(
        leading: handle,
        accent: colorNamed(entry.color),
        title: '${numbers[i]}. $name',
        icon: song == null ? null : songIconOf(song),
        subtitle: _nonEmpty(
          [
            if (entry.structure.isNotEmpty) 'Custom arrangement',
            if (entry.title.isNotEmpty) entry.title,
            if (background != null) 'Background: ${background.name}',
          ].join(' · '),
        ),
        trailingText: _nonEmpty([?key, if (capo > 0) 'capo $capo'].join(' · ')),
        selected: entry.id == model.activeEntryId,
        dimmed: song == null,
        onTap: song == null
            ? null
            : () {
                model.selectEntry(setlist, entry);
                onOpened();
              },
        menu: {
          if (song != null)
            'Song icon…': () => _chooseSongIcon(context, model, song),
          if (song != null)
            'Structure for this setlist…': () {
              model.selectEntry(setlist, entry);
              onEditStructure();
            },
          'Colour…': () async {
            final c = await _pickColor(context, entry.color);
            if (c != null) model.updateEntry(entry, color: c);
          },
          if (background != null)
            'Usual background': () => model.setEntryBackground(entry, null),
          if (song != null && previous?.type == EntryType.song)
            'Nest under the song above': () =>
                model.nestEntry(setlist, entry, previous!),
          'Remove from setlist': () => model.removeEntry(setlist, entry),
        },
      ),
    );
  }

  /// A song nested under [parent] (its [k]-th): played right after it, as
  /// part of the same song.
  Widget _subRow(
    BuildContext context,
    SetEntry parent,
    int k,
    String id,
    int rowIndex,
  ) {
    final song = model.songById(id);
    final parentName = model.songById(parent.songId)?.displayTitle ?? 'it';
    final key = song?.writtenKey?.transposed(song.transpose).name;
    return Padding(
      padding: const EdgeInsets.only(left: _indent),
      child: _Row(
        leading: _handle(rowIndex),
        title: song?.displayTitle ?? 'Missing song',
        icon: song == null ? null : songIconOf(song),
        trailingText: key,
        selected: false,
        dimmed: song == null,
        onTap: () {
          // Its song open, at where this one starts.
          model.selectEntry(setlist, parent);
          for (var p = 0; p < model.parts.length; p++) {
            if (model.nestedSongOfPart(p) == k + 1) {
              final slide = model.slidePartIndex.indexOf(p);
              if (slide >= 0) model.goTo(slide);
              break;
            }
          }
          onOpened();
        },
        menu: {
          'Move out of $parentName': () => model.unnestSong(setlist, parent, k),
        },
      ),
    );
  }

  /// A picture or video dropped on a song: its background in this
  /// setlist, or played after it. Anything else plays after it.
  Future<void> _droppedOnSong(
    BuildContext context,
    SetEntry entry,
    int i,
    MediaItem item,
  ) async {
    if (!item.canBeBackground) {
      model.addMediaToSetlist(setlist, item, at: i + 1);
      return;
    }
    final v = await showAppDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(item.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'bg'),
            child: const ListTile(
              leading: Icon(Icons.wallpaper),
              title: Text('Background for this song'),
              subtitle: Text('Here in this setlist'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'after'),
            child: const ListTile(
              leading: Icon(Icons.playlist_add),
              title: Text('Play after this song'),
            ),
          ),
        ],
      ),
    );
    if (v == 'bg') model.setEntryBackground(entry, item);
    if (v == 'after') model.addMediaToSetlist(setlist, item, at: i + 1);
  }
}

/// A held row's drag: passes the moves and the drop on.
class _RowDrag extends Drag {
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd, onCancel;
  _RowDrag({
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  @override
  void update(DragUpdateDetails details) => onUpdate(details);
  @override
  void end(DragEndDetails details) => onEnd();
  @override
  void cancel() => onCancel();
}

enum _Tree { none, parent, middle, last }

/// The lines joining a song to the songs nested under it: down from its
/// handle, then across to each of them (├ and └).
class _TreeLines extends CustomPainter {
  final Color color;
  final double width, x, indent;
  final _Tree kind;
  const _TreeLines({
    required this.color,
    required this.width,
    required this.x,
    required this.indent,
    required this.kind,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (kind == _Tree.none) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    // (The list's 6 px side padding is outside the row.)
    final lx = x;
    if (kind == _Tree.parent) {
      canvas.drawLine(Offset(lx, mid + 13), Offset(lx, size.height), paint);
      return;
    }
    final to = indent + 12 - 3; // just before the nested row's handle
    const r = 6.0;
    final path = Path()..moveTo(lx, 0);
    if (kind == _Tree.last) {
      path
        ..lineTo(lx, mid - r)
        ..quadraticBezierTo(lx, mid, lx + r, mid)
        ..lineTo(to, mid);
    } else {
      path
        ..lineTo(lx, size.height)
        ..moveTo(lx, mid)
        ..lineTo(to, mid);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TreeLines old) =>
      old.kind != kind ||
      old.color != color ||
      old.x != x ||
      old.width != width;
}

/// Where a held row will land: a line with a ring at its start, indented
/// when it will be nested (as Keydeck's).
class _DropLine extends CustomPainter {
  final double y, x, width;
  final Color color;
  const _DropLine({
    required this.y,
    required this.x,
    required this.color,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(x, y), 4, paint..strokeWidth = 2);
    canvas.drawLine(
      Offset(x + 4, y),
      Offset(size.width - 6, y),
      paint..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_DropLine old) =>
      old.y != y || old.x != x || old.color != color;
}

/// A setlist row media can be dropped on (outlined while one is over it).
class _MediaDrop extends StatelessWidget {
  final void Function(MediaItem item) onDrop;
  final Widget child;
  const _MediaDrop({required this.onDrop, required this.child});

  @override
  Widget build(BuildContext context) => DragTarget<MediaItem>(
    onAcceptWithDetails: (d) => onDrop(d.data),
    builder: (context, over, _) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: over.isEmpty
            ? null
            : Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: inkW(2),
              ),
        borderRadius: BorderRadius.circular(inkR(8)),
      ),
      child: child,
    ),
  );
}

/// A media item in a setlist: plays (or shows) when the setlist gets
/// there.
class _MediaEntryRow extends StatelessWidget {
  final PresenterModel model;
  final Setlist setlist;
  final SetEntry entry;
  final Widget handle;
  final VoidCallback onOpened;

  const _MediaEntryRow({
    required this.model,
    required this.setlist,
    required this.entry,
    required this.handle,
    required this.onOpened,
  });

  @override
  Widget build(BuildContext context) {
    final item = entry.media;
    final mode = entry.mediaMode;
    return _Row(
      leading: handle,
      accent: colorNamed(entry.color),
      title: entry.title.isEmpty ? (item?.name ?? 'Media') : entry.title,
      icon: switch (item?.kind) {
        MediaKind.image => Icons.image_outlined,
        MediaKind.video => Icons.movie_outlined,
        MediaKind.audio => Icons.music_note_outlined,
        MediaKind.youtube => Icons.smart_display_outlined,
        _ => Icons.link,
      },
      subtitle:
          '${item?.kind.label ?? 'Media'} · ${switch (mode) {
            LiveMode.play => item?.kind == MediaKind.image ? 'Full screen' : 'Plays',
            LiveMode.overlay => 'Over the lyrics',
            LiveMode.background => 'Becomes the background',
          }}',
      selected: entry.id == model.activeEntryId,
      onTap: item == null
          ? null
          : () {
              model.selectEntry(setlist, entry);
              onOpened();
            },
      menu: {
        if (item != null && item.canProject && mode != LiveMode.play)
          'Play full screen': () => model.setEntryMode(entry, LiveMode.play),
        if (item != null &&
            item.canProject &&
            item.kind != MediaKind.audio &&
            mode != LiveMode.overlay)
          'Show over the lyrics': () =>
              model.setEntryMode(entry, LiveMode.overlay),
        if (item != null && item.canBeBackground && mode != LiveMode.background)
          'Make it the background': () =>
              model.setEntryMode(entry, LiveMode.background),
        'Rename…': () async {
          final t = await _askName(context, 'Rename', entry.title);
          if (t != null) model.updateEntry(entry, title: t);
        },
        'Colour…': () async {
          final c = await _pickColor(context, entry.color);
          if (c != null) model.updateEntry(entry, color: c);
        },
        'Remove from setlist': () => model.removeEntry(setlist, entry),
      },
    );
  }
}

/// A Bible passage inside a setlist (it lives only here and in the
/// Bible tool, never in the library).
class _BibleEntryRow extends StatelessWidget {
  final PresenterModel model;
  final Setlist setlist;
  final SetEntry entry;
  final Widget handle;
  final VoidCallback onOpened;

  const _BibleEntryRow({
    required this.model,
    required this.setlist,
    required this.entry,
    required this.handle,
    required this.onOpened,
  });

  @override
  Widget build(BuildContext context) {
    final p = entry.passage;
    return _Row(
      leading: handle,
      accent: colorNamed(entry.color),
      title: entry.title.isEmpty ? (p?.reference ?? 'Bible') : entry.title,
      icon: Icons.menu_book_outlined,
      subtitle: 'Bible · ${p?.versions ?? '?'}',
      selected: entry.id == model.activeEntryId,
      onTap: p == null
          ? null
          : () {
              model.selectEntry(setlist, entry);
              onOpened();
            },
      menu: {
        'Rename…': () async {
          final t = await _askName(context, 'Rename', entry.title);
          if (t != null) model.updateEntry(entry, title: t);
        },
        'Colour…': () async {
          final c = await _pickColor(context, entry.color);
          if (c != null) model.updateEntry(entry, color: c);
        },
        'Remove from setlist': () => model.removeEntry(setlist, entry),
      },
    );
  }
}

/// Divider / label / event row inside a setlist.
class _MarkerRow extends StatelessWidget {
  final PresenterModel model;
  final Setlist setlist;
  final SetEntry entry;
  final Widget handle;

  const _MarkerRow({
    required this.model,
    required this.setlist,
    required this.entry,
    required this.handle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorNamed(entry.color) ?? scheme.outline;
    final menu = PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (v) async {
        switch (v) {
          case 'rename':
            final t = await _askName(context, 'Rename', entry.title);
            if (t != null) model.updateEntry(entry, title: t);
          case 'color':
            final c = await _pickColor(context, entry.color);
            if (c != null) model.updateEntry(entry, color: c);
          case 'remove':
            model.removeEntry(setlist, entry);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'color', child: Text('Colour…')),
        PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );

    final Widget body = switch (entry.type) {
      EntryType.divider => Row(
        children: [
          Text(
            entry.title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color, thickness: 1.5)),
        ],
      ),
      EntryType.label => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(inkR(12)),
            border: Border.all(
              color: color.withValues(alpha: 0.6),
              width: inkW(1),
            ),
          ),
          child: Text(entry.title, style: const TextStyle(fontSize: 12)),
        ),
      ),
      _ => Row(
        children: [
          Icon(Icons.event, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.title,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          handle,
          Expanded(child: body),
          menu,
        ],
      ),
    );
  }
}

/// List row with optional subtitle, tag dots, key text and a ⋯ menu.
class _Row extends StatelessWidget {
  final Widget? leading;
  final String title;

  /// The song's icon, before its title.
  final IconData? icon;
  final String? subtitle;

  /// Where the search was found in the lyrics, shown in quotes with the
  /// [query] words in bold.
  final String? snippet;
  final String query;
  final List<Color> dots;
  final String? trailingText;
  final bool selected;
  final bool dimmed;
  final Color? accent;
  final VoidCallback? onTap;
  final Map<String, VoidCallback> menu;

  const _Row({
    this.leading,
    required this.title,
    this.icon,
    this.subtitle,
    this.snippet,
    this.query = '',
    this.dots = const [],
    this.trailingText,
    required this.selected,
    required this.onTap,
    required this.menu,
    this.dimmed = false,
    this.accent,
  });

  /// "[snippet]" with the words of [query] in bold.
  static TextSpan _snippetSpan(String snippet, String query) {
    final words = searchWords(query).toList();
    bool hit(String token) => searchWords(
      token,
    ).any((w) => words.any((q) => q == words.last ? w.startsWith(q) : w == q));
    final parts = <TextSpan>[const TextSpan(text: '“')];
    for (final m in RegExp(r'\S+|\s+').allMatches(snippet)) {
      final t = m[0]!;
      parts.add(
        TextSpan(
          text: t,
          style: t.trim().isNotEmpty && hit(t)
              ? const TextStyle(fontWeight: FontWeight.w700)
              : null,
        ),
      );
    }
    parts.add(const TextSpan(text: '”'));
    return TextSpan(children: parts);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: accent == null
          ? null
          : BoxDecoration(
              border: Border(
                left: BorderSide(color: accent!, width: inkW(3)),
              ),
            ),
      // Own transparent Material: the selected-row fill is painted here, so
      // it scrolls and clips with the list instead of being painted on the
      // sidebar behind it (which drew it over the tag bar when scrolled).
      child: Material(
        // The selected fill behind the whole row (the key and ⋯ too).
        color: selected
            ? StyleExtras.of(context).selectedRowColor
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(inkR(8)),
        ),
        clipBehavior: Clip.antiAlias,
        // The key and ⋯ beside the tile rather than as its trailing: there
        // they sat below the middle of two-line rows. One tap / hover area
        // for the whole row, so its highlight covers all of it.
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Expanded(child: _tile(context, scheme)),
              _trailing(context, scheme),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, ColorScheme scheme) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.only(left: 12),
    selected: selected,
    selectedColor: StyleExtras.of(context).selectedRowText,
    // Its own fills off: the row's Material and InkWell paint them, across
    // the whole row.
    selectedTileColor: Colors.transparent,
    tileColor: Colors.transparent,
    leading: leading,
    minLeadingWidth: 0,
    // The key and ⋯ centred on the row (two lines or one).
    titleAlignment: ListTileTitleAlignment.center,
    title: Row(
      children: [
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(icon, size: 16, color: scheme.primary),
          ),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dimmed ? TextStyle(color: scheme.outline) : null,
          ),
        ),
        for (final c in dots.take(3))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: CircleAvatar(radius: 4, backgroundColor: c),
          ),
      ],
    ),
    subtitle: subtitle == null && snippet == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (snippet != null)
                Text.rich(
                  _snippetSpan(snippet!, query),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
  );

  Widget _trailing(BuildContext context, ColorScheme scheme) {
    final on = selected ? StyleExtras.of(context).selectedRowText : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailingText != null) ...[
          Text(
            trailingText!,
            style: TextStyle(
              fontSize: 12,
              color: on ?? scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
        ],
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_horiz, size: 18, color: on),
          onSelected: (k) => menu[k]!(),
          itemBuilder: (_) => [
            for (final k in menu.keys) PopupMenuItem(value: k, child: Text(k)),
          ],
        ),
      ],
    );
  }
}

// ---- Dialogs ----

Future<String?> _askName(
  BuildContext context,
  String title,
  String initial, {
  String hint = 'e.g. Sunday Service',
}) {
  return showAppDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, hint: hint),
  );
}

/// Owns its text controller so it is disposed only after the dialog's
/// closing animation finishes.
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.hint,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Delete',
}) async {
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Returns a colour name, '' for "no colour", or null if cancelled.
Future<String?> _pickColor(BuildContext context, String? current) {
  return showAppDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Colour'),
      contentPadding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final name in ['', ...namedColors.keys])
              Tooltip(
                message: name.isEmpty ? 'None' : name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, name),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor:
                        namedColors[name] ??
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: name == (current ?? '')
                        ? const Icon(Icons.check, size: 16)
                        : (name.isEmpty
                              ? const Icon(Icons.block, size: 16)
                              : null),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// The song's icon (OnSong's song icons), picked from a grid; saved at
/// once.
Future<void> _chooseSongIcon(
  BuildContext context,
  PresenterModel model,
  Song song,
) async {
  const none = '';
  final current = song.extra['icon'] as String?;
  final picked = await showAppDialog<String>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      Widget tile(String id, Widget icon, String label) {
        final selected = (current ?? none) == id;
        return Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(inkR(12)),
            onTap: () => Navigator.pop(context, id),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(inkR(12)),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: inkW(selected ? 2 : 1),
                ),
              ),
              child: Center(child: icon),
            ),
          ),
        );
      }

      return AlertDialog(
        title: Text('Icon for “${song.displayTitle}”'),
        content: SizedBox(
          width: 360,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tile(
                none,
                Text('None', style: TextStyle(color: scheme.onSurfaceVariant)),
                'No icon',
              ),
              for (final MapEntry(key: id, value: (icon, label))
                  in songIcons.entries)
                tile(id, Icon(icon, color: scheme.primary), label),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
  if (picked == null || picked == (current ?? none)) return;
  model.setIconOf(song.id, picked == none ? null : picked);
}

Future<Setlist?> _pickSetlist(BuildContext context, PresenterModel model) {
  return showAppDialog<Setlist>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to setlist'),
      children: [
        for (final set in model.setlists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, set),
            child: Text(set.name),
          ),
      ],
    ),
  );
}

Future<List<String>?> _pickSongs(BuildContext context, PresenterModel model) {
  final chosen = <String>[];
  var query = '';
  final all = [...model.songs]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return showAppDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        // The side pane's search: title, artist and lyrics, best first.
        final q = query.trim();
        final songs = q.isEmpty
            ? all
            : ([
                    for (final s in all)
                      if (s.searchRank(q) case final r?) (s, r),
                  ]..sort((a, b) => a.$2.compareTo(b.$2)))
                  .map((e) => e.$1)
                  .toList();
        return AlertDialog(
          title: const Text('Add songs'),
          content: SizedBox(
            width: 420,
            height: 460,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, i) {
                      final song = songs[i];
                      final n = chosen.indexOf(song.id);
                      return CheckboxListTile(
                        dense: true,
                        value: n >= 0,
                        title: Text(song.displayTitle),
                        // Found in the lyrics: where (as in the side pane).
                        subtitle: switch (q.isEmpty
                            ? null
                            : song.searchSnippet(q)) {
                          final snip? => Text(
                            snip,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          _ when song.artist.isNotEmpty => Text(song.artist),
                          _ => null,
                        },
                        // Shows the order songs will be added in.
                        secondary: n >= 0
                            ? CircleAvatar(
                                radius: 11,
                                child: Text(
                                  '${n + 1}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              )
                            : null,
                        onChanged: (v) => setState(() {
                          v == true
                              ? chosen.add(song.id)
                              : chosen.remove(song.id);
                        }),
                      );
                    },
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
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, chosen),
              child: Text(chosen.isEmpty ? 'Add' : 'Add ${chosen.length}'),
            ),
          ],
        );
      },
    ),
  );
}

/// Edit a setlist's name, event date and notes.
class _SetlistDetailsDialog extends StatefulWidget {
  final PresenterModel model;
  final Setlist setlist;
  const _SetlistDetailsDialog({required this.model, required this.setlist});

  @override
  State<_SetlistDetailsDialog> createState() => _SetlistDetailsDialogState();
}

class _SetlistDetailsDialogState extends State<_SetlistDetailsDialog> {
  late final _name = TextEditingController(text: widget.setlist.name);
  late final _notes = TextEditingController(text: widget.setlist.notes);
  late DateTime? _date = widget.setlist.eventDate;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Setlist details'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _date == null ? 'No event date' : formatDate(_date!),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: const Text('Pick date'),
                ),
                if (_date != null)
                  IconButton(
                    tooltip: 'Clear date',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _date = null),
                  ),
              ],
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
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
          onPressed: () {
            final name = _name.text.trim();
            widget.model.updateSetlist(
              widget.setlist,
              name: name.isEmpty ? null : name,
              eventDate: _date,
              clearEventDate: _date == null,
              notes: _notes.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Add, rename, recolour, hide and delete tags.
class _TagManager extends StatelessWidget {
  final PresenterModel model;
  const _TagManager({required this.model});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final counts = <String, int>{};
        for (final s in model.songs) {
          for (final t in s.tags) {
            counts[t] = (counts[t] ?? 0) + 1;
          }
        }
        // Phones: nearly the full width, compact buttons.
        final screen = MediaQuery.sizeOf(context);
        final compact = screen.width < 600;
        return AlertDialog(
          title: const Text('Tags'),
          insetPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 24)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          contentPadding: compact
              ? const EdgeInsets.fromLTRB(8, 12, 8, 0)
              : const EdgeInsets.fromLTRB(24, 20, 24, 24),
          content: SizedBox(
            width: compact ? screen.width - 20 - 16 : 460,
            height: compact ? screen.height * 0.6 : 420,
            child: model.tags.isEmpty
                ? const Center(child: Text('No tags yet.'))
                : ListView(
                    children: [
                      for (final tag in model.tags)
                        ListTile(
                          dense: true,
                          leading: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              final c = await _pickColor(context, tag.color);
                              if (c != null) model.updateTag(tag, color: c);
                            },
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor:
                                  colorNamed(tag.color) ?? Colors.grey.shade500,
                            ),
                          ),
                          contentPadding: compact
                              ? const EdgeInsets.symmetric(horizontal: 8)
                              : null,
                          horizontalTitleGap: compact ? 10 : null,
                          title: Text(
                            tag.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${counts[tag.id] ?? 0} songs'
                            '${tag.hidden ? ' · hidden from All Songs' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : null,
                                tooltip: tag.hidden
                                    ? 'Show in All Songs'
                                    : 'Hide from All Songs',
                                icon: Icon(
                                  tag.hidden
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () =>
                                    model.updateTag(tag, hidden: !tag.hidden),
                              ),
                              IconButton(
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : null,
                                tooltip: 'Rename',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  final n = await _askName(
                                    context,
                                    'Rename tag',
                                    tag.name,
                                    hint: 'Tag name',
                                  );
                                  if (n != null) model.updateTag(tag, name: n);
                                },
                              ),
                              IconButton(
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : null,
                                tooltip: model.openChordsLinkFor(tag.id) == null
                                    ? 'Share these songs on OpenChords'
                                    : 'OpenChords link & sync',
                                icon: Icon(
                                  model.openChordsLinkFor(tag.id) == null
                                      ? Icons.share_outlined
                                      : Icons.cloud_done_outlined,
                                ),
                                onPressed: () =>
                                    showOpenChordsShareTag(context, model, tag),
                              ),
                              IconButton(
                                visualDensity: compact
                                    ? VisualDensity.compact
                                    : null,
                                tooltip: 'Delete tag',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await _confirm(
                                    context,
                                    'Delete tag?',
                                    '"${tag.name}" will be removed from '
                                        '${counts[tag.id] ?? 0} songs. '
                                        'The songs are kept.',
                                  );
                                  if (ok) model.deleteTag(tag);
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final n = await _askName(
                  context,
                  'New tag',
                  '',
                  hint: 'e.g. Communion',
                );
                if (n != null) model.addTag(n, color: 'blue');
              },
              child: const Text('New tag'),
            ),
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

/// Reports its child's height after layout (for the A–Z jump estimate).
class _MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _MeasureHeight({required this.onHeight, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight r) =>
      r.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  ValueChanged<double> onHeight;
  _RenderMeasureHeight(this.onHeight);

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// Band Sync, in the side pane: your nickname, sessions on the network to
/// join, a setlist to lead, and the session you're in.
class _BandSyncPane extends StatefulWidget {
  final PresenterModel model;
  final ValueChanged<String> onOpenSetlist;
  const _BandSyncPane({required this.model, required this.onOpenSetlist});

  @override
  State<_BandSyncPane> createState() => _BandSyncPaneState();
}

class _BandSyncPaneState extends State<_BandSyncPane> {
  PresenterModel get model => widget.model;
  BandSync get band => model.bandSync;
  late final _nick = TextEditingController(text: model.settings.bandNickname);

  @override
  void initState() {
    super.initState();
    if (band.role == BandSyncRole.idle) band.scan();
  }

  @override
  void dispose() {
    if (band.role == BandSyncRole.idle) band.stopScan();
    _nick.dispose();
    super.dispose();
  }

  void _saveNick() {
    final v = _nick.text.trim();
    if (v != model.settings.bandNickname) {
      model.updateSettings((s) => s.bandNickname = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([band, model]),
      builder: (context, _) {
        Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
          child: Text(t, style: theme.textTheme.titleSmall),
        );
        Widget note(String t, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            t,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color ?? scheme.onSurfaceVariant,
            ),
          ),
        );
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          children: [
            note(
              'Play together on the same Wi-Fi: one device leads a setlist, '
              'the others follow its songs, sections and scrolling. Works '
              'with JustChords (PlayTogether) on iPad and Mac too.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: TextField(
                controller: _nick,
                enabled: band.role == BandSyncRole.idle,
                decoration: InputDecoration(
                  labelText: 'Your name',
                  hintText: band.nickname,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _saveNick(),
                onTapOutside: (_) => _saveNick(),
              ),
            ),
            if (band.error case final e?) note(e, color: scheme.error),
            ...switch (band.role) {
              BandSyncRole.leading => _leading(heading, note),
              BandSyncRole.following => _following(heading, note),
              BandSyncRole.idle => _idle(heading, note),
            },
          ],
        );
      },
    );
  }

  List<Widget> _leading(
    Widget Function(String) heading,
    Widget Function(String, {Color? color}) note,
  ) {
    final set = band.leadingSetlist;
    return [
      heading('Leading'),
      _Row(
        leading: const Icon(Icons.podcasts),
        title: set?.name ?? 'Setlist',
        subtitle: 'Others can join as “${band.nickname}”',
        selected: true,
        onTap: set == null ? null : () => widget.onOpenSetlist(set.id),
        menu: const {},
      ),
      heading('Following you (${band.followers.length})'),
      if (band.followers.isEmpty)
        note(
          'No one yet. On the other devices: Band Sync (or '
          'JustChords → Tools → PlayTogether), then pick this session.',
        ),
      for (final f in band.followers)
        _Row(
          leading: const Icon(Icons.tablet_mac_outlined),
          title: f,
          selected: false,
          onTap: null,
          menu: const {},
        ),
      Padding(
        padding: const EdgeInsets.all(10),
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop session'),
          onPressed: band.stopLeading,
        ),
      ),
    ];
  }

  List<Widget> _following(
    Widget Function(String) heading,
    Widget Function(String, {Color? color}) note,
  ) {
    final s = band.leader;
    final set = model.bandSetlist;
    final online = band.status == 'Leader online';
    return [
      heading('Following'),
      _Row(
        leading: Icon(online ? Icons.wifi_tethering : Icons.wifi_tethering_off),
        title: set?.name ?? s?.title ?? 'Session',
        subtitle: [if (s != null) 'from ${s.leader}', ?band.status].join(' · '),
        selected: true,
        onTap: set == null ? null : () => widget.onOpenSetlist(set.id),
        menu: const {},
      ),
      note(
        'The leader’s setlist is in Setlists while you follow; '
        'nothing is saved to your library.',
      ),
      Padding(
        padding: const EdgeInsets.all(10),
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.logout),
          label: const Text('Leave session'),
          onPressed: band.leave,
        ),
      ),
    ];
  }

  List<Widget> _idle(
    Widget Function(String) heading,
    Widget Function(String, {Color? color}) note,
  ) {
    final theme = Theme.of(context);
    return [
      if (band.status case final st?) note(st),
      Row(
        children: [
          Expanded(child: heading('Available sessions')),
          if (band.scanning)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox.square(
                dimension: 16,
                child: AppSpinner(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Scan again',
            icon: const Icon(Icons.refresh),
            onPressed: band.scan,
          ),
        ],
      ),
      if (band.sessions.isEmpty) note('Looking for sessions on this network…'),
      for (final s in band.sessions)
        _Row(
          leading: const Icon(Icons.podcasts),
          title: s.title.isEmpty ? 'Session' : s.title,
          subtitle: 'from ${s.leader}',
          selected: false,
          onTap: () => band.join(s),
          menu: const {},
        ),
      heading('New session'),
      if (model.setlists.isEmpty)
        note('Make a setlist first, then lead it from here.')
      else
        note('Lead a setlist: pick it.'),
      for (final set in model.setlists)
        _Row(
          leading: Icon(
            Icons.queue_music,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: set.name,
          subtitle: '${set.songCount} song${set.songCount == 1 ? '' : 's'}',
          selected: false,
          onTap: () async {
            await band.lead(set);
            if (band.role == BandSyncRole.leading &&
                set.entries.any((e) => e.type == EntryType.song)) {
              widget.onOpenSetlist(set.id);
            }
          },
          menu: const {},
        ),
    ];
  }
}
