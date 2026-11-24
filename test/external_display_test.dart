import 'dart:convert';

import 'package:bilingual_projector/browser.dart';
import 'package:bilingual_projector/native_display.dart';
import 'package:bilingual_projector/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bp/displays');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'list' => [
          {
            'id': 2,
            'name': 'HDMI Screen',
            'width': 1920,
            'height': 1080,
            'presentation': true,
          },
          {
            'id': 3,
            'name': 'Stage Monitor',
            'width': 1920,
            'height': 1080,
            'presentation': true,
          },
        ],
        'show' => 'screen',
        _ => null,
      };
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    NativeIO.onSend = null;
  });

  List<Map<String, dynamic>> sent() => [
    for (final c in calls)
      if (c.method == 'send')
        jsonDecode(c.arguments as String) as Map<String, dynamic>,
  ];

  Future<void> fromAndroid(String method, [Object? args]) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('lists screens with their id and name (no "null")', () async {
    final screens = await NativeDisplays.list();
    expect(screens.first.id, 2);
    expect(screens.first.name, 'HDMI Screen');
    expect(screens.first.plain, isTrue);
  });

  test('show sends the slides, and the projector can talk back', () async {
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await model.load();
    final screen = (await NativeDisplays.list()).first;

    await NativeDisplays.show(screen, model);
    expect(calls.where((c) => c.method == 'show').single.arguments, {
      'id': 2,
      'show': null,
    });
    expect(NativeDisplays.showing.value, {2: ''});
    expect(model.casting, isTrue);
    expect(sent().map((m) => m['type']), containsAll(['start', 'state']));

    // The projector says hello: the operator answers with the state and
    // knows a projector is showing.
    calls.clear();
    await fromAndroid('fromProjector', jsonEncode({'type': 'hello'}));
    await Future<void>.delayed(Duration.zero);
    expect(sent().map((m) => m['type']), contains('state'));
    expect(model.projectorActive, isTrue);

    // Closed on the desktop / unplugged: the operator stops casting.
    await fromAndroid('projectorClosed', 2);
    expect(NativeDisplays.showing.value, isEmpty);
    expect(model.casting, isFalse);
  });

  // Lyrics on the projector, the band's chords on a second screen.
  test('two screens at once, one kept on the stage view', () async {
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await model.load();
    final screens = await NativeDisplays.list();

    await NativeDisplays.show(screens[0], model);
    await NativeDisplays.show(screens[1], model, view: 'stage');
    expect(calls.where((c) => c.method == 'show').last.arguments, {
      'id': 3,
      'show': 'stage',
    });
    expect(NativeDisplays.showing.value, {2: '', 3: 'stage'});

    // One unplugged: the other goes on, and so does projecting.
    await fromAndroid('projectorClosed', 3);
    expect(NativeDisplays.showing.value, {2: ''});
    expect(model.casting, isTrue);
    expect(NativeIO.onSend, isNotNull);

    // Stopping one screen leaves the others alone.
    await NativeDisplays.show(screens[1], model, view: 'stage');
    calls.clear();
    await NativeDisplays.hide(2);
    expect(calls.single.arguments, {'id': 2});
    expect(NativeDisplays.showing.value, {3: 'stage'});
    await NativeDisplays.hide();
    expect(NativeDisplays.showing.value, isEmpty);
    expect(NativeIO.onSend, isNull);
  });
}
