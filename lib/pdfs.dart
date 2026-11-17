// PDFs: attached to a song (shown in a tab beside its ChordPro), or a song
// of their own (no ChordPro). The files are kept in the app's storage
// (IndexedDB in the browser / Linux app, files on Android), by id; the song
// only lists them, in `extra['pdfs']`, so backups of the library text stay
// small and the files travel in the backup zip.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'browser.dart';
import 'export.dart' show zipFiles;
import 'state.dart';

class PdfRef {
  final String id;
  final String name;
  const PdfRef(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static PdfRef? fromJson(Object? j) => j is Map && j['id'] is String
      ? PdfRef(j['id'] as String, '${j['name'] ?? 'PDF'}')
      : null;

  /// Its name without the extension (".pdf", ".png"…).
  String get title => name.replaceFirst(
    RegExp(r'\.(pdf|png|jpe?g|gif|webp)$', caseSensitive: false),
    '',
  );

  /// A picture (sheet music as an image) rather than a PDF.
  bool get isImage =>
      RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(name);

  /// Its file extension, for zips ("pdf", "png"…).
  String get ext {
    final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(name);
    return (m?.group(1) ?? 'pdf').toLowerCase();
  }
}

/// File types that can be sheet music (attached or a song of their own).
const sheetMusicExtensions = ['.pdf', '.png', '.jpg', '.jpeg', '.gif', '.webp'];

/// The PDFs attached to [song].
List<PdfRef> pdfsOf(Song song) => [
  for (final j in (song.extra['pdfs'] as List?) ?? const [])
    ?PdfRef.fromJson(j),
];

void setPdfs(Song song, List<PdfRef> pdfs) {
  if (pdfs.isEmpty) {
    song.extra.remove('pdfs');
  } else {
    song.extra['pdfs'] = [for (final p in pdfs) p.toJson()];
  }
}

/// A song that is only a PDF (no ChordPro to show or project).
bool isPdfOnly(Song song) => song.raw.trim().isEmpty && pdfsOf(song).isNotEmpty;

/// The PDF files themselves.
class PdfStore {
  static final _store = KeyValueStore();
  static final Map<String, Uint8List> _cache = {};

  static String _key(String id) => 'pdf:$id';

  /// Keeps [bytes] as a new PDF named [name].
  static Future<PdfRef> add(String name, Uint8List bytes) async {
    final ref = PdfRef(newId(), name);
    await put(ref.id, bytes);
    return ref;
  }

  static Future<void> put(String id, Uint8List bytes) async {
    _cache[id] = bytes;
    await _store.writeBytes(_key(id), bytes);
  }

  static Future<Uint8List?> bytes(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final b = await _store.readBytes(_key(id));
    if (b != null) _cache[id] = b;
    return b;
  }

  static Future<void> delete(String id) async {
    _cache.remove(id);
    await _store.delete(_key(id));
  }

  /// Whether [bytes] look like a PDF file.
  static bool looksLikePdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %PDF
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  /// Whether [bytes] look like a picture the app can show (PNG, JPEG, GIF,
  /// WebP).
  static bool looksLikeImage(Uint8List bytes) {
    bool at(int i, List<int> sig) {
      if (bytes.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (bytes[i + k] != sig[k]) return false;
      }
      return true;
    }

    return at(0, [0x89, 0x50, 0x4E, 0x47]) || // PNG
        at(0, [0xFF, 0xD8, 0xFF]) || // JPEG
        at(0, [0x47, 0x49, 0x46, 0x38]) || // GIF
        (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50]));
  }

  /// A PDF or a picture: something that can be sheet music.
  static bool looksLikeSheetMusic(Uint8List bytes) =>
      looksLikePdf(bytes) || looksLikeImage(bytes);
}

// ---- Library ----

