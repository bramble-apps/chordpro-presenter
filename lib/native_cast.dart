// Chromecast for the installed apps: on Android Google's Cast SDK, on
// desktop our own Cast client (cast_v2.dart), finds the devices and starts
// ChordPro Presenter's own receiver on the TV (Cast app 7EAC743B, the page
// at https://chordpro-presenter.web.app, source in cast_receiver/). Each slide is drawn here exactly like the projector and
// sent over the Cast connection as a picture, in pieces; the TV crossfades
// to it.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import 'cast_v2.dart';
import 'cast_feeder.dart';
import 'state.dart';
import 'eink.dart';
import 'bramble_icons.dart';

/// A Chromecast / Google TV to cast to (from Google's Cast SDK on
/// Android, or our own discovery on desktop).
class CastChoice {
  final String id;
  final String name;
  final String? model;

  /// The SDK's device (Android) or a [CastTarget] (desktop).
  final Object device;

  const CastChoice(this.id, this.name, this.model, this.device);

  CastChoice.android(GoogleCastDevice d)
    : this(d.deviceID, d.friendlyName, d.modelName, d);

  CastChoice.desktop(CastTarget t) : this(t.id, t.name, t.model, t);
}

class NativeCast {
  NativeCast._();

  /// ChordPro Presenter's receiver, registered in the Google Cast console.
  static const appId = '7EAC743B';
  static const _namespace = 'urn:x-cast:com.chordpropresenter.slides';

  /// Casting is available (the Android and desktop apps).
  static bool ready = false;

  /// Desktop: our own Cast client.
  static CastDiscovery? _discovery;
  static CastSession? _session;
  static bool get _desktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// The device being cast to, or null.
  static final connected = ValueNotifier<String?>(null);

  static Future<void> init() async {
    if (_desktop) {
      _discovery = CastDiscovery();
      ready = true;
      return;
    }
    if (!Platform.isAndroid) return;
    await GoogleCastContext.instance.setSharedInstanceWithOptions(
      GoogleCastOptionsAndroid(appId: appId, stopCastingOnAppTerminated: true),
    );
    GoogleCastSessionManager.instance.currentSessionStream.listen((s) {
      if (s == null) connected.value = null;
    });
    ready = true;
  }

  /// Devices found so far, updated as more answer.
  static Stream<List<CastChoice>> get devices {
    final d = _discovery;
    if (d != null) {
      return d.devices.map((l) => [for (final t in l) CastChoice.desktop(t)]);
    }
    return GoogleCastDiscoveryManager.instance.devicesStream.map(
      (l) => [for (final g in l) CastChoice.android(g)],
    );
  }

  static List<CastChoice> get devicesNow => [
    for (final t in _discovery?.current ?? const <CastTarget>[])
      CastChoice.desktop(t),
  ];

  static void startDiscovery() {
    final d = _discovery;
    if (d != null) {
      d.start();
    } else {
      GoogleCastDiscoveryManager.instance.startDiscovery();
    }
  }

  static void stopDiscovery() => _discovery?.stop();

  /// Each step of the last connection, shown under the device list, so a
  /// cast that gets stuck says where.
  static final steps = ValueNotifier<List<String>>(const []);

  static void _step(String s) {
    debugPrint('Cast: $s');
    steps.value = [...steps.value, s];
  }

