import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chordpro.dart';
import '../state.dart';
import '../translation.dart';
import '../eink.dart';

/// "Translate slides": pick a language and every section gets a translated
/// copy linked to it (shown together on the slide). Translate again to
/// update a language, or remove one / all. Changes are handed to
/// [onChanged] as they happen.
class TranslateDialog extends StatefulWidget {
  final String raw;
  final List<StructureItem> structure;
  final String language;
  final ValueChanged<TranslatedSong> onChanged;
  final ValueChanged<String>? onLanguage;
  final Translator translate;

  /// The song's title (a first line that's just the title isn't a verse).
  final String? title;

  const TranslateDialog({
    super.key,
    required this.raw,
    required this.structure,
    required this.language,
    required this.onChanged,
    this.onLanguage,
    this.translate = googleTranslate,
    this.title,
  });

  /// Swapped in tests.
  static Translator translator = googleTranslate;

  static Future<void> show(
    BuildContext context, {
    required String raw,
    required List<StructureItem> structure,
    required String language,
    required ValueChanged<TranslatedSong> onChanged,
    ValueChanged<String>? onLanguage,
    String? title,
  }) => showAppDialog<void>(
    context: context,
    builder: (_) => TranslateDialog(
      raw: raw,
      structure: structure,
      language: language,
      onChanged: onChanged,
      onLanguage: onLanguage,
      translate: translator,
      title: title,
    ),
  );

  @override
  State<TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<TranslateDialog> {
  late String _raw = widget.raw;
  late List<StructureItem> _structure = widget.structure;
  late Language _language = languageFor(widget.language) ?? languages.first;
  (int, int)? _progress;
  String? _error;

  List<String> get _done => translatedLanguages(_raw);

  void _apply(TranslatedSong r) {
    setState(() {
      _raw = r.raw;
      _structure = r.structure;
    });
    widget.onChanged(r);
  }

  Future<void> _translate() async {
    setState(() {
      _error = null;
      _progress = (0, 0);
    });
    try {
      final r = await translateSong(
        raw: _raw,
        structure: _structure,
        language: _language,
        translate: widget.translate,
        title: widget.title,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = (d, t));
        },
      );
      if (!mounted) return;
      _apply(r);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is TranslationError
            ? e.message
            : "Couldn't reach Google Translate. Check the internet "
                  'connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _remove([String? tag]) =>
      _apply(removeTranslation(_raw, _structure, tag: tag));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _done;
    final busy = _progress != null;
    final again = done.contains(_language.tag);
    // Fits a phone (the dialog's own padding takes ~112 px).
    final width = math.min(380.0, MediaQuery.sizeOf(context).width - 112);
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.language_rounded),
      title: const Text('Translate slides'),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownMenu<Language>(
              key: const Key('translate-language'),
              width: 380,
              label: const Text('Language'),
              leadingIcon: const Icon(Icons.public_rounded),
              initialSelection: _language,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 320,
              enabled: !busy,
              dropdownMenuEntries: [
                for (final l in languages)
                  DropdownMenuEntry(
                    value: l,
                    label: l.name,
                    labelWidget: Text(l.label),
                    trailingIcon: done.contains(l.tag)
                        ? Icon(Icons.check, size: 18, color: scheme.primary)
                        : null,
                  ),
              ],
              onSelected: (l) {
                if (l == null) return;
                setState(() => _language = l);
                widget.onLanguage?.call(l.code);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : _translate,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppSpinner(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate_rounded),
              label: Text(
                busy
                    ? (_progress!.$2 == 0
                          ? 'Translating…'
                          : 'Translating ${_progress!.$1} of ${_progress!.$2}…')
                    : again
                    ? 'Update ${_language.name}'
                    : done.isEmpty
                    ? 'Translate'
                    : 'Add ${_language.name}',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Translated', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final tag in done)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 4),
                  leading: const Icon(Icons.link_rounded, size: 20),
                  title: Text(languageFor(tag)?.label ?? tag),
                  trailing: IconButton(
                    tooltip: 'Remove ${languageFor(tag)?.name ?? tag}',
                    icon: const Icon(Icons.close),
                    onPressed: busy ? null : () => _remove(tag),
                  ),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: busy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove all translations'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Each section gets a translated copy, linked to it in the song '
              'structure so they show together. Edit or unlink them there. '
              'Lyrics are sent to Google Translate.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Opens [TranslateDialog] for the open song; changes apply as they're made.
Future<void> translateCurrentSong(BuildContext context, PresenterModel model) {
  final song = model.currentSong!;
  return TranslateDialog.show(
    context,
    raw: song.raw,
    structure: model.currentStructure,
    language: model.settings.translateTo,
    onLanguage: (code) => model.updateSettings((s) => s.translateTo = code),
    onChanged: (r) => model.applyTranslation(r.raw),
    title: song.title,
  );
}
