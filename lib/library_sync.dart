// Syncing two of this app's own libraries (Libraries → a library's ⋯ →
// "Compare & sync…"): what's only in one, what's in both but different,
// and for each a choice — send it over, bring it here, take one side's
// version, keep both (the other side's comes in as a copy), or skip.
//
// Songs are matched by id (a song copied between libraries keeps its id),
// else by title and artist (the same song added to both separately).
// Setlists likewise, by id, else by name. Nothing is ever deleted: a song
// removed from one library isn't removed from the other.

import 'dart:convert';

import 'state.dart';

/// One library's songs, setlists and tags, as lists that are changed in
/// place (the open library's own lists, or another's read from storage).
class LibrarySide {
  final String name;
  final List<Song> songs;
  final List<Setlist> setlists;
  final List<Tag> tags;
  LibrarySide(this.name, this.songs, this.setlists, this.tags);
}

/// What to do with one difference.
enum SyncChoice {
  /// This library's (open one's) way: send it there / keep this version.
  here,

  /// The other library's way: bring it here / take that version.
  there,

  /// Both versions in both libraries (a changed song only).
  both,
  skip,
}

class SongDiff {
  final Song? here, there;
  SongDiff(this.here, this.there);
  bool get changed => here != null && there != null;

  /// Which side was edited last (null: same time or unknown).
  bool? get hereNewer {
    final a = here?.date, b = there?.date;
    if (a == null || b == null || a.isAtSameMomentAs(b)) return null;
    return a.isAfter(b);
  }

  String get title => (here ?? there)!.displayTitle;
}

class SetlistDiff {
  final Setlist? here, there;
  SetlistDiff(this.here, this.there);
  bool get changed => here != null && there != null;
  String get name => (here ?? there)!.name;
}

/// The differences between two libraries, with a choice for each
/// (filled in by [LibraryDiff.choose] and changed by the person).
class LibraryDiff {
  final List<SongDiff> songs;
  final List<SetlistDiff> setlists;

  /// Songs in both and the same (here id → there id), for setlists.
  final Map<String, String> sameSongs;
  final Map<Object, SyncChoice> choices = {};

  LibraryDiff(this.songs, this.setlists, this.sameSongs);

  bool get isEmpty => songs.isEmpty && setlists.isEmpty;

  /// Sets every choice for a direction: [here] sends this library's to the
  /// other, [there] brings the other's here, null both ways (the newer
  /// version wins where both changed).
  void choose(SyncChoice? direction) {
    for (final d in songs) {
      choices[d] = _default(d.here != null, d.there != null, direction, () {
        final n = d.hereNewer;
        return n == null
            ? SyncChoice.skip
            : (n ? SyncChoice.here : SyncChoice.there);
      });
    }
    for (final d in setlists) {
      choices[d] = _default(
        d.here != null,
        d.there != null,
        direction,
        () => SyncChoice.skip,
      );
    }
  }

  static SyncChoice _default(
    bool here,
    bool there,
    SyncChoice? direction,
    SyncChoice Function() both,
  ) {
    if (here && there) return direction ?? both();
    if (here) {
      return direction == SyncChoice.there ? SyncChoice.skip : SyncChoice.here;
    }
    return direction == SyncChoice.here ? SyncChoice.skip : SyncChoice.there;
  }
}

