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

  /// The screen showing the projector, or null.
  static final showing = ValueNotifier<ExternalScreen?>(null);

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
          _stopped();
      }
    });
  }

  static Future<List<ExternalScreen>> list() async {
    _listen();
    final all = await _channel.invokeListMethod<Map<Object?, Object?>>('list');
    return [for (final m in all ?? const []) ExternalScreen.fromMap(m)];
  }

  static Future<void> show(ExternalScreen screen, PresenterModel model) async {
    _listen();
    _model = model;
    NativeIO.onSend = (msg) =>
        _channel.invokeMethod<void>('send', jsonEncode(msg));
    await _channel.invokeMethod<String>('show', {'id': screen.id});
    showing.value = screen;
    // Wake it in case it was stopped the last time it was shown; it asks
    // for the slides itself as it starts ('hello').
    model.sync.send({'type': 'start'});
    model.broadcastState();
    await model.startCast();
  }

  static Future<void> hide() async {
    if (showing.value == null) return;
    showing.value = null;
    NativeIO.onSend = null;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (_) {
      // Already gone.
    }
  }

  static void _stopped() {
    if (showing.value == null) return;
    showing.value = null;
    NativeIO.onSend = null;
    _model?.stopCast();
  }
}

/// The projector on the external screen: hears the operator, and answers
/// (hello, alive, picture requests) the same way a projector window does.
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

  Future<void> _show(ExternalScreen s) async {
    setState(() {
      _error = null;
      _opening = s.id;
    });
    try {
      await NativeDisplays.show(s, widget.model);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't show it: ${_message(e)}");
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<ExternalScreen?>(
      valueListenable: NativeDisplays.showing,
      builder: (context, on, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A monitor, TV or projector on USB-C / HDMI. Works with screen '
            'mirroring, Samsung DeX and desktop mode: on a DeX / desktop '
            'screen the projector opens as its own window (maximise it '
            'there if needed).',
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
                  on?.id == s.id
                      ? BrambleIcons.television
                      : BrambleIcons.desktop,
                ),
                title: Text(s.name),
                subtitle: Text(
                  '${s.width}×${s.height} · '
                  '${s.plain ? 'full screen' : 'desktop (opens a window)'}',
                ),
                trailing: on?.id == s.id
                    ? OutlinedButton(
                        onPressed: () async {
                          await NativeDisplays.hide();
                          widget.model.stopCast();
                        },
                        child: const Text('Stop'),
                      )
                    : FilledButton(
                        onPressed: _opening != null ? null : () => _show(s),
                        child: _opening == s.id
                            ? const SizedBox.square(
                                dimension: 16,
                                child: AppSpinner(strokeWidth: 2),
                              )
                            : const Text('Show'),
                      ),
              ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}
