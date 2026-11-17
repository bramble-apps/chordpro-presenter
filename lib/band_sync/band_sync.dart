// Band Sync: play together with other devices on the same network —
// JustChords' PlayTogether (iPads and Macs running JustChords) and other
// copies of this app. One device leads a setlist; the others follow its
// song, section and scrolling. See protocol.dart for the wire format.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library_import.dart';
import '../state.dart';
import 'protocol.dart';
import 'transport.dart';

enum BandSyncRole { idle, leading, following }

class BandSync extends ChangeNotifier {
  final PresenterModel model;
  final BandSyncTransport _t;

  BandSync(this.model, {BandSyncTransport? transport})
    : _t = transport ?? createBandSyncTransport() {
    _t.sessions.listen((s) {
      sessions = s;
      notifyListeners();
    });
    _t.followers.listen((f) {
      followers = f;
      notifyListeners();
    });
    _t.messages.listen(_onMessage);
    _t.connected.listen(_onConnected);
  }

  BandSyncRole role = BandSyncRole.idle;

  /// Sessions led by others on the network.
  List<BandSyncSession> sessions = const [];
  bool scanning = false;

  /// What's going on, in a few words ("Leader online"…), or a problem.
  String? status;
  String? error;

  /// The name others see.
  String get nickname {
    final n = model.settings.bandNickname.trim();
    if (n.isNotEmpty) return n;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPad',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux',
      _ => 'ChordPro Presenter',
    };
  }

  Timer? _scanSpinner;

  /// Looks for sessions (keeps listening for new ones; "scanning" only
  /// shows for the first few seconds).
  Future<void> scan() async {
    error = null;
    scanning = true;
    notifyListeners();
    _scanSpinner?.cancel();
    _scanSpinner = Timer(const Duration(seconds: 8), () {
      scanning = false;
      notifyListeners();
    });
    try {
      await _t.scan();
    } catch (e) {
      error = 'Couldn’t look for sessions: $e';
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    scanning = false;
    notifyListeners();
    try {
      await _t.stopScan();
    } catch (_) {}
  }

  // ---- Leading ----

  /// The setlist being led, and its followers' nicknames.
  String? leadingSetlistId;
  List<String> followers = const [];

  Setlist? get leadingSetlist => model.setlistById(leadingSetlistId);

  String? _sentData;
  String? _sentEntry;
  int _sentSection = 0;
  Timer? _scrollTimer;
  double? _pendingScroll;
  bool _autoscrolling = false;

  Map<String, dynamic> _setlistData(Setlist set) =>
      ptSetlistData(set, model.songById);

  /// What decides whether the setlist changed: its JSON without dates
  /// (an undated song or setlist gets "now" each time).
  static String _fingerprint(Map<String, dynamic> data) => jsonEncode({
    ...data,
    'date': null,
    'songs': [
      for (final s in (data['songs'] as List? ?? const []))
        if (s is Map) {...s, 'date': null},
    ],
  });

  /// Leads [set]: devices on the network can join and will follow.
  Future<void> lead(Setlist set) async {
    await leave();
    error = null;
    final data = _setlistData(set);
    try {
      await _t.lead(nickname, data);
    } catch (e) {
      error = 'Couldn’t start the session: $e';
      notifyListeners();
      return;
    }
    role = BandSyncRole.leading;
    leadingSetlistId = set.id;
    _sentData = _fingerprint(data);
    _sentEntry = null;
    status = 'Leading “${set.name}”';
    model.addListener(_leaderUpdate);
    model.selection.addListener(_leaderUpdate);
    model.autoscroll.addListener(_leaderAutoscroll);
    model.autoscroll.scrolled.addListener(_leaderScrolled);
    notifyListeners();
    _leaderUpdate();
  }

  Future<void> stopLeading() async {
    if (role != BandSyncRole.leading) return;
    model.removeListener(_leaderUpdate);
    model.selection.removeListener(_leaderUpdate);
    model.autoscroll.removeListener(_leaderAutoscroll);
    model.autoscroll.scrolled.removeListener(_leaderScrolled);
    _scrollTimer?.cancel();
    role = BandSyncRole.idle;
    leadingSetlistId = null;
    followers = const [];
    status = null;
    notifyListeners();
    try {
      await _t.stopLeading();
    } catch (_) {}
  }

  /// The JustChords sections of each part of the open song.
  List<List<int>> get _sections => jcSectionsOfParts(model.parts);

  int get _currentSection {
    final part = model.selectedPart;
    final s = _sections;
    if (part < 0 || part >= s.length || s[part].isEmpty) return 0;
    final nested = model.nestedSongOfPart(part);
    if (nested == 0 && model.activeEntry?.subSongIds.isEmpty != false) {
      return s[part].first;
    }
    // In songs nested together: counted within its own song only.
    final before = <int>{
      for (var i = 0; i < part; i++)
        if (model.nestedSongOfPart(i) == nested) ...s[i],
    }..removeAll(s[part]);
    return before.length;
  }

  /// The setlist changed, or another song / part was opened: tell the
  /// followers.
  void _leaderUpdate() {
    final set = leadingSetlist;
    if (set == null) {
      // The setlist was deleted: the session ends.
      stopLeading();
      return;
    }
    final data = _setlistData(set);
    final json = _fingerprint(data);
    if (json != _sentData) {
      _sentData = json;
      _t.send({'type': 'setlistData', 'setlistData': data});
    }
    if (model.activeSetlistId != set.id) return;
    // Followers have songs nested under another as entries of their own:
    // the one playing now, and where in it.
    final nested = model.nestedSongOfPart(model.selectedPart);
    final flat = set.flattened(model.songById);
    final at = flat.entries.indexWhere((e) => e.id == model.activeEntryId);
    if (at < 0) return;
    final index = at + nested;
    final entryId = flat.entries[index].id;
    final song = model.songById(flat.entries[index].songId ?? '');
    if (song == null) return;
    final section = _currentSection;
    if (entryId != _sentEntry) {
      _sentEntry = entryId;
      _t.send(
        ptCommand('gotoPlaylistIndexAndSection', [
          index,
        ], song.id.toUpperCase()),
      );
      if (section > 0) _goToSection(section);
      _sentSection = section;
      return;
    }
    if (section == _sentSection) return;
    final delta = section - _sentSection;
    if (delta.abs() <= 3) {
      for (var i = 0; i < delta.abs(); i++) {
        _t.send(
          ptCommand(
            delta > 0 ? 'nextSongSection' : 'previousSongSection',
            const [],
            _id(),
          ),
        );
      }
    } else {
      _goToSection(section);
    }
    _sentSection = section;
  }

  void _goToSection(int section) {
    _t.send(ptCommand('firstSongSection', const [], _id()));
    for (var i = 0; i < section; i++) {
      _t.send(ptCommand('nextSongSection', const [], _id()));
    }
  }

  void _leaderAutoscroll() {
    final a = model.autoscroll;
    if (a.running == _autoscrolling) return;
    _autoscrolling = a.running;
    if (a.running) {
      _t.send({
        'type': 'startAutoscroll',
        'autoscrollFromOffset': a.progress.value,
        'autoscrollToOffset': 1,
        'autoscrollDuration': a.remaining,
      });
    } else {
      _t.send({'type': 'stopAutoscroll', 'scrollOffset': a.scrolled.value});
    }
  }

  /// Scrolling: shared about 10 times a second (not while autoscrolling:
  /// the followers scroll by themselves then).
  void _leaderScrolled() {
    if (model.autoscroll.running) return;
    _pendingScroll = model.autoscroll.scrolled.value;
    _scrollTimer ??= Timer(const Duration(milliseconds: 100), () {
      _scrollTimer = null;
      final at = _pendingScroll;
      if (at != null && role == BandSyncRole.leading) {
        _t.send({'type': 'scrollTo', 'scrollOffset': at});
      }
    });
  }

  String _id() => newId().toUpperCase();

  // ---- Following ----

  /// The session being followed.
  BandSyncSession? leader;

  /// The leader's section (JustChords counts each section; a linked pair
  /// shows here as one slide).
  int _section = 0;
  bool _leaving = false;
  Timer? _retry;
  DateTime? _lostAt;

  Future<void> join(BandSyncSession session) async {
    await leave();
    error = null;
    try {
      await _t.join(session.host, session.port, nickname);
    } catch (e) {
      error = 'Couldn’t join: $e';
      notifyListeners();
      return;
    }
    leader = session;
    role = BandSyncRole.following;
    status = 'Leader online';
    unawaited(stopScan());
    notifyListeners();
  }

  /// Leaves the session (leading or following).
  Future<void> leave({String? reason}) async {
    if (role == BandSyncRole.leading) return stopLeading();
    if (role != BandSyncRole.following) return;
    _leaving = true;
    _retry?.cancel();
    _retry = null;
    role = BandSyncRole.idle;
    leader = null;
    status = reason;
    model.setBandSetlist(null, const []);
    notifyListeners();
    try {
      await _t.leave();
    } catch (_) {}
    _leaving = false;
  }

  void _onConnected(bool up) {
    if (role != BandSyncRole.following || _leaving) return;
    if (up) {
      _lostAt = null;
      status = 'Leader online';
      notifyListeners();
      return;
    }
    // Dropped: try again every few seconds for about a minute (as
    // JustChords does).
    _lostAt ??= DateTime.now();
    status = 'Leader offline — reconnecting…';
    notifyListeners();
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), () async {
      final s = leader;
      if (s == null || role != BandSyncRole.following) return;
      if (DateTime.now().difference(_lostAt!) > const Duration(minutes: 1)) {
        await leave(reason: 'Leader offline');
        return;
      }
      try {
        await _t.join(s.host, s.port, nickname);
      } catch (_) {
        _onConnected(false);
      }
    });
  }

  void _onMessage(Map<String, dynamic> m) {
    if (role != BandSyncRole.following) return;
    switch (m['type']) {
      case 'setlistData':
        final data = m['setlistData'];
        if (data is Map<String, dynamic>) _takeSetlist(data);
      case 'command':
        _command(m);
      case 'scrollTo':
        final at = (m['scrollOffset'] as num?)?.toDouble();
        if (at != null) model.autoscroll.seek.value = at;
      case 'startAutoscroll':
        model.autoscroll.startFrom(
          (m['autoscrollFromOffset'] as num?)?.toDouble() ?? 0,
          (m['autoscrollToOffset'] as num?)?.toDouble() ?? 1,
          (m['autoscrollDuration'] as num?)?.toDouble() ?? 90,
        );
      case 'stopAutoscroll':
        model.autoscroll.stop();
        final at = (m['scrollOffset'] as num?)?.toDouble();
        if (at != null) model.autoscroll.seek.value = at;
      case 'kick':
        leave(reason: 'Disconnected by leader');
    }
  }

  /// The leader's setlist, kept apart from the library (its ids prefixed,
  /// so the same songs in both never mix).
  static const _prefix = 'band:';

  void _takeSetlist(Map<String, dynamic> data) {
    final (set, songs) = parseJustChordsSetlist(data);
    final band = Setlist(
      id: '${_prefix}setlist',
      name: set.name,
      setSpecific: set.setSpecific,
      entries: [
        for (final e in set.entries)
          SetEntry(
            id: '$_prefix${e.id}',
            type: e.type,
            songId: e.songId == null ? null : '$_prefix${e.songId}',
            title: e.title,
            color: e.color,
            transpose: e.transpose,
            capo: e.capo,
            structure: e.structure,
          ),
      ],
    );
    final copies = [
      for (final s in songs)
        Song.fromJson({...s.toJson(), 'id': '$_prefix${s.id}'}),
    ];
    model.setBandSetlist(band, copies);
  }

  void _command(Map<String, dynamic> m) {
    final set = model.bandSetlist;
    if (set == null) return;
    switch (ptCommandName(m)) {
      case 'gotoPlaylistIndexAndSection':
        final data = ptCommandData(m);
        final id = ptCommandId(m)?.toUpperCase();
        var index = data.isNotEmpty ? data.first : -1;
        if (index < 0 || index >= set.entries.length) {
          index = set.entries.indexWhere(
            (e) => e.songId?.substring(_prefix.length).toUpperCase() == id,
          );
        }
        if (index < 0) return;
        final entry = set.entries[index];
        if (entry.type != EntryType.song) return;
        model.selectEntry(set, entry);
        _showSection(0);
      case 'nextSongSection':
        _showSection(_section + 1);
      case 'previousSongSection':
        _showSection(_section - 1);
      case 'firstSongSection':
        _showSection(0);
      case 'lastSongSection':
        _showSection(jcSectionCount(_sections) - 1);
      case 'nextSong':
        _stepSong(set, 1);
      case 'previousSong':
        _stepSong(set, -1);
    }
  }

  void _showSection(int section) {
    final s = _sections;
    final count = jcSectionCount(s);
    _section = section.clamp(0, count == 0 ? 0 : count - 1);
    final part = partOfSection(s, _section);
    final slide = model.slidePartIndex.indexOf(part);
    if (slide >= 0) model.goTo(slide);
  }

  void _stepSong(Setlist set, int dir) {
    var i = set.entries.indexWhere((e) => e.id == model.activeEntryId);
    while (true) {
      i += dir;
      if (i < 0 || i >= set.entries.length) return;
      if (set.entries[i].type == EntryType.song) break;
    }
    model.selectEntry(set, set.entries[i]);
    _showSection(0);
  }

  @override
  void dispose() {
    _scanSpinner?.cancel();
    _retry?.cancel();
    _scrollTimer?.cancel();
    super.dispose();
  }
}
