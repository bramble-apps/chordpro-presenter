import 'package:flutter/material.dart';

/// A colour theme: a main colour plus an accent. Each works in light and
/// dark mode (colours are derived for both).
class AppTheme {
  final String id;
  final String name;
  final Color primary;
  final Color accent;
  const AppTheme(this.id, this.name, this.primary, this.accent);
}

/// 'default' = the stock colour of the chosen desktop style (Adwaita blue,
/// Ubuntu orange, Plasma blue, Mint green, elementary blueberry, Material
/// purple). The rest work with any style.
const defaultThemeId = 'default';

const appThemes = [
  AppTheme(defaultThemeId, 'Default', Color(0xFF6750A4), Color(0xFF6750A4)),
  AppTheme('indigo', 'Indigo', Color(0xFF3F51B5), Color(0xFF00BFA5)),
  AppTheme('ocean', 'Ocean', Color(0xFF0277BD), Color(0xFF26C6DA)),
  AppTheme('forest', 'Forest', Color(0xFF2E7D32), Color(0xFFFFB300)),
  AppTheme('sunset', 'Sunset', Color(0xFFEF6C00), Color(0xFFEC407A)),
  AppTheme('rose', 'Rose', Color(0xFFC2185B), Color(0xFF7E57C2)),
  AppTheme('lavender', 'Lavender', Color(0xFF7E57C2), Color(0xFF26A69A)),
  AppTheme('crimson', 'Crimson', Color(0xFFC62828), Color(0xFFFFC107)),
  AppTheme('teal', 'Teal', Color(0xFF00897B), Color(0xFFFF7043)),
  AppTheme('sand', 'Sand', Color(0xFF8D6E63), Color(0xFF26A69A)),
  AppTheme('slate', 'Slate', Color(0xFF546E7A), Color(0xFFFF8F00)),
  AppTheme('midnight', 'Midnight', Color(0xFF1A237E), Color(0xFF00E5FF)),
  AppTheme('graphite', 'Graphite', Color(0xFF616161), Color(0xFF9E9E9E)),
];

AppTheme themeById(String id) =>
    appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);

/// Desktop look, modelled on each desktop's official theme: shapes,
/// borders, header bars, neutral greys, selection style and font. Colours
/// come from the published palettes (libadwaita CSS variables, KDE
/// BreezeLight/BreezeDark.colors, Yaru and Mint-Y sass, elementary palette).
enum UiStyle { material, adwaita, yaru, breeze, mint, elementary }

/// Neutral greys of a desktop theme.
class _Greys {
  final Color window, view, header, sidebar, button, border;
  const _Greys({
    required this.window,
    required this.view,
    required this.header,
    required this.sidebar,
    required this.button,
    required this.border,
  });
}

class _StyleSpec {
  final String label;
  final String description;

  /// The desktop's stock accent colour (used by the "Default" colour).
  final Color stockAccent;

  /// Built-in font id from fonts.dart (null = app default).
  final String? fontId;
  final double buttonRadius;
  final double cardRadius;
  final double dialogRadius;

  /// App uses a header bar + bottom toolbar (desktop) instead of floating
  /// toolbars (Material).
  final bool headerBar;
  final bool centeredTitle;

  /// Selected list rows are filled with the accent (KDE, Mint) instead of
  /// a neutral grey (GNOME, Ubuntu, elementary).
  final bool accentSelection;

  /// Thin borders around buttons (KDE).
  final bool borderedButtons;
  final bool compact;
  final _Greys? light;
  final _Greys? dark;

  const _StyleSpec({
    required this.label,
    required this.description,
    required this.stockAccent,
    this.fontId,
    required this.buttonRadius,
    required this.cardRadius,
    required this.dialogRadius,
    this.headerBar = true,
    this.centeredTitle = true,
    this.accentSelection = false,
    this.borderedButtons = false,
    this.compact = false,
    this.light,
    this.dark,
  });
}

