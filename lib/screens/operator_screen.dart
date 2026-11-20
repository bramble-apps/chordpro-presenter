import 'dart:math' as math;
import 'dart:convert';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../chordpro.dart';
import '../music.dart';
import '../song_sources.dart';
import '../autoscroll.dart';
import '../browser.dart';
import '../cast_feeder.dart';
import '../native.dart';
import '../fonts.dart';
import '../gospelizer.dart';
import '../metronome.dart';
import '../state.dart';
import '../themes.dart';
import '../widgets/cast_dialog.dart';
import '../widgets/chord_sheet.dart';
import '../widgets/song_swipe.dart';
import '../widgets/sticky_note.dart';
import '../widgets/pad_panel.dart';
import '../widgets/tuner_panel.dart';
import '../widgets/floating_panel.dart';
import '../widgets/media_pip.dart';
import '../widgets/media_pane.dart';
import '../media_library.dart' show mimeOfName;
import '../widgets/metronome_icon.dart';
import '../widgets/presentation_view.dart';
import '../widgets/projection_view.dart';
import '../widgets/format_pane.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/share_dialog.dart';
import '../widgets/sidebar.dart';
import '../widgets/song_editor.dart';
import '../widgets/structure_editor.dart';
import '../widgets/sidebar_icon.dart';
import '../widgets/ink_layer.dart';
import '../widgets/capo_icon.dart';
import '../widgets/capo_neck.dart';
import '../widgets/key_finder.dart';
import '../widgets/key_wheel.dart';
import '../widgets/ink_toolbar.dart';
import '../toolbar_items.dart';
import '../widgets/toolbar_editor.dart';
import '../chords/chord_db.dart';
import '../chords/chord_library.dart';
import '../chords/chord_strip.dart';
import '../pdfs.dart';
import '../widgets/import_dialog.dart';
import '../widgets/pdf_view.dart';
import '../widgets/sheet_images.dart';
import '../eink.dart';

/// Main window: sidebar | chord sheet | optional format panel.
class OperatorScreen extends StatefulWidget {
  final PresenterModel model;
  const OperatorScreen({super.key, required this.model});

  @override
  State<OperatorScreen> createState() => _OperatorScreenState();
}

