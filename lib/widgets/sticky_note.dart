import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import 'floating_panel.dart';
import 'rich_note_controller.dart';
import '../eink.dart';

/// Classic sticky-note colours.
const stickyColours = <(String, int)>[
  ('Yellow', 0xFFFFF475),
  ('Pink', 0xFFFFB3D1),
  ('Green', 0xFFCCFF90),
  ('Blue', 0xFFB3E5FC),
  ('Orange', 0xFFFFCC80),
  ('Purple', 0xFFD7B8FB),
];

/// Where notes live: floating over the app, or pinned onto a song's
/// sheet (one board per drawn sheet). Used to turn a note's position from
/// one into the other when pinning / unpinning.
class StickyBoards {
  static final floating = GlobalKey(debugLabel: 'floating notes');
  static final Map<String, GlobalKey> _pinned = {};

  /// The sheet (song + setlist entry) currently open.
  static String? currentSheet;

  static GlobalKey pinnedFor(String sheet) =>
      _pinned.putIfAbsent(sheet, () => GlobalKey(debugLabel: 'pinned $sheet'));

  static RenderBox? _box(GlobalKey? k) =>
      k?.currentContext?.findRenderObject() as RenderBox?;

  static RenderBox? get floatingBox => _box(floating);
  static RenderBox? get pinnedBox =>
      currentSheet == null ? null : _box(_pinned[currentSheet]);
}

/// A song's sticky notes: the floating ones (over the app) or the pinned
/// ones (on its sheet, scrolling with it). Each moves like the video
/// player (throw it, it settles; near an edge it snaps), resizes from any
/// corner, and shows its toolbar above it on hover.
class StickyLayer extends StatelessWidget {
  final PresenterModel model;
  final Song song;
  final bool pinned;
  final GlobalKey board;

  const StickyLayer({
    super.key,
    required this.model,
    required this.song,
    required this.board,
    this.pinned = false,
  });

  static const toolbarRoom = 52.0;

