// Slides as files: each slide is a picture of what the projector shows
// (rendered by captureSlides), put into a PDF, a PowerPoint deck or a
// single HTML page that plays full screen in any browser.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'format.dart';
import 'projection.dart';

/// One rendered slide: its picture (PNG) and its text (for alt text,
/// search and screen readers).
class SlideImage {
  final Uint8List png;
  final String text;
  const SlideImage(this.png, this.text);
}

/// A PDF with one full-bleed page per slide.
Future<Uint8List> slidesPdf(
  List<SlideImage> slides, {
  required double width,
  required double height,
  String title = '',
}) {
  final doc = pw.Document(title: title);
  // Points: a 16:9 slide is 960 × 540 pt (13.3 × 7.5 in, like PowerPoint).
  final pageWidth = 960.0;
  final format = PdfPageFormat(pageWidth, pageWidth * height / width);
  for (final s in slides) {
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(s.png), fit: pw.BoxFit.cover),
      ),
    );
  }
  return doc.save();
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\n', '&#10;');

const _ns =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const _head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _emptyTree =
    '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
    '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
    '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';

String _rels(List<(String, String, String)> rels) =>
    '$_head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${rels.map((r) => '<Relationship Id="${r.$1}" Type="${r.$2}" Target="${r.$3}"/>').join()}'
    '</Relationships>';

const _theme =
    '$_head<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Slides">'
    '<a:themeElements><a:clrScheme name="Slides">'
    '<a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="1F1F1F"/></a:dk2><a:lt2><a:srgbClr val="EEEEEE"/></a:lt2>'
    '<a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
    '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
    '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
    '</a:clrScheme><a:fontScheme name="Slides">'
    '<a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
    '</a:fontScheme><a:fmtScheme name="Slides"><a:fillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:fillStyleLst><a:lnStyleLst>'
    '<a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
    '<a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
    '<a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>'
    '</a:lnStyleLst><a:effectStyleLst>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '<a:effectStyle><a:effectLst/></a:effectStyle>'
    '</a:effectStyleLst><a:bgFillStyleLst>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    '</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';

/// PowerPoint's 16:9 width (13.333 in), in EMU; heights follow the shape.
const _slideCx = 12192000;

