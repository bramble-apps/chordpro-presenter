import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bilingual_projector/levels.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/tuner_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List sine(double amp, [int n = 4800]) => Float32List.fromList([
  for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * 440 * i / 48000),
]);

void main() {
  test('each method measures a sine wave as expected', () {
    final full = sine(1);
    expect(measureLevel(full, LevelMethod.dbfs), closeTo(0, 0.05));
    expect(measureLevel(full, LevelMethod.dbfsRms), closeTo(-3.01, 0.05));
    expect(measureLevel(full, LevelMethod.peak), closeTo(1, 0.001));
    expect(measureLevel(full, LevelMethod.rms), closeTo(0.7071, 0.001));
    expect(measureLevel(full, LevelMethod.avg), closeTo(2 / math.pi, 0.002));
    expect(measureLevel(full, LevelMethod.sqrtRms), closeTo(0.841, 0.002));
    final half = sine(0.5);
    expect(measureLevel(half, LevelMethod.dbfs), closeTo(-6.02, 0.05));
    expect(
      measureLevel(Float32List(100), LevelMethod.dbfs),
      lessThanOrEqualTo(-100),
    );
  });

  test('the meter: up at once, peak held, clip warning, scale', () {
    final m = LevelMeter(method: LevelMethod.dbfsRms)..on = true;
    m.add(sine(0.1)); // about −23 dB
    expect(m.value, closeTo(-23, 0.2));
    expect(m.level, closeTo((60 - 23) / 60, 0.01));
    expect(m.readout, '−23 dB');
    expect(m.clipping, isFalse);
    m.add(sine(1)); // loud, and touching full scale
    expect(m.level, greaterThan(0.9));
    expect(m.peak, m.level);
    expect(m.clipping, isTrue);
    // Quieter again: the bar falls gently, the peak stays up a while.
    final top = m.peak;
    m.add(sine(0.01));
    expect(m.level, lessThan(top));
    expect(m.peak, top);
    // Scale: twice the gain, 6 dB more.
    final s = LevelMeter(method: LevelMethod.dbfs, scale: 2)..on = true;
    s.add(sine(0.25));
    expect(s.value, closeTo(-6.02, 0.1));
  });

  testWidgets('the tuner panel\'s Levels tab', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PresenterModel.saveDelay = Duration.zero;
    final model = PresenterModel();
    final mic = StreamController<Float32List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 460,
            child: TunerPanel(model: model, debugSamples: mic.stream),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Tuner'), findsOneWidget);
    await tester.tap(find.text('Levels'));
    await tester.pump();
    mic.add(sine(0.04)); // −31 dBFS, −4 A-weighted at 440 Hz: 77 dB
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('77'), findsWidgets); // the big number (and peak)
    expect(find.text('Sound level (dB)'), findsWidgets); // the menu
    expect(find.text('OK'), findsOneWidget);
    // Calibrate 3 dB higher: 80, loud.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Read higher'));
    }
    await tester.pump();
    expect(model.settings.levelsCalibration, 3);
    expect(find.text('+3 dB'), findsOneWidget);
    mic.add(sine(0.04));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('80'), findsWidgets);
    expect(find.text('LOUD'), findsOneWidget);
    // Clipping: said plainly.
    mic.add(sine(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Too loud: clipping'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mic.close();
  });

  test('A-weighting follows the standard curve', () {
    // IEC 61672 table values (±0.5 dB; the top end bends a little at
    // 48 kHz).
    final a = AWeighting(48000);
    double db(double hz) => 20 * math.log(a.response(hz)) / math.ln10;
    for (final (hz, want) in const [
      (31.5, -39.4),
      (63.0, -26.2),
      (125.0, -16.1),
      (250.0, -8.6),
      (1000.0, 0.0),
      (4000.0, 1.0),
    ]) {
      expect(db(hz), closeTo(want, 0.5), reason: '$hz Hz');
    }
    // Rumble counts for far less than a voice: 50 Hz vs 1 kHz.
    final m = LevelMeter()..on = true;
    Float32List tone(double hz) => Float32List.fromList([
      for (var i = 0; i < 9600; i++)
        0.1 * math.sin(2 * math.pi * hz * i / 48000),
    ]);
    m.add(tone(1000));
    final voice = m.value;
    m.stopListening();
    m.add(tone(50));
    expect(voice - m.value, closeTo(30.2, 1.5));
  });

  test('everyday sound level by default', () {
    // Positive decibels like Apple Watch unless chosen otherwise.
    expect(AppSettings().levelsMethod, LevelMethod.soundLevel.name);
    expect(LevelMethod.values.first, LevelMethod.soundLevel);
    final m = LevelMeter()..on = true;
    m.add(Float32List(512)); // silence
    expect(m.readout, '0 dB');
    m.add(sine(0.1));
    expect(m.value, greaterThan(0));
  });
}