class _OperatorScreenState extends State<OperatorScreen>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showFormat = false;

  /// Preview hidden by the user while projecting.
  bool _previewHidden = false;

  /// Sidebar visible (fixed mode) / open (floating mode).
  /// Whether the sidebar is open. Toggling it rebuilds only what depends
  /// on it (not the chord sheets): see the ValueListenableBuilder in build.
  late final _open = ValueNotifier<bool>(
    !widget.model.settings.floatingSidebar,
  );
  bool get _sidebarOpen => _open.value;
  set _sidebarOpen(bool value) => _open.value = value;

  /// The docked sidebar sliding in (1) and out (0). While it slides, the
  /// sidebar and the sheet just move as pictures; the sheet is laid out
  /// at its new width once (when closing: at the start; when opening: at
  /// the end), not on every frame, so it stays smooth with long songs.
  late final AnimationController _side = AnimationController(
    vsync: this,
    duration: _slide,
    value: _sidebarOpen ? 1 : 0,
  );

  PresenterModel get model => widget.model;

  bool _updateShown = false;

  /// The reference recording playing in the little floating player.
  String? _pipUrl;
  String _pipTitle = '';

  void _play(Song song) {
    final url = song.audioUrl.trim();
    // A web page the app can't show itself, or YouTube where the app has
    // no embedded web player (desktop): open it in the browser.
    if (!canPlayInApp(url) || (youTubeInBrowser && youtubeId(url) != null)) {
      openUrl(url);
      return;
    }
    setState(() {
      _pipUrl = url;
      _pipTitle = song.displayTitle;
    });
  }

  /// Floats over everything; drag by its bar, resize at the corner.
  Widget _pip() => Positioned.fill(
    child: FloatingPanel(
      id: 'player',
      heightFor: MediaPip.heightFor,
      initialWidth: 340,
      minWidth: 240,
      maxWidth: 900,
      start: const Alignment(-1, 0.75),
      child: MediaPip(
        url: _pipUrl!,
        title: _pipTitle,
        onClose: () => setState(() => _pipUrl = null),
      ),
    ),
  );

  /// Offers a reload when the app has been rebuilt.
  void _checkUpdate() {
    if (!model.updateAvailable || _updateShown || !mounted) return;
    _updateShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: const Text(
          'A new version is ready. Projector screens updated themselves.',
        ),
        action: SnackBarAction(label: 'Reload', onPressed: reloadPage),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    model.addListener(_checkUpdate);
    HardwareKeyboard.instance.addHandler(_onKey);
    // Files dragged onto the window are imported like picked ones.
    // So are files and text shared to the app or opened with it.
    listenForDroppedFiles(
      onDragging: (over) => _dropping.value = over,
      onDrop: _importFiles,
      onText: _importSharedText,
    );
    _ink.addListener(_inkModeChanged);
    // Chord shapes for the diagrams (the sheets redraw once loaded).
    ChordLibrary.load().then((_) {
      if (mounted) setState(() {});
    });
    model.addListener(_inkFollowView);
    // The panels as they were left (closing the app or rotating).
    final ui = model;
    _open.value = ui.uiValue<bool>('op.sidebar') ?? _open.value;
    _showFormat = ui.uiValue<bool>('op.format') ?? false;
    _tunerOpen = ui.uiValue<bool>('op.tuner') ?? false;
    _padsOpen = ui.uiValue<bool>('op.pads') ?? false;
    mediaPaneOpen.value = ui.uiValue<bool>('op.media') ?? mediaPaneOpen.value;
    if (ui.uiValue<num>('op.mediaHeight') case final h?) {
      mediaPaneHeight.value = h.toDouble();
    }
    _open.addListener(_remember);
    mediaPaneOpen.addListener(_remember);
    mediaPaneHeight.addListener(_remember);
  }

  /// Notes which panels are open (see initState).
  void _remember() {
    model
      ..setUi('op.sidebar', _open.value)
      ..setUi('op.format', _showFormat)
      ..setUi('op.tuner', _tunerOpen)
      ..setUi('op.pads', _padsOpen)
      ..setUi('op.media', mediaPaneOpen.value)
      ..setUi('op.mediaHeight', mediaPaneHeight.value.roundToDouble());
  }

  // ---- Annotating ----

  final _ink = InkController();

  (bool, InkTarget) _inkMode = (false, InkTarget.sheet);

  /// The screen changes only when annotating starts / stops or switches
  /// between the sheet and the slide (not on every stroke).
  void _inkModeChanged() {
    final mode = (_ink.active, _ink.target);
    if (mode != _inkMode) setState(() => _inkMode = mode);
  }

  /// What annotating draws on follows the view: the slides in
  /// presentation mode (the slide grid), otherwise the chord sheet.
  void _inkFollowView() {
    _ink.target = model.settings.presentationMode
        ? InkTarget.slide
        : InkTarget.sheet;
  }

  void _toggleAnnotate() {
    _inkFollowView();
    _ink.active = !_ink.active;
  }

  /// The tool pill, floating over the song area like the video player and
  /// sticky notes: drag or throw it anywhere; it settles against edges.
  Widget _inkPill(Alignment start) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, box) {
        final size = InkToolbar.size;
        // Phones: shrunk to fit the width.
        final w = math.min(size.width, box.maxWidth - 16);
        final h = size.height * w / size.width;
        return FloatingPanel(
          id: 'ink-tools',
          freeAspect: true,
          resizable: false,
          dragAnywhere: true,
          initialWidth: w,
          minWidth: w,
          maxWidth: w,
          initialHeight: h,
          minHeight: h,
          maxHeight: h,
          margin: 8,
          start: start,
          child: FittedBox(
            child: InkToolbar(
              controller: _ink,
              onDone: () => _ink.active = false,
            ),
          ),
        );
      },
    ),
  );

  /// Annotating the slide: the preview, as wide as the song area, to draw
  /// on (what is drawn shows on the projector).
  Widget _inkSlideBoard(EdgeInsets padding) {
    final size = model.projectorSize;
    final song = model.currentSong;
    return Positioned.fill(
      child: Padding(
        padding: padding,
        child: Center(
          child: AspectRatio(
            aspectRatio: size.width / size.height,
            child: Material(
              elevation: inkE(8),
              color: Colors.black,
              // An outline, so a black slide stands out from the dark app.
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  StyleExtras.of(context).panelRadius,
                ),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: inkW(2),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: ProjectorDisplay(
                        data: model.projectionDataWith(ink: false),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      _ink,
                      model.inkVersion,
                      model.selection,
                    ]),
                    builder: (context, _) {
                      final i = model.selection.value;
                      final all = model.slideInk;
                      if (song == null || i < 0 || i >= all.length) {
                        return const SizedBox.shrink();
                      }
                      _ink.bind(
                        'slide|${song.id}|$i',
                        () => model.slideInk[i],
                        (v) => model.setSlideInk(i, v),
                      );
                      return InkCanvas(
                        strokes: all[i],
                        controller: _ink,
                        editable: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    mediaPaneOpen.removeListener(_remember);
    mediaPaneHeight.removeListener(_remember);
    _sliding.dispose();
    _open.dispose();
    SongSwipe.resizing.value = false;
    _side.dispose();
    _slideTimer?.cancel();
    model.removeListener(_checkUpdate);
    HardwareKeyboard.instance.removeHandler(_onKey);
    model.removeListener(_inkFollowView);
    _ink
      ..removeListener(_inkModeChanged)
      ..dispose();
    super.dispose();
  }

  /// Arrow keys and space change slides, unless the user is typing.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final key = event.logicalKey;
    // Arrows, Page Up/Down (what most Bluetooth page-turner pedals send)
    // and Space move the selected part, which is also what is projected.
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      model.next();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      model.previous();
      return true;
    }
    if (key == LogicalKeyboardKey.keyB && event is KeyDownEvent) {
      model.toggleBlackout();
      return true;
    }
    if (key == LogicalKeyboardKey.home) {
      model.firstSlide();
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      model.lastSlide();
      return true;
    }
    return false;
  }

  /// Opens the editor; true if it was saved. A song not in the library
  /// yet (new, or found online) is only added on Save.
  Future<bool> _edit(Song song) async {
    final saved = await SongEditor.show(
      context,
      song.copy(),
      tags: model.tags,
      model: model,
    );
    if (saved != null) model.addOrUpdate(saved);
    return saved != null;
  }

  Future<void> _editStructure() async {
    final song = model.currentSong;
    if (song == null) return;
    // With songs nested under it: their parts too (the words themselves
    // are each song's own, so they aren't changed here).
    final nested = model.activeEntry?.subSongIds.isNotEmpty ?? false;
    final played = model.playedCurrentSong ?? song;
    final result = await StructureEditor.show(
      context,
      raw: played.raw,
      initial: model.currentStructure,
      songKey: model.currentKey,
      subtitle: model.activeEntry != null ? 'For this setlist only' : null,
      inSetlist: model.activeEntry != null,
      title: song.title,
      translateTo: model.settings.translateTo,
      onTranslateTo: (code) =>
          model.updateSettings((s) => s.translateTo = code),
    );
    if (result == null) return;
    model.setStructure(
      result.structure,
      raw: !nested && result.raw != song.raw ? result.raw : null,
    );
  }

  Future<void> _confirmDelete(Song song) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text(
          '"${song.displayTitle}" will move to the Trash. '
          'You can restore it from ☰ → Trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (ok == true) model.deleteSong(song.id);
  }

  Future<void> _import() async {
    await _importFiles(
      await pickBinaryFiles(const [
        '.json',
        '.zip',
        ...sheetMusicExtensions,
        '.cho',
        '.chopro',
        '.chordpro',
        '.crd',
        '.pro',
        '.txt',
        '.show',
        '.onsong',
        '.onsongarchive',
        '.sbp',
        '.sbpbackup',
      ]),
    );
  }

  /// True while files are dragged over the window (the drop target shows).
  final _dropping = ValueNotifier(false);

  /// What the bottom of presentation mode depends on: the media pane
  /// (open, height) and the floating toolbar's size.
  final Listenable _bottomLayout = Listenable.merge([
    mediaPaneOpen,
    mediaPaneHeight,
    bottomBarSize,
    _topBarSize,
  ]);

  /// The media pane's height along the bottom (0: closed, or no room: on
  /// narrow screens it's a tab of presentation mode instead).
  double _paneHeight(BoxConstraints box) {
    if (!model.settings.presentationMode || model.currentSong == null) return 0;
    if (!mediaPaneOpen.value || box.maxWidth < 600) return 0;
    return mediaPaneHeight.value.clamp(150.0, box.maxHeight * 0.65);
  }

  /// The media pane along the bottom, edge to edge.
  Widget _bottomPane(double height) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: height,
    child: MediaPane(
      model: model,
      horizontal: true,
      onClose: () => mediaPaneOpen.value = false,
    ),
  );

  /// Imports [files] (picked, or dropped on the window).
  Future<void> _importFiles(List<(String, Uint8List)> files) async {
    if (files.isEmpty || !mounted) return;
    // Media goes to the media library: everything while its pane is open,
    // videos and audio always (pictures otherwise become picture songs).
    final paneOpen = _mediaPaneShown;
    bool toLibrary((String, Uint8List) f) {
      final mime = mimeOfName(f.$1);
      return mime.isNotEmpty && (paneOpen || !mime.startsWith('image/'));
    }

    final media = files.where(toLibrary).toList();
    if (media.isNotEmpty) {
      final n = await addDroppedMedia(model, media);
      if (!paneOpen && model.settings.presentationMode) {
        mediaPaneOpen.value = true;
      }
      _say('Added $n file${n == 1 ? '' : 's'} to Media.');
      files = files.where((f) => !toLibrary(f)).toList();
      if (files.isEmpty || !mounted) return;
    }
    // Backup zips (songs.json + PDFs) and PDFs (each a song); the rest is
    // text. Read it all first, then ask what to do with what's already here.
    final batch = ImportBatch();
    final texts = <(String, String)>[];
    for (final (name, bytes) in files) {
      if (looksLikeZip(bytes)) {
        batch.addAll(await readBackupZip(model, bytes));
      } else if (PdfStore.looksLikeSheetMusic(bytes)) {
        batch.songs.add(await pdfSong(name, bytes));
      } else {
        texts.add((name, utf8.decode(bytes, allowMalformed: true)));
      }
    }
    batch.addAll(model.readImport(texts));
    await _finishImport(batch);
  }

  /// Asks about songs already here (if any), adds [batch], says what came.
  Future<void> _finishImport(ImportBatch batch) async {
    if (!mounted) return;
    final options = batch.isEmpty
        ? const ImportOptions()
        : await askImportOptions(context, model, batch);
    if (options == null || !mounted) return;
    final summary = model.applyImport(batch, options);
    _say(
      batch.isEmpty
          ? 'Nothing to import in the selected file.'
          : summary.isEmpty
          ? 'Nothing new to import.'
          : summary.toString(),
    );
  }

  /// The media pane is showing (presentation mode, open).
  bool get _mediaPaneShown =>
      model.settings.presentationMode && mediaPaneOpen.value;

  /// A message (replacing the one showing, so the latest is seen).
  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Text shared to the app (Android "Share →"): a link to a song on a site
  /// the app reads is fetched; other text is taken as the song itself.
  Future<void> _importSharedText(String text, String? subject) async {
    // A remote control link: chordpropresenter://next, …://slide/3,
    // …://song?title=Amazing%20Grace, …://blackout?on=true.
    if (text.trim().toLowerCase().startsWith('chordpropresenter:')) {
      final uri = Uri.tryParse(text.trim());
      if (uri == null) return;
      final parts = [uri.host, ...uri.pathSegments].where((p) => p.isNotEmpty);
      final action = parts.firstOrNull ?? '';
      final value =
          parts.skip(1).firstOrNull ??
          uri.queryParameters['title'] ??
          uri.queryParameters['on'] ??
          uri.queryParameters['n'];
      if (!model.remote(action, value)) _say('Unknown link: $text');
      return;
    }
    final url = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
    final around = url == null ? text : text.replaceFirst(url, '');
    // A link, perhaps with the page's title: the song on that page.
    if (url != null && around.trim().split('\n').length <= 2) {
      try {
        final found = await songFromLink(url);
        if (!mounted) return;
        if (found == null) {
          _say(
            'Songs from that site can’t be read yet: share or paste the '
            'song’s text instead.',
          );
          return;
        }
        await _finishImport(
          ImportBatch()
            ..songs.add(
              Song(
                title: found.title.isEmpty ? 'Untitled' : found.title,
                raw: found.raw,
                artist: found.artist,
                capo: found.capo,
                key: found.capo == 0 && found.key.isNotEmpty
                    ? MusicKey.parse(found.key)
                    : null,
                copyright: found.copyright,
                ccli: found.ccli,
                structure: found.structure,
                date: DateTime.now(),
                extra: {'source': found.url},
              ),
            ),
        );
      } catch (_) {
        if (mounted) _say('Couldn’t read the song at that link.');
      }
      return;
    }
    if (text.trim().isEmpty) return;
    final raw = pastedToChordPro(text);
    final firstLine = text.trim().split('\n').first.trim();
    final title = (subject ?? '').trim().isNotEmpty
        ? subject!.trim()
        : ChordProHeader.parse(raw).titles.firstOrNull ??
              (firstLine.length <= 60 ? firstLine : 'Shared song');
    await _finishImport(
      ImportBatch()
        ..songs.add(Song(title: title, raw: raw, date: DateTime.now())),
    );
  }

  /// True while the sidebar slides; it ignores the mouse meanwhile so the
  /// buttons passing under the pointer don't flash hover highlights.
  final _sliding = ValueNotifier<bool>(false);
  Timer? _slideTimer;

  // Only the sidebar's IgnorePointer listens to this (no rebuild of the
  // whole screen when a slide starts or ends).
  void _markSliding() {
    _slideTimer?.cancel();
    _sliding.value = true;
    SongSwipe.resizing.value = true;
    _slideTimer = Timer(_slide + const Duration(milliseconds: 60), () {
      _sliding.value = false;
      // The songs before and after catch up once all is still.
      _slideTimer = Timer(const Duration(milliseconds: 350), () {
        SongSwipe.resizing.value = false;
      });
    });
  }

  void _toggleSidebar(bool narrow) {
    _markSliding();
    if (narrow) {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      _sidebarOpen = !_sidebarOpen;
      if (isEink(context)) {
        _side.value = _sidebarOpen ? 1 : 0;
        return;
      }
      // Bramble Notes' (Apple's) sidebar motion: quick off the mark, a
      // long gentle settle; opening a touch slower than closing
      _sidebarOpen
          ? _side.animateTo(
              1,
              duration: const Duration(milliseconds: 250),
              curve: _NotesSlide.show,
            )
          : _side.animateBack(
              0,
              duration: const Duration(milliseconds: 217),
              curve: _NotesSlide.hide,
            );
    }
  }

  /// The docked sidebar beside the sheet (see [_side]). The sheet's left
  /// edge follows the sidebar frame by frame; its right side (toolbar,
  /// edge) stays put. Only the song on screen is laid out each frame (the
  /// songs either side hold theirs, see SongSwipe.resizing), and its chord
  /// lines just re-wrap (ChordLine), so this stays cheap.
  Widget _docked(Widget panel, Widget content) {
    const w = _sidebarWidth + 1;
    return ClipRect(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _side,
            builder: (context, child) => Positioned(
              left: _side.value * w,
              top: 0,
              right: 0,
              bottom: 0,
              child: child!,
            ),
            child: RepaintBoundary(child: content),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w,
            child: AnimatedBuilder(
              animation: _side,
              builder: (context, child) => Offstage(
                // Kept (scroll position, search) while hidden.
                offstage: _side.value == 0,
                // (mid-slide it's out of reach anyway: not offered to screen
                // readers, whose parts may be off the window)
                child: ExcludeSemantics(
                  excluding: _side.value < 1,
                  child: Transform.translate(
                    offset: Offset((_side.value - 1) * w, 0),
                    child: child,
                  ),
                ),
              ),
              child: RepaintBoundary(
                child: Row(
                  children: [
                    SizedBox(width: _sidebarWidth, child: panel),
                    const VerticalDivider(width: 1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _sidebarWidth = 300.0;
  static const _floatingWidth = 320.0;
  static const _slide = Duration(milliseconds: 260);

  /// The sidebar button's size as drawn (measured: it differs by platform
  /// and theme). The sidebar's top row keeps that much room at its right,
  /// after the same 6 gap as between its other buttons, with the row's 4 of
  /// padding beyond it, and the button goes there: even spacing.
  final _toggleSize = ValueNotifier<Size>(const Size(40, 40));
  double get _toggleWidth => _toggleSize.value.width;

  /// Preview shows automatically while projecting; the button hides it.
  bool get _previewVisible =>
      model.projectorActive &&
      !_previewHidden &&
      !model.settings.presentationMode;

  @override
  Widget build(BuildContext context) {
    // Panels opened or closed since: remember them (after this frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remember();
    });
    // While casting, the slides go to the TV as pictures.
    return CastFeeder(
      model: model,
      caster: nativeCaster ?? browserCaster,
      // After a click, a button / list / slider shouldn't keep the
      // keyboard: the arrow keys are for the slides (desktop apps give
      // focus to whatever was clicked). Text fields keep it.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) =>
            WidgetsBinding.instance.addPostFrameCallback((_) => _dropFocus()),
        child: _screen(context),
      ),
    );
  }

  void _dropFocus() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (focus == null || ctx == null) return;
    if (ctx.findAncestorWidgetOfExactType<EditableText>() != null) return;
    if (ctx.widget is EditableText) return;
    focus.unfocus();
  }

  Widget _screen(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          if (!model.projectorActive) _previewHidden = false;
          final extras = StyleExtras.of(context);
          final narrow = constraints.maxWidth < 760;
          final floating = model.settings.floatingSidebar && !narrow;
          final sidebar = ValueListenableBuilder<bool>(
            valueListenable: _sliding,
            builder: (context, sliding, child) =>
                IgnorePointer(ignoring: sliding, child: child),
            child: Sidebar(
              model: model,
              onEditSong: _edit,
              onDeleteSong: _confirmDelete,
              onImport: _import,
              onEditStructure: _editStructure,
              onOpenSettings: () => showAppDialog<void>(
                context: context,
                builder: (_) => SettingsDialog(
                  model: model,
                  onCustomizeToolbar: () => _openToolbarEditor(narrow),
                ),
              ),
              // (the sidebar button rides in its top row while it's open)
              toggleRoom: narrow ? null : _toggleSize,
              // (phones: the drawer covers the button, so it has its own)
              trailing: narrow
                  ? SidebarToggleButton(
                      open: true,
                      onPressed: () =>
                          _scaffoldKey.currentState?.closeDrawer(),
                    )
                  : null,
              onOpened: () {
                if (narrow) _scaffoldKey.currentState?.closeDrawer();
                if (floating) {
                  _markSliding();
                  setState(() => _sidebarOpen = false);
                }
              },
            ),
          );
          // A Material (not a plain coloured box) so list-row highlights
          // and ripples stay visible on the sidebar colour.
          final sidebarPanel = Material(
            color: extras.sidebarColor,
            child: sidebar,
          );
          // Built once per rebuild of the screen; opening or closing the
          // sidebar reuses it (only the layout around it changes).
          final content = _content(narrow, extras);
          return ValueListenableBuilder<bool>(
            valueListenable: _open,
            builder: (context, _, _) {
              final floatingOpen = floating && _sidebarOpen;

              // The sidebar button, like Bramble Notes': in the sidebar's top
              // row (right of the search) while it's open, at the left of
              // the song while it's closed. Docked, it rides the sidebar's
              // edge as it slides, and parks at the left.
              final eink = isEink(context);
              final em = _einkMargin(_compact);
              final double edge = eink ? em : 8;
              final double closedTop = extras.headerBar ? 0 : (eink ? em : 12);
              // Open: centred on the sidebar's top row (its 3 or 8 of
              // padding, then a row as tall as its buttons, at least the
              // search's 40); in the header bar, measured from the bar's
              // centre, where the button box puts it.
              double openTop() => eink
                  ? (extras.headerBar ? 0 : em)
                  : extras.headerBar
                  ? 3 +
                        // (its width: it's round, and the bar may squeeze
                        // its height)
                        math.max(40.0, _toggleWidth) / 2 -
                        (_headerHeight - inkW(1)) / 2
                  : 8;
              // (from the pane's right edge: its 4 of padding and the button)
              double inRow() => _toggleWidth + 4;
              // (measured as drawn, for the room and the place above)
              Widget toggle(Widget button) {
                final measured = _ReportSize(size: _toggleSize, child: button);
                return extras.headerBar
                    ? SizedBox(
                        // Less the bar's bottom border, as its buttons are
                        // centred above that line.
                        height: _headerHeight - inkW(1),
                        child: Center(child: measured),
                      )
                    : measured;
              }

              return Scaffold(
                key: _scaffoldKey,
                drawer: narrow ? Drawer(child: SafeArea(child: sidebar)) : null,
                // Closing the Format drawer (swipe, tap outside, back) turns
                // its button off too.
                onEndDrawerChanged: (open) {
                  if (!open && (_showFormat || _showToolbar)) {
                    setState(() => _showFormat = _showToolbar = false);
                  }
                },
                endDrawer: narrow && _showToolbar
                    ? Drawer(width: 320, child: SafeArea(child: _toolbarPane()))
                    : narrow && _showFormat
                    ? Drawer(width: 320, child: SafeArea(child: _formatPane()))
                    : null,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: !narrow && !floating
                                ? _docked(sidebarPanel, content)
                                : content,
                          ),
                          if (_showToolbar && !narrow) ...[
                            const VerticalDivider(width: 1),
                            SizedBox(width: 320, child: _toolbarPane()),
                          ] else if (_showFormat && !narrow) ...[
                            const VerticalDivider(width: 1),
                            SizedBox(width: 320, child: _formatPane()),
                          ],
                        ],
                      ),
                      if (floating) ...[
                        // Dim the music while the floating sidebar is open.
                        IgnorePointer(
                          ignoring: !floatingOpen,
                          child: AnimatedOpacity(
                            duration: motion(context, _slide),
                            opacity: floatingOpen ? 1 : 0,
                            child: GestureDetector(
                              onTap: () => setState(() => _sidebarOpen = false),
                              child: const ColoredBox(
                                color: Color(0x33000000),
                                child: SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: motion(context, _slide),
                          curve: Curves.easeInOutCubic,
                          left: floatingOpen ? 8 : -_floatingWidth - 24,
                          top: 8,
                          bottom: 8,
                          width: _floatingWidth,
                          child: Material(
                            elevation: inkE(12),
                            color: extras.sidebarColor,
                            borderRadius: BorderRadius.circular(
                              inkR(extras.panelRadius + 4),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: sidebar,
                          ),
                        ),
                      ],
                      if (_tunerOpen && !_tunerFull) _tuner(),
                      if (_padsOpen && !_padsFull) _padPanel(),
                      if (narrow)
                        Positioned(
                          left: edge,
                          top: closedTop,
                          child: toggle(_sidebarButton(narrow, extras, floating)),
                        )
                      else if (floating)
                        ValueListenableBuilder<Size>(
                          valueListenable: _toggleSize,
                          builder: (context, _, child) => AnimatedPositioned(
                            duration: motion(context, _slide),
                            curve: Curves.easeInOutCubic,
                            // (the floating card: 8 in from the window)
                            left: floatingOpen
                                ? 8 + _floatingWidth - inRow()
                                : edge,
                            top: floatingOpen ? 8 + openTop() : closedTop,
                            child: child!,
                          ),
                          child: toggle(_sidebarButton(narrow, extras, floating)),
                        )
                      else
                        AnimatedBuilder(
                          animation: Listenable.merge([_side, _toggleSize]),
                          builder: (context, child) {
                            final t = _side.value;
                            return Positioned(
                              left: math.max(edge, _sidebarWidth * t - inRow()),
                              top: closedTop + (openTop() - closedTop) * t,
                              child: child!,
                            );
                          },
                          child: toggle(_sidebarButton(narrow, extras, floating)),
                        ),
                      if (model.currentSong case final song?)
                        Positioned.fill(
                          child: StickyLayer(
                            key: ValueKey('stickies-${song.id}'),
                            model: model,
                            song: song,
                            board: StickyBoards.floating,
                          ),
                        ),
                      if (_pipUrl != null) _pip(),
                      // Full screen: over everything (the sidebar button too).
                      if (_tunerOpen && _tunerFull) _tuner(),
                      if (_padsOpen && _padsFull) _padPanel(),
                      // Files dragged over the window: where they go.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _dropping,
                            builder: (context, over, _) => AnimatedOpacity(
                              duration: motion(
                                context,
                                const Duration(milliseconds: 150),
                              ),
                              opacity: over ? 1 : 0,
                              child: _DropTarget(
                                visible: over,
                                media: _mediaPaneShown,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _sidebarButton(bool narrow, StyleExtras extras, bool floating) {
    final shown = !narrow && _sidebarOpen;
    // (the divider bends into ‹ or › while the pointer is over it)
    final button = SidebarToggleButton(
      open: shown,
      onPressed: () => _toggleSidebar(narrow),
    );
    // In the header bar it sits flat like other header buttons, except
    // with a floating sidebar: then it gets its own raised background so it
    // stays easy to see over the dimmed music.
    if (extras.headerBar && !floating) return button;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: floating
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerHigh,
      shape: floating
          ? CircleBorder(
              side: BorderSide(color: scheme.outlineVariant, width: inkW(1)),
            )
          : extras.toolbarShape,
      elevation: inkE(floating ? 6 : extras.toolbarElevation),
      shadowColor: Colors.black54,
      child: button,
    );
  }

  Widget _formatPane() => FormatPane(
    model: model,
    onClose: () {
      // On phones the panel is a drawer: slide it shut (which turns the
      // button off) rather than pulling it out from under itself.
      final scaffold = _scaffoldKey.currentState;
      if (scaffold != null && scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
      } else {
        setState(() => _showFormat = false);
      }
    },
  );

  /// The open song plus its neighbours, drawn ahead for swiping.
  /// Built sheets, reused while nothing about them changed, so switching
  /// songs only rebuilds what really changed.
  final Map<String, Widget> _sheetCache = {};

  Widget _songStrip() {
    StickyBoards.currentSheet = model.currentSpec?.id;
    final s = model.settings;
    final look = Object.hash(
      jsonEncode(model.format.toJson()),
      s.sheetFont,
      s.chordFont,
      s.themeMusic,
      s.oled,
      Theme.of(context).colorScheme,
      model.projection.tidyLyrics,
      ChordLibrary.loaded,
      _chordLook(),
    );
    final used = <String>{};
    final ids = <String>{};
    SwipePage? page(SheetSpec? spec, {bool current = false}) {
      if (spec == null) return null;
      ids.add(spec.id);
      _selectionFor(spec.id).active = current;
      final key = [
        spec.id,
        spec.raw.hashCode,
        spec.transpose,
        spec.capo,
        spec.soundingKey?.name,
        spec.song.extra['layout'],
        // A saved edit replaces the song (new beats, title, details…).
        identityHashCode(spec.song),
        look,
        model.settings.gospelGlow,
      ].join('|');
      used.add(key);
      final child = _sheetCache[key] ??= _sheet(spec);
      return SwipePage(spec.id, child);
    }

    final strip = SongSwipe(
      current: page(model.currentSpec, current: true)!,
      before: [for (final s in model.neighbours(-1, 2)) page(s)!],
      after: [for (final s in model.neighbours(1, 2)) page(s)!],
      onGo: model.goSong,
      // Drawing on the sheet: strokes, not swipes.
      enabled: !_ink.active,
    );
    _sheetCache.removeWhere((k, _) => !used.contains(k));
    _selections.removeWhere((id, sel) {
      if (ids.contains(id)) return false;
      sel.dispose();
      return true;
    });
    return strip;
  }

  /// One selection per drawn song: follows the real selection while that
  /// song is open, otherwise shows its first part (how it will look once
  /// it slides in).
  final Map<String, _PageSelection> _selections = {};

  _PageSelection _selectionFor(String id) =>
      _selections[id] ??= _PageSelection(model.selection);

  Widget _sheet(SheetSpec spec) {
    final s = model.settings;
    final sheet = ChordSheet(
      song: spec.song,
      raw: spec.raw,
      passingGlow: s.gospelGlow,
      format: model.format,
      transpose: spec.transpose,
      displayKey: spec.displayKey,
      soundingKey: spec.soundingKey,
      capo: spec.capo,
      textFamily: FontService.option(s.sheetFont, s.customFonts).family,
      chordFamily: FontService.option(s.chordFont, s.customFonts).family,
      onOpenUrl: openUrl,
      parts: spec.parts,
      selectedSlide: _selectionFor(spec.id),
      slidePartIndex: spec.slidePartIndex,
      selectionStyle: model.format.selectionStyle,
      onSelectPart: model.selectPart,
      layout: model.layoutFor(spec.song),
      beats: model.beatsFor(spec.song),
      chords: _chordsConfig(spec.capo),
      autoscroll: model.autoscroll,
      // The place in the song, kept across rotating and reopening.
      initialScroll: model.uiValue<String>('sheet.song') == spec.id
          ? model.uiValue<num>('sheet.at')?.toDouble()
          : null,
      onScrolled: (at) => model
        ..setUi('sheet.song', spec.id)
        ..setUi('sheet.at', (at * 1000).round() / 1000),
      // Annotations and pinned notes ride on the sheet, scrolling with it.
      overlay: Stack(
        fit: StackFit.expand,
        children: [
          // Pictures on the page (under the annotations, so you can draw
          // on them).
          Positioned.fill(
            child: SheetImageLayer(model: model, song: spec.song),
          ),
          SheetInkLayer(
            controller: _ink,
            songId: spec.song.id,
            currentSongId: () => model.currentSong?.id,
            read: () => model.sheetInk(spec.song),
            write: (v) => model.setSheetInk(spec.song, v),
            changes: Listenable.merge([model.inkVersion, model]),
          ),
          StickyLayer(
            model: model,
            song: spec.song,
            pinned: true,
            board: StickyBoards.pinnedFor(spec.id),
          ),
        ],
      ),
    );
    // PDFs attached: tabs for the ChordPro and each PDF (a PDF-only song
    // shows just the PDF).
    final pdfs = pdfsOf(spec.song);
    final Widget page = pdfs.isEmpty
        ? sheet
        : SongDocTabs(
            song: spec.song,
            chordPro: spec.song.raw.trim().isEmpty ? null : sheet,
            pdfs: pdfs,
            model: model,
          );
    if (s.themeMusic) return page;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: neutralScheme(theme.brightness, oled: s.oled),
      ),
      child: page,
    );
  }

  /// One screen button for everything projection: open the projector
  /// window, cast, copy the link for other screens, stop.
  /// The Project menu (open a projector window, cast, link, stop).
  List<PopupMenuEntry<String>> _projectionItems() {
    final scheme = Theme.of(context).colorScheme;
    final on = model.projecting;
    return [
      PopupMenuItem(
        value: 'window',
        child: _menuRow(Icons.open_in_new_rounded, 'Open projector window'),
      ),
      PopupMenuItem(
        value: 'cast',
        child: _menuRow(
          model.casting ? Icons.cast_connected_rounded : Icons.cast_rounded,
          'Cast to a TV or display…',
        ),
      ),
      PopupMenuItem(
        value: 'link',
        child: _menuRow(
          Icons.link_rounded,
          'Copy projection link',
          subtitle: 'Open it on any phone, tablet or TV browser',
        ),
      ),
      if (on) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'stop',
          child: _menuRow(
            Icons.stop_rounded,
            'Stop projecting',
            subtitle: 'Closes every projector screen and cast',
            color: scheme.error,
          ),
        ),
      ],
    ];
  }

  /// A menu row: icon, title and maybe a line under it. (Not a ListTile:
  /// the menu is then as wide as its titles, which stay on one line.)
  Widget _menuRow(
    IconData icon,
    String title, {
    String? subtitle,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 14,
        children: [
          Icon(icon, color: color),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(color: color),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Menus with rows like [_menuRow]: wide enough for their titles.
  static const _menuWidth = BoxConstraints(minWidth: 240, maxWidth: 340);

  Future<void> _projectionChoice(String choice) async {
    switch (choice) {
      case 'window':
        model.startProjection();
      case 'cast':
        await showAppDialog<void>(
          context: context,
          builder: (_) => CastDialog(model: model),
        );
      case 'link':
        await _copyProjectionLink();
      case 'stop':
        await model.stopProjection();
    }
  }

  Widget _projectionMenu() {
    final scheme = Theme.of(context).colorScheme;
    final on = model.projecting;
    return PopupMenuButton<String>(
      tooltip: on ? 'Projecting' : 'Project',
      icon: Icon(
        on ? Icons.connected_tv_rounded : Icons.tv_rounded,
        color: on ? scheme.primary : null,
      ),
      onSelected: _projectionChoice,
      constraints: _menuWidth,
      itemBuilder: (_) => _projectionItems(),
    );
  }

  Future<void> _copyProjectionLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final info = await relayDetails();
    final url = info?['url'] as String?;
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Other screens need the app started with run.sh — '
            'then the link works on any device on this Wi-Fi.',
          ),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text('Copied $url')));
  }

  /// Edit, structure, format, preview (while projecting), projector.
  /// The desktop styles' header bar.
  static const _headerHeight = 46.0;

  /// Phone-sized screens: fewer buttons in the bars, the rest in "More".
  bool get _compact => MediaQuery.sizeOf(context).width < 520;

  void _addSticky(Song song) {
    // Top right, over the music; each new one a little lower and further
    // left so they don't stack exactly.
    final count = model.stickiesOf(song).length % 6;
    final width = MediaQuery.sizeOf(context).width;
    final at = Offset(
      (width - 300 - count * 28).clamp(16.0, double.infinity),
      150.0 + count * 28,
    );
    model.addSticky(at);
  }

  // ---- Tuner: a floating panel (or full screen) ----

  bool _tunerOpen = false;
  bool _tunerFull = false;

  Widget _tuner() {
    final panel = TunerPanel(
      model: model,
      fullscreen: _tunerFull,
      onFullscreen: () => setState(() => _tunerFull = !_tunerFull),
      onClose: () => setState(() {
        _tunerOpen = false;
        _tunerFull = false;
      }),
    );
    // One panel, kept across full screen and back (it keeps listening).
    final keyed = KeyedSubtree(key: _tunerKey, child: panel);
    if (_tunerFull) return Positioned.fill(child: keyed);
    return Positioned.fill(
      bottom: _einkPanelInset,
      child: LayoutBuilder(
        builder: (context, box) {
          // Narrow phones: as wide as fits, the same margin each side.
          final w = math.min(380.0, box.maxWidth - 32);
          return FloatingPanel(
            id: 'tuner',
            freeAspect: true,
            resizable: false,
            initialWidth: w,
            minWidth: w,
            maxWidth: w,
            initialHeight: 400,
            minHeight: 400,
            maxHeight: 400,
            start: Alignment.bottomRight,
            // (it opens above the bottom toolbar, not over it)
            startAbove: _panelStartAbove,
            child: keyed,
          );
        },
      ),
    );
  }

  final _tunerKey = GlobalKey();

  /// E-ink: floating panels stay above the bottom toolbar, never over it.
  /// How far above the foot a floating panel first appears: clear of the
  /// floating bottom toolbar (e-ink already leaves that room).
  double get _panelStartAbove =>
      _einkPanelInset == 0 && bottomBarSize.value != Size.zero
      ? bottomBarSize.value.height + 8
      : 0;

  double get _einkPanelInset =>
      isEink(context) && bottomBarSize.value != Size.zero
      ? bottomBarSize.value.height + _einkMargin(_compact) * 2
      : 0;

  // ---- Pads: a floating panel (or full screen); it keeps playing when
  // closed ----

  bool _padsOpen = false;
  bool _padsFull = false;
  final _padsKey = GlobalKey();

  Widget _padPanel() {
    final panel = KeyedSubtree(
      key: _padsKey,
      child: PadPanel(
        pads: model.pads,
        fullscreen: _padsFull,
        onFullscreen: () => setState(() => _padsFull = !_padsFull),
        onClose: () => setState(() {
          _padsOpen = false;
          _padsFull = false;
        }),
      ),
    );
    if (_padsFull) return Positioned.fill(child: panel);
    return Positioned.fill(
      bottom: _einkPanelInset,
      child: LayoutBuilder(
        builder: (context, box) {
          // Phones: smaller, to fit (its keys scale down with it).
          // (Inside the panel's 16 px margin on each side.)
          final w = math.min(PadPanel.size.width, box.maxWidth - 32);
          final h = math.min(PadPanel.size.height, box.maxHeight - 32);
          return FloatingPanel(
            id: 'pads',
            freeAspect: true,
            resizable: false,
            initialWidth: w,
            minWidth: w,
            maxWidth: w,
            initialHeight: h,
            minHeight: h,
            maxHeight: h,
            start: Alignment.bottomRight,
            // (it opens above the bottom toolbar, not over it)
            startAbove: _panelStartAbove,
            child: panel,
          );
        },
      ),
    );
  }

  /// The toolbar editor: a side pane where the Format pane goes.
  bool _showToolbar = false;

  void _openToolbarEditor(bool narrow) {
    setState(() {
      _showToolbar = true;
      _showFormat = false;
    });
    if (narrow) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scaffoldKey.currentState?.openEndDrawer(),
      );
    }
  }

  Widget _toolbarPane() => ToolbarEditor(
    model: model,
    compact: _compact,
    onClose: () {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold != null && scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
      } else {
        setState(() => _showToolbar = false);
      }
    },
  );

  void _toggleFormat(bool narrow) {
    _showToolbar = false;
    setState(() => _showFormat = !_showFormat);
    if (narrow && _showFormat) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scaffoldKey.currentState?.openEndDrawer(),
      );
    }
  }

  void _openSettings() => showAppDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(
      model: model,
      onCustomizeToolbar: () =>
          _openToolbarEditor(MediaQuery.sizeOf(context).width < 760),
    ),
  );

  // ---- Chord diagrams ----

  /// What the chord diagram settings look like (sheets redraw on change).
  String _chordLook() {
    final s = model.settings;
    return jsonEncode([
      s.showChordDiagrams,
      s.chordInstrument.name,
      s.showDiagramFingers,
      s.diagramZoom,
      s.diagramsCollapsed,
      s.tapChords,
      s.chordPlaySpeed.name,
      s.chordPrefs,
      s.customChords.length,
    ]);
  }

  ChordDiagramsConfig _chordsConfig(int capo) {
    final s = model.settings;
    return ChordDiagramsConfig(
      show: s.showChordDiagrams,
      instrument: s.chordInstrument,
      fingers: s.showDiagramFingers,
      zoom: s.diagramZoom,
      collapsed: s.diagramsCollapsed,
      tappable: s.tapChords,
      speed: s.chordPlaySpeed,
      prefs: s.chordPrefs,
      custom: s.customChords,
      capo: capo,
      onToggleCollapsed: () => model.updateSettings(
        (s) => s.diagramsCollapsed = !s.diagramsCollapsed,
      ),
      onShowChord: (name, chord, {anchor}) =>
          _showChord(name, chord, capo, anchor: anchor),
    );
  }

  /// "Chord Diagrams" for a chord: pick the shape to use, or make one.
  void _showChord(String name, ChordName chord, int capo, {Rect? anchor}) {
    final s = model.settings;
    final instrument = s.chordInstrument;
    final key = prefKey(instrument, chord);
    showChordDiagramsSheet(
      context,
      name: name,
      chord: chord,
      instrument: instrument,
      custom: s.customChords,
      preferred: s.chordPrefs[key],
      fingers: s.showDiagramFingers,
      capo: capo,
      speed: s.chordPlaySpeed,
      anchor: anchor,
      onChoose: (id) => model.updateSettings(
        (s) => s.chordPrefs = {...s.chordPrefs, key: id},
      ),
      onAddShape: () async {
        final shape = await showChordEditor(
          context,
          instrument: instrument,
          chord: chord,
        );
        if (shape == null) return;
        model.updateSettings((s) {
          s.customChords = [...s.customChords, shape];
          s.chordPrefs = {...s.chordPrefs, key: shape.id};
        });
      },
    );
  }

  /// Whether toolbar button [id] applies right now.
  bool _toolShown(String id, Song? song) => switch (id) {
    'preview' => model.projectorActive && !model.settings.presentationMode,
    'sticky' => song != null,
    _ => true,
  };

  /// What toolbar button [id] does (null: not now).
  VoidCallback? _toolAction(String id, bool narrow, Song? song) => switch (id) {
    'share' => song == null ? null : () => ShareDialog.show(context, model),
    'sticky' => song == null ? null : () => _addSticky(song),
    'insert' =>
      song == null ? null : () => insertSheetImage(context, model, song),
    'annotate' => song == null ? null : _toggleAnnotate,
    'edit' => song == null ? null : () => _edit(song),
    'structure' => song == null ? null : _editStructure,
    'format' => () => _toggleFormat(narrow),
    'present' => () => model.updateSettings(
      (s) => s.presentationMode = !s.presentationMode,
    ),
    'preview' => () => setState(() => _previewHidden = !_previewHidden),
    'settings' => _openSettings,
    _ => null,
  };

  /// The button's name as its tooltip / menu entry says it right now.
  String _toolLabel(String id) => switch (id) {
    'annotate' =>
      _ink.active ? 'Stop annotating' : 'Annotate (draw / highlight)',
    'format' => _showFormat ? 'Hide Format' : 'Show Format',
    'present' =>
      model.settings.presentationMode
          ? 'Back to the chord sheet'
          : 'Presentation mode (slide grid)',
    'preview' => _previewVisible ? 'Hide preview' : 'Show preview',
    'structure' =>
      model.activeEntry != null
          ? 'Song structure (this setlist)'
          : 'Song structure',
    _ => toolbarItem(id).label,
  };

  bool _toolSelected(String id) => switch (id) {
    'annotate' => _ink.active,
    'format' => _showFormat,
    'present' => model.settings.presentationMode,
    'preview' => _previewVisible,
    _ => false,
  };

  /// The top toolbar, as arranged in Settings → Customize toolbar: its
  /// buttons, then a ⋯ menu with the rest.
  /// The top toolbar's buttons. Given the [width] there is, the ones that
  /// don't fit go into the ⋯ menu (from the end) instead of off the edge.
  List<Widget> _topActions(bool narrow, Song? song, {double? width}) {
    final layout = toolbarLayout(model.settings, compact: _compact);
    var bar = [
      for (final id in layout.bar)
        if (_toolShown(id, song)) id,
    ];
    var more = [
      for (final id in layout.more)
        if (_toolShown(id, song)) id,
    ];
    if (width != null) {
      // An icon button, and the 2 px between them.
      final each =
          kMinInteractiveDimension +
          Theme.of(context).visualDensity.baseSizeAdjustment.dx +
          2;
      final room = (width / each).floor();
      if (bar.length + (more.isEmpty ? 0 : 1) > room) {
        final keep = math.max(0, math.min(bar.length, room - 1));
        more = [...bar.sublist(keep), ...more];
        bar = bar.sublist(0, keep);
      }
    }
    return [
      for (final id in bar)
        if (_toolShown(id, song))
          id == 'projector'
              ? _projectionMenu()
              : IconButton(
                  tooltip: _toolLabel(id),
                  isSelected: _toolSelected(id),
                  icon: toolbarItem(id).icon,
                  onPressed: _toolAction(id, narrow, song),
                ),
      if (more.isNotEmpty) _overflowMenu(more, narrow, song),
    ];
  }

  /// The ⋯ menu: the toolbar buttons put away there.
  Widget _overflowMenu(List<String> ids, bool narrow, Song? song) {
    return Builder(
      builder: (context) => PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        // Wide enough that labels stay on one line.
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
        // Below the toolbar, not over it.
        position: PopupMenuPosition.under,
        onSelected: (id) {
          if (id == 'projector') {
            // The Project menu opens where the ⋯ button is.
            final box = context.findRenderObject() as RenderBox;
            final at = box.localToGlobal(box.size.bottomLeft(Offset.zero));
            showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
              constraints: _menuWidth,
              items: _projectionItems(),
            ).then((v) {
              if (v != null) _projectionChoice(v);
            });
            return;
          }
          _toolAction(id, narrow, song)?.call();
        },
        itemBuilder: (_) => [
          for (final id in ids)
            PopupMenuItem(
              value: id,
              enabled:
                  id == 'projector' || _toolAction(id, narrow, song) != null,
              // (A row, not a ListTile: the menu is then as wide as its
              // labels, which stay on one line.)
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 14,
                children: [
                  toolbarItem(id).icon,
                  Text(_toolLabel(id), maxLines: 1, softWrap: false),
                  if (_toolSelected(id)) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Metronome, key, capo, and slide arrows while projecting.
  List<Widget> _bottomActions(Song? song) => [
    if (model.settings.showMetronome)
      // (its own layer: the swinging pendulum repaints just itself)
      RepaintBoundary(child: _MetronomeButton(metronome: model.metronome)),
    if (song != null &&
        model.settings.showPlayer &&
        song.audioUrl.trim().isNotEmpty)
      IconButton(
        tooltip: canPlayInApp(song.audioUrl)
            ? 'Play reference recording'
            : 'Open reference recording',
        isSelected: _pipUrl == song.audioUrl.trim(),
        icon: const Icon(Icons.play_circle_outline),
        onPressed: () => _play(song),
      ),
    if (song != null &&
        model.settings.showAutoscroll &&
        !model.settings.presentationMode)
      _AutoscrollButton(autoscroll: model.autoscroll),
    if (model.settings.showTuner)
      IconButton(
        tooltip: 'Tuner',
        isSelected: _tunerOpen,
        icon: const Icon(Icons.graphic_eq),
        onPressed: () => setState(() {
          _tunerOpen = !_tunerOpen;
          _tunerFull = false;
        }),
      ),
    if (model.settings.showPads)
      ListenableBuilder(
        listenable: model.pads,
        builder: (context, _) => IconButton(
          tooltip: model.pads.playing ? 'Pads (playing)' : 'Pads',
          isSelected: _padsOpen || model.pads.playing,
          icon: const Icon(Icons.waves),
          onPressed: () => setState(() {
            _padsOpen = !_padsOpen;
            _padsFull = false;
          }),
        ),
      ),
    if (gospelizerEnabled &&
        song != null &&
        model.settings.showGospel &&
        !isPdfOnly(song))
      _GospelButton(model: model),
    if (song != null) _KeyButton(model: model),
    if (song != null) _CapoButton(model: model),
    if (model.projectorActive)
      IconButton(
        tooltip: model.blackout ? 'Show lyrics again (B)' : 'Blackout (B)',
        isSelected: model.blackout,
        icon: Icon(
          model.blackout ? Icons.visibility_off : Icons.visibility_off_outlined,
        ),
        onPressed: model.toggleBlackout,
      ),
    if (model.projectorActive)
      ValueListenableBuilder<int>(
        valueListenable: model.selection,
        builder: (context, index, _) => Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Previous part (↑ ← PgUp)',
              icon: const Icon(Icons.chevron_left),
              onPressed: index > 0 ? model.previous : null,
            ),
            Text(
              model.slides.isEmpty
                  ? '0 / 0'
                  : '${index + 1} / ${model.slides.length}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Next part (↓ → PgDn Space)',
              icon: const Icon(Icons.chevron_right),
              onPressed: index < model.slides.length - 1 ? model.next : null,
            ),
          ],
        ),
      ),
  ];

  /// A scale model of the projector screen: the slide is laid out at the
  /// projector window's real size (same margins and text sizing), then the
  /// whole picture is shrunk to fit, so proportions match what the audience
  /// sees.
  Widget _preview() {
    final size = model.projectorSize;
    return Material(
      elevation: inkE(8),
      borderRadius: BorderRadius.circular(StyleExtras.of(context).panelRadius),
      clipBehavior: Clip.antiAlias,
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ProjectorDisplay(data: model.projectionData),
        ),
      ),
    );
  }

  Widget _content(bool narrow, StyleExtras extras) {
    final song = model.currentSong;
    final sheetArea = song == null
        ? const Center(child: Text('Add a song to get started.'))
        : model.settings.presentationMode
        ? null
        : ValueListenableBuilder<int>(
            valueListenable: model.libraryOrderVersion,
            builder: (context, _, _) => _songStrip(),
          );
    // The projector preview floats: drag anywhere on it, resize at the
    // corner, throw it and it settles (against an edge when close).
    final size = model.projectorSize;
    final preview = Positioned.fill(
      child: _previewVisible
          ? FloatingPanel(
              id: 'preview',
              heightFor: (w) => w * size.height / size.width,
              initialWidth: 320,
              minWidth: 180,
              maxWidth: 800,
              dragAnywhere: true,
              child: _preview(),
            )
          : const SizedBox.shrink(),
    );
    // Annotating the slide: a big preview to draw on instead of the small
    // floating one; the tool pill floats on top.
    List<Widget> annotating(EdgeInsets padding) => [
      if (_ink.active && _ink.target == InkTarget.slide && song != null)
        _inkSlideBoard(padding)
      else
        preview,
    ];

    if (extras.headerBar) {
      // Desktop layout: header bar, sheet, bottom toolbar.
      final theme = Theme.of(context);
      final title = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: extras.centeredTitle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            song?.displayTitle ?? 'ChordPro Presenter',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (song != null && song.artist.isNotEmpty)
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );
      final border = BorderSide(
        color: theme.colorScheme.outlineVariant,
        width: inkW(1),
      );
      return Column(
        children: [
          Container(
            height: _headerHeight,
            decoration: BoxDecoration(
              color: extras.headerColor,
              border: Border(bottom: border),
            ),
            padding: const EdgeInsets.only(right: 6),
            // Left gap for the sidebar button, which floats over the bar
            // (docked: only while the sidebar is closed; open, the button
            // is in the sidebar, and the gap closes as it slides)
            child: AnimatedBuilder(
              animation: _side,
              builder: (context, child) => Padding(
                padding: EdgeInsets.only(
                  left: narrow || model.settings.floatingSidebar
                      ? 56
                      : 12 + 44 * (1 - _side.value),
                ),
                child: child,
              ),
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  spacing: 2,
                  children: [
                    Expanded(
                      child: extras.centeredTitle
                          ? Center(child: title)
                          : Align(alignment: Alignment.centerLeft, child: title),
                    ),
                    const SizedBox(width: 4),
                    // The buttons first; the title keeps a little room on
                    // phones (the rest goes into ⋯).
                    ..._topActions(
                      narrow,
                      song,
                      width: c.maxWidth - 6 - math.min(120, c.maxWidth * 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => ListenableBuilder(
                listenable: _bottomLayout,
                builder: (context, _) {
                  final pane = _paneHeight(box);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          // The sheet edge to edge between the bars, as in
                          // the floating-toolbar layout (its words where the
                          // card's were). E-ink: to the bars and edges too
                          // (their lines frame it).
                          padding: isEink(context) || sheetArea != null
                              ? EdgeInsets.only(bottom: pane)
                              : EdgeInsets.fromLTRB(12, 12, 12, 12 + pane),
                          child: sheetArea != null && !isEink(context)
                              ? SheetInsets(
                                  framed: false,
                                  inset: const EdgeInsets.all(12),
                                  child: sheetArea,
                                )
                              : sheetArea ?? PresentationView(model: model),
                        ),
                      ),
                      if (pane > 0) _bottomPane(pane),
                      ...annotating(const EdgeInsets.fromLTRB(12, 12, 12, 96)),
                      if (_ink.active && song != null)
                        _inkPill(Alignment.bottomCenter),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: extras.headerColor,
              border: Border(top: border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _compact
                ? _BarFit(
                    // (E-ink: spread across the bar.)
                    child: Row(
                      mainAxisSize: isEink(context)
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      mainAxisAlignment: isEink(context)
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.start,
                      spacing: 4,
                      children: _bottomActions(song),
                    ),
                  )
                : Row(
                    spacing: 4,
                    children: [
                      ..._bottomActions(song).take(1),
                      const Spacer(),
                      ..._bottomActions(song).skip(1),
                    ],
                  ),
          ),
        ],
      );
    }

    // Material layout: floating toolbars over the sheet. In presentation
    // mode the slides run to the bottom of the window, under the toolbar
    // (they scroll out from behind it), or the media pane does.
    final presenting = sheetArea == null;
    final barPad = _compact ? 8.0 : 14.0;
    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: _bottomLayout,
        builder: (context, _) {
          final pane = _paneHeight(box);
          // How far up the toolbar reaches from the bottom. (E-ink: one
          // margin everywhere, see _einkMargin.)
          final eink = isEink(context);
          final em = _einkMargin(_compact);
          final band = eink
              ? bottomBarSize.value.height + em * 2
              : bottomBarSize.value.height + barPad + 8;
          final top = eink && _topBarSize.value != Size.zero
              ? _topBarSize.value.height + em * 2
              : 64.0;
          // The sheet edge to edge, under the toolbars: its words start
          // below the top one (where the card's did) and scroll up behind
          // it, and clear the bottom one at the end. (E-ink: framed by the
          // bars as before.)
          final fullBleed = !presenting && !eink;
          final scheme = Theme.of(context).colorScheme;
          final behind = pane > 0
              ? scheme.surfaceContainerHigh
              : scheme.surface;
          Widget halo(double right, double? top, double? bottom, Size size) =>
              Positioned(
                right: right,
                top: top,
                bottom: bottom,
                width: size.width,
                height: size.height,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        inkR(size.height / 2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: behind.withValues(alpha: 0.9),
                          blurRadius: 24,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              );
          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: fullBleed
                      ? EdgeInsets.only(bottom: pane)
                      : EdgeInsets.fromLTRB(
                          eink ? em : 16,
                          top,
                          eink ? em : 16,
                          // (E-ink: the sheet ends above the toolbar, not
                          // under.)
                          presenting
                              ? pane
                              : isEink(context)
                              ? band
                              : 16,
                        ),
                  child: fullBleed
                      ? SheetInsets(
                          framed: false,
                          inset: EdgeInsets.fromLTRB(
                            16,
                            top,
                            16,
                            pane > 0 ? 16 : band,
                          ),
                          child: sheetArea,
                        )
                      : sheetArea ??
                            PresentationView(
                              model: model,
                              bottomClearance: pane > 0 ? 0 : band,
                            ),
                ),
              ),
              if (pane > 0) _bottomPane(pane),
              // A soft halo around the toolbar while presenting, so the slides
              // and media behind it don't run into its edges. (Over the
              // sheet: just the toolbars' own shadow.)
              if (presenting &&
                  bottomBarSize.value != Size.zero &&
                  !isEink(context))
                halo(barPad, null, barPad, bottomBarSize.value),
              // E-ink: a plain plate instead (nothing shows round the
              // toolbar's edges, nothing is half hidden behind it).
              if (presenting &&
                  bottomBarSize.value != Size.zero &&
                  isEink(context))
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: bottomBarSize.value.width + em * 2,
                  height: bottomBarSize.value.height + em * 2,
                  child: ColoredBox(
                    color: pane > 0
                        ? Theme.of(context).colorScheme.surfaceContainerHigh
                        : Theme.of(context).colorScheme.surface,
                  ),
                ),
              // Clear of the sidebar button (left); on phones the bars may
              // scroll sideways rather than run off the screen.
              Positioned(
                top: eink ? em : 12,
                // (E-ink: past the sidebar button by the same margin.)
                left: _compact ? (eink ? em * 2 + 48 : 64) : null,
                right: eink ? em : (_compact ? 8 : 14),
                child: _ReportSize(
                  size: _topBarSize,
                  child: _compact
                      ? LayoutBuilder(
                          // Phones: what doesn't fit goes into ⋯.
                          builder: (context, c) => _BarFit(
                            child: _Pill(
                              stretch: eink,
                              children: _topActions(
                                narrow,
                                song,
                                width: c.maxWidth - 8,
                              ),
                            ),
                          ),
                        )
                      : _Pill(children: _topActions(narrow, song)),
                ),
              ),
              ...annotating(const EdgeInsets.fromLTRB(16, 64, 16, 150)),
              Positioned(
                left: _compact ? (eink ? em : 8) : null,
                right: eink ? em : barPad,
                bottom: eink ? em : barPad,
                child: _ReportSize(
                  size: bottomBarSize,
                  child: _compact
                      ? _BarFit(
                          child: _Pill(
                            stretch: eink,
                            children: _bottomActions(song),
                          ),
                        )
                      : _Pill(children: _bottomActions(song)),
                ),
              ),
              // Above the bottom toolbar, on top of everything.
              if (_ink.active && song != null)
                _inkPill(const Alignment(0, 0.8)),
            ],
          );
        },
      ),
    );
  }
}

