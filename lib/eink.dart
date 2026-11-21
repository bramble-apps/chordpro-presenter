// The e-ink look: black and white only, no shadows, gradients or
// animations, and lists that turn pages (arrows) instead of scrolling
// smoothly, which e-ink screens draw badly.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'themes.dart';
import 'bramble_icons.dart';

/// A line of a sheet drawn as one piece (chords over words): e-ink pages
/// keep it whole, like a line of text.
mixin EinkLine on RenderBox {}

/// Marks an e-ink theme (see [isEink]).
class Eink extends ThemeExtension<Eink> {
  const Eink();

  @override
  Eink copyWith() => this;

  @override
  Eink lerp(Eink? other, double t) => this;
}

/// The e-ink look is on (set by the app with the theme), for code with no
/// context to ask: painters and fixed shapes. See [setEink].
bool einkActive = false;

/// Turns the e-ink look's app-wide parts on or off: [einkActive], and
/// every animation (fades, slides, springs, switches, menus, Flutter's own
/// too) finishing within a frame. Code that needs real time from a ticker
/// (autoscroll, playback cursors) multiplies by [timeDilation].
void setEink(bool on) {
  einkActive = on;
  final dilation = on ? 0.001 : 1.0;
  if (timeDilation != dilation) timeDilation = dilation;
  // A steady text cursor (a blinking one redraws twice a second).
  EditableText.debugDeterministicCursor = on;
}

/// [r] as a corner radius: square on e-ink.
double inkR(double r) => einkActive ? 0 : r;

/// [e] as an elevation (a shadow): flat on e-ink.
double inkE(double e) => einkActive ? 0 : e;

/// Outlines on e-ink: thick enough to read at a glance.
const einkStroke = 2.0;

/// [w] as a line width: at least [einkStroke] on e-ink.
double inkW(double w) => einkActive && w < einkStroke ? einkStroke : w;

/// Whether the app is in the e-ink look.
bool isEink(BuildContext context) =>
    Theme.of(context).extension<Eink>() != null;

/// [d], or on e-ink a moment (changes appear at once; not zero, which
/// would finish some animations in the middle of laying out).
Duration motion(BuildContext context, Duration d) =>
    isEink(context) ? const Duration(milliseconds: 1) : d;

/// [showDialog], appearing at once on e-ink (no fade).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  // (a popover-like panel: no wash over the screen behind)
  bool dim = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: isEink(context) ? AnimationStyle.noAnimation : null,
  // E-ink: no grey wash behind (the dialog's thick edge sets it apart).
  barrierColor: isEink(context) || !dim ? Colors.transparent : null,
);

