import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bible.dart';
import '../browser.dart';
import '../eink.dart';
import '../state.dart';
import '../themes.dart';

/// Presentation mode's Bible tool. Top: the version (and, when added, a
/// second one shown beside it) and the chapter, with arrows to the next
/// and previous one. Middle: the chapter; tap a verse, then another for a
/// range. Bottom: show it, line it up in the queue, or save it in a
/// setlist. Passages never go in the song library.
class BiblePane extends StatefulWidget {
  final PresenterModel model;

  /// Room under the tool to keep it clear of the toolbar.
  final double bottomClearance;

  const BiblePane({super.key, required this.model, this.bottomClearance = 0});

  @override
  State<BiblePane> createState() => _BiblePaneState();
}

enum _View { verses, queue, saved }

class _BiblePaneState extends State<BiblePane> {
  BibleLibrary get lib => BibleLibrary.instance;
  PresenterModel get model => widget.model;

  Bible? _bible;
  String? _loaded;

  String? _error;

  String _book = '43';
  int _chapter = 3;
  int _from = 16;
  int _to = 16;
  _View _view = _View.verses;

  @override
  void initState() {
    super.initState();
    lib.addListener(_changed);
    lib.start().then((_) {
      final last = lib.last;
      if (last != null) {
        _book = last.book;
        _chapter = last.chapter;
        _from = last.from;
        _to = last.to;
      }
      _open(lib.version);
    });
  }

