import 'package:bilingual_projector/widgets/chord_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // On the web the font for letters the app's fonts lack (styled 𝘐𝘵𝘢𝘭𝘪𝘤𝘴
  // in chords) arrives after the first layout: the line must measure its
  // text again then, not keep the boxes it drew without the font.
  testWidgets('a chord line measures again when a font arrives', (
    tester,
  ) async {
    const pieces = [
      (chord: '(𝘛𝘰 𝘌𝘯𝘥𝘪𝘯𝘨)', lyric: '', runs: null),
      (chord: 'D ', lyric: 'name', runs: null),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ChordLine(
            pieces: pieces,
            chordStyle: TextStyle(fontSize: 14),
            lyricStyle: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderChordLine>(find.byType(ChordLine));
    final before = box.measures;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage({'type': 'fontsChange'}),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
    expect(box.measures, before + 1);
  });
}