/// [base] (a built theme, for its shapes and font) in black and white.
ThemeData einkTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final ink = dark ? Colors.white : Colors.black;
  final paper = dark ? Colors.black : Colors.white;
  final line = BorderSide(color: ink, width: einkStroke);
  final scheme = ColorScheme(
    brightness: base.brightness,
    primary: ink,
    onPrimary: paper,
    primaryContainer: paper,
    onPrimaryContainer: ink,
    secondary: ink,
    onSecondary: paper,
    // Selected things (toggles, chips, tonal buttons): filled black.
    secondaryContainer: ink,
    onSecondaryContainer: paper,
    tertiary: ink,
    onTertiary: paper,
    tertiaryContainer: paper,
    onTertiaryContainer: ink,
    error: ink,
    onError: paper,
    errorContainer: paper,
    onErrorContainer: ink,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: ink,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: paper,
    surfaceContainerHigh: paper,
    surfaceContainerHighest: paper,
    surfaceBright: paper,
    surfaceDim: paper,
    outline: ink,
    outlineVariant: ink,
    shadow: Colors.transparent,
    scrim: paper.withValues(alpha: 0.6),
    inverseSurface: ink,
    onInverseSurface: paper,
    inversePrimary: paper,
    surfaceTint: Colors.transparent,
  );
  final extras = base.extension<StyleExtras>();
  // Square corners, thick outlines.
  const radius = 0.0;
  RoundedRectangleBorder boxed([double _ = 0]) =>
      RoundedRectangleBorder(side: line);
  // Selected: filled black (white on black in dark mode).
  Color? fill(Set<WidgetState> s) =>
      s.contains(WidgetState.selected) ? ink : null;
  Color fore(Set<WidgetState> s) => s.contains(WidgetState.disabled)
      ? ink.withValues(alpha: 0.4)
      : s.contains(WidgetState.selected)
      ? paper
      : ink;
  final noTransitions = PageTransitionsTheme(
    builders: {for (final p in TargetPlatform.values) p: const _NoTransition()},
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    cardColor: paper,
    dividerColor: ink,
    shadowColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    // No grey washes: menus invert what's under the pointer (below),
    // elsewhere nothing changes on hover.
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    applyElevationOverlayColor: false,
    pageTransitionsTheme: noTransitions,
    dividerTheme: DividerThemeData(color: ink, space: 2, thickness: 1.5),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: line),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(ink),
        foregroundColor: WidgetStatePropertyAll(paper),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(boxed()),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(paper),
        foregroundColor: WidgetStatePropertyAll(ink),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(boxed()),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStatePropertyAll(paper),
        foregroundColor: WidgetStatePropertyAll(ink),
        side: WidgetStatePropertyAll(line),
        shape: WidgetStatePropertyAll(boxed()),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(ink),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        // Only the selected look is set here: otherwise each kind keeps
        // its own colours (a tonal button: white on black, not black on
        // black).
        backgroundColor: WidgetStateProperty.resolveWith(fill),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? fore(s) : null,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => fill(s) ?? paper,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(fore),
        side: WidgetStatePropertyAll(line),
        shape: WidgetStatePropertyAll(boxed()),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: boxed(16),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? paper : ink,
      ),
      thumbIcon: const WidgetStatePropertyAll(null),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ink : paper,
      ),
      trackOutlineColor: WidgetStatePropertyAll(ink),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => fill(s) ?? paper),
      checkColor: WidgetStatePropertyAll(paper),
      side: line,
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(ink)),
    sliderTheme: SliderThemeData(
      activeTrackColor: ink,
      inactiveTrackColor: ink.withValues(alpha: 0.25),
      thumbColor: ink,
      overlayColor: Colors.transparent,
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: paper,
    ),
    cardTheme: CardThemeData(
      color: paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: boxed(radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: line,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paper,
      elevation: 0,
      modalElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(top: line),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: boxed(radius),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) ||
                  s.contains(WidgetState.focused) ||
                  s.contains(WidgetState.pressed)
              ? ink
              : paper,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? ink.withValues(alpha: 0.4)
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused) ||
                    s.contains(WidgetState.pressed)
              ? paper
              : ink,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.hovered) ||
                  s.contains(WidgetState.focused) ||
                  s.contains(WidgetState.pressed)
              ? paper
              : ink,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(paper),
        elevation: const WidgetStatePropertyAll(0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(boxed(radius)),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(paper),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(boxed(radius)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: paper,
      selectedColor: ink,
      checkmarkColor: paper,
      labelStyle: TextStyle(color: ink),
      secondaryLabelStyle: TextStyle(color: paper),
      side: line,
      elevation: 0,
      pressElevation: 0,
      shape: boxed(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper,
      elevation: 0,
      indicatorColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: ink,
      indicatorColor: ink,
      dividerColor: ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: line,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ink,
      selectionColor: ink.withValues(alpha: 0.3),
      selectionHandleColor: ink,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: paper,
      selectedTileColor: ink,
      iconColor: ink,
      textColor: ink,
    ),
    drawerTheme: DrawerThemeData(
      // No grey wash over the rest (its edge sets it apart).
      scrimColor: Colors.transparent,
      backgroundColor: paper,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: Border(right: line),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: paper,
      contentTextStyle: TextStyle(color: ink),
      actionTextColor: ink,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: line,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      exitDuration: Duration.zero,
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: ink, width: einkStroke),
        borderRadius: BorderRadius.zero,
      ),
      textStyle: TextStyle(color: ink, fontSize: 12.5),
    ),
    extensions: [
      StyleExtras(
        headerBar: extras?.headerBar ?? false,
        centeredTitle: extras?.centeredTitle ?? true,
        headerColor: paper,
        sidebarColor: paper,
        selectedRowColor: ink,
        selectedRowText: paper,
        toolbarShape: boxed(),
        toolbarElevation: 0,
        panelRadius: radius,
      ),
      const Eink(),
    ],
  );
}

