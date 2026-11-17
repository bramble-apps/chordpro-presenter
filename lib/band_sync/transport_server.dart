import 'dart:async';

import '../browser.dart';
import 'transport_api.dart';

/// Band Sync through the app's local server (tools/serve.py): a browser
/// can't use Bonjour or TCP itself, so the server does, and the page
/// follows along by asking it for news (long polling).
BandSyncTransport createBandSyncTransport() => _ServerTransport();

class _ServerTransport implements BandSyncTransport {
  final _sessions = StreamController<List<BandSyncSession>>.broadcast();
  final _followers = StreamController<List<String>>.broadcast();
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  int _seq = -1;
  bool _polling = false;
  int _users = 0;

  @override
  Stream<List<BandSyncSession>> get sessions => _sessions.stream;
  @override
  Stream<List<String>> get followers => _followers.stream;
  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<bool> get connected => _connected.stream;

  Future<Object?> _post(String what, [Map<String, dynamic> body = const {}]) =>
      localServer('bandsync/$what', post: body);

  /// Listens for news while something is going on (scan, lead, follow).
  Future<void> _start() async {
    _users++;
    if (_polling) return;
    _polling = true;
    if (_seq < 0) {
      // Only news from now on.
      try {
        final r = await localServer('bandsync/events?after=999999999&wait=0');
        if (r is Map) _seq = (r['seq'] as num?)?.toInt() ?? 0;
      } catch (_) {
        _seq = 0;
      }
    }
    while (_users > 0) {
      try {
        final r = await localServer('bandsync/events?after=$_seq');
        if (r is! Map) continue;
        _seq = (r['seq'] as num?)?.toInt() ?? _seq;
        for (final e in (r['events'] as List?) ?? const []) {
          if (e is Map) _event(e);
        }
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    _polling = false;
  }

  void _stop() {
    if (_users > 0) _users--;
  }

  void _event(Map e) {
    switch (e['kind']) {
      case 'sessions':
        _sessions.add([
          for (final s in (e['sessions'] as List?) ?? const [])
            ?BandSyncSession.fromJson(s),
        ]);
      case 'followers':
        _followers.add([
          for (final n in (e['followers'] as List?) ?? const []) '$n',
        ]);
      case 'message':
        final m = e['message'];
        if (m is Map<String, dynamic>) _messages.add(m);
      case 'connected':
        _connected.add(e['value'] == true);
    }
  }

  bool _scanning = false;

  @override
  Future<void> scan() async {
    if (!_scanning) {
      _scanning = true;
      unawaited(_start());
    }
    await _post('scan');
  }

  @override
  Future<void> stopScan() async {
    if (_scanning) {
      _scanning = false;
      _stop();
    }
    await _post('stopscan');
  }

  bool _leading = false;

  @override
  Future<void> lead(String nickname, Map<String, dynamic> setlistData) async {
    if (!_leading) {
      _leading = true;
      unawaited(_start());
    }
    await _post('lead', {'nickname': nickname, 'setlistData': setlistData});
  }

  @override
  void send(Map<String, dynamic> message) =>
      unawaited(_post('send', {'message': message}).catchError((_) => null));

  @override
  Future<void> stopLeading() async {
    if (_leading) {
      _leading = false;
      _stop();
    }
    await _post('stoplead');
  }

  bool _following = false;

  @override
  Future<void> join(String host, int port, String nickname) async {
    if (!_following) {
      _following = true;
      unawaited(_start());
    }
    await _post('join', {'host': host, 'port': port, 'nickname': nickname});
  }

  @override
  Future<void> leave() async {
    if (_following) {
      _following = false;
      _stop();
    }
    await _post('leave');
  }
}
