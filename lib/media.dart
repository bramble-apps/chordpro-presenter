import 'dart:typed_data';

import 'browser.dart';
import 'media_library.dart' show uniqueMediaId;
import 'projection.dart';

/// Uploaded images/videos, kept in browser storage and cached in memory.
/// Both the operator and the projector window read from the same storage.
class MediaStore {
  static final _store = KeyValueStore();
  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, String> _urls = {};

  /// Opens the file picker and stores the chosen file.
  static Future<MediaRef?> pick({bool videos = true}) async {
    // With the local server running, upload to it: the browser sends the
    // file directly (reliable even where reading files in the page hangs),
    // and TVs / Chromecasts can load it straight from the server.
    if (await relayDetails() != null) {
      final up = await pickMediaToServer(videos: videos);
      if (up == null) return null;
      return MediaRef(up.$1, up.$2, up.$3, server: true);
    }
    final files = await pickMediaFiles(videos: videos);
    if (files.isEmpty) return null;
    return _keep(files.first);
  }

  /// The media library's picker: pictures, videos and audio, several at
  /// once (one at a time through the local server).
  static Future<List<MediaRef>> pickMany() async {
    if (await relayDetails() != null) {
      return [
        for (final (id, name, mime) in await pickMediaListToServer(audio: true))
          MediaRef(id, name, mime, server: true),
      ];
    }
    final files = await pickMediaFiles(audio: true, multiple: true);
    return [for (final f in files) await _keep(f)];
  }

  /// A file dropped on the window: kept like a picked one.
  static Future<MediaRef> add(String name, String mime, Uint8List bytes) async {
    if (await relayDetails() != null) {
      final up = await uploadMediaBytes(name, mime, bytes);
      if (up != null) return MediaRef(up.$1, up.$2, up.$3, server: true);
    }
    return _keep((name, mime, bytes));
  }

  static Future<MediaRef> _keep((String, String, Uint8List) file) async {
    final (name, mime, bytes) = file;
    final ref = MediaRef(
      uniqueMediaId('m'),
      name,
      mime.isEmpty ? 'image/png' : mime,
    );
    _bytes[ref.id] = bytes;
    try {
      await _store.writeBytes(ref.storageKey, bytes);
      debugLog('saved ${ref.storageKey}');
    } catch (e) {
      debugLog('save failed: $e');
      rethrow;
    }
    return ref;
  }

  /// On a cast screen (separate browser storage) missing files are asked
  /// for from the operator window over the cast connection.
  static Future<Uint8List?> Function(MediaRef ref)? remote;

  static Future<Uint8List?> bytes(MediaRef ref) async {
    final cached = _bytes[ref.id];
    if (cached != null && cached.isNotEmpty) return cached;
    if (ref.server) {
      return _bytes[ref.id] =
          await fetchBytes('media/${ref.id}') ?? Uint8List(0);
    }
    var b = await _store.readBytes(ref.storageKey);
    if ((b == null || b.isEmpty) && remote != null) b = await remote!(ref);
    return _bytes[ref.id] = b ?? Uint8List(0);
  }

  /// URL the video player can open.
  static Future<String?> url(MediaRef ref) async {
    if (ref.server) return 'media/${ref.id}';
    final cached = _urls[ref.id];
    if (cached != null) return cached;
    final b = await bytes(ref);
    if (b == null || b.isEmpty) return null;
    return _urls[ref.id] = blobUrl(b, ref.mime);
  }

  static Future<void> delete(MediaRef ref) async {
    if (ref.server) {
      _bytes.remove(ref.id);
      return; // kept on the server (it may still be used elsewhere)
    }
    _bytes.remove(ref.id);
    _urls.remove(ref.id);
    await _store.delete(ref.storageKey);
  }
}
