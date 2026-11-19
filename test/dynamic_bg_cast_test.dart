import 'dart:convert';
import 'dart:io';

import 'package:bilingual_projector/dynamic_bg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TV draws the animated wallpapers itself (cast_receiver/public/
/// dynamic_bg.js): its frames must match the app's.
void main() {
  test('the TV draws the same wallpaper frames as the app', () async {
    final node = await Process.run('node', [
      '--version',
    ]).then((r) => r.exitCode == 0, onError: (_) => false);
    if (!node) {
      markTestSkipped('node is not installed');
      return;
    }
    const w = 48, h = 27;
    final frames = [
      for (final p in dynamicPresets)
        for (final t in [0.0, 7.3, 61.25])
          {
            'name': p.name,
            'spec': DynamicRenderer.castSpec(DynamicBg(p)),
            't': t,
            'w': w,
            'h': h,
            'rgba': DynamicRenderer.frame(DynamicBg(p), t, w, h),
          },
    ];
    final proc = await Process.start('node', ['tool/dynamic_bg_check.js']);
    proc.stdin.write(jsonEncode(frames));
    await proc.stdin.close();
    final out = await proc.stdout.transform(utf8.decoder).join();
    final err = await proc.stderr.transform(utf8.decoder).join();
    expect(err, isEmpty);
    final results = (jsonDecode(out) as List).cast<Map>();
    expect(results.length, frames.length);
    for (final r in results) {
      // (Sine and power can differ in their last digit between the two:
      // a step of 1 in a colour at most, on a few pixels.)
      expect(
        r['max'] as int,
        lessThanOrEqualTo(1),
        reason: '${r['name']} at ${r['t']} s differs by ${r['max']}',
      );
    }
  });
}
