// Settings for what the projector window shows.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'dynamic_bg.dart';
import 'format.dart';

enum ProjectionView { lyrics, stage }

/// Dynamic: a moving wallpaper (see dynamic_bg.dart).
enum BackgroundType { color, media, dynamic }

enum MediaFit { fill, fit }

/// Section: one part at a time. Song: the whole song's lyrics, current part
/// highlighted.
enum TextMode { section, song }

enum HAlign { left, center, right }

enum VAlign { top, center, bottom }

enum Corner { topLeft, topRight, bottomLeft, bottomRight }

// ---- A song's opening slides ----
// Before a song's lyrics: a blank slide (just the background) and a title
// slide (title and artist), each optional. They are slides of their own,
// with no part of the song behind them.

const String _intro = '\u2063'; // invisible separator: never in lyrics

/// The blank slide's text.
const String blankSlide = '${_intro}blank';

/// A title slide's text ([title], then [artist] if any).
String titleSlide(String title, String artist) =>
    '${_intro}title\n$title\n$artist';

bool isBlankSlide(String slide) => slide == blankSlide;

/// (title, artist) of a title slide, or null.
(String, String)? titleSlideOf(String slide) {
  if (!slide.startsWith('${_intro}title\n')) return null;
  final lines = slide.split('\n');
  return (lines.length > 1 ? lines[1] : '', lines.length > 2 ? lines[2] : '');
}

/// A blank or title slide (not lyrics).
bool isIntroSlide(String slide) => slide.startsWith(_intro);

/// How many opening slides [slides] start with.
int introCount(List<String> slides) {
  var n = 0;
  while (n < slides.length && isIntroSlide(slides[n])) {
    n++;
  }
  return n;
}

/// The words on [slide], for text exports (a title slide: its title and
/// artist; the blank slide: nothing).
String slideWords(String slide) {
  if (isBlankSlide(slide)) return '';
  final t = titleSlideOf(slide);
  if (t == null) return slide;
  return [t.$1, if (t.$2.isNotEmpty) t.$2].join('\n');
}

/// Which slides of a song show a footer item.
enum OnSlides {
  off('Off'),
  first('First'),
  last('Last'),
  every('Every');

  final String label;
  const OnSlides(this.label);

  /// Shown on slide [index] of [count]?
  bool shows(int index, int count) => switch (this) {
    off => false,
    first => index == 0,
    last => index == count - 1,
    every => true,
  };

  /// Saved as its name (older files: true / false).
  static OnSlides from(Object? v, OnSlides fallback) => switch (v) {
    true => every,
    false => off,
    final String name => values.asNameMap()[name] ?? fallback,
    _ => fallback,
  };
}

/// Where the countdown timer sits on the projector.
enum TimerPlace {
  topLeft,
  top,
  topRight,
  left,
  center,
  right,
  bottomLeft,
  bottom,
  bottomRight;

  Alignment get alignment => switch (this) {
    topLeft => Alignment.topLeft,
    top => Alignment.topCenter,
    topRight => Alignment.topRight,
    left => Alignment.centerLeft,
    center => Alignment.center,
    right => Alignment.centerRight,
    bottomLeft => Alignment.bottomLeft,
    bottom => Alignment.bottomCenter,
    bottomRight => Alignment.bottomRight,
  };

  String get label => switch (this) {
    topLeft => 'Top left',
    top => 'Top',
    topRight => 'Top right',
    left => 'Left',
    center => 'Centre',
    right => 'Right',
    bottomLeft => 'Bottom left',
    bottom => 'Bottom',
    bottomRight => 'Bottom right',
  };
}

/// The countdown as last told to a screen: [ms] left at [at] (that screen's
/// own clock), so each screen counts down by itself between messages.
class CountdownState {
  final int ms;
  final bool running;

  /// Started (and not reset): shown on the projector.
  final bool active;
  final DateTime at;

