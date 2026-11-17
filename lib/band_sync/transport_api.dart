/// A Band Sync session someone is leading on the network.
class BandSyncSession {
  /// The leader's nickname, and the setlist's title.
  final String leader;
  final String title;
  final String host;
  final int port;

  const BandSyncSession({
    required this.leader,
    required this.title,
    required this.host,
    required this.port,
  });

  String get key => '$host:$port';

  Map<String, dynamic> toJson() => {
    'leader': leader,
    'title': title,
    'host': host,
    'port': port,
  };

  static BandSyncSession? fromJson(Object? j) => j is Map && j['port'] is num
      ? BandSyncSession(
          leader: '${j['leader'] ?? ''}',
          title: '${j['title'] ?? ''}',
          host: '${j['host'] ?? ''}',
          port: (j['port'] as num).toInt(),
        )
      : null;
}

/// Talks to other Band Sync / JustChords PlayTogether devices.
abstract class BandSyncTransport {
  /// Sessions found on the network (while scanning).
  Stream<List<BandSyncSession>> get sessions;
  Future<void> scan();
  Future<void> stopScan();

  // ---- Leading ----

  /// Starts a session: listens, advertises it, and sends [setlistData] to
  /// each follower that joins.
  Future<void> lead(String nickname, Map<String, dynamic> setlistData);

  /// Sends [message] to every follower (a new `setlistData` is also kept
  /// for followers joining later).
  void send(Map<String, dynamic> message);

  /// The followers' nicknames.
  Stream<List<String>> get followers;
  Future<void> stopLeading();

  // ---- Following ----

  Future<void> join(String host, int port, String nickname);

  /// Messages from the leader (pings are answered, repeated commands
  /// dropped).
  Stream<Map<String, dynamic>> get messages;

  /// False when the connection to the leader dropped.
  Stream<bool> get connected;
  Future<void> leave();
}
