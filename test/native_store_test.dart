import 'dart:io';
import 'dart:typed_data';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('bp_store');
    NativeIO.dataDir = dir.path;
    PresenterModel.saveDelay = Duration.zero;
  });
  tearDown(() {
    NativeIO.dataDir = null;
    dir.deleteSync(recursive: true);
  });

  test('saved as files on the device, and read back', () async {
    final store = KeyValueStore();
    await store.write('bilingual_projector_state', '{"songs":[]}');
    await store.writeBytes('media:m1', Uint8List.fromList([1, 2, 3]));
    expect(
      await KeyValueStore().read('bilingual_projector_state'),
      '{"songs":[]}',
    );
    expect(await KeyValueStore().readBytes('media:m1'), [1, 2, 3]);
    expect(KeyValueStore.memory, isEmpty, reason: 'not in memory');
    expect(
      Directory('${dir.path}/store')
          .listSync()
          .map((f) => f.path.split('.').last)
          .toSet(),
      {'txt', 'bin'},
      reason: 'no temporary files left behind',
    );
    await store.delete('media:m1');
    expect(await store.readBytes('media:m1'), isNull);
  });

  test('the library survives a restart', () async {
    final first = PresenterModel();
    await first.load();
    first.addOrUpdate(Song(title: 'Kept', raw: 'Verse:\n[G]Hello'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final again = PresenterModel();
    await again.load();
    expect(again.songs.map((s) => s.title), contains('Kept'));
  });
}