const _specs = {
  UiStyle.material: _StyleSpec(
    label: 'Material',
    description: 'Google Material 3 (Android, ChromeOS)',
    stockAccent: Color(0xFF6750A4),
    // (Sfera, the San Francisco stand-in, in place of Roboto)
    fontId: 'sfera',
    buttonRadius: 20,
    cardRadius: 12,
    dialogRadius: 28,
    headerBar: false,
  ),
  // libadwaita 1.7 CSS variables.
  UiStyle.adwaita: _StyleSpec(
    label: 'Adwaita',
    description: 'GNOME, Fedora',
    stockAccent: Color(0xFF3584E4),
    fontId: 'cantarell',
    buttonRadius: 6,
    cardRadius: 12,
    dialogRadius: 15,
    light: _Greys(
      window: Color(0xFFFAFAFB),
      view: Color(0xFFFFFFFF),
      header: Color(0xFFFFFFFF),
      sidebar: Color(0xFFEBEBED),
      button: Color(0xFFEAEAEC),
      border: Color(0x26000006),
    ),
    dark: _Greys(
      window: Color(0xFF222226),
      view: Color(0xFF1D1D20),
      header: Color(0xFF2E2E32),
      sidebar: Color(0xFF2E2E32),
      button: Color(0xFF3A3A3E),
      border: Color(0x26FFFFFF),
    ),
  ),
  // Yaru: #FAFAFA light bg, dark bg = lighten(#181818, 8%).
  UiStyle.yaru: _StyleSpec(
    label: 'Yaru',
    description: 'Ubuntu',
    stockAccent: Color(0xFFE95420),
    fontId: 'ubuntu',
    buttonRadius: 6,
    cardRadius: 9,
    dialogRadius: 12,
    light: _Greys(
      window: Color(0xFFFAFAFA),
      view: Color(0xFFFFFFFF),
      header: Color(0xFFEBEBEB),
      sidebar: Color(0xFFF0F0F0),
      button: Color(0xFFE8E8E8),
      border: Color(0xFFD7D7D7),
    ),
    dark: _Greys(
      window: Color(0xFF2C2C2C),
      view: Color(0xFF262626),
      header: Color(0xFF303030),
      sidebar: Color(0xFF282828),
      button: Color(0xFF3C3C3C),
      border: Color(0xFF454545),
    ),
  ),
  // KDE BreezeLight.colors / BreezeDark.colors (Plasma 6).
  UiStyle.breeze: _StyleSpec(
    label: 'Breeze',
    description: 'KDE Plasma',
    stockAccent: Color(0xFF3DAEE9),
    fontId: 'notosans',
    buttonRadius: 5,
    cardRadius: 5,
    dialogRadius: 7,
    centeredTitle: false,
    accentSelection: true,
    borderedButtons: true,
    compact: true,
    light: _Greys(
      window: Color(0xFFEFF0F1),
      view: Color(0xFFFFFFFF),
      header: Color(0xFFDEE0E2),
      sidebar: Color(0xFFEFF0F1),
      button: Color(0xFFFCFCFC),
      border: Color(0xFFBDC3C7),
    ),
    dark: _Greys(
      window: Color(0xFF202326),
      view: Color(0xFF141618),
      header: Color(0xFF292C30),
      sidebar: Color(0xFF202326),
      button: Color(0xFF292C30),
      border: Color(0xFF4D5357),
    ),
  ),
  // Mint-Y sass: header #EBEBED / #222226, bg 5% lighter, base #FFF / #333339.
  UiStyle.mint: _StyleSpec(
    label: 'Mint-Y',
    description: 'Linux Mint (Cinnamon)',
    stockAccent: Color(0xFF35A854),
    fontId: 'ubuntu',
    buttonRadius: 5,
    cardRadius: 6,
    dialogRadius: 8,
    accentSelection: true,
    light: _Greys(
      window: Color(0xFFF8F8F9),
      view: Color(0xFFFFFFFF),
      header: Color(0xFFEBEBED),
      sidebar: Color(0xFFF2F2F3),
      button: Color(0xFFFCFCFD),
      border: Color(0xFFCFCFD1),
    ),
    dark: _Greys(
      window: Color(0xFF2E2E33),
      view: Color(0xFF333339),
      header: Color(0xFF222226),
      sidebar: Color(0xFF29292E),
      button: Color(0xFF38383E),
      border: Color(0xFF26262A),
    ),
  ),
  // elementary stylesheet palette (SILVER_100 #fafafa, BLACK_500 #333).
  UiStyle.elementary: _StyleSpec(
    label: 'elementary',
    description: 'elementary OS (Pantheon)',
    stockAccent: Color(0xFF3689E6),
    buttonRadius: 4,
    cardRadius: 6,
    dialogRadius: 9,
    light: _Greys(
      window: Color(0xFFFAFAFA),
      view: Color(0xFFFFFFFF),
      header: Color(0xFFF0F0F0),
      sidebar: Color(0xFFF2F2F2),
      button: Color(0xFFF5F5F5),
      border: Color(0x26000000),
    ),
    dark: _Greys(
      window: Color(0xFF333333),
      view: Color(0xFF2B2B2B),
      header: Color(0xFF3A3A3A),
      sidebar: Color(0xFF2F2F2F),
      button: Color(0xFF444444),
      border: Color(0x26FFFFFF),
    ),
  ),
};

extension UiStyleInfo on UiStyle {
  String get label => _specs[this]!.label;
  String get description => _specs[this]!.description;
  Color get stockAccent => _specs[this]!.stockAccent;

  /// Font the style uses (a built-in font id), or null for the app default.
  String? get fontId => _specs[this]!.fontId;
}

