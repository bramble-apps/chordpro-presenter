// The installed apps' extras (device storage, Chromecast, sounds, YouTube
// player). The web app gets do-nothing stand-ins so it never pulls in
// dart:io code.
export 'native_none.dart' if (dart.library.io) 'native_io.dart';