  CountdownState({
    required this.ms,
    required this.running,
    required this.active,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  int get remainingMs => running
      ? math.max(0, ms - DateTime.now().difference(at).inMilliseconds)
      : ms;

  Map<String, dynamic> toJson() => {
    'ms': remainingMs,
    'running': running,
    'active': active,
  };

  static CountdownState? fromJson(Object? j) => j is Map<String, dynamic>
      ? CountdownState(
          ms: (j['ms'] as num?)?.toInt() ?? 0,
          running: j['running'] as bool? ?? false,
          active: j['active'] as bool? ?? false,
        )
      : null;
}

/// "4:59", or "1:02:03" for an hour or more (rounding up, so 0:00 only
/// shows when time is really up).
String formatCountdown(int ms) {
  final total = (ms / 1000).ceil();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

enum StageScheme { dark, light }

/// Stage view layouts: the whole chord sheet following along (classic), or
/// the current part large with the next one beside it, the song's parts
/// down the side and the time (modern).
enum StageLayout { classic, modern }

/// An uploaded image or video. The file itself lives in browser storage
/// under [storageKey].
class MediaRef {
  final String id;
  final String name;
  final String mime;

  /// Stored by the local server (served at `media/<id>`), rather than in
  /// this browser.
  final bool server;
  const MediaRef(this.id, this.name, this.mime, {this.server = false});

  bool get isVideo => mime.startsWith('video/');
  String get storageKey => 'media:$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mime': mime,
    if (server) 'server': true,
  };
  static MediaRef? fromJson(Object? j) => j is Map
      ? MediaRef(
          j['id'] as String,
          j['name'] as String,
          j['mime'] as String,
          server: j['server'] == true,
        )
      : null;
}

class ProjectionSettings {
  ProjectionView view = ProjectionView.lyrics;

  // ---- Lyrics view: background ----
  BackgroundType bgType = BackgroundType.color;
  Color bgColor = const Color(0xFF000000);
  MediaRef? bgMedia;
  MediaFit bgFit = MediaFit.fill;

  /// The moving wallpaper shown when [bgType] is dynamic.
  DynamicBg bgDynamic = DynamicBg();

  /// The operator's preview plays it too (the projector always does).
  bool bgDynamicPreview = true;

  /// Seconds to cross-fade when the background changes.
  double bgTransition = 1.0;

  /// A colour layer over the background to darken (or tint) it.
  Color bgDimColor = const Color(0xFF000000);
  int bgDim = 0; // % opacity

  // ---- Lyrics view: gradient overlay (over the background, under text) ----
  bool gradient = false;

  /// Two colours, or one colour fading to transparent.
  bool gradientTwoColors = false;
  Color gradientColor1 = const Color(0xFF000000);
  int gradientOpacity1 = 100;
  Color gradientColor2 = const Color(0xFF000000);
  int gradientOpacity2 = 0;

  /// Direction like CSS: 0° = towards the top, 90° = towards the right.
  int gradientAngle = 0;

  // ---- Lyrics view: text ----
  TextMode textMode = TextMode.section;

  /// Largest text size, in pixels on a 1080-pixel-tall screen (scales with
  /// the projector's real size). Text shrinks below this to fit.
  int textSize = 80;
  Color textColor = const Color(0xFFFFFFFF);
  bool textBold = true;
  bool textItalic = false;
  bool textCaps = false;
  bool textShadow = true;

  /// Space between lines, in % of normal (100).
  int textLineSpacing = 100;
  HAlign textAlign = HAlign.center;
  VAlign textPosition = VAlign.center;

  /// Remove " - ", lone "-" lines and double spaces from projected lyrics.
  bool tidyLyrics = true;

  // ---- Lyrics view: overlays ----
  MediaRef? logo;
  Corner logoCorner = Corner.bottomRight;

  /// Logo height, % of screen height.
  int logoSize = 12;
  bool footer = false;

  /// Before each song: a blank slide (only the background), then a slide
  /// with its title and artist.
  bool blankSlide = true;
  bool titleSlide = true;

  /// Each footer item, on which slides: the title, copyright, CCLI numbers
  /// and the song's own footer text.
  OnSlides footerTitle = OnSlides.every;
  OnSlides footerCopyright = OnSlides.every;
  OnSlides footerCcli = OnSlides.every;
  OnSlides footerText = OnSlides.every;

  /// Underscan: the picture shrunk inside the screen (for projectors and
  /// TVs that cut off the edges). [underscanW] / [underscanH]: its size in
  /// % of the screen's (the same when [underscanLocked], keeping the
  /// screen's shape); [underscanX] / [underscanY]: where it sits (-1 left /
  /// top … 1 right / bottom).
  bool underscan = false;
  int underscanW = 90;
  int underscanH = 90;
  bool underscanLocked = true;
  double underscanX = 0;
  double underscanY = 0;

  /// Shown instead of plain black while blacked out (null = black).
  MediaRef? blackoutMedia;

  /// How linked sections (a verse's translation…) look on the projector.
  final LinkedStyle linked = LinkedStyle();

  // ---- Countdown timer ----
  bool timerShow = true;

  /// Digit height, % of screen height.
  int timerSize = 10;
  TimerPlace timerPlace = TimerPlace.bottomRight;
  Color timerColor = const Color(0xFFFFFFFF);
  bool timerBold = true;
  bool timerItalic = false;
  bool timerShadow = true;

  /// Font for the timer ('' = same as the slides).
  String timerFont = '';

  // ---- Stage view ----
  StageLayout stageLayout = StageLayout.classic;

  /// Modern layout: fade between parts.
  bool stageFade = true;

  /// Modern layout: each kind of part (verse, chorus, bridge…) in its own
  /// colour in the parts list, or black and white.
  bool stageColourLabels = true;

  /// Modern layout: width of the parts list, % (0 hides it; the song's
  /// window gets the room it gives up).
  int stagePartsWidth = 100;
  StageScheme stageScheme = StageScheme.dark;

  /// Text size, % (100 = comfortable on a 1080p monitor).
  int stageTextSize = 85;

  /// Side margins, % of width.
  int stageMargin = 0;
  bool stageHeader = true;
  int stageHeaderSize = 100;
  bool stageFooter = true;
  int stageFooterSize = 100;

  List<MediaRef> get media => [?bgMedia, ?logo, ?blackoutMedia];

  Map<String, dynamic> toJson() => {
    'view': view.name,
    'bgType': bgType.name,
    'bgColor': bgColor.toARGB32(),
    'bgMedia': bgMedia?.toJson(),
    'bgFit': bgFit.name,
    'bgDynamic': bgDynamic.toJson(),
    'bgDynamicPreview': bgDynamicPreview,
    'bgTransition': bgTransition,
    'bgDimColor': bgDimColor.toARGB32(),
    'bgDim': bgDim,
    'gradient': gradient,
    'gradientTwoColors': gradientTwoColors,
    'gradientColor1': gradientColor1.toARGB32(),
    'gradientOpacity1': gradientOpacity1,
    'gradientColor2': gradientColor2.toARGB32(),
    'gradientOpacity2': gradientOpacity2,
    'gradientAngle': gradientAngle,
    'textMode': textMode.name,
    'textSize': textSize,
    'textColor': textColor.toARGB32(),
    'textBold': textBold,
    'textItalic': textItalic,
    'textCaps': textCaps,
    'textShadow': textShadow,
    'textLineSpacing': textLineSpacing,
    'textAlign': textAlign.name,
    'textPosition': textPosition.name,
    'tidyLyrics': tidyLyrics,
    'logo': logo?.toJson(),
    'logoCorner': logoCorner.name,
    'logoSize': logoSize,
    'footer': footer,
    'blankSlide': blankSlide,
    'titleSlide': titleSlide,
    'footerTitle': footerTitle.name,
    'footerCopyright': footerCopyright.name,
    'footerCcli': footerCcli.name,
    'footerText': footerText.name,
    'underscan': underscan,
    'underscanW': underscanW,
    'underscanH': underscanH,
    'underscanLocked': underscanLocked,
    'underscanX': underscanX,
    'underscanY': underscanY,
    'blackoutMedia': blackoutMedia?.toJson(),
    'linked': linked.toJson(),
    'timerShow': timerShow,
    'timerSize': timerSize,
    'timerPlace': timerPlace.name,
    'timerColor': timerColor.toARGB32(),
    'timerBold': timerBold,
    'timerItalic': timerItalic,
    'timerShadow': timerShadow,
    'timerFont': timerFont,
    'stageLayout': stageLayout.name,
    'stageFade': stageFade,
    'stageColourLabels': stageColourLabels,
    'stagePartsWidth': stagePartsWidth,
    'stageScheme': stageScheme.name,
    'stageTextSize': stageTextSize,
    'stageMargin': stageMargin,
    'stageHeader': stageHeader,
    'stageHeaderSize': stageHeaderSize,
    'stageFooter': stageFooter,
    'stageFooterSize': stageFooterSize,
  };

  void updateFrom(Map<String, dynamic> j) {
    T e<T extends Enum>(List<T> values, Object? v, T fallback) =>
        values.asNameMap()[v] ?? fallback;
    double d(Object? v, double f) => (v as num?)?.toDouble() ?? f;
    int i(Object? v, int f) => (v as num?)?.toInt() ?? f;
    bool b(Object? v, bool f) => v as bool? ?? f;
    view = e(ProjectionView.values, j['view'], view);
    bgType = e(BackgroundType.values, j['bgType'], bgType);
    bgColor = Color(i(j['bgColor'], bgColor.toARGB32()));
    bgMedia = j.containsKey('bgMedia')
        ? MediaRef.fromJson(j['bgMedia'])
        : bgMedia;
    bgFit = e(MediaFit.values, j['bgFit'], bgFit);
    if (j['bgDynamic'] is Map) bgDynamic = DynamicBg.fromJson(j['bgDynamic']);
    bgDynamicPreview = b(j['bgDynamicPreview'], bgDynamicPreview);
    bgTransition = d(j['bgTransition'], bgTransition);
    bgDimColor = Color(i(j['bgDimColor'], bgDimColor.toARGB32()));
    bgDim = i(j['bgDim'], bgDim);
    gradient = b(j['gradient'], gradient);
    gradientTwoColors = b(j['gradientTwoColors'], gradientTwoColors);
    gradientColor1 = Color(i(j['gradientColor1'], gradientColor1.toARGB32()));
    gradientOpacity1 = i(j['gradientOpacity1'], gradientOpacity1);
    gradientColor2 = Color(i(j['gradientColor2'], gradientColor2.toARGB32()));
    gradientOpacity2 = i(j['gradientOpacity2'], gradientOpacity2);
    gradientAngle = i(j['gradientAngle'], gradientAngle);
    textMode = e(TextMode.values, j['textMode'], textMode);
    textSize = i(j['textSize'], textSize);
    textColor = Color(i(j['textColor'], textColor.toARGB32()));
    textBold = b(j['textBold'], textBold);
    textItalic = b(j['textItalic'], textItalic);
    textCaps = b(j['textCaps'], textCaps);
    textShadow = b(j['textShadow'], textShadow);
    textLineSpacing = i(j['textLineSpacing'], textLineSpacing).clamp(60, 250);
    textAlign = e(HAlign.values, j['textAlign'], textAlign);
    textPosition = e(VAlign.values, j['textPosition'], textPosition);
    tidyLyrics = b(j['tidyLyrics'], tidyLyrics);
    logo = j.containsKey('logo') ? MediaRef.fromJson(j['logo']) : logo;
    logoCorner = e(Corner.values, j['logoCorner'], logoCorner);
    logoSize = i(j['logoSize'], logoSize);
    footer = b(j['footer'], footer);
    blankSlide = b(j['blankSlide'], blankSlide);
    titleSlide = b(j['titleSlide'], titleSlide);
    footerTitle = OnSlides.from(j['footerTitle'], footerTitle);
    footerCopyright = OnSlides.from(j['footerCopyright'], footerCopyright);
    footerCcli = OnSlides.from(j['footerCcli'], footerCcli);
    footerText = OnSlides.from(j['footerText'], footerText);
    underscan = b(j['underscan'], underscan);
    underscanW = i(j['underscanW'], underscanW).clamp(30, 100);
    underscanH = i(j['underscanH'], underscanH).clamp(30, 100);
    underscanLocked = b(j['underscanLocked'], underscanLocked);
    underscanX = d(j['underscanX'], underscanX).clamp(-1.0, 1.0);
    underscanY = d(j['underscanY'], underscanY).clamp(-1.0, 1.0);
    blackoutMedia = j.containsKey('blackoutMedia')
        ? MediaRef.fromJson(j['blackoutMedia'])
        : blackoutMedia;
    final l = j['linked'];
    if (l is Map<String, dynamic>) linked.updateFrom(l);
    timerShow = b(j['timerShow'], timerShow);
    timerSize = i(j['timerSize'], timerSize);
    timerPlace = e(TimerPlace.values, j['timerPlace'], timerPlace);
    timerColor = Color(i(j['timerColor'], timerColor.toARGB32()));
    timerBold = b(j['timerBold'], timerBold);
    timerItalic = b(j['timerItalic'], timerItalic);
    timerShadow = b(j['timerShadow'], timerShadow);
    timerFont = j['timerFont'] as String? ?? timerFont;
    stageLayout = e(StageLayout.values, j['stageLayout'], stageLayout);
    stageFade = b(j['stageFade'], stageFade);
    stageColourLabels = b(j['stageColourLabels'], stageColourLabels);
    stagePartsWidth = i(j['stagePartsWidth'], stagePartsWidth);
    stageScheme = e(StageScheme.values, j['stageScheme'], stageScheme);
    stageTextSize = i(j['stageTextSize'], stageTextSize);
    stageMargin = i(j['stageMargin'], stageMargin);
    stageHeader = b(j['stageHeader'], stageHeader);
    stageHeaderSize = i(j['stageHeaderSize'], stageHeaderSize);
    stageFooter = b(j['stageFooter'], stageFooter);
    stageFooterSize = i(j['stageFooterSize'], stageFooterSize);
  }

  static ProjectionSettings fromJson(Map<String, dynamic> j) =>
      ProjectionSettings()..updateFrom(j);
}

/// The gradient overlay as a Flutter gradient (null when turned off).
LinearGradient? overlayGradient(ProjectionSettings s) {
  if (!s.gradient) return null;
  final a = s.gradientColor1.withValues(alpha: s.gradientOpacity1 / 100);
  final b = s.gradientTwoColors
      ? s.gradientColor2.withValues(alpha: s.gradientOpacity2 / 100)
      : s.gradientColor1.withValues(alpha: 0);
  // CSS-style angle: 0° points up, so the first colour sits at the bottom.
  final rad = s.gradientAngle * math.pi / 180;
  final dx = math.sin(rad), dy = -math.cos(rad);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: [a, b],
  );
}
