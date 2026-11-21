import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilingual_projector/dynamic_bg.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/main.dart';
import 'package:bilingual_projector/screens/operator_screen.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/dynamic_background.dart';
import 'package:bilingual_projector/widgets/format_pane.dart';
import 'package:bilingual_projector/widgets/projection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectionData _data(ProjectionSettings s, {bool preview = false}) =>
    ProjectionData(
      settings: s,
      slides: const ['Amazing grace'],
      selection: ValueNotifier(0),
      transitionSeconds: 0,
      projectorFont: 'default',
      blackout: false,
      preview: preview,
    );

Widget _screen(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 640, height: 360, child: child)),
);

/// Real time passes (the drawing thread and picture decoding need it).
Future<void> _wait(WidgetTester tester, [int ms = 150]) async {
  await tester.runAsync(
    () => Future<void>.delayed(Duration(milliseconds: ms)),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  test('all 18 Keydeck presets, in its order', () {
    expect(dynamicPresets.map((p) => p.name), [
      'Rainbow',
      'Ocean Floor',
      'Neptune',
      'Snow Day',
      'Neon Splash',
      'Jade Cliffs',
      'Stormy Seas',
      'Poolside',
      'Nebula',
      'Black Smoke',
      'Lime Juice',
      'Solar Flare',
      'Sunset Dunes',
      'Morning Surf',
      'Lava Lamp',
      'Flamingo',
      'Cool Breeze',
      'Purple Vista',
    ]);
    expect(dynamicPresets.first.colors.length, 6);
    expect(dynamicPresets.map((p) => p.family).toSet(), {
      'KNGradientLinearBase',
      'KNGradientTerrainBase',
      'KNGradientTerrainFlyover',
      'KNGradientDiffusionBase',
      'KNWavesBase',
      'KNWavesSymmetrical',
      'KNGraphicSpheresBase',
    });
  });

  test("each kind has Keydeck's sliders", () {
    String list(String family) => dynamicControls(family)
        .map((c) => '${c.label}:${c.prop}:${c.min}:${c.max}:${c.decimals}')
        .join(' ');
    expect(
      list('KNGradientLinearBase'),
      'Angle:angle:0.0:360.0:1 Scale:scale:0.1:5.0:2 Speed:speed:0.0:100.0:2',
    );
    expect(
      list('KNGradientTerrainBase'),
      'Speed:noise_speed:0.0:100.0:2 Height:noise_amplitude:0.0:10.0:2 '
      'Peaks:noise_scale_horizontal:0.01:10.0:2',
    );
    expect(
      list('KNGradientTerrainFlyover'),
      'Movement:noise_movement:-100.0:100.0:0 '
      'Height:noise_amplitude:0.0:10.0:2 '
      'Peaks:noise_scale_horizontal:0.01:10.0:2',
    );
    expect(
      list('KNGradientDiffusionBase'),
      'Speed:noise_speed:0.0:5.0:2 '
      'Complexity:noise_octaves_iterations:1.0:8.0:0 '
      'Frequency:scale:0.1:5.0:2',
    );
    for (final f in ['KNWavesBase', 'KNWavesSymmetrical']) {
      expect(
        list(f),
        'Speed:speed:0.0:100.0:0 Amplitude:amplitude:0.0:10.0:2 '
        'Wavelength:scale:0.1:10.0:2 Focus:blur:0.0:10.0:2',
      );
    }
    expect(
      list('KNGraphicSpheresBase'),
      'Speed:speed:0.0:100.0:0 Complexity:noise_scale:0.0:10.0:2 '
      'Pattern:offset:0.0:10.0:2',
    );
    const angle = DynamicControl('Angle', 'angle', 0, 360, 1, '°');
    expect(angle.format(33.7000007), '33.7°');
    expect(angle.format(90), '90°');
    expect(angle.step, 0.1);
  });

  test('a preset and its changes survive a JSON round trip', () {
    final bg = DynamicBg(DynamicBg.presetNamed('Stormy Seas'));
    expect(bg.isPreset, isTrue);
    expect(bg.toJson(), {'preset': 'Stormy Seas'});
    expect(bg.hasBackground, isTrue);
    expect(bg.blendMode, 'Hard Light');

    bg
      ..setNum('speed', 12)
      ..setColor(1, const Color(0xFF336699))
      ..setBackground(const Color(0xFF101820));
    final back = DynamicBg.fromJson(jsonDecode(jsonEncode(bg.toJson())));
    expect(back.toJson(), bg.toJson());
    expect(back.name, 'Stormy Seas');
    expect(back.number('speed', 0), 12);
    expect(back.colors[1].color, const Color(0xFF336699));
    // (untouched colours stay the preset's exact ones)
    expect(back.colors[0].color, bg.preset.colors[0].color);
    expect(back.background, const Color(0xFF101820));
    expect(back.looksSame(bg), isTrue);
    expect(back.looksSame(DynamicBg(bg.preset)), isFalse);

    // Unknown or missing: the first preset.
    expect(DynamicBg.fromJson({'preset': 'Nope'}).name, 'Rainbow');
    expect(DynamicBg.fromJson(null).name, 'Rainbow');
  });

  test('Peaks sets both directions; whole-number sliders stay whole', () {
    final bg = DynamicBg(DynamicBg.presetNamed('Ocean Floor'))
      ..setNum('noise_scale_horizontal', 3.5);
    expect(bg.number('noise_scale_vertical', 0), 3.5);
    final d = DynamicBg(DynamicBg.presetNamed('Neptune'))
      ..setNum('noise_octaves_iterations', 3.4);
    expect(d.number('noise_octaves_iterations', 0), 3);
    // Sliders stay inside their range.
    final c = dynamicControls(d.family).first;
    d.setValue(c, 99);
    expect(d.value(c), c.max);
  });

  test('projection settings keep the dynamic background', () {
    final p = ProjectionSettings()
      ..bgType = BackgroundType.dynamic
      ..bgDynamic = (DynamicBg(DynamicBg.presetNamed('Lava Lamp'))
        ..setNum('speed', 80)
        ..setColor(0, const Color(0xFFAA0000)))
      ..bgDynamicPreview = false;
    final q = ProjectionSettings.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
    );
    expect(q.toJson(), p.toJson());
    expect(q.bgType, BackgroundType.dynamic);
    expect(q.bgDynamic.name, 'Lava Lamp');
    expect(q.bgDynamic.number('speed', 0), 80);
    expect(q.bgDynamic.colors[0].color, const Color(0xFFAA0000));
    expect(q.bgDynamicPreview, isFalse);

    // Settings saved before dynamic backgrounds existed.
    final old = ProjectionSettings.fromJson({'bgType': 'color'});
    expect(old.bgType, BackgroundType.color);
    expect(old.bgDynamic.name, 'Rainbow');
    expect(old.bgDynamicPreview, isTrue);
  });

  // Frames drawn by Keydeck's own renderer (kn_render::motion::render, 64×36)
  // for every preset at 0 s, 7.3 s and 4000 s: this port must draw the same.
  // (Keydeck works in 32-bit floats and this in 64-bit, so a channel may
  // round to the next step up or down.)
  test("frames match Keydeck's renderer", () {
    for (final preset in dynamicPresets) {
      for (final (label, t) in [('0', 0.0), ('7.3', 7.3), ('4000', 4000.0)]) {
        final file = File(
          'test/fixtures/dynamic_bg/'
          '${preset.name.replaceAll(' ', '-')}@$label.rgba',
        );
        final want = file.readAsBytesSync();
        // Keydeck's clock is a 32-bit float.
        final t32 = (Float32List(1)..[0] = t)[0];
        final got = DynamicRenderer.frame(DynamicBg(preset), t32, 64, 36);
        expect(got.length, want.length);
        var worst = 0, off = 0;
        for (var i = 0; i < got.length; i++) {
          final d = (got[i] - want[i]).abs();
          if (d > worst) worst = d;
          if (d > 1) off++;
        }
        expect(
          off / got.length,
          lessThan(0.002),
          reason: '${preset.name} at $label s: $off values differ, worst $worst',
        );
        expect(worst, lessThan(12), reason: '${preset.name} at $label s');
      }
    }
  });

  test('drawing a frame in strips gives the same picture', () {
    final bg = DynamicBg(DynamicBg.presetNamed('Jade Cliffs'));
    final whole = DynamicRenderer.frame(bg, 3, 48, 27);
    final r = DynamicRenderer(bg, 48, 27)..begin(3);
    final strips = Uint8List(48 * 27 * 4);
    for (var y = 0; y < 27; y += 5) {
      r.rows(y, (y + 5).clamp(0, 27), strips);
    }
    expect(strips, whole);
  });

  testWidgets('the projector plays the dynamic background', (tester) async {
    final s = ProjectionSettings()..bgType = BackgroundType.dynamic;
    await tester.pumpWidget(_screen(ProjectorDisplay(data: _data(s))));
    final bg = tester.widget<DynamicBackground>(find.byType(DynamicBackground));
    expect(bg.animate, isTrue);
    expect(bg.pixels, 480);
    final before = dynamicFramesShown;
    for (var i = 0; i < 12 && dynamicFramesShown < before + 2; i++) {
      await _wait(tester);
    }
    // Frame after frame arrives.
    expect(dynamicFramesShown, greaterThanOrEqualTo(before + 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slide tiles and pictures show its still', (tester) async {
    final s = ProjectionSettings()
      ..bgType = BackgroundType.dynamic
      ..bgDynamic = DynamicBg(DynamicBg.presetNamed('Nebula'));
    for (final display in [
      ProjectorDisplay(data: _data(s), tile: true),
      ProjectorDisplay(data: _data(s), picture: true),
    ]) {
      final before = dynamicFramesShown;
      await tester.pumpWidget(_screen(display));
      final bg = tester.widget<DynamicBackground>(
        find.byType(DynamicBackground),
      );
      expect(bg.animate, isFalse);
      for (var i = 0; i < 20 && dynamicFramesShown == before; i++) {
        await _wait(tester, 50);
      }
      expect(dynamicFramesShown, before + 1);
      // Nothing keeps moving.
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets("the operator's copy moves only with Preview Motion on", (
    tester,
  ) async {
    final s = ProjectionSettings()..bgType = BackgroundType.dynamic;
    DynamicBackground shown() =>
        tester.widget<DynamicBackground>(find.byType(DynamicBackground));
    await tester.pumpWidget(
      _screen(ProjectorDisplay(data: _data(s, preview: true))),
    );
    expect(shown().animate, isTrue);
    expect(shown().pixels, 320);
    s.bgDynamicPreview = false;
    await tester.pumpWidget(
      _screen(ProjectorDisplay(data: _data(s, preview: true))),
    );
    expect(shown().animate, isFalse);
    // The projector itself always plays it.
    await tester.pumpWidget(_screen(ProjectorDisplay(data: _data(s))));
    expect(shown().animate, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Format > Projection: pick a dynamic background and adjust it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    final m = PresenterModel();
    await m.load();
    // (A still preview, so the test can wait for the screen to settle.)
    m.updateProjection((p) => p.bgDynamicPreview = false);
    await tester.pumpWidget(
      BilingualProjectorApp(
        model: m,
        home: OperatorScreen(model: m),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show Format'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projection').last);
    await tester.pumpAndSettle();
    final pane = find
        .descendant(
          of: find.byType(FormatPane),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> show(Finder f) async {
      await tester.scrollUntilVisible(f, 120, scrollable: pane);
      await tester.pumpAndSettle();
    }

    await show(find.byTooltip('Dynamic'));
    await tester.tap(find.byTooltip('Dynamic'));
    await tester.pumpAndSettle();
    expect(m.projection.bgType, BackgroundType.dynamic);
    expect(m.projection.bgDynamic.name, 'Rainbow');

    // Six presets to a page; Rainbow's sliders.
    await show(find.text('Speed'));
    expect(find.byTooltip('Rainbow'), findsOneWidget);
    expect(find.byTooltip('Jade Cliffs'), findsOneWidget);
    expect(find.byTooltip('Stormy Seas'), findsNothing);
    for (final label in ['Preview Motion', 'Colours', 'Angle', 'Scale']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Background Colour'), findsNothing);
    expect(find.text('33.7\u00b0'), findsOneWidget);

    // The next page: a wave, with its own sliders and a background colour.
    await show(find.byTooltip('More backgrounds'));
    await tester.tap(find.byTooltip('More backgrounds'));
    await tester.pumpAndSettle();
    await show(find.byTooltip('Stormy Seas'));
    await tester.tap(find.byTooltip('Stormy Seas'));
    await tester.pumpAndSettle();
    expect(m.projection.bgDynamic.name, 'Stormy Seas');
    await show(find.text('Focus'));
    for (final label in ['Amplitude', 'Wavelength', 'Background Colour']) {
      expect(find.text(label), findsOneWidget);
    }

    // + on Speed (whole steps), saved with the settings.
    final speed = m.projection.bgDynamic.number('speed', 0);
    final more = find.descendant(
      of: find.ancestor(of: find.text('Speed'), matching: find.byType(Row)).first,
      matching: find.byTooltip('More'),
    );
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(m.projection.bgDynamic.number('speed', 0), speed + 1);
    expect(m.projection.toJson()['bgDynamic'], {
      'preset': 'Stormy Seas',
      'nums': {'speed': speed + 1},
    });

    // Picking the preset again puts it back as it comes.
    await show(find.byTooltip('Stormy Seas'));
    await tester.tap(find.byTooltip('Stormy Seas'));
    await tester.pumpAndSettle();
    expect(m.projection.bgDynamic.isPreset, isTrue);
  });
}