/// The top toolbar's size (e-ink lines the sheet up under it).
final _topBarSize = ValueNotifier(Size.zero);

/// E-ink: the one margin the sidebar button, both toolbars and the sheet
/// keep from the edges and from each other, so they all line up.
double _einkMargin(bool compact) => compact ? 8 : 12;

/// Tells [size] how big [child] is drawn (after each layout).
class _ReportSize extends SingleChildRenderObjectWidget {
  final ValueNotifier<Size> size;
  const _ReportSize({required this.size, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportSize(size);

  @override
  void updateRenderObject(BuildContext context, _RenderReportSize r) =>
      r.size_ = size;
}

class _RenderReportSize extends RenderProxyBox {
  ValueNotifier<Size> size_;
  _RenderReportSize(this.size_);

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s != size_.value) {
      // Not during layout: whoever listens rebuilds next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => size_.value = s);
    }
  }
}

/// The metronome: just its icon until tapped, which starts the click and
/// opens out − · BPM (type any) · + · the beat · more settings. Tap the
/// icon again to stop and fold it away. The pendulum swings with the beat.
class _MetronomeButton extends StatelessWidget {
  final Metronome metronome;
  const _MetronomeButton({required this.metronome});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: metronome,
      builder: (context, _) {
        final m = metronome;
        final dots = m.beatsPerBar.clamp(1, 8);
        final beatMs = (60000 / m.bpm).round();
        return AnimatedSize(
          duration: motion(context, const Duration(milliseconds: 180)),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: m.running ? 'Stop metronome' : 'Start metronome',
                isSelected: m.running,
                onPressed: m.toggle,
                icon: TweenAnimationBuilder<double>(
                  tween: Tween(
                    end: !m.running || m.beat < 0
                        ? 0
                        : (m.beat.isEven ? 1 : -1),
                  ),
                  duration: Duration(milliseconds: m.running ? beatMs : 200),
                  curve: Curves.easeInOutSine,
                  builder: (context, swing, _) => MetronomeIcon(swing: swing),
                ),
              ),
              if (m.running) ...[
                IconButton(
                  tooltip: 'Slower',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove, size: 20),
                  onPressed: () => m.setBpm(m.bpm - 1),
                ),
                _BpmField(metronome: m),
                IconButton(
                  tooltip: 'Faster',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => m.setBpm(m.bpm + 1),
                ),
                const SizedBox(width: 4),
                for (var i = 0; i < dots; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == m.beat
                          ? (i == 0 ? scheme.secondary : scheme.primary)
                          : scheme.outlineVariant,
                    ),
                  ),
                MenuAnchor(
                  builder: (context, controller, _) => IconButton(
                    tooltip: 'Metronome settings',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                  menuChildren: [_MetronomeSettings(metronome: m)],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The tempo, typed straight in.
class _BpmField extends StatefulWidget {
  final Metronome metronome;
  const _BpmField({required this.metronome});

  @override
  State<_BpmField> createState() => _BpmFieldState();
}

class _BpmFieldState extends State<_BpmField> {
  Metronome get m => widget.metronome;
  late final _field = TextEditingController(text: '${m.bpm}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    m.addListener(_changed);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _field.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _field.text.length,
        );
      } else {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    m.removeListener(_changed);
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_focus.hasFocus && _field.text != '${m.bpm}') {
      _field.text = '${m.bpm}';
    }
  }

  void _commit() {
    final v = int.tryParse(_field.text.trim());
    if (v != null) m.setBpm(v);
    _field.text = '${m.bpm}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: TextField(
        key: const Key('metronome-bpm'),
        controller: _field,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

/// Tempo slider, beats per bar, tap tempo and sound.
class _MetronomeSettings extends StatelessWidget {
  final Metronome metronome;
  const _MetronomeSettings({required this.metronome});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: metronome,
      builder: (context, _) {
        final m = metronome;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${m.bpm} BPM'),
              SizedBox(
                width: 220,
                child: Slider(
                  value: m.bpm.toDouble(),
                  min: Metronome.minBpm.toDouble(),
                  max: Metronome.maxBpm.toDouble(),
                  onChanged: (v) => m.setBpm(v.round()),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Beats per bar'),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: m.beatsPerBar > 1
                        ? () => m.setBeatsPerBar(m.beatsPerBar - 1)
                        : null,
                  ),
                  Text('${m.beatsPerBar}'),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: m.beatsPerBar < 16
                        ? () => m.setBeatsPerBar(m.beatsPerBar + 1)
                        : null,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: m.tap,
                    child: const Text('Tap tempo'),
                  ),
                  const SizedBox(width: 12),
                  const Text('Sound'),
                  Switch(value: m.sound, onChanged: m.setSound),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens a menu over the button [context] belongs to (like
/// [PopupMenuButton], for buttons drawn as the theme's icon buttons).
Future<T?> _menuFrom<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> items, {
  T? initialValue,
}) {
  final button = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: items,
    initialValue: initialValue,
    // Never narrower than its widest row (some phones measure text a
    // little wider than the menu allowed for).
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
  );
}

/// Scrolls the sheet by itself. Tap to start (straight away) and the bar
/// opens out with − · time left · +; tap pause and it folds away.
class _AutoscrollButton extends StatelessWidget {
  final Autoscroll autoscroll;
  const _AutoscrollButton({required this.autoscroll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: autoscroll,
      builder: (context, _) {
        final a = autoscroll;
        return AnimatedSize(
          duration: motion(context, const Duration(milliseconds: 180)),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: a.running ? 'Pause autoscroll' : 'Autoscroll',
                isSelected: a.running,
                icon: Icon(
                  a.running
                      ? Icons.pause_rounded
                      : Icons.keyboard_double_arrow_down_rounded,
                  color: a.running ? scheme.primary : null,
                ),
                onPressed: a.toggle,
              ),
              if (a.running) _AutoscrollTime(autoscroll: a),
            ],
          ),
        );
      },
    );
  }
}

/// − · time left (live; type any, down to the second) · +, 30 s steps.
class _AutoscrollTime extends StatefulWidget {
  final Autoscroll autoscroll;
  const _AutoscrollTime({required this.autoscroll});

