// Desktop apps (Linux; also Windows / macOS): the projector is a second
// window of the app, with its own engine (desktop_multi_window). The
// operator and projector windows talk over one two-way channel, the same
// messages a browser projector window gets. The main window also gets
// rounded bottom corners (Linux, see linux/runner/my_application.cc).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'package:window_manager/window_manager.dart';

import 'browser.dart';
import 'native_setup.dart';
import 'screens/projector_screen.dart';
import 'state.dart';

bool get isDesktop =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

const _projectorArgument = 'projector';
const _channel = WindowMethodChannel('bp/projector');

/// Runs this window's app if it's the projector window (returns true).
/// Called first thing in main().
Future<bool> runDesktopProjector() async {
  if (!isDesktop) return false;
  final WindowController window;
  try {
    window = await WindowController.fromCurrentEngine();
  } catch (_) {
    return false; // not started through desktop_multi_window
  }
  if (window.arguments != _projectorArgument) return false;

  await windowManager.ensureInitialized();
  await setUpProjectorIO();
  final model = ProjectorModel();
  NativeIO.onSend = (msg) {
    _channel.invokeMethod('toOperator', jsonEncode(msg)).catchError((_) {});
  };
  await _channel.setMethodCallHandler((call) async {
    if (call.method != 'message') return null;
    final msg = jsonDecode(call.arguments as String);
    if (msg is Map<String, dynamic>) model.sync.receive(msg);
    return null;
  });
  NativeIO.toggleFullscreen = () async {
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  };
  NativeIO.closeWindow = () => windowManager.close();
  final closing = <void Function()>[];
  NativeIO.onWindowClose = closing.add;
  // Closing the window: say goodbye and free the channel for the next one.
  await windowManager.setPreventClose(true);
  windowManager.addListener(
    _CloseListener(() async {
      for (final c in closing) {
        c();
      }
      await _channel.setMethodCallHandler(null);
      await windowManager.destroy();
    }),
  );
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'ChordPro Presenter — Projector',
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.black,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(
    MaterialApp(
      title: 'ChordPro Presenter — Projector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: ProjectorScreen(model: model),
    ),
  );
  return true;
}

class _CloseListener with WindowListener {
  final Future<void> Function() onClose;
  _CloseListener(this.onClose);

  @override
  void onWindowClose() => onClose();
}

/// The desktop app's main window is running (not tests, not phones).
bool _desktopApp = false;

/// The operator window: opens the projector window and passes messages.
Future<void> setUpDesktopOperator(PresenterModel model) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  _desktopApp = true;
  // No embedded web player on desktop: recordings open in the browser.
  NativeIO.youTubeInBrowser = true;
  await _channel.setMethodCallHandler((call) async {
    if (call.method != 'toOperator') return null;
    final msg = jsonDecode(call.arguments as String);
    if (msg is Map<String, dynamic>) model.sync.receive(msg);
    return null;
  });
  NativeIO.onSend = (msg) {
    // Only reaches a projector window if one is open.
    _channel.invokeMethod('message', jsonEncode(msg)).catchError((_) {});
  };
  NativeIO.openProjector = () async {
    for (final w in await WindowController.getAll()) {
      if (w.arguments == _projectorArgument) {
        await w.show();
        return;
      }
    }
    await WindowController.create(
      const WindowConfiguration(
        arguments: _projectorArgument,
        hiddenAtLaunch: true,
      ),
    );
  };
}

/// The main window's frame: rounded bottom corners (the window manager
/// rounds only the top), square when maximised or full screen.
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;
  const DesktopWindowFrame({super.key, required this.child});

  static const radius = 12.0;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _square = false;

  /// Only the Linux app's main window draws its own corners.
  final bool _frame = _desktopApp && Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (!_frame) return;
    windowManager.addListener(this);
    _check();
  }

  @override
  void dispose() {
    if (_frame) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _check() async {
    final square =
        await windowManager.isMaximized() || await windowManager.isFullScreen();
    if (mounted && square != _square) setState(() => _square = square);
  }

  @override
  void onWindowMaximize() => _check();
  @override
  void onWindowUnmaximize() => _check();
  @override
  void onWindowEnterFullScreen() => _check();
  @override
  void onWindowLeaveFullScreen() => _check();
  @override
  void onWindowResized() => _check();

  @override
  Widget build(BuildContext context) {
    if (!_frame || _square) return widget.child;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(DesktopWindowFrame.radius),
      ),
      child: widget.child,
    );
  }
}
