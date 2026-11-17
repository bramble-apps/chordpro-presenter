// Remote: editing the library and controlling the slides from another
// device on the same Wi-Fi. The address to open there (shown with a QR
// code), and the strip that window shows at the top of its song list.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../browser.dart';
import '../state.dart';
import '../eink.dart';

/// Shows the address (and QR code) to edit this library from a phone,
/// tablet or another computer's browser.
Future<void> showEditLink(BuildContext context) async {
  final relay = await relayDetails();
  if (!context.mounted) return;
  final edit = relay?['edit'] as String?;
  final ip = relay?['editIp'] as String?;
  await showAppDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      if (edit == null || ip == null) {
        return AlertDialog(
          title: const Text('Remote'),
          content: const Text(
            'This works when the app runs on a computer (the Linux app, or '
            'the web app started with run.sh): any phone, tablet or laptop '
            'on the same Wi-Fi can then edit its library and control its '
            'slides in a browser.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      }
      Widget address(String url, {bool big = false}) => Row(
        children: [
          Expanded(
            child: SelectableText(
              url.replaceFirst('http://', ''),
              style:
                  (big
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                        fontWeight: big ? FontWeight.w600 : null,
                        color: big ? scheme.primary : null,
                      ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ],
      );
      return AlertDialog(
        title: const Text('Remote'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              const Text(
                'On a phone, tablet or laptop on the same Wi-Fi, open this '
                'in a browser:',
              ),
              address(edit, big: true),
              Text(
                'If that doesn’t open (some Android phones), use:',
                style: theme.textTheme.bodySmall,
              ),
              address(ip),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(data: ip, size: 170),
                ),
              ),
              Text(
                'There you can edit the library (changes show up here as '
                'they are made) and, with its Remote switch on, choose the '
                'song and the slide this computer shows. Keep the app open '
                'on this computer.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}

/// At the top of the song list in an editing window: whose library this
/// is, or why it couldn't be fetched.
class RemoteEditStrip extends StatelessWidget {
  final PresenterModel model;
  const RemoteEditStrip({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = model.remoteError;
    final color = error == null
        ? scheme.primaryContainer
        : scheme.errorContainer;
    final on = error == null
        ? scheme.onPrimaryContainer
        : scheme.onErrorContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(inkR(10)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(
            error == null ? Icons.wifi_tethering : Icons.wifi_off,
            size: 18,
            color: on,
          ),
          Expanded(
            child: Text(
              error ??
                  (model.remoteControl
                      ? 'Remote on: the song and slide you pick here show '
                            'on your computer.'
                      : 'Editing “${model.remoteLibraryName ?? 'Library'}” '
                            'on your computer: changes are saved there.'),
              style: TextStyle(color: on, fontSize: 13),
            ),
          ),
          // Remote: this window also controls the computer's slides.
          if (error == null)
            Tooltip(
              message: model.remoteControl
                  ? 'Stop controlling the computer’s slides'
                  : 'Control the computer’s slides from here',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Remote',
                    style: TextStyle(
                      color: on,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: FittedBox(
                      child: Switch(
                        key: const Key('remote-control'),
                        value: model.remoteControl,
                        onChanged: model.setRemoteControl,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
