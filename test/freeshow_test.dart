import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/chordpro.dart';
import 'package:bilingual_projector/export.dart';
import 'package:bilingual_projector/freeshow.dart';
import 'package:bilingual_projector/state.dart';
import 'package:bilingual_projector/translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PresenterModel model;
  setUp(() async {
    KeyValueStore.memory.clear();
    PresenterModel.saveDelay = Duration.zero;
    model = PresenterModel();
    await model.load();
  });

  test('export: groups, layout order, chords, translations', () {
    const raw = '''Verse 1:
[G]Morning [D]light
On the hill

Chorus:
[C]We sing

Verse 1 (FR):
Lumière du matin
Sur la colline''';
    final song = Song(
      title: 'Morning',
      raw: raw,
      artist: 'Me',
      ccli: '123',
      structure: withTranslations(raw, const [
        StructureItem.section('Verse 1'),
        StructureItem.section('Chorus'),
        StructureItem.section('Verse 1'),
      ]),
    );
    model.addOrUpdate(song);
    final file = exportFreeShow(ExportSource.spec(model.specFor(song), model));
    final decoded = jsonDecode(file) as List;
    final show = decoded[1] as Map<String, dynamic>;
    expect(show['name'], 'Morning');
    expect(show['meta']['CCLI'], '123');
    final layout = (show['layouts'] as Map).values.first['slides'] as List;
    final slides = show['slides'] as Map;
    final groups = [for (final r in layout) slides[r['id']]['group']];
    expect(groups, ['Verse 1', 'Chorus', 'Verse 1'], reason: 'repeats kept');
    expect(layout[0]['id'], layout[2]['id'], reason: 'same slide reused');

    final verse = slides[layout[0]['id']] as Map;
    expect(verse['globalGroup'], 'verse');
    final items = verse['items'] as List;
    expect(items, hasLength(2), reason: 'lyrics + French');
    final line = (items[0]['lines'] as List).first as Map;
    expect(line['text'][0]['value'], 'Morning light');
    expect(
      [for (final c in line['chords']) (c['pos'], c['key'])],
      [(0, 'G'), (8, 'D')],
    );
    expect(items[1]['language'], 'fr');
    expect(items[1]['lines'][0]['text'][0]['value'], 'Lumière du matin');

    // And back: the same song.
    final back = importFreeShow(freeShowData(decoded)!);
    expect(back.title, 'Morning');
    expect(back.artist, 'Me');
    expect(
      ChordPro.sectionText(back.raw, 'Verse 1'),
      'Verse 1:\n[G]Morning [D]light\nOn the hill',
    );
    expect(ChordPro.sectionNames(back.raw), [
      'Verse 1',
      'Verse 1 (FR)',
      'Chorus',
    ]);
    expect(
      [for (final i in back.structure) (i.name, i.linked)],
      [
        ('Verse 1', true),
        ('Verse 1 (FR)', false),
        ('Chorus', false),
        ('Verse 1', true),
        ('Verse 1 (FR)', false),
      ],
    );
  });

  test('import: continuation slides, numbered duplicates, file name', () {
    final show = {
      'name': '',
      'settings': {'activeLayout': 'L'},
      'meta': {'author': 'Writer', 'key': 'D'},
      'slides': {
        'a': {
          'group': 'Verse',
          'items': [
            {
              'lines': [
                {
                  'text': [
                    {'value': 'One two'},
                  ],
                  'chords': [
                    {'pos': 4, 'key': 'A'},
                  ],
                },
              ],
            },
          ],
          'children': ['a2'],
        },
        'a2': {
          'group': null,
          'items': [
            {
              'lines': [
                {
                  'text': [
                    {'value': 'Three'},
                  ],
                },
              ],
            },
          ],
        },
        'b': {
          'group': 'Verse',
          'items': [
            {
              'lines': [
                {
                  'text': [
                    {'value': 'Other'},
                  ],
                },
              ],
            },
          ],
        },
        'x': {'group': 'Hidden', 'items': []},
      },
      'layouts': {
        'L': {
          'slides': [
            {'id': 'a'},
            {'id': 'b'},
            {'id': 'x', 'disabled': true},
            {'id': 'a'},
          ],
        },
      },
    };
    final song = importFreeShow(
      freeShowData(['id', show])!,
      fileName: 'Great Song.show',
    );
    expect(song.title, 'Great Song');
    expect(song.artist, 'Writer');
    expect(song.key?.name, 'D');
    expect(song.raw, 'Verse:\nOne [A]two\n\nThree\n\nVerse 2:\nOther');
    expect(
      [for (final i in song.structure) i.name],
      ['Verse', 'Verse 2', 'Verse'],
    );
  });

  test('a .show file imports through the library import', () {
    final n = model.importFiles([
      (
        'x.show',
        jsonEncode([
          'id',
          {
            'name': 'Imported',
            'slides': {
              's': {
                'group': 'Chorus',
                'items': [
                  {
                    'lines': [
                      {
                        'text': [
                          {'value': 'La la'},
                        ],
                      },
                    ],
                  },
                ],
              },
            },
            'layouts': {
              'L': {
                'slides': [
                  {'id': 's'},
                ],
              },
            },
          },
        ]),
      ),
    ]);
    expect(n.songs, 1);
    expect(model.currentSong!.title, 'Imported');
    expect(model.currentSong!.raw, 'Chorus:\nLa la');
  });
}
