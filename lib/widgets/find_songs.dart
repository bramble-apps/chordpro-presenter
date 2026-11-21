import 'dart:convert';

import 'package:flutter/material.dart';

import '../browser.dart';
import '../music.dart';
import '../song_sources.dart';
import '../state.dart';
import '../themes.dart';
import '../eink.dart';
import '../bramble_icons.dart';

/// Find songs online, in the side pane: one search across the song sites,
/// a preview, and "Add to library". Sites that won't hand songs to the app
/// open in the browser; a song copied from anywhere can be pasted in.
class FindSongsPane extends StatefulWidget {
  final PresenterModel model;

  /// Opens with the paste box ready.
  final bool paste;

  /// Opens the song editor for a found song; true if it was saved (only
  /// then is it added to the library).
  final Future<bool> Function(Song song) onEdit;

  const FindSongsPane({
    super.key,
    required this.model,
    required this.onEdit,
    this.paste = false,
  });

  @override
  State<FindSongsPane> createState() => _FindSongsPaneState();
}

/// One site's part of a search.
class _SiteResults {
  List<SongHit> hits = const [];
  bool loading = true;
  String? error;
}

class _FindSongsPaneState extends State<FindSongsPane> {
  PresenterModel get model => widget.model;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, _SiteResults> _results = {};
  String _searched = '';
  int _search = 0; // the latest search (older ones are ignored)

  // The open result.
  SongHit? _open;
  FoundSong? _song;
  String? _songError;
  final Set<String> _added = {};

  /// Sites showing all their results (others show the first few).
  final Set<String> _expanded = {};
  static const _perSite = 6;

