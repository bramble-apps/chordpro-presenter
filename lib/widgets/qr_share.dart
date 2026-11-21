// A song as a QR code: the ChordPro text itself (footer and credits too),
// so any phone camera shows it with no app and no link. Shown big (long
// songs make dense codes that need size to scan), saved as a picture or
// printed. A song too long even for the largest code is split in two (or
// more), at section breaks.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../browser.dart';
import '../eink.dart';
import '../bramble_icons.dart';

// How many bytes of text each code size (version 1–40) holds, by error
// correction (ISO/IEC 18004, byte mode). (The QR library doesn't say when
// text is too long; it cuts it.)
const _capacityL = [
  17, 32, 53, 78, 106, 134, 154, 192, 230, 271, 321, 367, 425, 458, 520, //
  586, 644, 718, 792, 858, 929, 1003, 1091, 1171, 1273, 1367, 1465, 1528,
  1628, 1732, 1840, 1952, 2068, 2188, 2303, 2431, 2563, 2699, 2809, 2953,
];
const _capacityM = [
  14, 26, 42, 62, 84, 106, 122, 152, 180, 213, 251, 287, 331, 362, 412, //
  450, 504, 560, 624, 666, 711, 779, 857, 911, 997, 1059, 1125, 1190, 1264,
  1370, 1452, 1538, 1628, 1722, 1809, 1911, 1989, 2099, 2213, 2331,
];

/// The smallest code version that holds [data] at [level] (L or M), or
/// null if it's too long for any.
int? qrVersionFor(String data, int level) {
  final bytes = utf8.encode(data).length;
  final caps = level == QrErrorCorrectLevel.M ? _capacityM : _capacityL;
  for (var v = 0; v < caps.length; v++) {
    if (caps[v] >= bytes) return v + 1;
  }
  return null;
}

/// One code's worth of a song.
class QrPart {
  final String text;
  final int version;

  /// Error correction: medium when the code stays a moderate size, else
  /// low (fine on screens and clean prints).
  final int level;
  const QrPart(this.text, this.version, this.level);
}

/// [text] in as few codes as it takes (one, unless it's very long), each
/// headed "(part 1 of 2)" when split.
List<QrPart> qrParts(String text, String title) {
  QrPart? fit(String t) {
    final m = qrVersionFor(t, QrErrorCorrectLevel.M);
    if (m != null && m <= 25) return QrPart(t, m, QrErrorCorrectLevel.M);
    final l = qrVersionFor(t, QrErrorCorrectLevel.L);
    return l == null ? null : QrPart(t, l, QrErrorCorrectLevel.L);
  }

  final whole = fit(text);
  if (whole != null) return [whole];
  // Split at blank lines (between sections), into pieces of about equal
  // size; more pieces until each fits.
  final paras = text.trimRight().split(RegExp(r'\n\s*\n'));
  for (var n = 2; n <= 6; n++) {
    final total = text.length;
    final pieces = <String>[];
    var cur = StringBuffer();
    for (final p in paras) {
      final target = total / n;
      if (cur.isNotEmpty &&
          cur.length + p.length > target &&
          pieces.length < n - 1) {
        pieces.add(cur.toString());
        cur = StringBuffer();
      }
      if (cur.isNotEmpty) cur.write('\n\n');
      cur.write(p);
    }
    pieces.add(cur.toString());
    final parts = <QrPart>[];
    for (final (i, p) in pieces.indexed) {
      final head = i == 0
          ? ''
          : '$title (part ${i + 1} of ${pieces.length})\n\n';
      final tail = '\n\n(part ${i + 1} of ${pieces.length})';
      final part = fit('$head$p$tail\n');
      if (part == null) break;
      parts.add(part);
    }
    if (parts.length == pieces.length) return parts;
  }
  return [];
}

/// Shows [text] (a song as shared: ChordPro or plain text) as QR code(s).
Future<void> showTextQr(BuildContext context, String title, String text) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => _QrDialog(title: title, text: text),
    );

class _QrDialog extends StatefulWidget {
  final String title, text;
  const _QrDialog({required this.title, required this.text});

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  late final List<QrPart> _parts = qrParts(widget.text, widget.title);
  int _shown = 0;

  QrPart get _part => _parts[_shown];

  String get _sizeNote {
    final v = _part.version;
    final squares = 17 + 4 * v;
    final hint = v <= 20
        ? 'easy to scan'
        : v <= 30
        ? 'scan from a phone screen or a print about 6 cm wide'
        : 'show it big: full screen, or printed about 9 cm wide';
    return '${widget.text.length} characters · $squares × $squares squares · $hint';
  }

  QrPainter _painter(QrPart p) => QrPainter(
    data: p.text,
    version: p.version,
    errorCorrectionLevel: p.level,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  );

  Future<Uint8List> _png(QrPart p) async {
    final data = await _painter(p)
        .toImageData(1400, format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  String get _fileStem {
    final t = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '').trim();
    return t.isEmpty ? 'song' : t;
  }

  Future<void> _save() async {
    for (final (i, p) in _parts.indexed) {
      final suffix = _parts.length > 1 ? ' (${i + 1} of ${_parts.length})' : '';
      downloadBytes('$_fileStem QR$suffix.png', await _png(p), 'image/png');
    }
  }

  Future<void> _print() async {
    final doc = pw.Document(title: widget.title);
    for (final (i, p) in _parts.indexed) {
      final png = await _png(p);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            children: [
              pw.Text(widget.title, style: const pw.TextStyle(fontSize: 22)),
              if (_parts.length > 1)
                pw.Text('Part ${i + 1} of ${_parts.length}'),
              pw.SizedBox(height: 8),
              pw.Text('Scan with your phone camera'),
              pw.SizedBox(height: 24),
              // Big enough to scan even the densest codes.
              pw.Image(pw.MemoryImage(png), width: 12 * PdfPageFormat.cm),
            ],
          ),
        ),
      );
    }
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: '$_fileStem QR',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_parts.isEmpty) {
      return AlertDialog(
        title: const Text('Too long for QR codes'),
        content: const Text('This song is too long even for several codes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    }
    return Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Close',
                  color: Colors.black87,
                  icon: const Icon(BrambleIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy the text',
                  color: Colors.black87,
                  icon: const Icon(BrambleIcons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Song text copied')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Save as picture',
                  color: Colors.black87,
                  icon: const Icon(BrambleIcons.downloadSimple),
                  onPressed: _save,
                ),
                IconButton(
                  tooltip: 'Print',
                  color: Colors.black87,
                  icon: const Icon(BrambleIcons.printer),
                  onPressed: _print,
                ),
              ],
            ),
            if (_parts.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 0; i < _parts.length; i++)
                      ButtonSegment(
                        value: i,
                        label: Text('Part ${i + 1} of ${_parts.length}'),
                      ),
                  ],
                  selected: {_shown},
                  onSelectionChanged: (v) => setState(() => _shown = v.first),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = (box.biggest.shortestSide - 32).clamp(
                    120.0,
                    2000.0,
                  );
                  return Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: CustomPaint(
                        size: Size.square(side),
                        painter: _painter(_part),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                '${_parts.length > 1 ? 'Too long for one code: scan each part. ' : ''}'
                'Scan with any phone camera to get the song as text.\n$_sizeNote',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