/// The parts every deck needs, plus [slides] (each slide's shapes) and
/// pictures: [pictures] maps a slide (0-based) to its picture's file name
/// in `ppt/media/`, all of which are in [media].
Uint8List _pptx({
  required List<String> slides,
  required Map<int, String> pictures,
  required Map<String, Uint8List> media,
  required int cy,
  required String title,
  String background = '000000',
  double? fade,
}) {
  const cx = _slideCx;
  // A fade into each slide ([fade] seconds; PowerPoint 2010+ reads the
  // exact time, older ones a speed).
  final ms = fade == null ? 0 : (fade * 1000).round().clamp(100, 10000);
  final speed = ms <= 500 ? 'fast' : (ms <= 1000 ? 'med' : 'slow');
  final transition = fade == null
      ? ''
      : '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
            '<mc:Choice xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" Requires="p14">'
            '<p:transition spd="$speed" p14:dur="$ms"><p:fade/></p:transition></mc:Choice>'
            '<mc:Fallback><p:transition spd="$speed"><p:fade/></p:transition></mc:Fallback>'
            '</mc:AlternateContent>';
  final files = <String, String>{};
  final n = slides.length;

  files['[Content_Types].xml'] =
      '$_head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Default Extension="gif" ContentType="image/gif"/>'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
      '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
      '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
      '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
      '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
      '<Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>'
      '<Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '${[for (var i = 1; i <= n; i++) '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'].join()}'
      '</Types>';

  files['_rels/.rels'] = _rels([
    ('rId1', '$_rel/officeDocument', 'ppt/presentation.xml'),
    (
      'rId2',
      'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
      'docProps/core.xml',
    ),
    ('rId3', '$_rel/extended-properties', 'docProps/app.xml'),
  ]);
  files['docProps/core.xml'] =
      '$_head<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_xml(title)}</dc:title><dc:creator>ChordPro Presenter</dc:creator>'
      '</cp:coreProperties>';
  files['docProps/app.xml'] =
      '$_head<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>ChordPro Presenter</Application><Slides>$n</Slides></Properties>';

  files['ppt/presentation.xml'] =
      '$_head<p:presentation $_ns saveSubsetFonts="1">'
      '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
      '<p:sldIdLst>${[for (var i = 1; i <= n; i++) '<p:sldId id="${255 + i}" r:id="rId${9 + i}"/>'].join()}</p:sldIdLst>'
      '<p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="6858000" cy="9144000"/>'
      '</p:presentation>';
  files['ppt/_rels/presentation.xml.rels'] = _rels([
    ('rId1', '$_rel/slideMaster', 'slideMasters/slideMaster1.xml'),
    ('rId2', '$_rel/theme', 'theme/theme1.xml'),
    ('rId3', '$_rel/presProps', 'presProps.xml'),
    ('rId4', '$_rel/viewProps', 'viewProps.xml'),
    ('rId5', '$_rel/tableStyles', 'tableStyles.xml'),
    for (var i = 1; i <= n; i++)
      ('rId${9 + i}', '$_rel/slide', 'slides/slide$i.xml'),
  ]);
  files['ppt/presProps.xml'] = '$_head<p:presentationPr $_ns/>';
  files['ppt/viewProps.xml'] = '$_head<p:viewPr $_ns/>';
  files['ppt/tableStyles.xml'] =
      '$_head<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>';
  files['ppt/theme/theme1.xml'] = _theme;

  files['ppt/slideMasters/slideMaster1.xml'] =
      '$_head<p:sldMaster $_ns><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="$background"/></a:solidFill>'
      '<a:effectLst/></p:bgPr></p:bg><p:spTree>$_emptyTree</p:spTree></p:cSld>'
      '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" '
      'accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
      '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
      '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>';
  files['ppt/slideMasters/_rels/slideMaster1.xml.rels'] = _rels([
    ('rId1', '$_rel/slideLayout', '../slideLayouts/slideLayout1.xml'),
    ('rId2', '$_rel/theme', '../theme/theme1.xml'),
  ]);
  files['ppt/slideLayouts/slideLayout1.xml'] =
      '$_head<p:sldLayout $_ns type="blank" preserve="1"><p:cSld name="Blank">'
      '<p:spTree>$_emptyTree</p:spTree></p:cSld>'
      '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
  files['ppt/slideLayouts/_rels/slideLayout1.xml.rels'] = _rels([
    ('rId1', '$_rel/slideMaster', '../slideMasters/slideMaster1.xml'),
  ]);

  for (var i = 1; i <= n; i++) {
    files['ppt/slides/slide$i.xml'] =
        '$_head<p:sld $_ns><p:cSld><p:spTree>$_emptyTree${slides[i - 1]}'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '$transition</p:sld>';
    final picture = pictures[i - 1];
    files['ppt/slides/_rels/slide$i.xml.rels'] = _rels([
      ('rId1', '$_rel/slideLayout', '../slideLayouts/slideLayout1.xml'),
      if (picture != null) ('rId2', '$_rel/image', '../media/$picture'),
    ]);
  }

  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  for (final e in media.entries) {
    // Already compressed: stored as is.
    archive.addFile(
      ArchiveFile.bytes('ppt/media/${e.key}', e.value)
        ..compression = CompressionType.none,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A picture filling the slide (rId2 in the slide's relationships).
String _picture(int id, String name, String alt, int cy) =>
    '<p:pic><p:nvPicPr><p:cNvPr id="$id" name="${_xml(name)}" descr="${_xml(alt)}"/>'
    '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
    '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
    '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$_slideCx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>';

/// A PowerPoint deck (.pptx): one slide per picture, full bleed, with the
/// slide's words as the picture's alt text. Looks exactly like the
/// projector, but the words can't be edited.
Uint8List slidesPptx(
  List<SlideImage> slides, {
  required double width,
  required double height,
  String title = '',
  double? fade,
}) {
  final cy = (_slideCx * height / width).round();
  return _pptx(
    slides: [
      for (var i = 0; i < slides.length; i++)
        _picture(2, 'Slide ${i + 1}', slides[i].text, cy),
    ],
    pictures: {for (var i = 0; i < slides.length; i++) i: 'image${i + 1}.png'},
    media: {
      for (var i = 0; i < slides.length; i++)
        'image${i + 1}.png': slides[i].png,
    },
    cy: cy,
    title: title,
    fade: fade,
  );
}

/// Fonts every computer has, for editable decks.
const pptxFonts = [
  'Arial',
  'Helvetica',
  'Calibri',
  'Verdana',
  'Tahoma',
  'Trebuchet MS',
  'Segoe UI',
  'Georgia',
  'Times New Roman',
  'Garamond',
];

String _hex(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// The projector's look, for text slides.
class TextSlideLook {
  final Color background;
  final Uint8List? backgroundImage;

  /// `png`, `jpeg` or `gif`.
  final String backgroundExt;
  final Color dimColor;
  final double dim; // 0–1
  final Color color;
  final bool bold, italic, caps, shadow;
  final HAlign align;
  final VAlign position;

  /// Largest text, in pixels on a 1080-high screen (the projector's
  /// "text size").
  final double maxSize;
  final LinkedStyle linked;
  final String font;

  /// Space between lines, in % of normal.
  final int lineSpacing;

  const TextSlideLook({
    this.background = const Color(0xFF000000),
    this.backgroundImage,
    this.backgroundExt = 'png',
    this.dimColor = const Color(0xFF000000),
    this.dim = 0,
    this.color = const Color(0xFFFFFFFF),
    this.bold = true,
    this.italic = false,
    this.caps = false,
    this.shadow = true,
    this.align = HAlign.center,
    this.position = VAlign.center,
    this.maxSize = 80,
    required this.linked,
    this.font = 'Arial',
    this.lineSpacing = 100,
  });
}

/// Roughly how wide text is, in ems per character (sans, bold a bit wider).
double _emPerChar(bool bold) => bold ? 0.56 : 0.52;

/// The biggest size (px on a 1080p screen) at which [pieces] fit in a
/// [w] × [h] box (px): stacked, or side by side.
double _fit(List<String> pieces, double w, double h, TextSlideLook look) {
  double needH(String t, double size, double width) {
    var lines = 0;
    for (final l in t.split('\n')) {
      final chars = l.trim().length * (look.caps ? 1.12 : 1.0);
      final perLine = width / (size * _emPerChar(look.bold));
      lines += chars == 0 ? 1 : (chars / perLine).ceil();
    }
    return lines * size * 1.2;
  }

  double scale(int i) => i == 0 ? 1 : look.linked.size / 100;
  var size = look.maxSize;
  while (size > 12) {
    var fits = true;
    if (look.linked.sideBySide && pieces.length > 1) {
      final colW = (w - 48 * (pieces.length - 1)) / pieces.length;
      for (var i = 0; i < pieces.length; i++) {
        if (needH(pieces[i], size * scale(i), colW) > h) fits = false;
      }
    } else {
      var total = 0.0;
      for (var i = 0; i < pieces.length; i++) {
        total += needH(pieces[i], size * scale(i), w);
        if (i > 0) total += size * 0.6;
      }
      if (total > h) fits = false;
    }
    if (fits) break;
    size -= 2;
  }
  return size;
}

/// A text box of [paras] (pre-built `<a:p>`s) at [x], [y], [w], [h] (EMU).
String _textBox(
  int id,
  String name,
  int x,
  int y,
  int w,
  int h,
  String anchor,
  String paras,
) =>
    '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="${_xml(name)}"/>'
    '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
    '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
    '<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" '
    'anchor="$anchor"><a:normAutofit/></a:bodyPr><a:lstStyle/>$paras</p:txBody></p:sp>';

/// A PowerPoint deck with real, editable text: the projector's background,
/// colours, alignment and translations, in a font every computer has
/// ([TextSlideLook.font]).
Uint8List slidesPptxText(
  List<String> slides, {
  required double width,
  required double height,
  required TextSlideLook look,
  String title = '',
  double? fade,
}) {
  final cy = (_slideCx * height / width).round();
  // Pixels of a 1080-high screen → EMU and points.
  final emuPerPx = cy / 1080;
  final ptPerPx = emuPerPx / 12700;
  final screenW = 1080 * width / height;
  final pad = 48.0;
  final boxW = screenW - pad * 2, boxH = 1080 - pad * 2;
  final algn = switch (look.align) {
    HAlign.left => 'l',
    HAlign.center => 'ctr',
    HAlign.right => 'r',
  };
  final anchor = switch (look.position) {
    VAlign.top => 't',
    VAlign.center => 'ctr',
    VAlign.bottom => 'b',
  };

  String run(String text, double sizePx, {required bool linked}) {
    final l = look.linked;
    final bold = look.bold || (linked && l.bold);
    final italic = look.italic || (linked && l.italic);
    final base = linked ? (l.color ?? look.color) : look.color;
    final alpha = linked && l.dim ? 55000 : 100000;
    final shadow = linked ? (look.shadow || l.shadow) : look.shadow;
    final sz = (sizePx * ptPerPx * 100).round().clamp(100, 400000);
    return '<a:r><a:rPr lang="en-US" sz="$sz" b="${bold ? 1 : 0}" '
        'i="${italic ? 1 : 0}"${look.caps ? ' cap="all"' : ''} dirty="0">'
        '<a:solidFill><a:srgbClr val="${_hex(base)}">'
        '${alpha < 100000 ? '<a:alpha val="$alpha"/>' : ''}</a:srgbClr></a:solidFill>'
        '${shadow ? '<a:effectLst><a:outerShdw blurRad="76200" dist="25400" dir="5400000" algn="ctr" rotWithShape="0"><a:srgbClr val="000000"><a:alpha val="70000"/></a:srgbClr></a:outerShdw></a:effectLst>' : ''}'
        '<a:latin typeface="${_xml(look.font)}"/><a:ea typeface="${_xml(look.font)}"/>'
        '<a:cs typeface="${_xml(look.font)}"/></a:rPr><a:t>${_xml(text)}</a:t></a:r>';
  }

  String paras(String piece, double sizePx, {required bool linked}) => [
    for (final line in piece.split('\n'))
      '<a:p><a:pPr algn="$algn"><a:lnSpc><a:spcPct val="${look.lineSpacing * 1000}"/></a:lnSpc></a:pPr>'
          '${line.trim().isEmpty ? '' : run(line, sizePx, linked: linked)}'
          '<a:endParaRPr lang="en-US" sz="${(sizePx * ptPerPx * 100).round().clamp(100, 400000)}" dirty="0"/></a:p>',
  ].join();

  final shapes = <String>[];
  for (final text in slides) {
    // A title slide: the title large and the artist under it, centred.
    final titled = titleSlideOf(text);
    final pieces = (titled == null ? text : '')
        .split('\u2029')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (pieces.isEmpty) pieces.add('');
    final size = _fit(pieces, boxW, boxH, look);
    double sizeOf(int i) => i == 0 ? size : size * look.linked.size / 100;

    final out = StringBuffer();
    var id = 2;
    if (look.backgroundImage != null) {
      out.write(_picture(id++, 'Background', '', cy));
    }
    if (look.dim > 0) {
      out.write(
        '<p:sp><p:nvSpPr><p:cNvPr id="${id++}" name="Dim"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$_slideCx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="${_hex(look.dimColor)}">'
        '<a:alpha val="${(look.dim * 100000).round()}"/></a:srgbClr></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>',
      );
    }
    final x = (pad * emuPerPx).round();
    final y = (pad * emuPerPx).round();
    final w = (boxW * emuPerPx).round();
    final h = (boxH * emuPerPx).round();
    if (titled != null) {
      String line(String t, double px, bool bold) =>
          '<a:p><a:pPr algn="ctr"/>${run(t, px, linked: false).replaceFirst('b="${look.bold ? 1 : 0}"', 'b="${bold ? 1 : 0}"')}'
          '<a:endParaRPr lang="en-US" dirty="0"/></a:p>';
      out.write(
        _textBox(
          id++,
          'Title',
          x,
          y,
          w,
          h,
          'ctr',
          line(titled.$1, look.maxSize * 1.3, true) +
              (titled.$2.trim().isEmpty
                  ? ''
                  : line(titled.$2, look.maxSize * 0.6, false)),
        ),
      );
    } else if (isBlankSlide(text)) {
      // Just the background.
    } else if (look.linked.sideBySide && pieces.length > 1) {
      // One box per language, side by side.
      final gap = (48 * emuPerPx).round();
      final colW = ((w - gap * (pieces.length - 1)) / pieces.length).round();
      for (var i = 0; i < pieces.length; i++) {
        out.write(
          _textBox(
            id++,
            i == 0 ? 'Lyrics' : 'Translation $i',
            x + i * (colW + gap),
            y,
            colW,
            h,
            anchor,
            paras(pieces[i], sizeOf(i), linked: i > 0),
          ),
        );
      }
    } else {
      // Stacked in one box, a small gap between languages.
      final body = StringBuffer();
      for (var i = 0; i < pieces.length; i++) {
        if (i > 0) {
          body.write(
            '<a:p><a:pPr algn="$algn"/><a:endParaRPr lang="en-US" '
            'sz="${(size * 0.5 * ptPerPx * 100).round().clamp(100, 400000)}" dirty="0"/></a:p>',
          );
        }
        body.write(paras(pieces[i], sizeOf(i), linked: i > 0));
      }
      out.write(_textBox(id++, 'Lyrics', x, y, w, h, anchor, '$body'));
    }
    shapes.add('$out');
  }

  final image = look.backgroundImage;
  final file = 'background.${look.backgroundExt}';
  return _pptx(
    slides: shapes,
    pictures: image == null
        ? const {}
        : {for (var i = 0; i < slides.length; i++) i: file},
    media: image == null ? const {} : {file: image},
    cy: cy,
    title: title,
    background: _hex(look.background),
    fade: fade,
  );
}

String _html(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// One HTML file with every slide inside it: open it in any browser and
/// present. → / Space / click: next; ←: back; F: full screen; Home / End.
String slidesHtml(List<SlideImage> slides, {String title = 'Slides'}) {
  final images = [
    for (var i = 0; i < slides.length; i++)
      '<img src="data:image/png;base64,${base64Encode(slides[i].png)}" '
          'alt="${_html(slides[i].text)}"${i == 0 ? ' class="on"' : ''}>',
  ].join('\n');
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_html(title)}</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  #deck { position: fixed; inset: 0; cursor: pointer; }
  #deck img { position: absolute; inset: 0; width: 100%; height: 100%;
    object-fit: contain; opacity: 0; transition: opacity .25s ease; }
  #deck img.on { opacity: 1; }
  #bar { position: fixed; left: 50%; bottom: 16px; transform: translateX(-50%);
    font: 14px/1 system-ui, sans-serif; color: #fff; background: rgba(0,0,0,.55);
    padding: 8px 14px; border-radius: 999px; opacity: 0; transition: opacity .3s;
    pointer-events: none; }
  body.hint #bar { opacity: 1; }
</style>
</head>
<body class="hint">
<div id="deck">
$images
</div>
<div id="bar"><span id="n">1</span> / ${slides.length} · ← → to move · F for full screen</div>
<script>
  const slides = [...document.querySelectorAll('#deck img')];
  let i = 0, hide;
  function show(n) {
    n = Math.max(0, Math.min(slides.length - 1, n));
    slides[i].classList.remove('on');
    i = n;
    slides[i].classList.add('on');
    document.getElementById('n').textContent = i + 1;
    hint();
  }
  function hint() {
    document.body.classList.add('hint');
    clearTimeout(hide);
    hide = setTimeout(() => document.body.classList.remove('hint'), 1800);
  }
  function full() {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen?.();
  }
  document.addEventListener('keydown', (e) => {
    if (['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter'].includes(e.key)) show(i + 1);
    else if (['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace'].includes(e.key)) show(i - 1);
    else if (e.key === 'Home') show(0);
    else if (e.key === 'End') show(slides.length - 1);
    else if (e.key === 'f' || e.key === 'F') full();
    else return;
    e.preventDefault();
  });
  document.getElementById('deck').addEventListener('click', (e) =>
    show(e.clientX < innerWidth / 3 ? i - 1 : i + 1));
  let x0 = null;
  addEventListener('touchstart', (e) => x0 = e.touches[0].clientX, {passive: true});
  addEventListener('touchend', (e) => {
    if (x0 === null) return;
    const dx = e.changedTouches[0].clientX - x0;
    if (Math.abs(dx) > 40) show(dx < 0 ? i + 1 : i - 1);
    x0 = null;
  });
  addEventListener('mousemove', hint);
  hint();
</script>
</body>
</html>
''';
}
