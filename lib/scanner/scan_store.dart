// Scans kept in the app: the pages (as pictures), the score read from them
// (with corrections) and how it was last played.

import 'dart:convert';
import 'dart:typed_data';

import '../browser.dart';
import '../state.dart' show newId;
import 'playback.dart';
import 'score.dart';

/// A page of a scan: its picture (PNG or JPEG) and size.
class ScanPage {
  final Uint8List image;
  final int width, height;
  const ScanPage(this.image, this.width, this.height);
}

class ScanInfo {
  final String id, title;
  final DateTime date;
  final int pages, notes;

  /// The song it came from (its sheet music), if any.
  final String? songId;

  /// The file it was read from (a song's PDF or picture), to open it again
  /// without reading.
  final String? source;
  const ScanInfo(
    this.id,
    this.title,
    this.date,
    this.pages,
    this.notes,
    this.songId, [
    this.source,
  ]);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'pages': pages,
    'notes': notes,
    if (songId != null) 'song': songId,
    if (source != null) 'src': source,
  };

  static ScanInfo fromJson(Map<String, dynamic> j) => ScanInfo(
    j['id'] as String,
    j['title'] as String? ?? 'Scan',
    DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
    j['pages'] as int? ?? 1,
    j['notes'] as int? ?? 0,
    j['song'] as String?,
    j['src'] as String?,
  );
}

abstract final class ScanStore {
  static final _store = KeyValueStore();
  static const _listKey = 'scans';

  static Future<List<ScanInfo>> list() async {
    final raw = await _store.read(_listKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          ScanInfo.fromJson(Map<String, dynamic>.from(j as Map)),
      ]..sort((a, b) => b.date.compareTo(a.date));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _putInfo(ScanInfo info) async {
    final all = [
      for (final s in await list())
        if (s.id != info.id) s,
      info,
    ];
    await _store.write(_listKey, jsonEncode([for (final s in all) s.toJson()]));
  }

  /// The scan read from [source] before, if kept.
  static Future<ScanInfo?> forSource(String source) async {
    for (final s in await list()) {
      if (s.source == source) return s;
    }
    return null;
  }

  /// Keeps a new scan; returns its id.
  static Future<String> add(
    String title,
    List<ScanPage> pages,
    Score score,
    PlaySettings play, {
    String? songId,
    String? source,
  }) async {
    final id = newId();
    for (final (i, p) in pages.indexed) {
      await _store.writeBytes('scan:$id:page$i', p.image);
    }
    await save(
      id,
      title,
      score,
      play,
      pages: pages.length,
      songId: songId,
      source: source,
    );
    return id;
  }

  /// Keeps the score and playing settings of scan [id].
  static Future<void> save(
    String id,
    String title,
    Score score,
    PlaySettings play, {
    required int pages,
    String? songId,
    String? source,
  }) async {
    await _store.write(
      'scan:$id',
      jsonEncode({
        'score': score.toJson(),
        'play': play.toJson(),
        'sizes': [
          for (final (w, h) in score.pages) [w, h],
        ],
      }),
    );
    await _putInfo(
      ScanInfo(
        id,
        title,
        DateTime.now(),
        pages,
        score.notes.where((n) => !n.rest).length,
        songId,
        source,
      ),
    );
  }

  static Future<(Score, PlaySettings, List<ScanPage>)?> load(String id) async {
    final raw = await _store.read('scan:$id');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final score = Score.fromJson(Map<String, dynamic>.from(j['score'] as Map));
    final play = PlaySettings.fromJson(
      Map<String, dynamic>.from(j['play'] as Map),
    );
    final pages = <ScanPage>[];
    for (final (i, (w, h)) in score.pages.indexed) {
      final bytes = await _store.readBytes('scan:$id:page$i');
      if (bytes == null) break;
      pages.add(ScanPage(bytes, w, h));
    }
    return (score, play, pages);
  }

  static Future<void> delete(String id) async {
    final info = (await list()).where((s) => s.id == id).firstOrNull;
    for (var i = 0; i < (info?.pages ?? 0); i++) {
      await _store.delete('scan:$id:page$i');
    }
    await _store.delete('scan:$id');
    final rest = [
      for (final s in await list())
        if (s.id != id) s,
    ];
    await _store.write(
      _listKey,
      jsonEncode([for (final s in rest) s.toJson()]),
    );
  }
}