/// New screens appear at once.
class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// Scrolling for e-ink: no flinging or stretching (each frame of motion is a
/// smeary redraw), no scroll bars, and page arrows on every list taller (or
/// wider) than it shows. Dragging and the mouse wheel still work.
class EinkScrollBehavior extends MaterialScrollBehavior {
  const EinkScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const _NoFling(parent: ClampingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final controller = details.controller;
    // Not for text fields (their own scrolling), slides (pages already)
    // or a list that asks not to.
    // Only lists that run down the screen: sideways strips (swatches,
    // chips, toolbars) are short and keep plain dragging.
    if (controller == null ||
        axisDirectionToAxis(details.direction) != Axis.vertical ||
        controller is PageController ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<NoPageArrows>() != null) {
      return child;
    }
    return _PageArrows(
      controller: controller,
      axis: axisDirectionToAxis(details.direction),
      child: child,
    );
  }
}

/// A list under this has no e-ink page arrows (it brings its own).
class NoPageArrows extends StatelessWidget {
  final Widget child;
  const NoPageArrows({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Lets go of a list where the finger lifts: no gliding on.
class _NoFling extends ScrollPhysics {
  const _NoFling({super.parent});

  @override
  _NoFling applyTo(ScrollPhysics? ancestor) =>
      _NoFling(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(position, 0);
}

/// A page back / page forward pair over the end of a list, shown while
/// there is more than one page.
class _PageArrows extends StatefulWidget {
  final ScrollController controller;
  final Axis axis;
  final Widget child;

  const _PageArrows({
    required this.controller,
    required this.axis,
    required this.child,
  });

  @override
  State<_PageArrows> createState() => _PageArrowsState();
}

class _PageArrowsState extends State<_PageArrows> {
  /// Whether the arrows are showing (they take room from the list, so a
  /// list just too tall with them stays as it is rather than flicker).
  bool _shown = false;
  static const _bar = 44.0;

  /// The list's viewport (to find its lines).
  final _view = GlobalKey();

  /// Where the line cut off by the bottom edge starts (it's blanked out,
  /// and the next page starts with it), or null.
  double? _cut;

  void _refresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      return;
    }
    setState(() => _cut = _cutLine());
  }

  /// The lines on show, top to bottom, in the viewport's coordinates:
  /// text and chord lines, those touching merged into one (a line is
  /// never split).
  List<(double, double)> _lines() {
    final box = _view.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const [];
    final h = box.size.height;
    final spans = <(double, double)>[];
    void visit(RenderObject o) {
      if (o is RenderParagraph || o is EinkLine) {
        if (o is RenderBox && o.hasSize) {
          final top = o.localToGlobal(Offset.zero, ancestor: box).dy;
          final bottom = top + o.size.height;
          if (bottom > -h && top < h * 2) spans.add((top, bottom));
        }
        return;
      }
      o.visitChildren(visit);
    }

    box.visitChildren(visit);
    spans.sort((a, b) => a.$1.compareTo(b.$1));
    final lines = <(double, double)>[];
    for (final s in spans) {
      if (lines.isNotEmpty && s.$1 < lines.last.$2 - 0.5) {
        final last = lines.removeLast();
        lines.add((last.$1, math.max(last.$2, s.$2)));
      } else {
        lines.add(s);
      }
    }
    return lines;
  }

  double _height() {
    final box = _view.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  /// The line the bottom edge cuts through (one starting on this page).
  double? _cutLine() {
    if (widget.axis != Axis.vertical) return null;
    final h = _height();
    for (final (top, bottom) in _lines()) {
      if (top > 0.5 && top < h - 0.5 && bottom > h + 0.5) return top;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    final listened = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _refresh();
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (_) {
          _refresh();
          return false;
        },
        child: KeyedSubtree(key: _view, child: widget.child),
      ),
    );
    // The cut-off line blanked out (it starts the next page).
    final shown = Stack(
      children: [
        listened,
        if (_cut != null && _shown)
          Positioned(
            left: 0,
            right: 0,
            top: _cut,
            bottom: 0,
            child: ColoredBox(color: Theme.of(context).colorScheme.surface),
          ),
      ],
    );
    final arrows = _arrows(context);
    // Below the list (beside it for a sideways one), never over it; over
    // its end when the list sizes itself. (A render object, not a
    // LayoutBuilder: menus measure their lists to size themselves.)
    return _ArrowsLayout(
      axis: widget.axis,
      children: [
        shown,
        if (arrows != null)
          SizedBox(
            height: vertical ? _bar : null,
            width: vertical ? null : _bar,
            child: Center(child: arrows),
          ),
      ],
    );
  }

  Widget? _arrows(BuildContext context) {
    final c = widget.controller;
    final show = _visible(c);
    if (show != _shown) {
      _shown = show;
    }
    if (!show) return null;
    final p = c.position;
    final vertical = widget.axis == Axis.vertical;
    void go(double to) => c.jumpTo(to.clamp(0.0, p.maxScrollExtent));
    void next() {
      final h = p.viewportDimension;
      // The cut-off line starts the next page; else the first line below.
      final cut = _cutLine();
      double? to = cut;
      if (to == null) {
        for (final (top, _) in _lines()) {
          if (top >= h - 0.5) {
            to = top;
            break;
          }
        }
      }
      if (to == null || to < 1) to = h * 0.9;
      go(p.pixels + to);
    }

    void previous() {
      // A screen up, so the page ends where this one starts; then, if a
      // line is cut at the top, back a little more to show it whole (the
      // bottom one is blanked out instead).
      go(p.pixels - p.viewportDimension);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !c.hasClients) return;
        for (final (top, bottom) in _lines()) {
          if (top < -0.5 && bottom > 0.5) {
            go(c.position.pixels + top);
            break;
          }
        }
      });
    }