  @override
  State<_AutoscrollTime> createState() => _AutoscrollTimeState();
}

class _AutoscrollTimeState extends State<_AutoscrollTime> {
  Autoscroll get a => widget.autoscroll;
  late final _field = TextEditingController(text: formatDuration(a.remaining));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    a.addListener(_changed);
    a.progress.addListener(_changed);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _field.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _field.text.length,
        );
      } else {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    a.removeListener(_changed);
    a.progress.removeListener(_changed);
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Counts down with the page (but not while you're typing).
  void _changed() {
    if (_focus.hasFocus) return;
    final text = formatDuration(a.remaining);
    if (_field.text != text) _field.text = text;
  }

  /// Typed time left; anything unreadable goes back to the live one.
  void _commit() {
    final v = parseDuration(_field.text);
    if (v != null) a.setRemaining(v);
    _field.text = formatDuration(a.remaining);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '30 seconds less',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 20),
          onPressed: () => a.addRemaining(-Autoscroll.step),
        ),
        SizedBox(
          width: 60,
          child: TextField(
            key: const Key('autoscroll-time'),
            controller: _field,
            focusNode: _focus,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
        IconButton(
          tooltip: '30 seconds more',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => a.addRemaining(Autoscroll.step),
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final PresenterModel model;
  const _KeyButton({required this.model});

  @override
  Widget build(BuildContext context) {
    final written = model.currentSong!.writtenKey;
    final current = model.currentTranspose;
    final setSpecific = model.editingSetSpecific;
    final scheme = Theme.of(context).colorScheme;

    String labelFor(int offset) {
      if (written != null) return written.transposed(offset).name;
      return offset == 0 ? 'Original' : (offset > 0 ? '+$offset' : '$offset');
    }

    final items = <PopupMenuEntry<int>>[
      if (setSpecific)
        const PopupMenuItem<int>(
          enabled: false,
          height: 32,
          child: Text(
            'Key for this setlist only',
            style: TextStyle(fontSize: 12),
          ),
        ),
      for (var offset = -6; offset <= 5; offset++)
        PopupMenuItem<int>(
          value: offset,
          height: 36,
          // (Sized to its contents, so the menu is wide enough for
          // "original" whatever the text size.)
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                child: offset == current
                    ? const Icon(Icons.check, size: 16)
                    : null,
              ),
              SizedBox(width: 56, child: Text(labelFor(offset))),
              Text(
                offset == 0
                    ? 'original'
                    : (offset > 0 ? '+$offset' : '$offset'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
    ];

    // The theme's icon button, so hover / press look like the others.
    return Builder(
      builder: (context) => IconButton(
        tooltip: setSpecific ? 'Change key (this setlist only)' : 'Change key',
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        // the key wheel (circle of fifths); the old list stays for a long press
        onPressed: () => _openKeyWheel(context),
        onLongPress: () async {
          final v = await _menuFrom(context, items, initialValue: current);
          if (v != null) model.setTranspose(v);
        },
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note,
              size: 18,
              color: setSpecific ? scheme.tertiary : null,
            ),
            const SizedBox(width: 4),
            // just the key: ♪ B ▾ ("+2" or "Original" when the song's key is unknown)
            Text(
              key: const ValueKey('key-button-label'),
              written == null
                  ? labelFor(current)
                  : written.transposed(current).name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

extension on _KeyButton {
  /// The key wheel in a dialog: turning it changes the song's key as it comes
  /// to rest, so the song behind follows.
  void _openKeyWheel(BuildContext context) {
    final song = model.currentSong!;
    final chords = [
      for (final m in RegExp(r'\[([^\]]+)\]').allMatches(song.raw))
        ?Chord.parse(m.group(1)!),
    ];
    // the Key button's place on screen: the panel rises from it
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    showAppDialog<void>(
      context: context,
      // (the song behind stays as bright as it is: it changes key as you turn)
      dim: false,
      // the wheel, and (the mic) the key finder in the same panel
      builder: (context) => KeyMenu(
        frame: ({required title, required actions, required builder}) => KeyWheelPopover(
          anchor: anchor,
          setlistOnly: model.editingSetSpecific,
          title: title,
          actions: actions,
          builder: builder,
        ),
        wheel: (size) => KeyWheel(
          // (a fresh wheel after the key finder moved the song)
          key: ValueKey(model.currentTranspose),
          original: song.writtenKey,
          offset: model.currentTranspose,
          chords: chords,
          size: size,
          onChanged: model.setTranspose,
        ),
        finder: (size, back) => KeyFinderView(
          size: size,
          written: song.writtenKey,
          transpose: model.currentTranspose,
          onUse: (offset) {
            model.setTranspose(offset);
            back();
          },
        ),
      ),
    );
  }
}

/// Capo position (chord shapes shift down; the key stays the same).
/// The Gospelizer's quick button (✨): opens its switches — on for this
/// song, the glow, and whether it may change the song's own chords.
class _GospelButton extends StatelessWidget {
  final PresenterModel model;
  const _GospelButton({required this.model});

  @override
  Widget build(BuildContext context) {
    final song = model.currentSong!;
    return Builder(
      builder: (context) => IconButton(
        tooltip: 'Gospelizer',
        isSelected: song.gospelOn,
        icon: const Icon(Icons.auto_awesome_outlined),
        selectedIcon: const Icon(Icons.auto_awesome),
        onPressed: () {
          final box = context.findRenderObject() as RenderBox;
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          final at = RelativeRect.fromRect(
            box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
            Offset.zero & overlay.size,
          );
          showMenu<void>(
            context: context,
            position: at,
            constraints: const BoxConstraints(minWidth: 300, maxWidth: 340),
            items: [_GospelPanel(model: model)],
          );
        },
      ),
    );
  }
}

/// The Gospelizer's switches, as a menu that stays open while you flip
/// them.
class _GospelPanel extends PopupMenuEntry<void> {
  final PresenterModel model;
  const _GospelPanel({required this.model});

  @override
  double get height => 200;

  @override
  bool represents(void value) => false;

  @override
  State<_GospelPanel> createState() => _GospelPanelState();
}

class _GospelPanelState extends State<_GospelPanel> {
  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final song = model.currentSong;
        final s = model.settings;
        if (song == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              dense: true,
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Gospelizer'),
              subtitle: const Text('Gospel reharmonization of this song'),
              value: song.gospelOn,
              onChanged: model.setGospel,
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              title: const Text('Glow'),
              subtitle: Text(
                isEink(context)
                    ? 'Not in e-ink: added chords are in brackets'
                    : 'Off: added chords in brackets, (D7)',
              ),
              value: s.gospelGlow,
              onChanged: (v) => model.updateSettings((s) => s.gospelGlow = v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Keep the song’s chords'),
              subtitle: const Text(
                'Off: a full reharmonization — colours, secondary '
                'dominants, borrowed chords, tritone subs',
              ),
              value: s.gospelKeep,
              onChanged: model.setGospelKeep,
            ),
          ],
        );
      },
    );
  }
}

class _CapoButton extends StatelessWidget {
  final PresenterModel model;
  const _CapoButton({required this.model});

  @override
  Widget build(BuildContext context) {
    final capo = model.currentCapo;
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (context) => IconButton(
        tooltip: model.editingSetSpecific ? 'Capo (this setlist only)' : 'Capo',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // the capo neck in a popover; the old list stays for a long press
        onPressed: () => _openCapoNeck(context),
        onLongPress: () async {
          final v = await _menuFrom(context, [
            for (var i = 0; i <= capoMax; i++)
              CheckedPopupMenuItem<int>(
                value: i,
                checked: i == capo,
                height: 36,
                child: Text(i == 0 ? 'No capo' : 'Capo $i'),
              ),
          ], initialValue: capo);
          if (v != null) model.setCapo(v);
        },
        // the capo icon, with the fret when there is one
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // (the same colour as the toolbar's other icons, capo or not)
            const CapoIcon(size: 22),
            if (capo > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$capo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on _CapoButton {
  /// The capo neck in a popover rising from the Capo button: drag the capo
  /// along it; the song changes as it comes to rest on a fret.
  void _openCapoNeck(BuildContext context) {
    final song = model.currentSong!;
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    // the song's chords (each once, in order), shown as played with the capo
    final seen = <String>{};
    final chords = [
      for (final m in RegExp(r'\[([^\]]+)\]').allMatches(song.raw))
        if (Chord.parse(m.group(1)!) != null && seen.add(m.group(1)!)) m.group(1)!,
    ].take(8).toList();
    var shown = model.currentCapo;
    showAppDialog<void>(
      context: context,
      dim: false,
      builder: (context) => KeyWheelPopover(
        anchor: anchor,
        setlistOnly: model.editingSetSpecific,
        title: null,
        maxWidth: 320,
        sizeFor: (width, room) => (room - 32).clamp(240.0, 430.0),
        builder: (height) => StatefulBuilder(
          builder: (context, setState) {
            final scheme = Theme.of(context).colorScheme;
            final t = model.currentTranspose - shown;
            final key = song.writtenKey?.transposed(t);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CapoNeck(
                  capo: model.currentCapo,
                  height: height,
                  onMoving: (f) => setState(() => shown = f),
                  onChanged: model.setCapo,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shown == 0 ? 'No capo' : 'Capo $shown',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (model.editingSetSpecific)
                        Text('this setlist only', style: TextStyle(fontSize: 12, color: scheme.tertiary)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final c in chords)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(inkR(8)),
                                border: isEink(context) ? Border.all(width: inkW(1), color: scheme.outline) : null,
                              ),
                              child: Text(
                                renderChord(
                                  c,
                                  transpose: t,
                                  key: key,
                                  notation: ChordNotation.standard,
                                  minorStyle: MinorStyle.m,
                                  accidentals: Accidentals.auto,
                                ),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A bar that stays right-aligned when it fits and scrolls sideways when it
/// doesn't (phones, or when the metronome / autoscroll controls open out).
class _BarFit extends StatelessWidget {
  final Widget child;
  const _BarFit({required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    // E-ink: never a strip to scroll; it shrinks to fit instead.
    // (Edge to edge, its buttons spread evenly, so it lines up with the
    // sheet under it.)
    child: isEink(context)
        ? LayoutBuilder(
            builder: (context, c) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: IntrinsicWidth(child: child),
              ),
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            clipBehavior: Clip.none,
            child: child,
          ),
  );
}

/// Rounded floating container used for the toolbar and navigation buttons.
class _Pill extends StatelessWidget {
  final List<Widget> children;

  /// Fills the width it's given, the buttons spread evenly (e-ink phones).
  final bool stretch;
  const _Pill({required this.children, this.stretch = false});

  @override
  Widget build(BuildContext context) {
    final extras = StyleExtras.of(context);
    return Material(
      elevation: extras.toolbarElevation,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: extras.toolbarShape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: stretch
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          spacing: 2,
          children: children,
        ),
      ),
    );
  }
}

/// See [_OperatorScreenState._selections].
class _PageSelection extends ChangeNotifier implements ValueListenable<int> {
  final ValueListenable<int> source;
  _PageSelection(this.source) {
    source.addListener(_changed);
  }

  bool _active = false;
  bool get active => _active;
  set active(bool v) {
    if (v == _active) return;
    final before = value;
    _active = v;
    if (value != before) notifyListeners();
  }

  @override
  int get value => _active ? source.value : 0;

  void _changed() {
    if (_active) notifyListeners();
  }

  @override
  void dispose() {
    source.removeListener(_changed);
    super.dispose();
  }
}

/// Shown while files are dragged over the window.
class _DropTarget extends StatelessWidget {
  final bool visible;

  /// Dropped files go to the media library (its pane is open).
  final bool media;
  const _DropTarget({required this.visible, this.media = false});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(inkR(20)),
        border: Border.all(color: scheme.primary, width: inkW(3)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(Icons.file_download_outlined, size: 56, color: scheme.primary),
            Text(
              media ? 'Drop to add to Media' : 'Drop to import',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              media
                  ? 'Pictures, videos and audio (songs and PDFs import as '
                        'usual)'
                  : 'Songs, backups, PDFs, pictures, videos and audio',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bramble Notes' sidebar motion: the frames where Apple's sidebar edge
/// moved, as (time, progress), followed straight between them.
class _NotesSlide extends Curve {
  final List<(double, double)> points;
  const _NotesSlide(this.points);

  static const show = _NotesSlide([
    (0, 0), (1 / 14, .03), (2 / 14, .21), (3 / 14, .31), (5 / 14, .42),
    (7 / 14, .64), (9 / 14, .84), (11 / 14, .955), (13 / 14, .998), (1, 1),
  ]);
  static const hide = _NotesSlide([
    (0, 0), (1 / 13, .03), (3 / 13, .199), (4 / 13, .419), (6 / 13, .644),
    (10 / 13, .851), (12 / 13, .998), (1, 1),
  ]);

  @override
  double transformInternal(double t) {
    for (var i = 1; i < points.length; i++) {
      final (t1, p1) = points[i];
      if (t <= t1) {
        final (t0, p0) = points[i - 1];
        return p0 + (p1 - p0) * ((t - t0) / (t1 - t0));
      }
    }
    return 1;
  }
}
