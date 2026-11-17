// Google Cast for the desktop apps (Linux, Windows, macOS), where Google's
// Cast SDK doesn't exist: finds Chromecasts / Google TVs on the network
// (mDNS, _googlecast._tcp) and talks the Cast protocol to them directly —
// a TLS connection on port 8009 carrying small framed messages (a
// protobuf "CastMessage" with a JSON text payload). Enough to start a
// receiver app (ChordPro Presenter's) and send it messages.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

/// A Cast device found on the network.
class CastTarget {
  final String id;
  final String name;
  final String? model;
  final InternetAddress address;
  final int port;

  const CastTarget({
    required this.id,
    required this.name,
    required this.model,
    required this.address,
    required this.port,
  });
}

/// Finds Cast devices on the local network, again every few seconds.
class CastDiscovery {
  final _found = <String, CastTarget>{};
  final _controller = StreamController<List<CastTarget>>.broadcast();
  Timer? _again;
  bool _looking = false;

  Stream<List<CastTarget>> get devices => _controller.stream;
  List<CastTarget> get current =>
      _found.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  void start() {
    _again ??= Timer.periodic(const Duration(seconds: 8), (_) => _look());
    _look();
  }

  void stop() {
    _again?.cancel();
    _again = null;
  }

  Future<void> _look() async {
    if (_looking) return;
    _looking = true;
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (
            host,
            int port, {
            bool reuseAddress = true,
            bool reusePort = false,
            int ttl = 1,
          }) => RawDatagramSocket.bind(
            host,
            port,
            reuseAddress: true,
            reusePort: !Platform.isWindows,
            ttl: ttl,
          ),
    );
    try {
      await client.start();
      const service = '_googlecast._tcp.local';
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(service),
        timeout: const Duration(seconds: 3),
      )) {
        final instance = ptr.domainName;
        String? name, model, id;
        await for (final txt in client.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(instance),
          timeout: const Duration(seconds: 2),
        )) {
          for (final line in txt.text.split('\n')) {
            final eq = line.indexOf('=');
            if (eq < 0) continue;
            final k = line.substring(0, eq), v = line.substring(eq + 1);
            if (k == 'fn') name = v;
            if (k == 'md') model = v;
            if (k == 'id') id = v;
          }
        }
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(instance),
          timeout: const Duration(seconds: 2),
        )) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            final key = id ?? instance;
            _found[key] = CastTarget(
              id: key,
              name: name ?? instance.split('.').first,
              model: model,
              address: ip.address,
              port: srv.port,
            );
            _controller.add(current);
            break;
          }
          break;
        }
      }
    } catch (_) {
      // No network (or mDNS blocked): try again next round.
    } finally {
      client.stop();
      _looking = false;
    }
  }
}

/// A connection to one Cast device, with a receiver app started on it.
class CastSession {
  static const _connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const _heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _receiver = 'urn:x-cast:com.google.cast.receiver';
  static const _sender = 'sender-0';

  final SecureSocket _socket;
  final void Function() onClosed;
  final _buffer = BytesBuilder();
  Timer? _ping;
  int _requestId = 0;
  String? _transport;
  String? _sessionId;
  final _statuses = StreamController<Map<String, dynamic>>.broadcast();
  bool _closed = false;

  CastSession._(this._socket, this.onClosed) {
    _socket.listen(
      _onData,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  /// Connects to [target] and starts receiver app [appId] on it.
  static Future<CastSession> start(
    CastTarget target,
    String appId, {
    required void Function() onClosed,
  }) async {
    final socket = await SecureSocket.connect(
      target.address,
      target.port,
      // Cast devices use their own certificates.
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 6),
    );
    final session = CastSession._(socket, onClosed);
    try {
      await session._launch(appId);
    } catch (_) {
      session.close();
      rethrow;
    }
    return session;
  }

  Future<void> _launch(String appId) async {
    _send(_connection, 'receiver-0', {'type': 'CONNECT'});
    _ping = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _send(_heartbeat, 'receiver-0', {'type': 'PING'}),
    );
    final running = _statuses.stream
        .map((status) {
          final apps = (status['applications'] as List?) ?? const [];
          for (final a in apps) {
            if (a is Map && a['appId'] == appId) return a;
          }
          return null;
        })
        .firstWhere((a) => a != null)
        .timeout(const Duration(seconds: 25));
    _send(_receiver, 'receiver-0', {
      'type': 'LAUNCH',
      'appId': appId,
      'requestId': ++_requestId,
    });
    final app = (await running)!;
    _transport = app['transportId'] as String;
    _sessionId = app['sessionId'] as String?;
    _send(_connection, _transport!, {'type': 'CONNECT'});
  }

