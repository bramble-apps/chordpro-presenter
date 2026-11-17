// Draws a dynamic background's frames without holding up the screen: on
// another thread in the installed apps, a few rows at a time in the browser
// (which has no threads for this).
export 'dynamic_frames_main.dart'
    if (dart.library.io) 'dynamic_frames_isolate.dart';
