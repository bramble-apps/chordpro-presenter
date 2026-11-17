import 'dart:async';

import 'package:flutter/material.dart';

import '../abc.dart';
import '../fonts.dart';
import 'abc_view.dart';
import '../eink.dart';

/// Writes or edits an ABC tune with the music drawn live under it (and
/// playable). Returns the tune's text, or null when cancelled.
Future<String?> editAbc(BuildContext context, String initial) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => _AbcEditor(initial: initial),
    );

/// The lines between {start_of_abc} and {end_of_abc} of [abcTemplate].
String get abcTemplateTune {
  final lines = abcTemplate.split('\n');
  return lines.sublist(1, lines.length - 1).join('\n');
}

class _AbcEditor extends StatefulWidget {
  final String initial;
  const _AbcEditor({required this.initial});

  @override
  State<_AbcEditor> createState() => _AbcEditorState();
}

class _AbcEditorState extends State<_AbcEditor> {
  late final _text = TextEditingController(text: widget.initial);
  late String _shown = widget.initial;
  Timer? _wait;

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) {
    // Redraw once typing pauses.
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _shown = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readable = parseAbc(_shown) != null;
    return AlertDialog(
      title: const Text('Melody (ABC notation)'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 5,
                maxLines: 12,
                onChanged: _changed,
                style: TextStyle(
                  fontFamily: FontOption('cousine', '').family,
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              Text(
                'Header: T: title, M: time (3/4), L: note length (1/8), '
                'Q: tempo (1/4=90), K: key (G, Dm, Bb). Notes: C D E… is '
                'the octave from middle C, c d e… the one above, '
                "' and , move an octave. A number after a note makes it "
                'longer (C2), / shorter (C/). ^ sharp, _ flat, = natural, '
                'z rest, [CEG] chord, - tie, (3 triplet, | bar, |: :| '
                'repeat, [1 [2 endings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(inkR(8)),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: inkW(1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: readable
                      ? AbcView(
                          lines: _shown.split('\n'),
                          style: theme.textTheme.bodyLarge!,
                          ink: scheme.onSurface,
                          accent: scheme.primary,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No notes yet: the music shows here as you '
                            'type.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text.trimRight()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