  @override
  void dispose() {
    lib.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open(String id) async {
    setState(() => _error = null);
    try {
      final bible = await lib.load(id);
      if (!mounted) return;
      setState(() {
        _bible = bible;
        _loaded = id;
        _keepInRange();
      });
      _reveal();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open $id: $e');
    }
  }

  /// Keeps the chosen book, chapter and verses ones the version has.
  void _keepInRange() {
    final bible = _bible;
    if (bible == null || bible.books.isEmpty) return;
    final book = bible.book(_book) ?? bible.books.first;
    _book = book.number;
    if (book.chapters.isEmpty) return;
    final ch = book.chapter(_chapter) ?? book.chapters.first;
    _chapter = ch.numberValue;
    final last = ch.verses.isEmpty ? 1 : ch.verses.last.numberValue;
    _from = _from.clamp(1, last);
    _to = _to.clamp(_from, last);
  }

  BibleBook? get _bookNow => _bible?.book(_book);
  Chapter? get _chapterNow => _bookNow?.chapter(_chapter);

  BiblePassage get _passage => BiblePassage(
    version: lib.version,
    second: lib.second,
    book: _book,
    chapter: _chapter,
    from: _from,
    to: _to,
    perSlide: lib.perSlide,
  );

  void _say(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  void _goTo(String book, int chapter, int from, int to) {
    setState(() {
      _book = book;
      _chapter = chapter;
      _from = from;
      _to = to;
      _view = _View.verses;
      _keepInRange();
    });
    _reveal();
  }

  /// The next (+1) or previous (-1) chapter, on into the next book.
  void _stepChapter(int dir) {
    final bible = _bible, book = _bookNow;
    if (bible == null || book == null) return;
    final i = book.chapters.indexWhere((c) => c.numberValue == _chapter) + dir;
    if (i >= 0 && i < book.chapters.length) {
      _goTo(book.number, book.chapters[i].numberValue, 1, 1);
      return;
    }
    final b = bible.books.indexOf(book) + dir;
    if (b < 0 || b >= bible.books.length) return;
    final next = bible.books[b];
    if (next.chapters.isEmpty) return;
    final ch = dir > 0 ? next.chapters.first : next.chapters.last;
    _goTo(next.number, ch.numberValue, 1, 1);
  }

  Future<void> _pick() async {
    final bible = _bible;
    if (bible == null) return;
    final r = await showAppDialog<_Picked>(
      context: context,
      builder: (context) =>
          _PassagePicker(bible: bible, book: _book, version: lib.version),
    );
    if (r != null) _goTo(r.book, r.chapter, r.from, r.to);
  }

  /// Tap a verse: that verse. Tap another: the range between them. Tap
  /// again: start over at that verse.
  void _tapVerse(int v) {
    setState(() {
      if (_from == _to && v != _from) {
        if (v < _from) {
          _from = v;
        } else {
          _to = v;
        }
      } else {
        _from = _to = v;
      }
    });
  }

  Future<void> _show(BiblePassage p) async {
    try {
      await model.showPassage(p);
    } catch (e) {
      _say('Could not show ${p.reference}: $e');
    }
  }

  /// The passage on screen again, after a change to how passages look
  /// (one shown from this tool, not from a setlist).
  void _refreshLive({String? second, bool noSecond = false}) {
    final live = model.currentPassage;
    if (live == null || model.passageFromSetlist) return;
    _show(
      live.copyWith(second: second, noSecond: noSecond, perSlide: lib.perSlide),
    );
  }

  void _setVersion(String id) {
    lib.version = id;
    if (lib.second == id) lib.second = null;
    lib.save();
    _open(id);
  }

  void _setSecond(String? id) {
    lib.second = id;
    lib.save();
    _refreshLive(second: id, noSecond: id == null);
  }

  Future<void> _import() async {
    final files = await pickBinaryFiles(const ['.xml']);
    for (final (name, bytes) in files) {
      try {
        final info = await lib.importXml(name, bytes);
        _say('Added ${info.name} (${info.id}).');
      } catch (e) {
        _say('$name: ${e is FormatException ? e.message : e}');
      }
    }
  }

  Future<void> _remove(BibleVersionInfo v) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${v.name}?'),
        content: const Text(
          'Passages saved in setlists with this version stay, but can\'t '
          'show until you import it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await lib.remove(v.id);
    if (_loaded == v.id) _open(lib.version);
  }

  Future<void> _saveToSetlist() async {
    final p = _passage;
    final name = TextEditingController();
    void create(BuildContext context) {
      final t = name.text.trim();
      if (t.isNotEmpty) Navigator.pop(context, model.createSetlist(t));
    }

    final set = await showAppDialog<Setlist>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save ${p.reference} in a setlist'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in model.setlists)
                ListTile(
                  leading: const Icon(Icons.queue_music_outlined),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.entries.length} item'
                    '${s.entries.length == 1 ? '' : 's'}',
                  ),
                  onTap: () => Navigator.pop(context, s),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          hintText: 'New setlist…',
                          isDense: true,
                        ),
                        onSubmitted: (_) => create(context),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Create it and save',
                      icon: const Icon(Icons.add),
                      onPressed: () => create(context),
                    ),
                  ],
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
        ],
      ),
    );
    name.dispose();
    if (set == null) return;
    model.addPassageToSetlist(set, p);
    _say('Saved ${p.reference} in ${set.name}.');
  }

  /// Height of every control in the top row and in the action pill (a
  /// comfortable touch target).
  static const _control = 40.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final verses = _view == _View.verses;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, c.maxWidth),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _body(context)),
                    // The verses fade in under the top row…
                    if (verses && !isEink(context))
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 22,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  _backdrop(context),
                                  _backdrop(context).withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (verses && _chapterNow != null) ...[
                      // …and out behind the action pill.
                      if (!isEink(context))
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _control + 56,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: const [0, 0.75],
                                  colors: [
                                    _backdrop(context).withValues(alpha: 0),
                                    _backdrop(context),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 10,
                        child: _actions(context, c.maxWidth),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: widget.bottomClearance),
            ],
          );
        },
      ),
    );
  }

  /// What the tool sits on (the fade under the verses ends in it).
  Color _backdrop(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  // ---- Top: chapter, versions ----

  /// One of the top row's controls: all the same height, in the theme's
  /// toolbar shape and colour.
  Widget _pill(
    BuildContext context, {
    Key? key,
    required Widget child,
    bool selected = false,
    bool raised = false,
    double height = _control,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final extras = StyleExtras.of(context);
    return Material(
      key: key,
      color: selected ? extras.selectedRowColor : scheme.surfaceContainerHigh,
      shape: extras.toolbarShape,
      elevation: raised ? inkE(extras.toolbarElevation) : 0,
      shadowColor: Colors.black54,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(height: height, child: child),
    );
  }

  Widget _pillLabel(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
  );

  /// "‹ John 3 ›": the chapter (tap to choose another) between arrows to
  /// the previous and the next one.
  Widget _chapterPill(BuildContext context, {bool tight = false}) {
    final book = _bookNow;
    Widget arrow(IconData icon, String tip, int dir) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: () => _stepChapter(dir),
        child: SizedBox(
          width: tight ? 28 : 40,
          height: _control,
          child: Icon(icon),
        ),
      ),
    );
    return _pill(
      context,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, 'Previous chapter', -1),
          Flexible(
            child: Tooltip(
              message: 'Choose a book and chapter, or type a passage',
              child: InkWell(
                key: const Key('bible-pick'),
                onTap: _bible == null ? null : _pick,
                child: Container(
                  height: _control,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _pillLabel(
                    book == null ? '…' : '${book.name} $_chapter',
                  ),
                ),
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 'Next chapter', 1),
        ],
      ),
    );
  }

  /// A version: opens the list of versions. [onRemove]: with a × (the
  /// second version).
  Widget _versionPill(
    BuildContext context, {
    required String id,
    required String tooltip,
    required Iterable<BibleVersionInfo> choices,
    required ValueChanged<String> onChanged,
    VoidCallback? onRemove,
  }) {
    return _pill(
      context,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: tooltip,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final v in choices)
                CheckedPopupMenuItem(
                  value: v.id,
                  checked: v.id == id,
                  child: Text('${v.id} · ${v.name}'),
                ),
            ],
            child: Container(
              height: _control,
              alignment: Alignment.center,
              padding: EdgeInsets.only(
                left: 14,
                right: onRemove == null ? 6 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pillLabel(id),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            Tooltip(
              message: 'Show one version only',
              child: InkWell(
                onTap: onRemove,
                child: const SizedBox(
                  width: 36,
                  height: _control,
                  child: Icon(Icons.close, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "+ Version": puts a second version beside the first.
  Widget _addVersion(BuildContext context, {required bool label}) {
    final others = [
      for (final v in lib.versions)
        if (v.id != lib.version) v,
    ];
    final scheme = Theme.of(context).colorScheme;
    final face = Container(
      height: _control,
      alignment: Alignment.center,
      padding: EdgeInsets.only(left: 12, right: label ? 16 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 20, color: scheme.primary),
          if (label) ...[
            const SizedBox(width: 4),
            Text(
              'Version',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
    // One other version: a tap adds it. More: a tap lists them.
    return _pill(
      context,
      key: const Key('bible-add-version'),
      child: others.length == 1
          ? Tooltip(
              message: 'Show ${others.first.id} beside ${lib.version}',
              child: InkWell(
                onTap: () => _setSecond(others.first.id),
                child: face,
              ),
            )
          : PopupMenuButton<String>(
              tooltip: 'Show a second version beside ${lib.version}',
              enabled: others.isNotEmpty,
              onSelected: _setSecond,
              itemBuilder: (_) => [
                for (final v in others)
                  PopupMenuItem(
                    value: v.id,
                    child: Text('${v.id} · ${v.name}'),
                  ),
              ],
              child: face,
            ),
    );
  }

  /// Options. [lists]: with the queue and the saved passages (narrow
  /// tools, which have no room for their own buttons).
  Widget _moreMenu(BuildContext context, {required bool lists}) {
    final queued = lib.queue.length;
    final saved = model.savedPassages.length;
    return _pill(
      context,
      child: PopupMenuButton<String>(
        tooltip: 'Options',
        onSelected: (v) {
          switch (v) {
            case 'queue':
              setState(() => _view = _View.queue);
            case 'saved':
              setState(() => _view = _View.saved);
            case 'import':
              _import();
            case 'numbers':
              lib.numbers = !lib.numbers;
              lib.save();
              _refreshLive();
            case 'reference':
              lib.reference = !lib.reference;
              lib.save();
              _refreshLive();
            default:
              if (v.startsWith('per:')) {
                lib.perSlide = int.parse(v.substring(4));
                lib.save();
                _refreshLive();
              } else if (lib.versionById(v) case final info?) {
                _remove(info);
              }
          }
        },
        itemBuilder: (_) => [
          if (lists) ...[
            PopupMenuItem(
              value: 'queue',
              child: ListTile(
                key: const Key('bible-queue'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.playlist_play),
                title: Text(queued == 0 ? 'Queue' : 'Queue ($queued)'),
              ),
            ),
            PopupMenuItem(
              value: 'saved',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmarks_outlined),
                title: Text(
                  saved == 0
                      ? 'Saved in setlists'
                      : 'Saved in setlists ($saved)',
                ),
              ),
            ),
            const PopupMenuDivider(),
          ],
          const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text('Verses on each slide'),
          ),
          for (final n in const [1, 2, 3, 4])
            CheckedPopupMenuItem(
              value: 'per:$n',
              height: 40,
              checked: lib.perSlide == n,
              child: Text('$n'),
            ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: 'numbers',
            checked: lib.numbers,
            child: const Text('Verse numbers'),
          ),
          CheckedPopupMenuItem(
            value: 'reference',
            checked: lib.reference,
            child: const Text('Reference under the verses'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'import',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.file_open_outlined),
              title: Text('Import a Bible (XML)…'),
            ),
          ),
          for (final v in lib.versions)
            if (!v.bundled)
              PopupMenuItem(
                value: v.id,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text('Remove ${v.id}'),
                ),
              ),
        ],
        child: SizedBox(
          width: _control,
          height: _control,
          child: Center(
            child: Badge(
              isLabelVisible: lists && queued > 0,
              label: Text('$queued'),
              child: const Icon(Icons.more_vert),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the queue or the saved passages (wide tools).
  Widget _viewToggle(
    BuildContext context, {
    required _View view,
    required IconData icon,
    required String label,
    required int count,
    Key? key,
  }) {
    final on = _view == view;
    final extras = StyleExtras.of(context);
    return _pill(
      context,
      selected: on,
      child: Tooltip(
        message: on ? 'Back to the verses' : label,
        child: InkWell(
          key: key,
          onTap: () => setState(() => _view = on ? _View.verses : view),
          child: SizedBox(
            width: _control,
            height: _control,
            child: Center(
              child: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: Icon(icon, color: on ? extras.selectedRowText : null),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, double width) {
    final second = lib.second;
    // Wide tools: the lists get buttons, "+ Version" its word.
    final wide = width >= 520;
    const gap = SizedBox(width: 6);
    return Padding(
      // (Edge to edge, like the panels above it.)
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        children: [
          // (The chapter gives way first when there's little room.)
          Expanded(
            child: Row(
              children: [
                Flexible(
                  // (Narrow tools: slimmer arrows, room for the name.)
                  child: _chapterPill(context, tight: width < 360),
                ),
                gap,
                _versionPill(
                  context,
                  id: lib.version,
                  tooltip: 'Version',
                  choices: lib.versions,
                  onChanged: _setVersion,
                ),
                gap,
                if (second == null)
                  _addVersion(context, label: width >= 400)
                else
                  _versionPill(
                    context,
                    id: second,
                    tooltip: 'Version shown beside ${lib.version}',
                    choices: lib.versions.where((v) => v.id != lib.version),
                    onChanged: _setSecond,
                    onRemove: () => _setSecond(null),
                  ),
              ],
            ),
          ),
          gap,
          if (wide) ...[
            _viewToggle(
              context,
              key: const Key('bible-queue'),
              view: _View.queue,
              icon: Icons.playlist_play,
              label: 'Queue',
              count: lib.queue.length,
            ),
            gap,
            _viewToggle(
              context,
              view: _View.saved,
              icon: Icons.bookmarks_outlined,
              label: 'Saved in setlists',
              count: model.savedPassages.length,
            ),
            gap,
          ],
          _moreMenu(context, lists: !wide),
        ],
      ),
    );
  }

  // ---- Middle: verses, queue, saved ----

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_bible == null) {
      return const Center(
        child: SizedBox(width: 28, height: 28, child: AppSpinner()),
      );
    }
    return switch (_view) {
      _View.verses => _verses(context),
      _View.queue => _queue(context),
      _View.saved => _saved(context),
    };
  }

  /// The first picked verse (scrolled into view by [_reveal]).
  final _fromKey = GlobalKey();

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _fromKey.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c, alignment: 0.15);
      }
    });
  }

  /// The chapter. [scrolls]: on its own (else inside a scrolling parent).
  Widget _verses(BuildContext context, {bool scrolls = true}) {
    final verses = _chapterNow?.verses ?? const <Verse>[];
    final current = model.currentPassage;
    // Every verse built (a chapter is at most 176), so the picked one can
    // be scrolled to.
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final v in verses) _verse(context, v, current)],
    );
    // (Room under the last verse for the action pill.)
    const padding = EdgeInsets.fromLTRB(0, 10, 0, _control + 40);
    if (!scrolls) return Padding(padding: padding, child: list);
    return SingleChildScrollView(
      key: PageStorageKey('bible-$_loaded-$_book-$_chapter'),
      padding: padding,
      child: list,
    );
  }

  Widget _verse(BuildContext context, Verse v, BiblePassage? current) {
    final scheme = Theme.of(context).colorScheme;
    final extras = StyleExtras.of(context);
    final n = v.numberValue;
    final picked = n >= _from && n <= _to;
    final live =
        current != null &&
        current.book == _book &&
        current.chapter == _chapter &&
        n >= current.from &&
        n <= current.to;
    // A range reads as one block: only its ends are rounded.
    final r = Radius.circular(inkR(extras.panelRadius));
    final shape = BorderRadius.vertical(
      top: !picked || n == _from ? r : Radius.zero,
      bottom: !picked || n == _to ? r : Radius.zero,
    );
    return Material(
      key: n == _from ? _fromKey : null,
      color: picked ? extras.selectedRowColor : Colors.transparent,
      borderRadius: shape,
      child: InkWell(
        borderRadius: shape,
        onTap: () => _tapVerse(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 9, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  v.number,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.6,
                    color: live
                        ? scheme.primary
                        : picked
                        ? extras.selectedRowText
                        : scheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.text,
                  style: TextStyle(
                    color: picked ? extras.selectedRowText : null,
                    height: 1.35,
                  ),
                ),
              ),
              if (live)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(Icons.slideshow, size: 16, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Queue" / "Saved" with a way back to the verses.
  Widget _listTitle(String title, {List<Widget> actions = const []}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to the verses',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _view = _View.verses),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _passageTile(
    BuildContext context, {
    Key? key,
    required BiblePassage p,
    String? note,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final live = model.currentPassage == p;
    return ListTile(
      key: key,
      dense: true,
      selected: live,
      leading: Icon(live ? Icons.slideshow : Icons.menu_book_outlined),
      title: Text(p.reference),
      subtitle: Text([?note, p.versions].join(' · ')),
      onTap: onTap,
      trailing: trailing,
    );
  }

  Widget _queue(BuildContext context) {
    return Column(
      children: [
        _listTitle(
          'Queue',
          actions: [
            if (lib.queue.isNotEmpty) ...[
              TextButton(onPressed: lib.clearQueue, child: const Text('Clear')),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.skip_next),
                label: const Text('Show next'),
                onPressed: () {
                  final p = lib.queue.first;
                  lib.dequeue(0);
                  _show(p);
                },
              ),
            ],
          ],
        ),
        Expanded(
          child: lib.queue.isEmpty
              ? const _Empty(
                  icon: Icons.playlist_add,
                  text:
                      'Nothing lined up. Pick verses and press the queue '
                      'button next to Show.',
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  buildDefaultDragHandles: false,
                  itemCount: lib.queue.length,
                  onReorderItem: lib.reorder,
                  itemBuilder: (context, i) {
                    final p = lib.queue[i];
                    return _passageTile(
                      context,
                      key: ValueKey('q$i-${p.key}'),
                      p: p,
                      note: i == 0 ? 'Next' : '${i + 1}',
                      onTap: () {
                        lib.dequeue(i);
                        _show(p);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Remove from the queue',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => lib.dequeue(i),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle, size: 20),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _saved(BuildContext context) {
    final saved = model.savedPassages;
    return Column(
      children: [
        _listTitle('Saved in setlists'),
        Expanded(
          child: saved.isEmpty
              ? const _Empty(
                  icon: Icons.bookmark_add_outlined,
                  text:
                      'Nothing saved. Pick verses and press the bookmark '
                      'next to Show: the passage goes in a setlist (never '
                      'in the song library).',
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final (set, entry) in saved)
                      _passageTile(
                        context,
                        p: entry.passage!,
                        note: set.name,
                        onTap: () => model.selectEntry(set, entry),
                        trailing: IconButton(
                          tooltip: 'Remove from ${set.name}',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => model.removeEntry(set, entry),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  // ---- Bottom: the action pill ----

  /// The picked verses and what to do with them, floating over the end
  /// of the chapter: add to the queue, save in a setlist, show.
  Widget _actions(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final p = _passage;
    final slides = ((_to - _from + 1) / lib.perSlide).ceil();
    // Room for words on Queue and Save.
    final labels = width >= 460;
    Widget action({
      Key? key,
      required IconData icon,
      required String label,
      required String tooltip,
      required VoidCallback onPressed,
    }) => labels
        ? Tooltip(
            message: tooltip,
            child: TextButton.icon(
              key: key,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, _control),
                foregroundColor: scheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: Icon(icon),
              label: Text(label),
              onPressed: onPressed,
            ),
          )
        : IconButton(
            key: key,
            tooltip: tooltip,
            constraints: const BoxConstraints.tightFor(
              width: _control,
              height: _control,
            ),
            icon: Icon(icon),
            onPressed: onPressed,
          );
    return _pill(
      context,
      raised: true,
      height: _control + 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pillLabel(p.referenceIn(_bible)),
                  Text(
                    slides == 1 ? '1 slide' : '$slides slides',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            action(
              key: const Key('bible-queue-add'),
              icon: Icons.playlist_add,
              label: 'Queue',
              tooltip: 'Add to the queue',
              onPressed: () {
                lib.enqueue(p);
                _say('${p.reference} is in the queue.');
              },
            ),
            action(
              icon: Icons.bookmark_add_outlined,
              label: 'Save',
              tooltip: 'Save in a setlist',
              onPressed: _saveToSetlist,
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              key: const Key('bible-show'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, _control),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                // The full control height whatever the platform (desktops
                // shrink buttons) and no extra touch margin: the same gap
                // to the pill's edge above, below and at the end.
                fixedSize: const Size.fromHeight(_control),
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.slideshow),
              label: const Text('Show'),
              onPressed: () => _show(p),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.outline),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Picked = ({String book, int chapter, int from, int to});

/// Choose a passage: type it ("Jn 3:16-18"), or tap a book, then a
/// chapter.
class _PassagePicker extends StatefulWidget {
  final Bible bible;
  final String book;
  final String version;

  const _PassagePicker({
    required this.bible,
    required this.book,
    required this.version,
  });

  @override
  State<_PassagePicker> createState() => _PassagePickerState();
}

class _PassagePickerState extends State<_PassagePicker> {
  final _text = TextEditingController();

  /// The book whose chapters show (null: the list of books).
  BibleBook? _book;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _go() {
    final r = parsePassage(_text.text, widget.bible);
    if (r == null) {
      setState(
        () => _error = _text.text.trim().isEmpty
            ? null
            : 'No such passage in ${widget.version}',
      );
      return;
    }
    Navigator.pop<_Picked>(context, r);
  }

  Widget _tile(
    BuildContext context, {
    required String label,
    required bool current,
    required double width,
    required VoidCallback onTap,
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(inkR(8)),
      side: BorderSide(color: scheme.outlineVariant, width: inkW(1)),
    );
    return SizedBox(
      key: key,
      width: width,
      height: 40,
      child: Material(
        color: current ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                    color: current ? scheme.onSecondaryContainer : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 0, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );

  Widget _books(BuildContext context, double width) {
    const gap = 6.0;
    final columns = width >= 380 ? 4 : 3;
    final tile = ((width - gap * (columns - 1)) / columns).floorToDouble();
    int number(BibleBook b) => int.tryParse(b.number) ?? 99;
    Widget group(String title, Iterable<BibleBook> books) {
      final list = books.toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, title),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final b in list)
                _tile(
                  context,
                  key: ValueKey('bible-book-${b.number}'),
                  label: b.name,
                  current: b.number == widget.book,
                  width: tile,
                  onTap: () {
                    // One chapter: nothing more to choose.
                    if (b.chapters.length == 1) {
                      Navigator.pop<_Picked>(context, (
                        book: b.number,
                        chapter: b.chapters.first.numberValue,
                        from: 1,
                        to: 1,
                      ));
                    } else {
                      setState(() => _book = b);
                    }
                  },
                ),
            ],
          ),
        ],
      );
    }

    final all = widget.bible.books;
    return ListView(
      children: [
        group('Old Testament', all.where((b) => number(b) <= 39)),
        group(
          'New Testament',
          all.where((b) => number(b) >= 40 && number(b) <= 66),
        ),
        group('Other books', all.where((b) => number(b) > 66)),
      ],
    );
  }

  Widget _chapters(BuildContext context, BibleBook book, double width) {
    const gap = 6.0;
    final columns = width >= 380 ? 7 : 5;
    final tile = ((width - gap * (columns - 1)) / columns).floorToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'All books',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _book = null),
            ),
            Text(
              book.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in book.chapters)
                  _tile(
                    context,
                    key: ValueKey('bible-chapter-${c.number}'),
                    label: c.number,
                    current: false,
                    width: tile,
                    onTap: () => Navigator.pop<_Picked>(context, (
                      book: book.number,
                      chapter: c.numberValue,
                      from: 1,
                      to: 1,
                    )),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final book = _book;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      title: TextField(
        controller: _text,
        // (Not on phones: the keyboard would cover the books.)
        autofocus: size.width >= 600,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Type a passage: John 3:16-18',
          errorText: _error,
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(inkR(10)),
          ),
          suffixIcon: IconButton(
            tooltip: 'Go',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _go,
          ),
        ),
        onSubmitted: (_) => _go(),
      ),
      content: SizedBox(
        width: 460,
        height: math.min(460, size.height * 0.62),
        child: LayoutBuilder(
          builder: (context, c) => book == null
              ? _books(context, c.maxWidth)
              : _chapters(context, book, c.maxWidth),
        ),
      ),
    );
  }
}