  static Future<T?> _try<T>(String what, Future<T> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _step('$what: no answer after 5 s');
    } catch (e) {
      _step('$what failed: $e');
    }
    return null;
  }

  static Future<void> connect(CastChoice choice) async {
    steps.value = const [];
    _step('Connecting to ${choice.name}…');
    if (choice.device case final CastTarget target) {
      // Desktop: our own Cast client.
      try {
        _session = await CastSession.start(
          target,
          appId,
          onClosed: () {
            _session = null;
            connected.value = null;
          },
        );
      } catch (e) {
        _step('The TV did not start ChordPro Presenter ($e)');
        throw StateError("The TV didn't start ChordPro Presenter");
      }
      _step('Connected to ${choice.name} ✓');
      caster.reset();
      connected.value = choice.name;
      return;
    }
    final device = choice.device as GoogleCastDevice;
    final sessions = GoogleCastSessionManager.instance;
    await sessions.startSessionWithDevice(device);
    // Wait for the TV to start ChordPro Presenter.
    for (var i = 0; i < 100; i++) {
      if (sessions.connectionState == GoogleCastConnectState.connected) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (sessions.connectionState != GoogleCastConnectState.connected) {
      _step(
        'The TV did not finish connecting '
        '(${sessions.connectionState.name})',
      );
      throw StateError("The TV didn't finish connecting");
    }
    final opened = await _try(
      'Opening the slide channel',
      () => sessions.addMessageChannel(_namespace),
    );
    _step(
      opened == true
          ? 'Connected to ${device.friendlyName} ✓'
          : 'Connected, but the slide channel did not open ($opened)',
    );
    // A fresh TV page has none of the slides yet.
    caster.reset();
    connected.value = device.friendlyName;
  }

  static Future<void> stop() async {
    if (connected.value == null) return;
    connected.value = null;
    final session = _session;
    if (session != null) {
      _session = null;
      await session.stop();
      return;
    }
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  /// Sends one JSON message to ChordPro Presenter on the TV.
  static Future<bool> _message(String json) async {
    final session = _session;
    if (session != null) return session.send(_namespace, json);
    return GoogleCastSessionManager.instance.sendMessage(_namespace, json);
  }

  /// Sends the slides to the TV (pre-loaded pictures; see cast_feeder.dart).
  static final caster = SlideCaster(
    send: _message,
    connected: connected,
    onStep: _step,
  );
}

/// "Chromecast & Google TV" in the cast dialog of the Android app.
class NativeCastSection extends StatefulWidget {
  final PresenterModel model;
  const NativeCastSection({super.key, required this.model});

  static bool get available => NativeCast.ready;

  @override
  State<NativeCastSection> createState() => _NativeCastSectionState();
}

class _NativeCastSectionState extends State<NativeCastSection> {
  String? _error;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    NativeCast.startDiscovery();
  }

  @override
  void dispose() {
    NativeCast.stopDiscovery();
    super.dispose();
  }

  Future<void> _connect(CastChoice d) async {
    setState(() {
      _error = null;
      _connecting = d.id;
    });
    try {
      await NativeCast.connect(d);
      await widget.model.startCast();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not cast: $e');
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _stop() async {
    await NativeCast.stop();
    widget.model.stopCast();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: NativeCast.connected,
      builder: (context, on, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shows the slides on a Chromecast or Google TV on this Wi-Fi '
            'network, and follows your selection.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<CastChoice>>(
            stream: NativeCast.devices,
            initialData: NativeCast.devicesNow,
            builder: (context, snap) {
              final devices = snap.data ?? const <CastChoice>[];
              if (devices.isEmpty) {
                return const ListTile(
                  dense: true,
                  leading: SizedBox.square(
                    dimension: 18,
                    child: AppSpinner(strokeWidth: 2),
                  ),
                  title: Text('Looking for devices…'),
                );
              }
              return Column(
                children: [
                  for (final d in devices)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        on == d.name
                            ? BrambleIcons.screencastFill
                            : BrambleIcons.televisionSimple,
                      ),
                      title: Text(d.name),
                      subtitle: d.model == null ? null : Text(d.model!),
                      trailing: on == d.name
                          ? OutlinedButton(
                              onPressed: _stop,
                              child: const Text('Stop'),
                            )
                          : FilledButton(
                              onPressed: _connecting != null || on != null
                                  ? null
                                  : () => _connect(d),
                              child: _connecting == d.id
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: AppSpinner(strokeWidth: 2),
                                    )
                                  : const Text('Cast'),
                            ),
                    ),
                ],
              );
            },
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          // What happened, step by step (to see where a cast gets stuck).
          ValueListenableBuilder<List<String>>(
            valueListenable: NativeCast.steps,
            builder: (context, steps, _) => steps.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SelectableText(
                      steps.map((s) => '• $s').join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The app's slide sender, once casting is available here (else null).
SlideCaster? get nativeCaster => NativeCast.ready ? NativeCast.caster : null;
