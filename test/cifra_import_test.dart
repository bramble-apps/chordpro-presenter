import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/song_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show pumpApp;

void main() {
  testWidgets('Cifra Club: opened in the in-app browser, imported from it', (
    tester,
  ) async {
    final oldFetch = fetchPage;
    String? opened;
    addTearDown(() {
      fetchPage = oldFetch;
      NativeIO.browseImport = null;
    });
    fetchPage = (url) async {
      if (url.contains('solr.sscdn.co')) {
        return '{"response":{"docs":[{"tipo":"2","txt":"Luz","art":"A",'
            '"dns":"a","url":"luz"}]}}';
      }
      throw SongSourceError('Offline');
    };
    // The person taps Import on the page: what the page script reads.
    NativeIO.browseImport = (context, url, script) async {
      opened = url;
      expect(script, cifraPageScript);
      return jsonEncode({
        'pre': '[Intro] G  D\nG          D\nLuz do mundo',
        'title': 'Luz',
        'artist': 'A',
        'key': 'G',
        'url': url,
      });
    };

    await pumpApp(tester);
    await tester.tap(find.byTooltip('New…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find songs online'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('find-songs')), 'luz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    // Not "opens in your browser": it opens here.
    expect(find.textContaining('opens in your browser'), findsNothing);
    await tester.tap(find.text('Luz'));
    await tester.pumpAndSettle();
    expect(opened, 'https://www.cifraclub.com/a/luz/');
    final text = tester.widget<SelectableText>(
      find.byKey(const Key('found-song-text')),
    );
    expect(text.data, 'Intro:\n[G] [D]\n[G]Luz do mund[D]o');
    expect(find.text('Add to library'), findsOneWidget);
  });
}
