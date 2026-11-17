// Browser features (sync channel, windows, files). The web version is used
// in the app; the stub lets the UI run in `flutter test`.
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';

/// PayPal page for donations toward the app's development.
const donateUrl =
    'https://www.paypal.com/donate/?hosted_button_id=5EP8EM86U9P7Q';
