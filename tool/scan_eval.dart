// ignore_for_file: avoid_print
// Measures the sheet music reader on generated test pages: each sN.json
// lists the true notes; prints how many were found right.
//   dart run tool/scan_eval.dart <dir> [only]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilingual_projector/scanner/reader.dart';

PageImage readPgm(String path) {
  final b = File(path).readAsBytesSync();
  var i = 0;
  String token() {
    while (b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9) {
      i++;
    }
    final s = i;
    while (!(b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9)) {
      i++;
    }
    return String.fromCharCodes(b.sublist(s, i));
  }

  token();
  final w = int.parse(token()), h = int.parse(token());
  token();
  i++;
  return PageImage(w, h, Uint8List.sublistView(b, i, i + w * h));
}

void main(List<String> args) {
  final dir = Directory(args[0]);
  final only = args.length > 1 ? args[1] : null;
  if (args.length > 3) readerProbe = (int.parse(args[2]), int.parse(args[3]));
  var tp = 0, fn = 0, fp = 0, ptp = 0;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceAll('.json', '');
    if (only != null && !name.contains(only)) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map;
    final pages = [
      for (final p in j['pages'] as List) readPgm('${dir.path}/$p'),
    ];
    final reports = <PageReport>[];
    final sw = Stopwatch()..start();
    if (only != null) readerLog = [];
    final score = readScore(pages, reports: reports);
    readerLog?.forEach(print);
    final truth = [
      for (final n in j['notes'] as List)
        '${(n['staff'] as int) - 1} ${(n['onset'] as num).toStringAsFixed(2)} ${n['midi']}',
    ];
    final got = [
      for (final n in score.notes.where((n) => !n.rest))
        '${n.staff} ${n.onset.toStringAsFixed(2)} ${n.midi}',
    ];
    // Pitches alone (in order, per staff), ignoring timing.
    final tPitch = [
      for (final n in j['notes'] as List)
        '${(n['staff'] as int) - 1} ${n['midi']}',
    ];
    final gPitch = [
      for (final n in score.notes.where((n) => !n.rest)) '${n.staff} ${n.midi}',
    ];
    int matches(List<String> a, List<String> b) {
      final left = <String, int>{};
      for (final x in a) {
        left[x] = (left[x] ?? 0) + 1;
      }
      var m = 0;
      for (final x in b) {
        if ((left[x] ?? 0) > 0) {
          left[x] = left[x]! - 1;
          m++;
        }
      }
      return m;
    }

    if (only != null) {
      _overlay(
        pages.first,
        score,
        '${Directory.systemTemp.path}/omr-$name.ppm',
      );
    }
    if (only != null) {
      for (final n in score.ordered) {
        print(
          '  m${n.measure} st${n.staff} v${n.voice} ${n.onset.toStringAsFixed(2)} ${n.rest ? 'rest' : n.midi} ${n.type}${'.' * n.dots}${n.triplet ? '3' : ''} x${n.box.l.round()}',
        );
      }
      for (final mm in score.measures) {
        print(
          '  measure ${mm.onset} ${mm.length} ${mm.box.l.round()}-${mm.box.r.round()} ${mm.repeatStart} ${mm.repeatEnd}',
        );
      }
    }
    if (only != null) {
      for (final st in [0, 1]) {
        print(
          'TRUTH st$st: ${[for (final n in j['notes'] as List)
            if (n['staff'] - 1 == st && (n['onset'] as num) < 40) '${(n['onset'] as num).toStringAsFixed(2)}:${n['midi']}'].join(' ')}',
        );
        print(
          'GOT   st$st: ${[for (final n in score.ordered)
            if (n.staff == st && n.onset < 40) '${n.onset.toStringAsFixed(2)}:${n.rest ? 'r' : n.midi}${n.type[0]}${n.voice == 2 ? 'v2' : ''}'].join(' ')}',
        );
      }
    }
    final m = matches(truth, got);
    final pm = matches(tPitch, gPitch);
    tp += m;
    ptp += pm;
    fn += truth.length - m;
    fp += got.length - m;
    final r = reports.first;
    print(
      '$name ${j['kind']} L${j['level']}: notes ${truth.length} found ${got.length} '
      'right $m (pitch $pm)  key ${j['fifths']}/${score.fifths} time ${j['meter']}/${score.beats}/${score.beatType} '
      'clefs ${score.clefs.map((c) => c.name).join(',')}  sp ${r.space.toStringAsFixed(1)} lt ${r.line} '
      'staves ${r.staves} sys ${r.systems} ang ${r.angle.toStringAsFixed(2)} measures ${score.measures.length} ${sw.elapsedMilliseconds}ms',
    );
  }
  print(
    'ALL: right $tp, missed $fn, extra $fp, pitch-only right $ptp '
    '(${(100 * tp / (tp + fn)).toStringAsFixed(1)}% timed, ${(100 * ptp / (tp + fn)).toStringAsFixed(1)}% pitch)',
  );
}

const _colors = {
  'whole': [255, 0, 255],
  'half': [0, 160, 0],
  'quarter': [0, 0, 255],
  'eighth': [255, 120, 0],
  '16th': [255, 0, 0],
  '32nd': [120, 0, 0],
};

void _overlay(PageImage p, dynamic score, String path) {
  final out = Uint8List(p.width * p.height * 3);
  for (var i = 0; i < p.width * p.height; i++) {
    final v = 150 + p.gray[i] * 105 ~/ 255;
    out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = v;
  }
  void px(int x, int y, List<int> c) {
    if (x < 0 || y < 0 || x >= p.width || y >= p.height) return;
    final i = (y * p.width + x) * 3;
    out[i] = c[0];
    out[i + 1] = c[1];
    out[i + 2] = c[2];
  }

  for (final n in score.notes) {
    final c = n.rest ? [0, 200, 200] : _colors[n.type]!;
    final b = n.box;
    for (var x = b.l.round(); x <= b.r.round(); x++) {
      for (var t = 0; t < 2; t++) {
        px(x, b.t.round() + t, c);
        px(x, b.b.round() - t, c);
      }
    }
    for (var y = b.t.round(); y <= b.b.round(); y++) {
      for (var t = 0; t < 2; t++) {
        px(b.l.round() + t, y, c);
        px(b.r.round() - t, y, c);
      }
    }
    // dots, accidentals as marks under it
    if (n.accidental != null) {
      for (var k = 0; k < 6; k++) {
        px(b.l.round() - 4 - k, b.cy.round(), [255, 0, 0]);
      }
    }
  }
  for (final m in score.measures) {
    for (var y = m.box.t.round(); y < m.box.b.round(); y++) {
      px(m.box.l.round(), y, [255, 200, 0]);
    }
  }
  final f = File(path).openSync(mode: FileMode.write);
  f.writeStringSync('P6\n${p.width} ${p.height}\n255\n');
  f.writeFromSync(out);
  f.closeSync();
}