    final step = p.viewportDimension * 0.9;
    final pages = (p.maxScrollExtent / step).ceil() + 1;
    final page = p.pixels >= p.maxScrollExtent - 1
        ? pages
        : (p.pixels / step).round() + 1;
    return EinkPageBar(
      page: math.min(page, pages),
      pages: pages,
      vertical: vertical,
      onPrevious: p.pixels > 0 ? previous : null,
      onNext: p.pixels < p.maxScrollExtent ? next : null,
    );
  }

  /// More than one page (and big enough to page).
  bool _visible(ScrollController c) {
    if (!c.hasClients || c.positions.length != 1) return false;
    final p = c.position;
    if (!p.hasContentDimensions || !p.hasViewportDimension) {
      // Measured after this frame: look again then.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      return _shown;
    }
    // The room the list has, with the arrows' own room counted back in.
    final room = p.viewportDimension + (_shown ? _bar : 0);
    // Small strips (a row of chips, a short box) keep plain scrolling.
    if (room < 120) return false;
    return p.maxScrollExtent > (_shown ? 0 : 0.5);
  }
}

/// [DropdownButton], or on e-ink a square, outlined menu (Flutter's own
/// dropdown menu always has a soft shadow and no edge).
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final bool isDense;
  final bool isExpanded;
  final Widget? underline;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isDense = false,
    this.isExpanded = false,
    this.underline,
  });

  @override
  Widget build(BuildContext context) {
    if (!isEink(context)) {
      return DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isDense: isDense,
        isExpanded: isExpanded,
        underline: underline,
        // (the list's text the size of the app's menus)
        style: listTextStyle(context),
        // (the app's light caret, as its own dropdowns)
        icon: const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(BrambleIcons.caretDown, size: 16),
        ),
      );
    }
    return _InkMenu<T>(
      value: value,
      items: items ?? const [],
      onChanged: onChanged,
      isExpanded: isExpanded,
      outlined: true,
    );
  }
}

/// [DropdownButtonFormField], or on e-ink the same field with a square,
/// outlined menu.
class AppDropdownField<T> extends StatefulWidget {
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final bool isDense;
  final bool isExpanded;
  final TextStyle? style;

  const AppDropdownField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.isDense = true,
    this.isExpanded = false,
    this.style,
  });

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  late T? _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    if (!isEink(context)) {
      return DropdownButtonFormField<T>(
        initialValue: widget.initialValue,
        items: widget.items,
        onChanged: widget.onChanged,
        decoration: widget.decoration ?? const InputDecoration(),
        isDense: widget.isDense,
        isExpanded: widget.isExpanded,
        style: widget.style ?? listTextStyle(context),
      );
    }
    return InputDecorator(
      decoration: (widget.decoration ?? const InputDecoration()).copyWith(
        isDense: widget.isDense,
      ),
      child: _InkMenu<T>(
        value: _value,
        items: widget.items ?? const [],
        onChanged: widget.onChanged == null
            ? null
            : (v) {
                setState(() => _value = v);
                widget.onChanged!(v);
              },
        isExpanded: true,
        outlined: false,
        style: widget.style ?? listTextStyle(context),
      ),
    );
  }
}

