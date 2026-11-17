import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../state.dart' show newId;
import 'protocol.dart';
import 'transport_api.dart';

/// Band Sync over the network directly (installed apps).
BandSyncTransport createBandSyncTransport() => _IoTransport();

class _IoTransport implements BandSyncTransport {
  // ---- Discovery ----

  final _sessions = StreamController<List<BandSyncSession>>.broadcast();
  final Map<String, BandSyncSession> _found = {};
  BonsoirDiscovery? _discovery;

  @override
  Stream<List<BandSyncSession>> get sessions => _sessions.stream;

  @override
  Future<void> scan() async {
    await stopScan();
    _found.clear();
    _sessions.add(const []);
    final d = _discovery = BonsoirDiscovery(type: bandSyncService);
    await d.initialize();
    d.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          event.service.resolve(d.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          _resolved(event.service);
        case BonsoirDiscoveryServiceUpdatedEvent():
          _resolved(event.service);
        case BonsoirDiscoveryServiceLostEvent():
          _found.remove(event.service.name);
          _sessions.add(_found.values.toList());
        default:
          break;
      }
    });
    await d.start();
  }

  void _resolved(BonsoirService s) {
    final host = s.host;
    if (host == null) return;
    _found[s.name] = BandSyncSession(
      leader: s.name,
      title: s.attributes['playlist'] ?? '',
      host: host,
      port: s.port,
    );
    _sessions.add(_found.values.toList());
  }

  @override
  Future<void> stopScan() async {
    final d = _discovery;
    _discovery = null;
    if (d != null) await d.stop();
  }

  // ---- Leading ----

  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  Timer? _ping;
  Map<String, dynamic> _setlistData = const {};
  final Map<Socket, String> _followers = {};
  final _followerNames = StreamController<List<String>>.broadcast();

  @override
  Stream<List<String>> get followers => _followerNames.stream;

  void _followersChanged() => _followerNames.add([
    for (final n in _followers.values)
      if (n.isNotEmpty) n,
  ]);

  @override
  Future<void> lead(String nickname, Map<String, dynamic> setlistData) async {
    await stopLeading();
    _setlistData = setlistData;
    final server = _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    server.listen(_accept);
    _ping = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _send({'type': 'ping'}),
    );
    final b = _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: nickname,
        type: bandSyncService,
        port: server.port,
        attributes: {'playlist': '${setlistData['title'] ?? ''}'},
      ),
    );
    try {
      await b.initialize();
      await b.start();
    } catch (_) {
      // No Bonjour here (or it failed): followers can still join by
      // address; the session just isn't listed.
      _broadcast = null;
    }
  }

  /// The port the session listens on (while leading).
  int? get port => _server?.port;

  void _accept(Socket s) {
    _followers[s] = '';
    final decoder = PtDecoder();
    s.add(ptFrame({'type': 'setlistData', 'setlistData': _setlistData}));
    s.listen(
      (chunk) {
        for (final m in decoder.add(chunk)) {
          if (m['type'] == 'nickname') {
            _followers[s] = '${m['nickname'] ?? ''}';
            _followersChanged();
          }
        }
      },
      onDone: () => _drop(s),
      onError: (_) => _drop(s),
    );
  }

  void _drop(Socket s) {
    if (_followers.remove(s) != null) _followersChanged();
    s.destroy();
  }

  void _send(Map<String, dynamic> m) {
    final f = ptFrame(m);
    for (final s in _followers.keys.toList()) {
      try {
        s.add(f);
      } catch (_) {
        _drop(s);
      }
    }
  }

  @override
  void send(Map<String, dynamic> message) {
    if (message['type'] == 'setlistData') {
      _setlistData = message['setlistData'] as Map<String, dynamic>;
    }
    _send(message);
  }

  @override
  Future<void> stopLeading() async {
    if (_server == null) return;
    _send({'type': 'kick'});
    _ping?.cancel();
    for (final s in _followers.keys.toList()) {
      await s.flush().catchError((_) {});
      s.destroy();
    }
    _followers.clear();
    _followersChanged();
    await _server?.close();
    _server = null;
    final b = _broadcast;
    _broadcast = null;
    if (b != null) await b.stop();
  }

  // ---- Following ----

  Socket? _socket;
  String? _lastCommandId;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> join(String host, int port, String nickname) async {
    _socket?.destroy();
    final s = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 6),
    );
    _socket = s;
    _connected.add(true);
    s.add(ptFrame({'type': 'nickname', 'nickname': nickname}));
    final decoder = PtDecoder();
    s.listen(
      (chunk) {
        for (final m in decoder.add(chunk)) {
          if (m['type'] == 'ping') {
            s.add(ptFrame({'type': 'pong'}));
            continue;
          }
          if (m['type'] == 'command') {
            final id = ptCommandId(m);
            if (id != null && id == _lastCommandId) continue;
            _lastCommandId = id;
          }
          _messages.add(m);
        }
      },
      onDone: () => _lost(s),
      onError: (_) => _lost(s),
    );
  }

  void _lost(Socket s) {
    if (_socket != s) return;
    _socket = null;
    s.destroy();
    _connected.add(false);
  }

  @override
  Future<void> leave() async {
    final s = _socket;
    _socket = null;
    s?.destroy();
  }
}

/// A fresh command id (UPPERCASE UUID v4, as JustChords writes them).
String bandSyncId() => newId().toUpperCase();