  @override
  Widget build(BuildContext context) {
    // Rebuilds by itself (sheets are drawn ahead and reused).
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final notes = [
          for (final n in model.stickiesOf(song))
            if (n.pinned == pinned) n,
        ];
        return Stack(
          key: board,
          children: [
            for (final n in notes)
              Positioned.fill(
                child: FloatingPanel(
                  key: ValueKey('${pinned ? 'pin' : 'float'}-${n.id}'),
                  id: '${pinned ? 'pin' : 'float'}-${n.id}',
                  freeAspect: true,
                  allCorners: true,
                  overhang: toolbarRoom,
                  margin: pinned ? 0 : 8,
                  startAt: Offset(n.x, n.y - toolbarRoom),
                  initialWidth: n.width,
                  initialHeight: n.height,
                  // Can be smaller than its toolbar (which keeps one size
                  // and stays on screen).
                  minWidth: 110,
                  minHeight: 70,
                  maxWidth: 900,
                  maxHeight: 900,
                  onSettled: (r) => model.updateSticky(
                    song,
                    n
                      ..x = r.left
                      ..y = r.top
                      ..width = r.width
                      ..height = r.height,
                  ),
                  child: StickyCard(model: model, song: song, note: n),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One note: a strip to drag it by, the text, and (above it, on hover) a
/// toolbar for bold, italic, size, colour and delete.
class StickyCard extends StatefulWidget {
  final PresenterModel model;
  final Song song;
  final StickyNote note;
  const StickyCard({
    super.key,
    required this.model,
    required this.song,
    required this.note,
  });

  @override
  State<StickyCard> createState() => _StickyCardState();
}

class _StickyCardState extends State<StickyCard>
    with SingleTickerProviderStateMixin {
  /// When notes were just pinned / unpinned: they arrive with a little
  /// lowering / lifting animation (picked up by whichever card shows them,
  /// even if the page is rebuilt meanwhile).
  static final Map<String, DateTime> _justMoved = {};

  /// The toolbar's width (7 round buttons in the pill).
  static const toolbarWidth = 7 * 36.0 + 8;

  late final _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );
  final _portal = OverlayPortalController();
  final _anchor = LayerLink();

  /// Round buttons inside the pill-shaped toolbar.
  static final _round = IconButton.styleFrom(
    shape: const CircleBorder(),
    fixedSize: const Size.square(36),
    minimumSize: const Size.square(36),
    padding: EdgeInsets.zero,
  );

  late final _text = RichNoteController.fromRuns(
    widget.note.runs,
    text: widget.note.text,
    base: CharStyle(
      bold: widget.note.bold,
      italic: widget.note.italic,
      size: widget.note.size,
    ),
  )..addListener(_textChanged);
  final _focus = FocusNode();
  bool _hover = false;
  Timer? _leave;
  Timer? _typing;

  StickyNote get note => widget.note;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    final moved = _justMoved[note.id];
    if (moved != null) {
      final done =
          DateTime.now().difference(moved).inMilliseconds /
          _settle.duration!.inMilliseconds;
      if (done < 1) {
        _settle.forward(from: done.clamp(0.0, 1.0));
      } else {
        _justMoved.remove(note.id);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
  }

  @override
  void dispose() {
    _leave?.cancel();
    _typing?.cancel();
    _settle.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save({bool notify = false}) =>
      widget.model.updateSticky(widget.song, note, notify: notify);

  void _change(void Function() f) {
    setState(f);
    _save();
  }

  /// Pins the note onto the sheet right where it is (or back to floating
  /// over the app), so it doesn't jump.
  void _togglePin() {
    final me = context.findRenderObject() as RenderBox?;
    final to = note.pinned ? StickyBoards.floatingBox : StickyBoards.pinnedBox;
    if (me == null || to == null) return;
    // The note's top-left (under the toolbar room), on screen.
    final onScreen = me.localToGlobal(const Offset(0, StickyLayer.toolbarRoom));
    final there = to.globalToLocal(onScreen);
    FloatingPanel.forget('pin-${note.id}');
    FloatingPanel.forget('float-${note.id}');
    _justMoved[note.id] = DateTime.now();
    note
      ..pinned = !note.pinned
      ..x = there.dx
      ..y = there.dy;
    widget.model.updateSticky(widget.song, note, notify: true);
  }

  /// Text or formatting changed: saved shortly after.
  void _textChanged() {
    note
      ..text = _text.text
      ..runs = _text.toRuns()
      ..bold = _text.base.bold
      ..italic = _text.base.italic
      ..size = _text.base.size;
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 400), _save);
    if (mounted) setState(() {}); // toolbar on / off states
  }

  // A short grace period so moving from the note up to its toolbar
  // doesn't make the toolbar vanish.
  void _enter() {
    _leave?.cancel();
    if (!_hover) setState(() => _hover = true);
  }

  void _exit() {
    _leave?.cancel();
    _leave = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => _hover = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final moving = FloatingPanel.movingOf(context);
    // E-ink: white paper, black ink and edge, whatever its colour.
    final eink = isEink(context);
    final paper = eink ? Colors.white : Color(note.colour);
    final ink = eink ? Colors.black : const Color(0xFF1F1F1F);
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Room for the toolbar, which is drawn in the overlay (so it
          // can be wider than a small note and still take taps).
          CompositedTransformTarget(
            link: _anchor,
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => _floatingToolbar(moving),
              child: const SizedBox(height: StickyLayer.toolbarRoom),
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _settle,
              builder: (context, child) {
                // Pinned: lowered onto the page (a dip, and a small
                // shadow); floating: lifted off it (a big shadow).
                final t = Curves.easeOutCubic.transform(_settle.value);
                final resting = note.pinned ? 1.0 : 5.0;
                final from = note.pinned ? 5.0 : 1.0;
                final dip = note.pinned
                    ? 1 - 0.045 * math.sin(math.pi * _settle.value)
                    : 1 + 0.03 * math.sin(math.pi * _settle.value);
                return Transform.scale(
                  scale: dip,
                  child: Material(
                    color: paper,
                    elevation: inkE(from + (resting - from) * t),
                    shadowColor: Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(inkR(3)),
                      side: eink
                          ? const BorderSide(color: Colors.black, width: 2)
                          : BorderSide.none,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: child,
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The strip to drag it by.
                  FloatingDragArea(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: eink
                            ? null
                            : Colors.black.withValues(alpha: 0.06),
                        border: eink
                            ? const Border(
                                bottom: BorderSide(color: Colors.black),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.drag_handle,
                        size: 14,
                        color: eink ? ink : ink.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      cursorColor: ink,
                      // Per-letter bold / italic / size come from the
                      // controller; this is the rest.
                      style: TextStyle(
                        color: ink,
                        fontSize: _text.base.size,
                        height: 1.3,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Note…',
                        hintStyle: TextStyle(color: ink.withValues(alpha: 0.4)),
                        // Plain paper: no field outline in any style.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          8,
                          12,
                          12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The toolbar above the note, in the overlay: on hover (or while
  /// typing, for touch screens), never while the note is being moved, and
  /// slid sideways if needed to stay on screen.
  Widget _floatingToolbar(ValueListenable<bool>? moving) =>
      ValueListenableBuilder<bool>(
        valueListenable: moving ?? ValueNotifier(false),
        builder: (context, isMoving, _) {
          final show = (_hover || _focus.hasFocus) && !isMoving;
          var dx = 0.0;
          final box = this.context.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize && box.attached) {
            final left = box.localToGlobal(Offset.zero).dx;
            final screen = MediaQuery.sizeOf(context).width;
            final fits = math.max(8.0, screen - toolbarWidth - 8);
            dx = left.clamp(8.0, fits) - left;
          }
          return CompositedTransformFollower(
            link: _anchor,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: Offset(dx, 0),
            child: Align(
              alignment: Alignment.bottomLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: MouseRegion(
                onEnter: (_) => _enter(),
                onExit: (_) => _exit(),
                child: IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    key: const Key('sticky-toolbar'),
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: show ? Offset.zero : const Offset(0, 0.15),
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOutCubic,
                      child: AnimatedScale(
                        scale: show ? 1 : 0.94,
                        alignment: Alignment.bottomLeft,
                        duration: const Duration(milliseconds: 110),
                        curve: Curves.easeOutCubic,
                        // Taps here keep the text's selection; the gap
                        // under the toolbar counts as the toolbar (so
                        // moving up to it doesn't make it vanish).
                        child: TextFieldTapRegion(
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _toolbar(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Every control sits in the same 36 px circle, whatever its state.
    Widget slot(Widget child) => SizedBox.square(dimension: 36, child: child);
    Widget button(String tip, IconData icon, VoidCallback onTap, {bool? on}) =>
        slot(
          IconButton(
            tooltip: tip,
            isSelected: on,
            padding: EdgeInsets.zero,
            style: _round.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                on == true ? scheme.primary.withValues(alpha: 0.18) : null,
              ),
              foregroundColor: on == true
                  ? WidgetStatePropertyAll(scheme.primary)
                  : null,
            ),
            icon: Icon(icon, size: 20),
            onPressed: onTap,
          ),
        );
    return Material(
      elevation: inkE(6),
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(inkR(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The selection, or the whole note when nothing is selected.
            button(
              'Bold',
              Icons.format_bold,
              _text.toggleBold,
              on: _text.all((c) => c.bold),
            ),
            button(
              'Italic',
              Icons.format_italic,
              _text.toggleItalic,
              on: _text.all((c) => c.italic),
            ),
            button('Smaller text', Icons.remove, () => _text.resize(-2)),
            button('Larger text', Icons.add, () => _text.resize(2)),
            slot(
              PopupMenuButton<int>(
                tooltip: 'Note colour',
                position: PopupMenuPosition.under,
                onOpened: _enter,
                onSelected: (c) => _change(() => note.colour = c),
                itemBuilder: (context) => [
                  for (final (name, c) in stickyColours)
                    PopupMenuItem(
                      value: c,
                      height: 40,
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c == note.colour
                                    ? scheme.primary
                                    : Colors.black26,
                                width: inkW(c == note.colour ? 2.5 : 1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(name),
                        ],
                      ),
                    ),
                ],
                // An icon-style button, so it's round like the others.
                style: _round,
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Color(note.colour),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26, width: inkW(1)),
                  ),
                ),
              ),
            ),
            button(
              note.pinned
                  ? 'Unpin (float over the app)'
                  : 'Pin to the page (scrolls with it)',
              note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              _togglePin,
              on: note.pinned,
            ),
            button(
              'Delete note',
              Icons.delete_outline,
              () => widget.model.removeSticky(widget.song, note.id),
            ),
          ],
        ),
      ),
    );
  }
}