/// The e-ink dropdown: the chosen item and ▾; a themed (square, outlined)
/// menu of the items, the chosen one ticked.
class _InkMenu<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final bool outlined;
  final TextStyle? style;

  const _InkMenu({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isExpanded,
    required this.outlined,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    DropdownMenuItem<T>? chosen;
    for (final i in items) {
      if (i.value == value) chosen = i;
    }
    final enabled = onChanged != null;
    return MenuAnchor(
      builder: (context, menu, _) {
        final label = DefaultTextStyle.merge(
          style: style,
          child: chosen?.child ?? const SizedBox(),
        );
        final row = Row(
          mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (isExpanded) Expanded(child: label) else Flexible(child: label),
            const SizedBox(width: 4),
            Icon(
              BrambleIcons.caretDown,
              size: 16,
              color: enabled ? ink : ink.withValues(alpha: 0.4),
            ),
          ],
        );
        return InkWell(
          onTap: enabled
              ? () => menu.isOpen ? menu.close() : menu.open()
              : null,
          child: outlined
              ? Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: ink, width: einkStroke),
                  ),
                  child: row,
                )
              : row,
        );
      },
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            leadingIcon: Icon(
              item.value == value ? BrambleIcons.check : null,
              size: 18,
            ),
            onPressed: item.enabled
                ? () {
                    item.onTap?.call();
                    onChanged?.call(item.value);
                  }
                : null,
            child: item.child,
          ),
      ],
    );
  }
}

/// [CircularProgressIndicator], or on e-ink a still hourglass (a spinner
/// would redraw the screen for as long as it shows).
class AppSpinner extends StatelessWidget {
  final double? value;
  final double? strokeWidth;
  final Color? color;
  const AppSpinner({super.key, this.value, this.strokeWidth, this.color});

  @override
  Widget build(BuildContext context) {
    if (value == null && isEink(context)) {
      return LayoutBuilder(
        builder: (context, c) {
          final size = c.hasBoundedHeight && c.maxHeight < 36
              ? c.maxHeight
              : 24.0;
          return Icon(BrambleIcons.hourglass, size: size, color: color);
        },
      );
    }
    return CircularProgressIndicator(
      value: value,
      strokeWidth: strokeWidth,
      color: color,
    );
  }
}

/// [LinearProgressIndicator], or on e-ink (when it can't say how far) a
/// still, half-filled bar.
class AppProgressBar extends StatelessWidget {
  final double? value;
  final double? minHeight;
  const AppProgressBar({super.key, this.value, this.minHeight});

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: value ?? (isEink(context) ? 0.5 : null),
    minHeight: minHeight,
  );
}

/// The e-ink page strip: ‹ page / pages ›, the same everywhere.
class EinkPageBar extends StatelessWidget {
  final int page;
  final int pages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool vertical;

  const EinkPageBar({
    super.key,
    required this.page,
    required this.pages,
    required this.onPrevious,
    required this.onNext,
    this.vertical = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.onSurface, width: einkStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous page',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              vertical ? BrambleIcons.caretUp : BrambleIcons.caretLeft,
            ),
            onPressed: onPrevious,
          ),
          Text(
            '$page/$pages',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              vertical ? BrambleIcons.caretDown : BrambleIcons.caretRight,
            ),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Rows split into pages of whole rows (none cut off at the bottom): only
/// page [page] shows. [onPages] hears how many pages there are.
class EinkPagedRows extends MultiChildRenderObjectWidget {
  final int page;
  final ValueChanged<int> onPages;

  const EinkPagedRows({
    super.key,
    required this.page,
    required this.onPages,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPagedRows(page, onPages);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPagedRows)
      ..page = page
      ..onPages = onPages;
  }
}

class _PagedRowData extends ContainerBoxParentData<RenderBox> {
  int page = 0;
}

class _RenderPagedRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PagedRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PagedRowData> {
  _RenderPagedRows(this._page, this.onPages);

  int _page;
  set page(int v) {
    if (v == _page) return;
    _page = v;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ValueChanged<int> onPages;
  int _pages = 1;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PagedRowData) {
      child.parentData = _PagedRowData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    var page = 0;
    var y = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: size.width),
        parentUsesSize: true,
      );
      final h = child.size.height;
      // Doesn't fit under the last one: the next page.
      if (y > 0 && y + h > size.height) {
        page++;
        y = 0;
      }
      final data = child.parentData! as _PagedRowData;
      if (data.page != page) markNeedsSemanticsUpdate();
      data
        ..page = page
        ..offset = Offset(0, y);
      y += h;
      child = data.nextSibling;
    }
    final pages = page + 1;
    if (pages != _pages) {
      _pages = pages;
      WidgetsBinding.instance.addPostFrameCallback((_) => onPages(pages));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _PagedRowData;
      if (data.page == _page) context.paintChild(child, offset + data.offset);
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _PagedRowData;
      if (data.page == _page) {
        final hit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (result, p) => child!.hitTest(result, position: p),
        );
        if (hit) return true;
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _PagedRowData;
      if (data.page == _page) visitor(child);
      child = data.nextSibling;
    }
  }
}

