import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../browser.dart';
import '../native.dart';
import '../state.dart';
import '../eink.dart';

/// "Show on another screen": Chromecast, attached / AirPlay displays.
class CastDialog extends StatefulWidget {
  final PresenterModel model;
  const CastDialog({super.key, required this.model});

  @override
  State<CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<CastDialog> {
  List<DisplayInfo>? _displays;

  /// Chromecasts found by the local server (works from any browser).
  List<Map<String, dynamic>>? _devices;
  Map<String, dynamic>? _relay;
  bool _scanning = false;
  String? _castError;
  final Set<String> _castingTo = {};

  @override
  void initState() {
    super.initState();
    relayDetails().then((r) {
      if (!mounted) return;
      setState(() => _relay = r);
      if (r != null && r['cast'] == true) _scan();
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _castError = null;
    });
    try {
      final d = await castDevices();
      if (!mounted) return;
      setState(() {
        _devices = d.where((x) => x['audioOnly'] != true).toList();
        _castingTo
          ..clear()
          ..addAll([
            for (final x in d)
              if (x['casting'] == true) x['id'] as String,
          ]);
      });
    } catch (e) {
      if (mounted) setState(() => _castError = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _toggleDevice(String id) async {
    setState(() => _castError = null);
    try {
      if (_castingTo.contains(id)) {
        await castStop(id);
        setState(() => _castingTo.remove(id));
      } else {
        await castStart(id);
        setState(() => _castingTo.add(id));
      }
    } catch (e) {
      if (mounted) setState(() => _castError = 'Could not cast: $e');
    }
  }

  String? _message;
  bool _busy = false;

  PresenterModel get model => widget.model;

  Future<void> _cast() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final error = await model.startCast();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = error ?? 'Casting. Use the arrow keys or your pedal as usual.';
    });
  }

  Future<void> _findDisplays() async {
    final list = await listDisplays();
    if (mounted) setState(() => _displays = list);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          Text(text, style: theme.textTheme.titleSmall),
        ],
      ),
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: theme.textTheme.bodySmall),
    );

    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => AlertDialog(
        title: const Text('Show on another screen'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading(Icons.cast, 'Chromecast & Google TV'),
                // The Android app casts with Google's Cast SDK.
                if (NativeCastSection.available)
                  NativeCastSection(model: model)
                else if (_relay != null && _relay!['cast'] == true) ...[
                  note(
                    'Works from any browser. The TV loads the projector '
                    'from this computer and follows your selection.',
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: AppSpinner(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('Find devices'),
                      ),
                    ],
                  ),
                  for (final d in _devices ?? const <Map<String, dynamic>>[])
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _castingTo.contains(d['id'])
                            ? Icons.cast_connected
                            : Icons.tv,
                      ),
                      title: Text('${d['name']}'),
                      subtitle: Text('${d['model']}'),
                      trailing: _castingTo.contains(d['id'])
                          ? OutlinedButton(
                              onPressed: () => _toggleDevice(d['id'] as String),
                              child: const Text('Stop'),
                            )
                          : FilledButton(
                              onPressed: () => _toggleDevice(d['id'] as String),
                              child: const Text('Cast'),
                            ),
                    ),
                  if (_devices != null && _devices!.isEmpty)
                    note('No Chromecasts found on this network.'),
                  if (_castError != null)
                    Text(
                      _castError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (castSupported) ...[
                    const SizedBox(height: 8),
                    note('Or use this browser\'s own casting:'),
                  ],
                ] else if (!castSupported)
                  note(
                    'Start the app with tools/serve.py to cast from any '
                    'browser, or open it in Chrome / Edge / Brave.',
                  ),
                if (castSupported) ...[
                  note(
                    'Sends the projector view (lyrics or stage view, with '
                    'backgrounds) to a Chromecast or Google TV on your '
                    'network, or to a connected display.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || model.casting ? null : _cast,
                        icon: const Icon(Icons.cast),
                        label: const Text('Cast…'),
                      ),
                      if (model.casting)
                        OutlinedButton.icon(
                          onPressed: model.stopCast,
                          icon: const Icon(Icons.cast_connected),
                          label: const Text('Stop casting'),
                        ),
                    ],
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_message!),
                  ),
                if (_relay != null) ...[
                  heading(Icons.qr_code_2, 'Any screen with a web browser'),
                  note(
                    'Open this link on a smart TV, tablet, phone or another '
                    'computer on the same Wi-Fi. It shows the projector and '
                    'stays in sync.',
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(6),
                        child: QrImageView(
                          data: '${_relay!['url']}',
                          size: 120,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText('${_relay!['url']}'),
                            TextButton.icon(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: '${_relay!['url']}'),
                              ),
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy link'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                // The Android app shows the projector on a monitor / TV /
                // projector plugged into the phone (or Samsung DeX).
                if (NativeDisplaySection.available) ...[
                  heading(Icons.connected_tv, 'External display'),
                  NativeDisplaySection(model: model),
                ] else
                  heading(
                    Icons.desktop_windows_outlined,
                    'Displays on this computer',
                  ),
                if (NativeDisplaySection.available)
                  const SizedBox.shrink()
                else if (displayListSupported) ...[
                  OutlinedButton.icon(
                    onPressed: _findDisplays,
                    icon: const Icon(Icons.search),
                    label: const Text('Find displays'),
                  ),
                  if (_displays != null && _displays!.isEmpty)
                    note('No displays found (or permission was declined).'),
                  for (final d in _displays ?? const <DisplayInfo>[])
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(d.primary ? Icons.laptop_mac : Icons.tv),
                      title: Text(d.label),
                      subtitle: Text(
                        '${d.width}×${d.height}${d.primary ? ' · this screen' : ''}',
                      ),
                      trailing: TextButton(
                        onPressed: () => openProjectorOn(d),
                        child: const Text('Open projector here'),
                      ),
                    ),
                  note('Then press F in the projector window for fullscreen.'),
                ] else
                  note(
                    'Open the projector window (▶), drag it onto the other '
                    'display, then press F (or double-click) for fullscreen.',
                  ),
                heading(Icons.airplay, 'AirPlay'),
                if (isMac) ...[
                  note(
                    'AirPlay is part of macOS, so use it as an extra display:',
                  ),
                  note(
                    '1. Control Centre (top-right of the menu bar) → Screen '
                    'Mirroring → pick your Apple TV or AirPlay TV.\n'
                    '2. In the same menu choose "Use As Separate Display".\n'
                    '3. Above, tap Find displays → Open projector here (or drag '
                    'the projector window onto the TV) and press F.',
                  ),
                ] else
                  note(
                    'Browsers can\'t send AirPlay themselves. Use Cast, or '
                    'mirror the projector window with your device\'s own '
                    'screen-sharing.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