String _key(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

String _songKey(Song s) => '${_key(s.displayTitle)}|${_key(s.displayArtist)}';

/// A song's content (what makes two copies the same), leaving out its id,
/// dates, tags and this app's bookkeeping.
String _content(Song s) {
  final j = s.toJson()
    ..remove('id')
    ..remove('date')
    ..remove('tags')
    ..remove('extra');
  return jsonEncode(j);
}

/// Pairs [a] with [b]: same id, else same key (when only one has it).
Map<T, T> _pair<T>(
  List<T> a,
  List<T> b,
  String Function(T) id,
  String Function(T) key,
) {
  final pairs = <T, T>{};
  final bById = {for (final x in b) id(x): x};
  final taken = <T>{};
  for (final x in a) {
    final y = bById[id(x)];
    if (y != null) {
      pairs[x] = y;
      taken.add(y);
    }
  }
  final aKeys = <String, List<T>>{}, bKeys = <String, List<T>>{};
  for (final x in a) {
    if (!pairs.containsKey(x)) (aKeys[key(x)] ??= []).add(x);
  }
  for (final y in b) {
    if (!taken.contains(y)) (bKeys[key(y)] ??= []).add(y);
  }
  for (final e in aKeys.entries) {
    final ys = bKeys[e.key];
    if (e.value.length == 1 && ys != null && ys.length == 1) {
      pairs[e.value.single] = ys.single;
    }
  }
  return pairs;
}

/// What a setlist holds, in the other library's terms ([songKey] maps a
/// song id to something both libraries agree on).
String _setContent(Setlist s, String Function(String? songId) songKey) =>
    jsonEncode([
      s.name,
      for (final e in s.entries)
        [e.type.name, e.type == EntryType.song ? songKey(e.songId) : e.title],
    ]);

LibraryDiff compareLibraries(LibrarySide here, LibrarySide there) {
  final songPairs = _pair<Song>(here.songs, there.songs, (s) => s.id, _songKey);
  final hereToThere = {for (final e in songPairs.entries) e.key.id: e.value.id};
  final songs = <SongDiff>[];
  final same = <String, String>{};
  for (final s in here.songs) {
    final t = songPairs[s];
    if (t == null) {
      songs.add(SongDiff(s, null));
    } else if (_content(s) != _content(t)) {
      songs.add(SongDiff(s, t));
    } else {
      same[s.id] = t.id;
    }
  }
  final paired = songPairs.values.toSet();
  for (final t in there.songs) {
    if (!paired.contains(t)) songs.add(SongDiff(null, t));
  }

  // Setlists: compared through the songs' pairing.
  final hereSong = {for (final s in here.songs) s.id: s};
  final thereSong = {for (final s in there.songs) s.id: s};
  String keyHere(String? id) =>
      hereSong[id] == null ? '?' : _songKey(hereSong[id]!);
  String keyThere(String? id) =>
      thereSong[id] == null ? '?' : _songKey(thereSong[id]!);
  final setPairs = _pair<Setlist>(
    here.setlists,
    there.setlists,
    (s) => s.id,
    (s) => _key(s.name),
  );
  final sets = <SetlistDiff>[];
  for (final s in here.setlists) {
    final t = setPairs[s];
    if (t == null) {
      sets.add(SetlistDiff(s, null));
    } else if (_setContent(s, keyHere) != _setContent(t, keyThere)) {
      sets.add(SetlistDiff(s, t));
    }
  }
  final setsPaired = setPairs.values.toSet();
  for (final t in there.setlists) {
    if (!setsPaired.contains(t)) sets.add(SetlistDiff(null, t));
  }
  songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return LibraryDiff(songs, sets, {...hereToThere, ...same})..choose(null);
}

/// What [applyLibrarySync] did, for telling the person.
class LibrarySyncResult {
  int songsHere = 0, songsThere = 0, setsHere = 0, setsThere = 0;

  String describe(String hereName, String thereName) {
    String n(int c, String what) => '$c $what${c == 1 ? '' : 's'}';
    final parts = [
      if (songsThere + setsThere > 0)
        'to $thereName: ${[if (songsThere > 0) n(songsThere, 'song'), if (setsThere > 0) n(setsThere, 'setlist')].join(', ')}',
      if (songsHere + setsHere > 0)
        'to $hereName: ${[if (songsHere > 0) n(songsHere, 'song'), if (setsHere > 0) n(setsHere, 'setlist')].join(', ')}',
    ];
    return parts.isEmpty ? 'Nothing to change' : 'Copied ${parts.join('; ')}';
  }
}

/// Carries out [diff]'s choices on both sides (their lists change in
/// place; save both afterwards).
LibrarySyncResult applyLibrarySync(
  LibraryDiff diff,
  LibrarySide here,
  LibrarySide there,
) {
  final r = LibrarySyncResult();
  // Song ids across: here → there and there → here, as songs are paired
  // or copied (setlists need them).
  final toThere = {...diff.sameSongs};
  final toHere = {for (final e in diff.sameSongs.entries) e.value: e.key};
  for (final d in diff.songs) {
    if (d.changed) {
      toThere[d.here!.id] = d.there!.id;
      toHere[d.there!.id] = d.here!.id;
    }
  }

  List<String> tagsFor(Song s, LibrarySide from, LibrarySide to) => [
    for (final id in s.tags)
      if (from.tags.where((t) => t.id == id).firstOrNull case final t?)
        (to.tags.where((x) => x.name == t.name).firstOrNull ??
                (Tag(name: t.name, color: t.color, hidden: t.hidden)
                  ..let(to.tags.add)))
            .id,
  ];

  /// [s] into [to]: replacing [replace] (keeping its id), or as a new song
  /// (keeping [s]'s id unless [newId]).
  Song put(
    Song s,
    LibrarySide from,
    LibrarySide to, {
    Song? replace,
    bool newId = false,
    String? title,
  }) {
    final j = s.toJson()..['tags'] = tagsFor(s, from, to);
    if (replace != null) j['id'] = replace.id;
    if (newId) j.remove('id');
    if (title != null) j['title'] = title;
    final copy = Song.fromJson(j);
    if (replace != null) {
      to.songs[to.songs.indexOf(replace)] = copy;
    } else {
      to.songs.add(copy);
    }
    return copy;
  }

  for (final d in diff.songs) {
    final c = diff.choices[d] ?? SyncChoice.skip;
    if (c == SyncChoice.skip) continue;
    if (!d.changed) {
      if (d.here != null && c == SyncChoice.here) {
        toThere[d.here!.id] = put(d.here!, here, there).id;
        toHere[d.here!.id] = d.here!.id;
        r.songsThere++;
      } else if (d.there != null && c == SyncChoice.there) {
        toHere[d.there!.id] = put(d.there!, there, here).id;
        toThere[d.there!.id] = d.there!.id;
        r.songsHere++;
      }
      continue;
    }
    switch (c) {
      case SyncChoice.here:
        put(d.here!, here, there, replace: d.there);
        r.songsThere++;
      case SyncChoice.there:
        put(d.there!, there, here, replace: d.here);
        r.songsHere++;
      case SyncChoice.both:
        // Each side gets the other's version as a copy beside its own.
        put(
          d.there!,
          there,
          here,
          newId: true,
          title: '${d.there!.displayTitle} (${there.name})',
        );
        put(
          d.here!,
          here,
          there,
          newId: true,
          title: '${d.here!.displayTitle} (${here.name})',
        );
        r.songsHere++;
        r.songsThere++;
      case SyncChoice.skip:
        break;
    }
  }

  /// [set] into [to], its songs mapped across (missing ones copied too).
  void putSet(
    Setlist set,
    LibrarySide from,
    LibrarySide to,
    Map<String, String> across, {
    Setlist? replace,
  }) {
    final toIds = {for (final s in to.songs) s.id};
    final entries = <SetEntry>[];
    for (final e in set.entries) {
      final j = e.toJson();
      if (e.type == EntryType.song) {
        var id = across[e.songId];
        if (id == null || !toIds.contains(id)) {
          final song = from.songs.where((s) => s.id == e.songId).firstOrNull;
          if (song == null) continue;
          id = put(song, from, to).id;
          across[song.id] = id;
          toIds.add(id);
        }
        j['songId'] = id;
      }
      entries.add(SetEntry.fromJson(j));
    }
    final j = set.toJson()..['entries'] = [for (final e in entries) e.toJson()];
    if (replace != null) j['id'] = replace.id;
    final copy = Setlist.fromJson(j);
    if (replace != null) {
      to.setlists[to.setlists.indexOf(replace)] = copy;
    } else {
      to.setlists.add(copy);
    }
  }

  for (final d in diff.setlists) {
    final c = diff.choices[d] ?? SyncChoice.skip;
    if (c == SyncChoice.here && d.here != null) {
      putSet(d.here!, here, there, toThere, replace: d.there);
      r.setsThere++;
    } else if (c == SyncChoice.there && d.there != null) {
      putSet(d.there!, there, here, toHere, replace: d.here);
      r.setsHere++;
    }
  }
  return r;
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