/// E-ink: the heading of a section opened on its own — ‹ and its title,
/// in line with the content's left edge, a rule under it, then room.
class EinkBackHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const EinkBackHeader({super.key, required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onBack,
        child: Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.onSurface, width: einkStroke),
            ),
          ),
          child: Row(
            spacing: 4,
            children: [
              const Icon(BrambleIcons.caretLeft),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list and (maybe) its page strip: the strip after the list when the
/// room is bounded, else over the list's end. Measurable (intrinsics).
class _ArrowsLayout extends MultiChildRenderObjectWidget {
  final Axis axis;
  const _ArrowsLayout({required this.axis, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArrowsLayout(axis);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderArrowsLayout).axis = axis;
  }
}

class _ArrowsData extends ContainerBoxParentData<RenderBox> {}

class _RenderArrowsLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ArrowsData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ArrowsData> {
  _RenderArrowsLayout(this._axis);

  Axis _axis;
  set axis(Axis v) {
    if (v == _axis) return;
    _axis = v;
    markNeedsLayout();
  }

  bool get _vertical => _axis == Axis.vertical;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ArrowsData) child.parentData = _ArrowsData();
  }

  RenderBox get _list => firstChild!;
  RenderBox? get _strip => childAfter(firstChild!);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _list.getMinIntrinsicWidth(height);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _list.getMaxIntrinsicWidth(height);
  @override
  double computeMinIntrinsicHeight(double width) =>
      _list.getMinIntrinsicHeight(width);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _list.getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _list.getDryLayout(constraints);

  @override
  void performLayout() {
    final list = _list, strip = _strip;
    final bounded = _vertical
        ? constraints.hasBoundedHeight
        : constraints.hasBoundedWidth;
    if (strip == null || !bounded) {
      list.layout(constraints, parentUsesSize: true);
      (list.parentData! as _ArrowsData).offset = Offset.zero;
      size = list.size;
      if (strip != null) {
        strip.layout(constraints.loosen(), parentUsesSize: true);
        (strip.parentData! as _ArrowsData).offset = Offset(
          size.width - strip.size.width - 4,
          size.height - strip.size.height - 4,
        );
      }
      return;
    }
    if (_vertical) {
      strip.layout(
        BoxConstraints.tightFor(width: constraints.maxWidth).loosen(),
        parentUsesSize: true,
      );
      final h = strip.size.height;
      list.layout(
        constraints.copyWith(
          minHeight: math.max(0, constraints.minHeight - h),
          maxHeight: math.max(0, constraints.maxHeight - h),
        ),
        parentUsesSize: true,
      );
      (list.parentData! as _ArrowsData).offset = Offset.zero;
      (strip.parentData! as _ArrowsData).offset = Offset(
        (list.size.width - strip.size.width) / 2,
        list.size.height,
      );
      size = constraints.constrain(Size(list.size.width, list.size.height + h));
    } else {
      strip.layout(
        BoxConstraints.tightFor(height: constraints.maxHeight).loosen(),
        parentUsesSize: true,
      );
      final w = strip.size.width;
      list.layout(
        constraints.copyWith(
          minWidth: math.max(0, constraints.minWidth - w),
          maxWidth: math.max(0, constraints.maxWidth - w),
        ),
        parentUsesSize: true,
      );
      (list.parentData! as _ArrowsData).offset = Offset.zero;
      (strip.parentData! as _ArrowsData).offset = Offset(
        list.size.width,
        (list.size.height - strip.size.height) / 2,
      );
      size = constraints.constrain(Size(list.size.width + w, list.size.height));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The text of the app's lists of choices (dropdowns, as menus): Material's
/// label size, 14, in the surface's text colour.
TextStyle listTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.labelLarge!.copyWith(
    color: theme.colorScheme.onSurface,
    fontWeight: FontWeight.w400,
  );
}