  /// Sends a JSON text message to the receiver app on [namespace].
  bool send(String namespace, String json) {
    final to = _transport;
    if (to == null || _closed) return false;
    _sendRaw(namespace, to, json);
    return true;
  }

  /// Stops the receiver app and closes the connection.
  Future<void> stop() async {
    if (!_closed && _sessionId != null) {
      _send(_receiver, 'receiver-0', {
        'type': 'STOP',
        'sessionId': _sessionId,
        'requestId': ++_requestId,
      });
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _ping?.cancel();
    _socket.destroy();
    _statuses.close();
  }

  void _send(String namespace, String to, Map<String, Object?> message) =>
      _sendRaw(namespace, to, jsonEncode(message));

  void _sendRaw(String namespace, String to, String payload) {
    if (_closed) return;
    final body = _encode(
      source: _sender,
      destination: to,
      namespace: namespace,
      payload: payload,
    );
    final frame = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(body);
    _socket.add(frame.takeBytes());
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.toBytes();
    var at = 0;
    while (bytes.length - at >= 4) {
      final n = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
      if (bytes.length - at - 4 < n) break;
      _onMessage(_decode(bytes.sublist(at + 4, at + 4 + n)));
      at += 4 + n;
    }
    _buffer.clear();
    if (at < bytes.length) _buffer.add(bytes.sublist(at));
  }

  void _onMessage(_Message m) {
    if (m.payload == null) return;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(m.payload!) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch ((m.namespace, json['type'])) {
      case (_heartbeat, 'PING'):
        _send(_heartbeat, m.source, {'type': 'PONG'});
      case (_receiver, 'RECEIVER_STATUS'):
        final status = json['status'];
        if (status is Map<String, dynamic>) {
          if (!_statuses.isClosed) _statuses.add(status);
          // Our app is no longer running (stopped from the TV / another
          // phone): the session is over.
          final apps = (status['applications'] as List?) ?? const [];
          if (_transport != null &&
              !apps.any((a) => a is Map && a['transportId'] == _transport)) {
            _onDone();
          }
        }
      case (_connection, 'CLOSE'):
        if (m.source == _transport || m.source == 'receiver-0') _onDone();
    }
  }

  void _onDone() {
    if (_closed) return;
    close();
    onClosed();
  }

  // ---- The CastMessage protobuf, by hand (six fields) ----

  static Uint8List _encode({
    required String source,
    required String destination,
    required String namespace,
    required String payload,
  }) {
    final out = BytesBuilder();
    void varint(int v) {
      while (v >= 0x80) {
        out.addByte((v & 0x7F) | 0x80);
        v >>= 7;
      }
      out.addByte(v);
    }

    void text(int field, String s) {
      final b = utf8.encode(s);
      varint(field << 3 | 2);
      varint(b.length);
      out.add(b);
    }

    varint(1 << 3); // protocol_version = CASTV2_1_0 (0)
    varint(0);
    text(2, source);
    text(3, destination);
    text(4, namespace);
    varint(5 << 3); // payload_type = STRING (0)
    varint(0);
    text(6, payload);
    return out.takeBytes();
  }

  static _Message _decode(Uint8List b) {
    var i = 0;
    int varint() {
      var v = 0, shift = 0;
      while (i < b.length) {
        final x = b[i++];
        v |= (x & 0x7F) << shift;
        if (x < 0x80) break;
        shift += 7;
      }
      return v;
    }

    String? source, destination, namespace, payload;
    while (i < b.length) {
      final tag = varint();
      final field = tag >> 3, wire = tag & 7;
      if (wire == 0) {
        varint();
      } else if (wire == 2) {
        final n = varint();
        final value = b.sublist(i, i + n);
        i += n;
        String s() => utf8.decode(value, allowMalformed: true);
        switch (field) {
          case 2:
            source = s();
          case 3:
            destination = s();
          case 4:
            namespace = s();
          case 6:
            payload = s();
        }
      } else {
        break; // not used by Cast messages
      }
    }
    return _Message(source ?? '', destination ?? '', namespace ?? '', payload);
  }
}

class _Message {
  final String source, destination, namespace;
  final String? payload;
  const _Message(this.source, this.destination, this.namespace, this.payload);
}