/// Keeps [bytes] (a PDF named [name]) and makes a song of it (not yet in
/// the library).
Future<Song> pdfSong(String name, Uint8List bytes) async {
  final ref = await PdfStore.add(name, bytes);
  return Song(
    title: ref.title,
    raw: '',
    date: DateTime.now(),
    extra: {
      'pdfs': [ref.toJson()],
    },
  );
}

/// Adds [bytes] (a PDF named [name]) as a song of its own.
Future<Song> addPdfSong(
  PresenterModel model,
  String name,
  Uint8List bytes,
) async {
  final song = await pdfSong(name, bytes);
  model.addOrUpdate(song);
  return song;
}

/// Every PDF the library uses (songs and trash), and the pictures placed
/// on songs' sheets (kept the same way, so backups carry them).
List<PdfRef> libraryPdfs(PresenterModel model) {
  final seen = <String>{};
  return [
    for (final s in [...model.songs, ...model.trash]) ...[
      for (final p in pdfsOf(s))
        if (seen.add(p.id)) p,
      for (final j in model.sheetImagesOf(s))
        if (j['file'] is String && seen.add(j['file'] as String))
          PdfRef(j['file'] as String, j['name'] as String? ?? 'image.png'),
    ],
  ];
}

// ---- Backups ----

/// The whole library as a zip: `songs.json` (as "Export everything") and
/// each PDF as `pdfs/<id>.pdf`.
Future<Uint8List> libraryBackupZip(PresenterModel model) async => zipFiles({
  'songs.json': utf8.encode(model.toJsonString()),
  for (final p in libraryPdfs(model))
    'pdfs/${p.id}.${p.ext}': ?await PdfStore.bytes(p.id),
});

/// The library's PDFs in a zip, named after their songs (for JustChords
/// users: JustChords takes ChordPro songs only).
Future<Uint8List> pdfsZip(PresenterModel model) async {
  final names = <String>{};
  String unique(String name) {
    final dot = name.lastIndexOf('.');
    final ext = name.substring(dot + 1);
    var n = name
        .substring(0, dot)
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
        .trim();
    if (n.isEmpty) n = 'PDF';
    var candidate = '$n.$ext';
    for (var i = 2; !names.add(candidate); i++) {
      candidate = '$n ($i).$ext';
    }
    return candidate;
  }

  final files = <String, List<int>>{};
  for (final s in model.songs) {
    final pdfs = pdfsOf(s);
    for (final p in pdfs) {
      final b = await PdfStore.bytes(p.id);
      if (b == null) continue;
      files[unique(
            '${pdfs.length == 1 && s.title.isNotEmpty ? s.title : '${s.title} – ${p.title}'}.${p.ext}',
          )] =
          b;
    }
  }
  return zipFiles(files);
}

/// Whether [bytes] are a zip file.
bool looksLikeZip(Uint8List bytes) =>
    bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

/// Reads a backup zip (songs.json + pdfs/): the PDFs are stored right
/// away (by id, so the songs find them once imported).
Future<ImportBatch> readBackupZip(PresenterModel model, Uint8List zip) async {
  final archive = ZipDecoder().decodeBytes(zip);
  final texts = <(String, String)>[];
  final loose = <Song>[];
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.split('/').last;
    final data = Uint8List.fromList(f.content as List<int>);
    final pdf = RegExp(r'^pdfs/([^/.]+)\.[A-Za-z0-9]+$').firstMatch(f.name);
    if (pdf != null) {
      await PdfStore.put(pdf.group(1)!, data);
    } else if (PdfStore.looksLikeSheetMusic(data)) {
      loose.add(await pdfSong(name, data));
    } else if (!name.startsWith('.')) {
      texts.add((name, utf8.decode(data, allowMalformed: true)));
    }
  }
  return model.readImport(texts)..songs.addAll(loose);
}

/// Imports a backup zip as [options] say.
Future<ImportSummary> importBackupZip(
  PresenterModel model,
  Uint8List zip, [
  ImportOptions options = const ImportOptions(),
]) async => model.applyImport(await readBackupZip(model, zip), options);
