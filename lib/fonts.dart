import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser.dart';

/// A font the sheet or projector can use. Built-in fonts are bundled in
/// assets/fonts and loaded the first time they are chosen; custom fonts
/// are files the user uploaded, stored in the browser.
class FontOption {
  final String id;
  final String label;
  final List<String> files; // regular, bold, italic, bold italic

  const FontOption(this.id, this.label, [this.files = const []]);

  /// Family name to use in TextStyle (null = app default).
  String? get family => id == 'default' ? null : 'bp_$id';
  bool get isCustom => id.startsWith('custom_');
}

List<String> _set(String prefix, {bool boldItalic = true}) => [
  '$prefix-Regular.ttf',
  '$prefix-Bold.ttf',
  '$prefix-Italic.ttf',
  if (boldItalic) '$prefix-BoldItalic.ttf',
];

final builtInFonts = <FontOption>[
  const FontOption('default', 'Default (Roboto)'),
  FontOption('lato', 'Lato', _set('Lato')),
  FontOption('ptsans', 'PT Sans', _set('PT_Sans-Web')),
  FontOption('ubuntu', 'Ubuntu', _set('Ubuntu')),
  FontOption('cantarell', 'Cantarell (GNOME)', _set('Cantarell')),
  FontOption('notosans', 'Noto Sans (KDE)', _set('NotoSans')),
  FontOption('atkinson', 'Atkinson Hyperlegible', _set('AtkinsonHyperlegible')),
  FontOption('tinos', 'Tinos (like Times New Roman)', _set('Tinos')),
  FontOption('cousine', 'Cousine (like Courier New)', _set('Cousine')),
  FontOption(
    'courierprime',
    'Courier Prime (typewriter)',
    _set('CourierPrime'),
  ),
];

/// An uploaded font. The file itself is stored under [storageKey].
class CustomFont {
  final String id;
  final String name;
  const CustomFont(this.id, this.name);

  String get storageKey => 'font:$id';
  FontOption get option => FontOption(id, name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory CustomFont.fromJson(Map<String, dynamic> j) =>
      CustomFont(j['id'] as String, j['name'] as String);
}

class FontService {
  static final _loaded = <String>{'default'};
  static final _store = KeyValueStore();

  static FontOption option(String id, List<CustomFont> custom) {
    for (final f in builtInFonts) {
      if (f.id == id) return f;
    }
    for (final c in custom) {
      if (c.id == id) return c.option;
    }
    return builtInFonts.first;
  }

  /// Loads a font family if needed. Returns once it can be used.
  static Future<void> ensure(String id) async {
    if (_loaded.contains(id)) return;
    try {
      final loader = FontLoader('bp_$id');
      final builtIn = builtInFonts.where((f) => f.id == id).firstOrNull;
      if (builtIn != null) {
        for (final file in builtIn.files) {
          loader.addFont(rootBundle.load('assets/fonts/$file'));
        }
      } else {
        final data = await _store.read('font:$id');
        if (data == null) return;
        loader.addFont(Future.value(ByteData.sublistView(base64Decode(data))));
      }
      await loader.load();
      _loaded.add(id);
    } catch (e) {
      debugPrint('Could not load font $id: $e');
    }
  }

  /// Stores an uploaded font file and returns its entry.
  static Future<CustomFont> addCustom(String fileName, Uint8List bytes) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final name = fileName.replaceAll(
      RegExp(r'\.(ttf|otf)$', caseSensitive: false),
      '',
    );
    await _store.write('font:$id', base64Encode(bytes));
    final font = CustomFont(id, name);
    await ensure(id);
    return font;
  }

  static Future<void> removeCustom(CustomFont font) =>
      _store.delete(font.storageKey);
}