/// Layout facts the app's own widgets read from the theme.
class StyleExtras extends ThemeExtension<StyleExtras> {
  final bool headerBar;
  final bool centeredTitle;
  final Color headerColor;
  final Color sidebarColor;
  final Color selectedRowColor;
  final Color selectedRowText;
  final ShapeBorder toolbarShape;
  final double toolbarElevation;
  final double panelRadius;

  const StyleExtras({
    required this.headerBar,
    required this.centeredTitle,
    required this.headerColor,
    required this.sidebarColor,
    required this.selectedRowColor,
    required this.selectedRowText,
    required this.toolbarShape,
    required this.toolbarElevation,
    required this.panelRadius,
  });

  static StyleExtras of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StyleExtras>() ??
        StyleExtras(
          headerBar: false,
          centeredTitle: true,
          headerColor: theme.colorScheme.surfaceContainerHigh,
          sidebarColor: theme.colorScheme.surface,
          selectedRowColor: theme.colorScheme.secondaryContainer,
          selectedRowText: theme.colorScheme.onSecondaryContainer,
          toolbarShape: const StadiumBorder(),
          toolbarElevation: 4,
          panelRadius: 8,
        );
  }

  @override
  StyleExtras copyWith() => this;

  @override
  StyleExtras lerp(StyleExtras? other, double t) =>
      t < 0.5 ? this : other ?? this;
}

/// Tooltips appear after a short pause, as on desktop systems, instead of
/// the moment the pointer passes over a button.
const _tooltipWait = Duration(milliseconds: 500);

ColorScheme _oled(ColorScheme s) => s.copyWith(
  surface: Colors.black,
  surfaceContainerLowest: Colors.black,
  surfaceContainerLow: const Color(0xFF080808),
  surfaceContainer: const Color(0xFF101010),
  surfaceContainerHigh: const Color(0xFF181818),
  surfaceContainerHighest: const Color(0xFF222222),
);

ThemeData buildTheme(
  AppTheme t,
  Brightness brightness, {
  bool oled = false,
  UiStyle style = UiStyle.material,
  String? fontFamily,
}) => _evenLists(
  _buildTheme(t, brightness, oled: oled, style: style, fontFamily: fontFamily),
);

/// Every list of choices at one size: popup menus (⋯, Project…) and menus
/// in Material's label size, 14, as the app's dropdowns (listTextStyle),
/// regular weight, in every style.
ThemeData _evenLists(ThemeData theme) {
  final size = Typography.material2021(platform: theme.platform)
      .englishLike
      .labelLarge!
      .copyWith(fontWeight: FontWeight.w400);
  final on = theme.colorScheme.onSurface;
  final item = size.copyWith(color: on);
  return theme.copyWith(
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      textStyle: item,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? item.copyWith(color: on.withValues(alpha: .38))
            : item,
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: (theme.menuButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(item),
      ),
    ),
  );
}

