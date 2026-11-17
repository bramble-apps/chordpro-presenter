// The media library: pictures, videos, audio and links (YouTube…) kept for
// projecting, sorted into folders. Each can be played on the projector
// (full screen), shown over the lyrics, set as the background, or put in a
// setlist, where it plays when the setlist reaches it.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'projection.dart';
import 'widgets/media_pip.dart' show youtubeId;

enum MediaKind {
  image('Picture'),
  video('Video'),
  audio('Audio'),
  youtube('YouTube'),
  link('Link');

  final String label;
  const MediaKind(this.label);
}

/// What a media item does on the projector.
enum LiveMode {
  /// Full screen, over the lyrics (black around it), with sound.
  play('Play'),

  /// Over the lyrics, which show through its see-through parts.
  overlay('Overlay'),

  /// As the projector background, under the lyrics (pictures and videos).
  background('Background');

  final String label;
  const LiveMode(this.label);
}

class MediaItem {
  final String id;
  String name;

  /// Folder path ("" = top, "Easter/Backgrounds" = nested).
  String folder;
  final MediaKind kind;

  /// The file (pictures, videos, audio).
  final MediaRef? file;

  /// The link (YouTube, other pages).
  final String url;
  final DateTime added;

  MediaItem({
    String? id,
    required this.name,
    required this.kind,
    this.folder = '',
    this.file,
    this.url = '',
    DateTime? added,
  }) : id = id ?? uniqueMediaId('mi'),
       added = added ?? DateTime.now();

  /// A picked or uploaded file.
  factory MediaItem.fromFile(MediaRef ref, {String folder = ''}) => MediaItem(
    name: _withoutExtension(ref.name),
    kind: kindOfMime(ref.mime, ref.name),
    file: ref,
    folder: folder,
  );

  /// A pasted link: YouTube, a media file, or any page.
  factory MediaItem.fromUrl(
    String url, {
    String name = '',
    String folder = '',
  }) {
    final u = url.trim();
    final yt = youtubeId(u);
    final kind = yt != null
        ? MediaKind.youtube
        : kindOfMime('', Uri.tryParse(u)?.path ?? '');
    final uri = Uri.tryParse(u);
    final last = uri?.pathSegments.where((p) => p.isNotEmpty).lastOrNull;
    return MediaItem(
      name: name.isNotEmpty
          ? name
          : yt != null
          ? 'YouTube video'
          : last == null
          ? (uri?.host.isNotEmpty ?? false ? uri!.host : u)
          : _withoutExtension(Uri.decodeComponent(last)),
      kind: kind,
      url: u,
      folder: folder,
    );
  }

  /// The same item under a new id (repairs ids that clashed).
  MediaItem withNewId() => MediaItem(
    name: name,
    kind: kind,
    folder: folder,
    file: file,
    url: url,
    added: added,
  );

  String? get youtube => kind == MediaKind.youtube ? youtubeId(url) : null;

  /// YouTube's still picture for the video.
  String? get thumbnailUrl => youtube == null
      ? null
      : 'https://img.youtube.com/vi/$youtube/hqdefault.jpg';

  /// Can be the projector background (a picture or video file).
  bool get canBeBackground =>
      file != null && (kind == MediaKind.image || kind == MediaKind.video);

  /// Shows something on the projector (links to other pages only open in
  /// a browser).
  bool get canProject => kind != MediaKind.link;

  /// The file name to save it as.
  String get exportName {
    if (file == null) return '$name.url';
    final ext = RegExp(r'\.[A-Za-z0-9]{1,5}$').firstMatch(file!.name)?[0] ?? '';
    return '$name$ext';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (folder.isNotEmpty) 'folder': folder,
    if (file != null) 'file': file!.toJson(),
    if (url.isNotEmpty) 'url': url,
    'added': added.toIso8601String(),
  };

  static MediaItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = MediaKind.values.asNameMap()[j['kind']];
    if (kind == null) return null;
    return MediaItem(
      id: j['id'] as String?,
      name: (j['name'] as String?) ?? '',
      kind: kind,
      folder: (j['folder'] as String?) ?? '',
      file: MediaRef.fromJson(j['file']),
      url: (j['url'] as String?) ?? '',
      added: DateTime.tryParse((j['added'] as String?) ?? ''),
    );
  }
}

/// The kind of a file from its type (or, failing that, its name).
MediaKind kindOfMime(String mime, String name) {
  if (mime.startsWith('image/')) return MediaKind.image;
  if (mime.startsWith('video/')) return MediaKind.video;
  if (mime.startsWith('audio/')) return MediaKind.audio;
  final ext = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(name)?[1]?.toLowerCase();
  return switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' => MediaKind.image,
    'mp4' || 'm4v' || 'webm' || 'mov' || 'mkv' => MediaKind.video,
    'mp3' ||
    'm4a' ||
    'aac' ||
    'wav' ||
    'ogg' ||
    'oga' ||
    'opus' ||
    'flac' => MediaKind.audio,
    _ => MediaKind.link,
  };
}

/// The type of a file from its name (dropped files come without one), or
/// "" when it isn't a picture, video or audio file.
String mimeOfName(String name) {
  final ext = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(name)?[1]?.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' => 'image/heic',
    'mp4' || 'm4v' => 'video/mp4',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    _ => '',
  };
}

var _idCounter = 0;
final _idRandom = math.Random();

/// A new id that's different even for files added in the same moment
/// (browser clocks only count milliseconds).
String uniqueMediaId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${(_idCounter++).toRadixString(36)}'
    '${_idRandom.nextInt(1 << 30).toRadixString(36)}';

String _withoutExtension(String name) {
  final n = name.replaceFirst(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '');
  return n.isEmpty ? name : n;
}

/// What the projector is showing from the media library (besides the
/// lyrics): [item] in [mode], playing or paused. [started] tells screens
/// apart a fresh start from the same item again (restart).
class LiveMedia {
  final MediaItem item;
  final LiveMode mode;
  final bool playing;
  final int started;

  const LiveMedia(
    this.item,
    this.mode, {
    this.playing = true,
    this.started = 0,
  });

  LiveMedia withPlaying(bool on) =>
      LiveMedia(item, mode, playing: on, started: started);

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'mode': mode.name,
    'playing': playing,
    'started': started,
  };

  static LiveMedia? fromJson(Object? j) {
    if (j is! Map) return null;
    final item = MediaItem.fromJson(j['item']);
    if (item == null) return null;
    return LiveMedia(
      item,
      LiveMode.values.asNameMap()[j['mode']] ?? LiveMode.play,
      playing: j['playing'] != false,
      started: (j['started'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The folder [path]'s parent ("" for a top-level folder).
String parentFolder(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// The last part of a folder [path].
String folderName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Where to load a picture from another site: in browsers through the
/// local server (they won't let the app read other sites' pictures, and
/// showing them as page elements instead leaves drawing glitches); the
/// installed apps load it directly.
String pictureSource(String url) =>
    kIsWeb ? 'image?url=${Uri.encodeQueryComponent(url)}' : url;