  // Pasting.
  late bool _pasting = widget.paste;
  final _paste = TextEditingController();
  final _pasteTitle = TextEditingController();
  final _pasteArtist = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _paste.dispose();
    _pasteTitle.dispose();
    _pasteArtist.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final id = ++_search;
    setState(() {
      _searched = q;
      _open = null;
      _expanded.clear();
      _results
        ..clear()
        ..addAll({for (final s in searchSites) s: _SiteResults()});
    });
    await Future.wait([
      for (final site in searchSites)
        searchSite(site, q, langs: model.settings.songDbLangs).then(
          (hits) {
            if (!mounted || id != _search) return;
            setState(() {
              _results[site]!
                ..hits = hits
                ..loading = false;
            });
          },
          onError: (Object e) {
            if (!mounted || id != _search) return;
            setState(() {
              _results[site]!
                ..error = e is SongSourceError ? e.message : "Couldn't search"
                ..loading = false;
            });
          },
        ),
    ]);
  }

  /// Opened in the in-app browser and imported from there (Cifra Club:
  /// the site turns away apps that fetch its pages themselves).
  bool _viaBrowser(SongHit hit) =>
      hit.source == cifraSite && canImportFromBrowser;

  Future<void> _openHit(SongHit hit) async {
    if (_viaBrowser(hit)) {
      setState(() {
        _open = hit;
        _song = null;
        _songError = null;
      });
      final page = await importFromBrowser(context, hit.url, cifraPageScript);
      if (!mounted || _open != hit) return;
      if (page == null) {
        // Closed without importing: back to the results.
        setState(() => _open = null);
        return;
      }
      try {
        final song = cifraClubFromPage(
          jsonDecode(page) as Map<String, dynamic>,
          hit.url,
        );
        setState(() => _song = song);
      } catch (e) {
        setState(
          () => _songError = e is SongSourceError
              ? e.message
              : "Couldn't read the song on that page.",
        );
      }
      return;
    }
    if (hit.opensInBrowser) {
      openUrl(hit.url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${hit.source} opened in your browser. Copy the song there, '
            'then paste it below.',
          ),
        ),
      );
      setState(() => _pasting = true);
      return;
    }
    setState(() {
      _open = hit;
      _song = null;
      _songError = null;
    });
    try {
      final song = await fetchSong(hit);
      if (mounted && _open == hit) setState(() => _song = song);
    } catch (e) {
      if (mounted && _open == hit) {
        setState(
          () => _songError = e is SongSourceError
              ? e.message
              : "Couldn't open that song.",
        );
      }
    }
  }

  bool _inLibrary(String title, String artist) {
    final t = foldAccents(title.toLowerCase().trim());
    final a = foldAccents(artist.toLowerCase().trim());
    return model.songs.any(
      (s) =>
          foldAccents(s.title.toLowerCase().trim()) == t &&
          (a.isEmpty || foldAccents(s.artist.toLowerCase().trim()) == a),
    );
  }

  /// Opens the full editor with the found song; it's added on Save.
  Future<void> _add(FoundSong f) async {
    final song = Song(
      title: f.title.isEmpty ? 'Untitled' : f.title,
      raw: f.raw,
      artist: f.artist,
      capo: f.capo,
      // With a capo the chords are shapes: let the app work the key out.
      key: f.capo == 0 && f.key.isNotEmpty ? MusicKey.parse(f.key) : null,
      copyright: f.copyright,
      ccli: f.ccli,
      structure: f.structure,
      extra: {'source': f.url},
    );
    final saved = await widget.onEdit(song);
    if (!saved || !mounted) return;
    setState(() => _added.add(f.url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${model.currentSong?.title}" to your library'),
      ),
    );
  }

  /// The pasted song in the full editor; it's added on Save.
  Future<void> _addPasted() async {
    var text = _paste.text;
    final guess = guessTitle(text);
    // The title line isn't part of the song.
    if (guess != null && _pasteTitle.text.trim() == guess.$1) {
      final lines = text.split('\n');
      final i = lines.indexWhere((l) => l.trim().isNotEmpty);
      if (i >= 0) text = lines.sublist(i + 1).join('\n');
    }
    final raw = pastedToChordPro(text);
    if (raw.trim().isEmpty) return;
    final song = Song(
      title: _pasteTitle.text.trim(),
      artist: _pasteArtist.text.trim(),
      raw: raw,
    );
    final saved = await widget.onEdit(song);
    if (!saved || !mounted) return;
    _paste.clear();
    _pasteTitle.clear();
    _pasteArtist.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${model.currentSong?.title}" to your library'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_open != null) return _preview(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      children: [
        TextField(
          key: const Key('find-songs'),
          controller: _query,
          autofocus: !widget.paste,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Type song name',
            prefixIcon: const Icon(BrambleIcons.magnifyingGlass, size: 20),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(BrambleIcons.xCircleFill, size: 18),
                    onPressed: () => setState(() {
                      _query.clear();
                      _results.clear();
                      _searched = '';
                    }),
                  ),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(inkR(24)),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_searched.isEmpty)
          _card(
            context,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 12),
              child: Text(
                'Type a song name and press Enter to search\n'
                'Ultimate Guitar, Worship Together, Worship Leader, '
                'chords-and-tabs.net, Chordie and Cifra Club at once.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          _resultList(context),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Search other sites'),
        _card(context, _otherSites(context)),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Paste a song'),
        _card(context, _pasteBox(context)),
        const SizedBox(height: 16),
        _sectionTitle(context, 'Worship Leader song database'),
        _card(context, _languages(context)),
        const SizedBox(height: 16),
        _card(
          context,
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Songs found here belong to their writers and publishers. '
              'This app doesn\'t host, sell or license any of them: it only '
              'fetches what a site already shows, when you ask. A song '
              'being free to read online doesn\'t make it free to project, '
              'print or share, so make sure you\'re covered (for example by '
              'a CCLI licence) and follow each site\'s terms.',
              key: const Key('find-disclaimer'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A rounded card (a Material, so rows inside show their hover / press).
  Widget _card(BuildContext context, Widget child) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(
      StyleExtras.of(context).panelRadius + 6,
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _resultList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (final site in searchSites) {
      final r = _results[site];
      if (r == null) continue;
      if (r.loading) {
        rows.add(
          ListTile(
            dense: true,
            leading: const SizedBox.square(
              dimension: 18,
              child: AppSpinner(strokeWidth: 2),
            ),
            title: Text('Searching $site…'),
          ),
        );
        continue;
      }
      if (r.error != null) {
        rows.add(
          ListTile(
            dense: true,
            leading: Icon(
              BrambleIcons.cloudSlash,
              size: 18,
              color: scheme.outline,
            ),
            title: Text(site),
            subtitle: Text(r.error!),
          ),
        );
        continue;
      }
      final all = _expanded.contains(site);
      for (final hit in all ? r.hits : r.hits.take(_perSite)) {
        rows.add(_hitRow(context, hit));
      }
      if (!all && r.hits.length > _perSite) {
        rows.add(
          ListTile(
            dense: true,
            leading: Icon(BrambleIcons.caretDown, color: scheme.primary),
            title: Text(
              'More from $site (${r.hits.length - _perSite})',
              style: TextStyle(color: scheme.primary),
            ),
            onTap: () => setState(() => _expanded.add(site)),
          ),
        );
      }
    }
    final done = _results.values.every((r) => !r.loading);
    if (done && rows.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('No songs found.', textAlign: TextAlign.center),
        ),
      );
    }
    return _card(
      context,
      Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _hitRow(BuildContext context, SongHit hit) {
    final scheme = Theme.of(context).colorScheme;
    final have = _added.contains(hit.url) || _inLibrary(hit.title, hit.artist);
    final stars = hit.rating == null
        ? ''
        : '${'★' * hit.rating!.round().clamp(0, 5)}'
              '${hit.votes == null ? '' : ' (${hit.votes})'}';
    final sub = [
      if (hit.artist.isNotEmpty) hit.artist,
      if (stars.isNotEmpty) stars,
      if (hit.rating == null && hit.votes != null) '${hit.votes} votes',
    ].join(', ');
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: () => _openHit(hit),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  Text(
                    hit.opensInBrowser && !_viaBrowser(hit)
                        ? '${hit.source} · opens in your browser'
                        : hit.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small?.copyWith(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (have)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Tooltip(
                  message: 'In your library',
                  child: Icon(
                    BrambleIcons.checkCircleFill,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
              ),
            Icon(
              hit.opensInBrowser && !_viaBrowser(hit)
                  ? BrambleIcons.arrowSquareOut
                  : BrambleIcons.caretRight,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final theme = Theme.of(context);
    final hit = _open!;
    final song = _song;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to results',
              icon: const Icon(BrambleIcons.arrowLeft),
              onPressed: () => setState(() => _open = null),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.title ?? hit.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if ((song?.artist ?? hit.artist).isNotEmpty)
                        song?.artist ?? hit.artist,
                      hit.source,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(
                    song != null && _added.contains(song.url)
                        ? BrambleIcons.check
                        : BrambleIcons.tbLibraryPlus,
                    size: 18,
                  ),
                  label: Text(
                    song != null && _added.contains(song.url)
                        ? 'Added'
                        : 'Add to library',
                  ),
                  onPressed: song == null || _added.contains(song.url)
                      ? null
                      : () => _add(song),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Open on ${hit.source}',
                icon: const Icon(BrambleIcons.arrowSquareOut, size: 18),
                onPressed: () => openUrl(hit.url),
              ),
            ],
          ),
        ),
        if (song != null && (song.capo > 0 || song.key.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              [
                if (song.key.isNotEmpty) 'Key ${song.key}',
                if (song.capo > 0) 'Capo ${song.capo}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(inkR(8)),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: inkW(1),
              ),
            ),
            child: song != null
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      song.raw,
                      key: const Key('found-song-text'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  )
                : Center(
                    child: _songError != null
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _songError!,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const AppSpinner(),
                  ),
          ),
        ),
      ],
    );
  }

  List<BrowseSite> get _customSites => [
    for (final j in model.settings.songSites) ?BrowseSite.fromJson(j),
  ];

  Widget _otherSites(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.text.trim();
    Widget row(BrowseSite site, {bool custom = false}) => ListTile(
      dense: true,
      title: Text(site.name),
      subtitle: Text(
        q.isNotEmpty && site.searchUrl.contains('{q}')
            ? 'Search "$q" in your browser'
            : 'Opens in your browser',
      ),
      onTap: () => openUrl(site.urlFor(q)),
      trailing: custom
          ? IconButton(
              tooltip: 'Remove ${site.name}',
              icon: const Icon(BrambleIcons.x, size: 18),
              onPressed: () => model.updateSettings(
                (s) => s.songSites.removeWhere(
                  (j) => j['name'] == site.name && j['url'] == site.searchUrl,
                ),
              ),
            )
          : const Icon(BrambleIcons.arrowSquareOut, size: 18),
    );
    return Column(
      children: [
        for (final s in browseSites) row(s),
        for (final s in _customSites) row(s, custom: true),
        ListTile(
          dense: true,
          leading: Icon(BrambleIcons.plus, color: scheme.primary),
          title: const Text('Add site'),
          onTap: _addSite,
        ),
      ],
    );
  }

  Future<void> _addSite() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a song site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. hymnary.org',
              ),
            ),
            TextField(
              controller: url,
              decoration: const InputDecoration(
                labelText: 'Search link',
                hintText: 'https://hymnary.org/search?qu={q}',
                helperText: '{q} is replaced by the song name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final n = name.text.trim();
    var u = url.text.trim();
    name.dispose();
    url.dispose();
    if (ok != true || u.isEmpty) return;
    if (!u.startsWith('http')) u = 'https://$u';
    final label = n.isNotEmpty ? n : (Uri.tryParse(u)?.host ?? u);
    model.updateSettings((s) => s.songSites.add({'name': label, 'url': u}));
  }

  Widget _pasteBox(BuildContext context) {
    if (!_pasting) {
      return ListTile(
        dense: true,
        leading: const Icon(BrambleIcons.clipboardText),
        title: const Text('Paste a song copied from any website'),
        subtitle: const Text('Chords above the words become ChordPro'),
        onTap: () => setState(() => _pasting = true),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          TextField(
            key: const Key('paste-song'),
            controller: _paste,
            autofocus: widget.paste,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: const InputDecoration(
              hintText: 'Paste the song here (chords above the words)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (text) {
              final g = guessTitle(text);
              if (g != null && _pasteTitle.text.isEmpty) {
                _pasteTitle.text = g.$1;
                if (_pasteArtist.text.isEmpty) _pasteArtist.text = g.$2;
              }
              setState(() {});
            },
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('paste-title'),
                  controller: _pasteTitle,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _pasteArtist,
                  decoration: const InputDecoration(
                    labelText: 'Artist',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          FilledButton.icon(
            icon: const Icon(BrambleIcons.tbLibraryPlus, size: 18),
            label: const Text('Add to library'),
            onPressed: _paste.text.trim().isEmpty ? null : _addPasted,
          ),
        ],
      ),
    );
  }

  Widget _languages(BuildContext context) {
    final on = model.settings.songDbLangs;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            'Searched offline: each language is downloaded once from '
            'worshipleaderapp.com (their free database) and refreshed '
            'weekly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in worshipLeaderLanguages.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: on.contains(e.key),
                  onSelected: (v) => model.updateSettings((s) {
                    final list = [...s.songDbLangs];
                    v ? list.add(e.key) : list.remove(e.key);
                    s.songDbLangs = list;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
