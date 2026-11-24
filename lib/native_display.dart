// External displays for the Android app: a monitor, TV or projector on
// USB-C / HDMI, or Samsung DeX / Android desktop mode. The projector runs
// in its own engine (secondaryDisplayMain) and is put on that screen by
// android/.../ExternalDisplay.kt: drawn straight onto a plain / mirrored
// screen, or as its own window on a DeX / desktop-mode screen. Messages
// pass both ways, as between a projector window and the operator.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browser.dart';
import 'state.dart';
import 'eink.dart';
import 'bramble_icons.dart';

/// A screen the projector can go on.
class ExternalScreen {
  final int id;
  final String name;
  final int width;
  final int height;

  /// A plain / mirrored screen (the projector is drawn straight onto it);
  /// otherwise a desktop (DeX…), where it opens as a window.
  final bool plain;

  const ExternalScreen({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.plain,
  });

  factory ExternalScreen.fromMap(Map<Object?, Object?> m) => ExternalScreen(
    id: m['id'] as int,
    name: m['name'] as String,
    width: m['width'] as int,
    height: m['height'] as int,
    plain: m['presentation'] as bool,
  );
}

class NativeDisplays {
  NativeDisplays._();

  static const _channel = MethodChannel('bp/displays');
  static bool _listening = false;
  static PresenterModel? _model;

  /// The screens showing the projector (by id), each with the view it's
  /// kept on ('stage': the band's chords; '': whatever the Format pane
  /// says). Two screens can show different views.
  static final showing = ValueNotifier<Map<int, String>>(const {});

  /// Bumped when a screen is plugged in or out.
  static final changes = ValueNotifier<int>(0);

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'displaysChanged':
          changes.value++;
        case 'fromProjector':
          // The projector says hello / is alive / asks for a picture.
          final msg = jsonDecode(call.arguments as String);
          if (msg is Map<String, dynamic>) _model?.sync.receive(msg);
        case 'projectorClosed':
          // Unplugged, or its window was closed on the desktop.
          _stopped(call.arguments as int?);
      }
    });
  }

  static Future<List<ExternalScreen>> list() async {
    _listen();
    final all = await _channel.invokeListMethod<Map<Object?, Object?>>('list');
    return [for (final m in all ?? const []) ExternalScreen.fromMap(m)];
  }

  /// [view]: the view this screen is kept on ('stage'), or null to
  /// follow the Format pane.
  static Future<void> show(
    ExternalScreen screen,
    PresenterModel model, {
    String? view,
  }) async {
    _listen();
    _model = model;
    NativeIO.onSend = (msg) =>
        _channel.invokeMethod<void>('send', jsonEncode(msg));
    await _channel.invokeMethod<String>('show', {
      'id': screen.id,
      'show': view,
    });
    showing.value = {...showing.value, screen.id: view ?? ''};
    // Wake it in case it was stopped the last time it was shown; it asks
    // for the slides itself as it starts ('hello').
    model.sync.send({'type': 'start'});
    model.broadcastState();
    await model.startCast();
  }

  /// Takes the projector off screen [id], or off every screen.
  static Future<void> hide([int? id]) async {
    if (showing.value.isEmpty) return;
    showing.value = {
      if (id != null)
        for (final e in showing.value.entries)
          if (e.key != id) e.key: e.value,
    };
    if (showing.value.isEmpty) NativeIO.onSend = null;
    try {
      await _channel.invokeMethod<void>('hide', {'id': id});
    } on PlatformException catch (_) {
      // Already gone.
    }
  }

  static void _stopped(int? id) {
    if (!showing.value.containsKey(id)) return;
    showing.value = {
      for (final e in showing.value.entries)
        if (e.key != id) e.key: e.value,
    };
    if (showing.value.isNotEmpty) return;
    NativeIO.onSend = null;
    _model?.stopCast();
  }
}

