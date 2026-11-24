import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browser.dart';
import 'fonts.dart';
import 'screens/operator_screen.dart';
import 'screens/projector_screen.dart';
import 'cloud_sync.dart';
import 'openchords.dart';
import 'state.dart';
import 'widgets/sync_dialog.dart';
import 'eink.dart';
import 'themes.dart';
import 'native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web / Linux app: no browser right-click menu over selectable text. It
  // needs an invisible page element over each chord sheet, and the ones of
  // the songs lined up beside it (for swiping) lay over the Format pane,
  // taking its scrolling. Selection keeps Flutter's own copy menu.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  // The chord shapes come from chords-db (MIT licence).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'chords-db',
    ], await rootBundle.loadString('assets/chords/LICENSE-chords-db.txt'));
  });
  // The icons: Bramble Icons, made from Phosphor and Tabler (MIT licences).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Phosphor Icons',
    ], await rootBundle.loadString('assets/fonts/LICENSE-phosphor.txt'));
    yield LicenseEntryWithLineBreaks([
      'Tabler Icons',
    ], await rootBundle.loadString('assets/fonts/LICENSE-tabler.txt'));
  });
  // The interface (Material style): Sfera, from Inter (SIL Open Font Licence).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Sfera (Inter)',
    ], await rootBundle.loadString('assets/fonts/LICENSE-sfera.txt'));
  });
  // The tempo, time signature and key: Abril Fatface (SIL Open Font Licence).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Abril Fatface',
    ], await rootBundle.loadString('assets/fonts/LICENSE-abrilfatface.txt'));
  });
  // Desktop app: the projector window runs its own app.
  if (!kIsWeb && await runDesktopProjector()) return;
  // Installed apps: save on the device, system pickers and sharing.
  if (!kIsWeb) await setUpNativeIO();
  // Phones: the app runs under the status and navigation bars (edge to
  // edge); the main screen keeps its controls clear of them.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  if (currentView() == 'projector') {
    runApp(
      MaterialApp(
        title: 'ChordPro Presenter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: ProjectorScreen(model: ProjectorModel()),
      ),
    );
    return;
  }

  // Opened at chordpro.local:8080/edit: editing the library of the app
  // running on that computer.
  final model = PresenterModel()..remoteEdit = currentView() == 'edit';
  await model.load();
  final s = model.settings;
  await Future.wait([
    for (final id in {
      s.sheetFont,
      s.chordFont,
      s.projectorFont,
      ?s.uiStyle.fontId,
    })
      FontService.ensure(id),
  ]);
  if (!kIsWeb) await setUpDesktopOperator(model);
  // Backups and sync, as set up in ☰ → Backup & sync.
  cloudSync = CloudSync(model)..start();
  // Shared setlists and folders, as set up in Settings → OpenChords.
  OpenChordsAutoSync(model).start();
  runApp(BilingualProjectorApp(model: model));
}

/// The projector on an external display (monitor, TV or projector on
/// USB-C / HDMI, or a screen the phone casts to): Android starts it here,
/// alongside the operator app.
@pragma('vm:entry-point')
Future<void> secondaryDisplayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpProjectorIO();
  // (A screen kept on the stage view while another shows the lyrics.)
  final model = ProjectorModel(
    pinned: ProjectorModel.pinnedViewNamed(await externalProjectorShow()),
  );
  runApp(
    MaterialApp(
      title: 'ChordPro Presenter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      // Whatever route the display was opened with, show the projector.
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => externalProjector(model, ProjectorScreen(model: model)),
      ),
    ),
  );
}

/// The operator app, re-themed whenever the settings change.
class BilingualProjectorApp extends StatelessWidget {
  /// The arrow keys move between slides (see OperatorScreen); they don't
  /// hop the keyboard focus between buttons and list rows (Flutter's
  /// default on desktop). Text fields keep theirs. (Made once.)
  static final _shortcuts = {
    for (final e in WidgetsApp.defaultShortcuts.entries)
      if (e.value is! DirectionalFocusIntent) e.key: e.value,
  };

  final PresenterModel model;
  final Widget? home;
  const BilingualProjectorApp({super.key, required this.model, this.home});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final s = model.settings;
        setEink(s.eink);
        final theme = themeById(s.themeId);
        final styleFont = s.uiStyle.fontId;
        if (styleFont != null) FontService.ensure(styleFont);
        final family = styleFont == null
            ? null
            : FontOption(styleFont, '').family;
        return MaterialApp(
          // The arrow keys move between slides (see OperatorScreen); they
          // don't hop the keyboard focus between buttons and list rows
          // (Flutter's default on desktop). Text fields keep theirs.
          shortcuts: _shortcuts,
          title: 'ChordPro Presenter',
          debugShowCheckedModeBanner: false,
          themeMode: switch (s.mode) {
            ThemeModeSetting.system => ThemeMode.system,
            ThemeModeSetting.light => ThemeMode.light,
            ThemeModeSetting.dark => ThemeMode.dark,
          },
          // Same settings → the very same theme objects. A freshly built
          // (unequal) theme would make Flutter animate a "theme change",
          // rebuilding the whole app every frame for a moment.
          theme: _cachedTheme(
            'light|${s.themeId}|${s.uiStyle}|$family|${s.eink}',
            () => _ink(
              s.eink,
              buildTheme(
                theme,
                Brightness.light,
                // E-ink: one look, Breeze's flat bars (the chosen style's
                // font still applies).
                style: s.eink ? UiStyle.breeze : s.uiStyle,
                fontFamily: family,
              ),
            ),
          ),
          darkTheme: _cachedTheme(
            'dark|${s.themeId}|${s.uiStyle}|$family|${s.oled}|${s.eink}',
            () => _ink(
              s.eink,
              buildTheme(
                theme,
                Brightness.dark,
                oled: s.oled,
                // E-ink: one look, Breeze's flat bars (the chosen style's
                // font still applies).
                style: s.eink ? UiStyle.breeze : s.uiStyle,
                fontFamily: family,
              ),
            ),
          ),
          // E-ink: changes appear at once.
          themeAnimationDuration: s.eink
              ? Duration.zero
              : kThemeAnimationDuration,
          home: home ?? OperatorScreen(model: model),
          // Desktop app: rounded bottom corners on the main window.
          builder: (context, child) {
            child ??= const SizedBox();
            if (s.eink) {
              // No animations (widgets that honour it) and page arrows
              // instead of smooth scrolling.
              child = MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: ScrollConfiguration(
                  behavior: const EinkScrollBehavior(),
                  child: child,
                ),
              );
            }
            return kIsWeb ? child : DesktopWindowFrame(child: child);
          },
        );
      },
    );
  }
}

ThemeData _ink(bool eink, ThemeData t) => eink ? einkTheme(t) : t;

final Map<String, ThemeData> _themes = {};

ThemeData _cachedTheme(String key, ThemeData Function() build) {
  final hit = _themes[key];
  if (hit != null) return hit;
  if (_themes.length > 8) _themes.clear();
  return _themes[key] = build();
}
