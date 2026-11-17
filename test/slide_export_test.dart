import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bilingual_projector/format.dart';
import 'package:bilingual_projector/projection.dart';
import 'package:bilingual_projector/slide_export.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1 × 1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
);

void main() {
  final slides = [
    SlideImage(_png, 'Amazing grace & "love"\nline two'),
    SlideImage(_png, 'Second <slide>'),
  ];

  test('pptx: the parts PowerPoint needs, one picture per slide', () {
    final bytes = slidesPptx(slides, width: 1920, height: 1080, title: 'T');
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    for (final part in [
      '[Content_Types].xml',
      '_rels/.rels',
      'ppt/presentation.xml',
      'ppt/slideMasters/slideMaster1.xml',
      'ppt/slideLayouts/slideLayout1.xml',
      'ppt/theme/theme1.xml',
      'ppt/slides/slide1.xml',
      'ppt/slides/slide2.xml',
      'ppt/media/image2.png',
    ]) {
      expect(names, contains(part));
    }
    final slide = utf8.decode(
      zip.findFile('ppt/slides/slide1.xml')!.content as List<int>,
    );
    expect(slide, contains('descr="Amazing grace &amp; &quot;love&quot;'));
    expect(
      utf8.decode(zip.findFile('ppt/presentation.xml')!.content as List<int>),
      contains('<p:sldSz cx="12192000" cy="6858000"/>'),
    );
    final out = Platform.environment['SLIDE_EXPORT_OUT'];
    if (out != null) {
      File('$out/sample.pptx').writeAsBytesSync(bytes);
    }
  });

  test('pdf: a page per slide', () async {
    final bytes = await slidesPdf(slides, width: 1920, height: 1080);
    final text = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
    final out = Platform.environment['SLIDE_EXPORT_OUT'];
    if (out != null) File('$out/sample.pdf').writeAsBytesSync(bytes);
  });

  test('html: every slide inside, keys to move', () {
    final html = slidesHtml(slides, title: 'My <set>');
    expect('data:image/png;base64,'.allMatches(html).length, 2);
    expect(html, contains('<title>My &lt;set&gt;</title>'));
    expect(html, contains('alt="Second &lt;slide&gt;"'));
    expect(html, contains('ArrowRight'));
    final out = Platform.environment['SLIDE_EXPORT_OUT'];
    if (out != null) File('$out/sample.html').writeAsStringSync(html);
  });

  test('editable pptx: real text in the chosen font, the projector look', () {
    String slideXml(List<int> bytes, int n) => utf8.decode(
      ZipDecoder()
              .decodeBytes(bytes)
              .findFile('ppt/slides/slide$n.xml')!
              .content
          as List<int>,
    );
    final texts = [
      'Morning light & hill\nOn the hill',
      'We sing tonight\u2029Nous chantons ce soir',
    ];
    final stacked = slidesPptxText(
      texts,
      width: 1920,
      height: 1080,
      look: TextSlideLook(
        linked: LinkedStyle()
          ..italic = true
          ..dim = true,
        font: 'Georgia',
        color: const Color(0xFFFFEE00),
        caps: true,
      ),
    );
    final one = slideXml(stacked, 1);
    expect(one, contains('<a:t>Morning light &amp; hill</a:t>'));
    expect(one, contains('<a:t>On the hill</a:t>'));
    expect(one, contains('<a:latin typeface="Georgia"/>'));
    expect(one, contains('val="FFEE00"'));
    expect(one, contains('cap="all"'));
    expect(one, contains('<a:normAutofit/>'), reason: 'shrinks on overflow');
    final two = slideXml(stacked, 2);
    expect(RegExp('<p:sp>').allMatches(two).length, 1, reason: 'one box');
    expect(two, contains('i="1"'), reason: 'translation italic');
    expect(two, contains('<a:alpha val="55000"/>'), reason: 'dimmed');

    // Side by side with a background picture and dimming.
    final beside = slidesPptxText(
      texts,
      width: 1920,
      height: 1080,
      look: TextSlideLook(
        linked: LinkedStyle()..sideBySide = true,
        backgroundImage: _png,
        dim: 0.4,
      ),
    );
    final zip = ZipDecoder().decodeBytes(beside);
    expect(zip.findFile('ppt/media/background.png'), isNotNull);
    final b2 = slideXml(beside, 2);
    expect(b2, contains('name="Translation 1"'));
    expect(b2, contains('<a:alpha val="40000"/>'), reason: 'dim layer');
    expect(b2, contains('r:embed="rId2"'), reason: 'background picture');
    final out = Platform.environment['SLIDE_EXPORT_OUT'];
    if (out != null) {
      File('$out/editable.pptx').writeAsBytesSync(stacked);
      File('$out/editable2.pptx').writeAsBytesSync(beside);
    }
  });

  test('pptx: fades between slides; blank and title slides', () {
    String slideXml(List<int> bytes, int n) => utf8.decode(
      ZipDecoder()
              .decodeBytes(bytes)
              .findFile('ppt/slides/slide$n.xml')!
              .content
          as List<int>,
    );
    final deck = slidesPptxText(
      [blankSlide, titleSlide('Hosanna', 'Brooke Ligertwood'), 'Praise'],
      width: 1920,
      height: 1080,
      look: TextSlideLook(linked: LinkedStyle()),
      fade: 0.5,
    );
    for (var i = 1; i <= 3; i++) {
      final xml = slideXml(deck, i);
      expect(xml, contains('<p:fade/>'));
      expect(xml, contains('p14:dur="500"'));
    }
    expect(slideXml(deck, 1), isNot(contains('<p:txBody>')), reason: 'blank');
    final title = slideXml(deck, 2);
    expect(title, contains('<a:t>Hosanna</a:t>'));
    expect(title, contains('<a:t>Brooke Ligertwood</a:t>'));
    expect(title, contains('anchor="ctr"'));
    // No fade unless asked.
    final plain = slidesPptxText(
      ['Praise'],
      width: 1920,
      height: 1080,
      look: TextSlideLook(linked: LinkedStyle()),
    );
    expect(slideXml(plain, 1), isNot(contains('p:transition')));
    final out = Platform.environment['SLIDE_EXPORT_OUT'];
    if (out != null) File('$out/fade.pptx').writeAsBytesSync(deck);
  });
}
