// How Band Sync reaches other devices. The installed apps (Android,
// desktop) use sockets and Bonjour directly; the web app (and the Linux app,
// which runs it) goes through its local server, tools/serve.py.

export 'transport_api.dart';
export 'transport_io.dart' if (dart.library.js_interop) 'transport_server.dart';
