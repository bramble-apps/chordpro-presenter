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
    expect(screens.single.id, 2);
    expect(screens.single.name, 'HDMI Screen');
    expect(screens.single.plain, isTrue);
  });

  test('show sends the slides, and the projector can talk back', () async {
    KeyValueStore.memory.clear();
    final model = PresenterModel();
    await model.load();
    final screen = (await NativeDisplays.list()).single;

    await NativeDisplays.show(screen, model);
    expect(calls.where((c) => c.method == 'show').single.arguments, {'id': 2});
    expect(NativeDisplays.showing.value?.id, 2);
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
    await fromAndroid('projectorClosed');
    expect(NativeDisplays.showing.value, isNull);
    expect(model.casting, isFalse);
  });
}