/// The projector on the external screen: hears the operator, and answers
/// (hello, alive, picture requests) the same way a projector window does.
/// The view the external screen this projector is on is kept on ('stage'
/// / 'lyrics'), or null: it follows the Format pane.
Future<String?> externalProjectorShow() async {
  try {
    return await const MethodChannel('bp/projector')
        .invokeMethod<String>('show');
  } catch (_) {
    return null;
  }
}

Widget externalProjector(ProjectorModel model, Widget child) {
  const channel = MethodChannel('bp/projector');
  NativeIO.onSend = (msg) =>
      channel.invokeMethod<void>('toOperator', jsonEncode(msg));
  channel.setMethodCallHandler((call) async {
    if (call.method != 'message') return;
    final msg = jsonDecode(call.arguments as String);
    if (msg is Map<String, dynamic>) model.sync.receive(msg);
  });
  return child;
}

/// "External display" in the cast dialog of the Android app.
class NativeDisplaySection extends StatefulWidget {
  final PresenterModel model;
  const NativeDisplaySection({super.key, required this.model});

  static bool get available => Platform.isAndroid;

  @override
  State<NativeDisplaySection> createState() => _NativeDisplaySectionState();
}

class _NativeDisplaySectionState extends State<NativeDisplaySection> {
  List<ExternalScreen>? _screens;
  String? _error;
  int? _opening;

  @override
  void initState() {
    super.initState();
    _find();
    // Plugging a screen in (or out) updates the list by itself.
    NativeDisplays.changes.addListener(_find);
  }

  @override
  void dispose() {
    NativeDisplays.changes.removeListener(_find);
    super.dispose();
  }

  Future<void> _find() async {
    try {
      final s = await NativeDisplays.list();
      if (mounted) setState(() => _screens = s);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  String _message(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  Future<void> _show(ExternalScreen s, {String? view}) async {
    setState(() {
      _error = null;
      _opening = s.id;
    });
    try {
      await NativeDisplays.show(s, widget.model, view: view);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't show it: ${_message(e)}");
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Map<int, String>>(
      valueListenable: NativeDisplays.showing,
      builder: (context, on, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A monitor, TV or projector on USB-C / HDMI. Works with screen '
            'mirroring, Samsung DeX and desktop mode: on a DeX / desktop '
            'screen the projector opens as its own window (maximise it '
            'there if needed). With two screens, "Stage view" keeps one on '
            'the band\'s chords while the other shows the lyrics.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          if (_screens == null && _error == null)
            const AppProgressBar()
          else if (_screens != null && _screens!.isEmpty)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(BrambleIcons.tbDeviceDesktopOff),
              title: const Text('No external screen connected'),
              trailing: IconButton(
                tooltip: 'Look again',
                icon: const Icon(BrambleIcons.arrowsClockwise),
                onPressed: _find,
              ),
            )
          else
            for (final s in _screens ?? const <ExternalScreen>[])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  on.containsKey(s.id)
                      ? BrambleIcons.television
                      : BrambleIcons.desktop,
                ),
                title: Text(s.name),
                subtitle: Text(
                  on[s.id] == 'stage'
                      ? 'Showing the stage view'
                      : '${s.width}×${s.height} · '
                            '${s.plain ? 'full screen' : 'desktop (opens a window)'}',
                ),
                trailing: on.containsKey(s.id)
                    ? OutlinedButton(
                        onPressed: () async {
                          await NativeDisplays.hide(s.id);
                          // (The last one: projecting has ended.)
                          if (NativeDisplays.showing.value.isEmpty) {
                            widget.model.stopCast();
                          }
                        },
                        child: const Text('Stop'),
                      )
                    : _opening == s.id
                    ? const SizedBox.square(
                        dimension: 16,
                        child: AppSpinner(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _opening != null
                                ? null
                                : () => _show(s, view: 'stage'),
                            child: const Text('Stage view'),
                          ),
                          FilledButton(
                            onPressed: _opening != null ? null : () => _show(s),
                            child: const Text('Show'),
                          ),
                        ],
                      ),
              ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}
