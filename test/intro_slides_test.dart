import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/widgets/projection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PresenterModel> _model() async {
  KeyValueStore.memory.clear();
  PresenterModel.saveDelay = Duration.zero;
  final model = PresenterModel();
  await model.load();
  model.addOrUpdate(
    Song(
      id: 'h',
      title: 'Alléluia',
      artist: 'Someone',
      raw: 'Verse 1:\nAl[G]lé - lu - ia, a-men\n\nChorus:\nSing',
    ),
  );
  model.selectSong('h');
  return model;
}

Future<void> _show(WidgetTester tester, PresenterModel model, int i) async {
  model.goTo(i);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 1920,
        height: 1080,
        child: ProjectorDisplay(data: model.projectionData),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  test('a blank slide, then a title slide, before the lyrics', () async {
    final model = await _model();
    expect(model.slides.take(2), [
      blankSlide,
      titleSlide('Alléluia', 'Someone'),
    ]);
    expect(model.slidePartIndex.take(3), [-1, -1, 0]);
    expect(model.slides[2], 'Alléluia, a-men');

    model.updateProjection((p) => p.blankSlide = false);
    expect(isBlankSlide(model.slides.first), isFalse);
    model.updateProjection((p) => p.titleSlide = false);
    expect(model.slides.first, 'Alléluia, a-men');
    expect(model.slidePartIndex.first, 0);
  });

  testWidgets('title slide: title and artist; blank: no words or footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final model = await _model();
    model.updateProjection(
      (p) => p
        ..footer = true
        ..footerTitle = OnSlides.every,
    );

    // The title slide: title and artist, and no title in the footer.
    await _show(tester, model, 1);
    expect(find.text('Alléluia'), findsOneWidget);
    expect(find.text('Someone'), findsOneWidget);

    // A lyrics slide: the footer has the title.
    await _show(tester, model, 2);
    expect(find.text('Alléluia'), findsOneWidget); // the footer

    // The blank slide: nothing at all.
    await _show(tester, model, 0);
    expect(find.text('Alléluia'), findsNothing);
    expect(find.text('Someone'), findsNothing);
  });

  test('search ignores accents, chords, spaces and punctuation', () {
    final key = searchKey('Alléluia\nSomeone\n\nAl[G]lé - lu - ia, a-men!');
    expect(searchMatches(key, 'alleluia'), isTrue);
    expect(searchMatches(key, 'ALLÉLUIA'), isTrue);
    expect(searchMatches(key, 'al le lu ia'), isTrue);
    expect(searchMatches(key, 'amen'), isTrue);
    expect(searchMatches(key, 'someone alleluia'), isTrue); // any order
    expect(searchMatches(key, 'hosanna'), isFalse);
    // An accent written as a separate mark (e + ́).
    expect(searchMatches(searchKey('Alléluia'), 'alleluia'), isTrue);
  });
}