ThemeData _buildTheme(
  AppTheme t,
  Brightness brightness, {
  bool oled = false,
  UiStyle style = UiStyle.material,
  String? fontFamily,
}) {
  final spec = _specs[style]!;
  final dark = brightness == Brightness.dark;
  final isDefault = t.id == defaultThemeId;
  final primaryColor = isDefault ? spec.stockAccent : t.primary;

  var scheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: brightness,
  );
  if (!isDefault) {
    final accent = ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: brightness,
    );
    scheme = scheme.copyWith(
      secondary: accent.primary,
      onSecondary: accent.onPrimary,
      secondaryContainer: accent.primaryContainer,
      onSecondaryContainer: accent.onPrimaryContainer,
    );
  }

  if (style == UiStyle.material) {
    if (oled && dark) scheme = _oled(scheme);
    return ThemeData(
      colorScheme: scheme,
      fontFamily: fontFamily,
      tooltipTheme: const TooltipThemeData(waitDuration: _tooltipWait),
      extensions: [
        StyleExtras(
          headerBar: false,
          centeredTitle: true,
          headerColor: scheme.surfaceContainerHigh,
          sidebarColor: scheme.surface,
          selectedRowColor: scheme.secondaryContainer,
          selectedRowText: scheme.onSecondaryContainer,
          toolbarShape: const StadiumBorder(),
          toolbarElevation: 4,
          panelRadius: 8,
        ),
      ],
    );
  }

  // Desktop styles: the accent is used as-is (suggested actions, switches,
  // focus), on the desktop's own neutral greys.
  final g = dark ? spec.dark! : spec.light!;
  final accent = primaryColor;
  final onAccent =
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final fg = dark ? const Color(0xFFFCFCFC) : const Color(0xFF232629);
  final dimFg = dark ? const Color(0xFFA1A9B1) : const Color(0xFF5E6266);
  var header = g.header, sidebar = g.sidebar;
  scheme = scheme.copyWith(
    primary: accent,
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,
    // Raised (non-suggested) buttons, chips and tonal buttons are neutral.
    secondaryContainer: g.button,
    onSecondaryContainer: fg,
    surface: g.window,
    onSurface: fg,
    onSurfaceVariant: dimFg,
    surfaceContainerLowest: g.view,
    surfaceContainerLow: g.view,
    surfaceContainer: g.window,
    surfaceContainerHigh: g.header,
    surfaceContainerHighest: g.button,
    outline: g.border,
    outlineVariant: g.border,
  );
  if (oled && dark) {
    scheme = _oled(scheme);
    header = const Color(0xFF121212);
    sidebar = const Color(0xFF0A0A0A);
  }

  final border = BorderSide(color: g.border);
  RoundedRectangleBorder rounded(double r, {bool withBorder = false}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: withBorder ? border : BorderSide.none,
      );
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    rounded(spec.buttonRadius, withBorder: spec.borderedButtons),
  );
  final selectedRow = spec.accentSelection
      ? accent
      : (dark ? const Color(0x1AFFFFFF) : const Color(0x1A000006));
  final selectedText = spec.accentSelection ? onAccent : fg;

  return ThemeData(
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: spec.compact ? VisualDensity.compact : null,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: DividerThemeData(color: g.border, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(rounded(spec.buttonRadius)),
        side: WidgetStatePropertyAll(border),
        backgroundColor: WidgetStatePropertyAll(g.button),
        foregroundColor: WidgetStatePropertyAll(fg),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        foregroundColor: WidgetStatePropertyAll(accent),
      ),
    ),
    // Toolbar icon buttons are flat until hovered (GNOME, KDE, Mint…).
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(rounded(spec.buttonRadius)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? fg.withValues(alpha: 0.35)
              : s.contains(WidgetState.selected)
              ? accent
              : fg,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(rounded(spec.buttonRadius)),
        side: WidgetStatePropertyAll(border),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : g.button,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? onAccent : fg,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      thumbIcon: const WidgetStatePropertyAll(null),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent
            : (dark ? const Color(0xFF545458) : const Color(0xFFCDCDD0)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: dark ? const Color(0xFFE0E0E0) : Colors.white,
      inactiveTrackColor: g.border,
      trackHeight: 4,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: g.view,
      shape: rounded(spec.cardRadius, withBorder: true),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark
          ? Color.lerp(g.header, Colors.white, 0.03)
          : g.window,
      elevation: 8,
      shape: rounded(spec.dialogRadius, withBorder: spec.borderedButtons),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? g.header : g.view,
      elevation: 3,
      shape: rounded(spec.cardRadius, withBorder: true),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(dark ? g.header : g.view),
        shape: WidgetStatePropertyAll(
          rounded(spec.cardRadius, withBorder: true),
        ),
        elevation: const WidgetStatePropertyAll(3),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: rounded(spec.buttonRadius, withBorder: true),
      backgroundColor: g.button,
      selectedColor: spec.accentSelection
          ? accent.withValues(alpha: 0.25)
          : selectedRow,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F000006),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.buttonRadius),
        borderSide: spec.borderedButtons ? border : BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.buttonRadius),
        borderSide: spec.borderedButtons ? border : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(spec.buttonRadius),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: rounded(spec.buttonRadius),
      selectedColor: selectedText,
      selectedTileColor: selectedRow,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: sidebar,
      shape: const RoundedRectangleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded(spec.cardRadius),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(6),
      radius: Radius.circular(3),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: _tooltipWait,
      decoration: BoxDecoration(
        color: dark ? const Color(0xF0101012) : const Color(0xF0303034),
        borderRadius: BorderRadius.circular(spec.buttonRadius),
      ),
      // The tip is always dark here, so its text is always light (Flutter's
      // default text is dark in dark mode).
      textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
    ),
    extensions: [
      StyleExtras(
        headerBar: spec.headerBar,
        centeredTitle: spec.centeredTitle,
        headerColor: header,
        sidebarColor: sidebar,
        selectedRowColor: selectedRow,
        selectedRowText: selectedText,
        toolbarShape: rounded(spec.buttonRadius + 2, withBorder: true),
        toolbarElevation: 0,
        panelRadius: spec.cardRadius,
      ),
    ],
  );
}

/// Plain black-on-white / white-on-black colours, for the music sheet when
/// the theme should not colour it (the style's shapes and font are kept).
ColorScheme neutralScheme(Brightness brightness, {bool oled = false}) {
  var scheme = ColorScheme.fromSeed(
    seedColor: Colors.grey,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  if (brightness == Brightness.light) {
    scheme = scheme.copyWith(surfaceContainerLowest: Colors.white);
  } else if (oled) {
    scheme = _oled(scheme);
  }
  return scheme;
}
