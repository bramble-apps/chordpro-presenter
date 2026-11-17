// ignore_for_file: avoid_print
// Runs the sheet music reader on page images (PGM) and prints what it read,
// measure by measure; writes an overlay picture next to each (debugging).
//   dart run tool/scan_page.dart <out-dir> <page.pgm>...
import 'dart:io';
import 'dart:typed_data';

import 'package:bilingual_projector/scanner/reader.dart';
import 'package:bilingual_projector/scanner/score.dart';

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

const _colors = {
  'whole': [255, 0, 255],
  'half': [0, 160, 0],
  'quarter': [0, 0, 255],
  'eighth': [255, 120, 0],
  '16th': [255, 0, 0],
  '32nd': [120, 0, 0],
};

String name(ScoreNote n) {
  if (n.rest) return 'r';
  const acc = {1: '#', -1: 'b', 0: '', 2: 'x', -2: 'bb'};
  return '${stepOf(n.diatonic)}${acc[n.alter]}${n.diatonic ~/ 7}';
}

void main(List<String> args) {
  final out = args.first;
  final pages = [for (final p in args.skip(1)) readPgm(p)];
  if (Platform.environment['LOG'] != null) readerLog = [];
  final score = readScore(pages);
  for (final l in readerLog ?? const <String>[]) {
    if (l.startsWith(Platform.environment['LOG']!)) print(l);
  }
  print(
    'key ${score.fifths} time ${score.beats}/${score.beatType} clefs ${score.clefs.map((c) => c.name)} measures ${score.measures.length}',
  );
  final byM = <int, List<ScoreNote>>{};
  for (final n in score.ordered) {
    byM.putIfAbsent(n.measure, () => []).add(n);
  }
  for (final (i, m) in score.measures.indexed) {
    final ns = byM[i] ?? const [];
    final total = ns.isEmpty
        ? 0
        : ns.map((n) => n.onset + n.duration).reduce((a, b) => a > b ? a : b) -
              m.onset;
    print(
      'm${i + 1} p${m.page} s${m.system} x${m.box.l.round()}-${m.box.r.round()}${m.fifths == null ? '' : ' k${m.fifths}'}${m.ending == null ? '' : ' e${m.ending}'}${m.repeatStart ? ' |:' : ''}${m.repeatEnd ? ' :|' : ''}${m.time == null ? '' : ' {${m.time!.$1}/${m.time!.$2}}'} [${total.toStringAsFixed(2)}${(total - score.lengthOf(i)).abs() > 0.01 ? ' !' : ''}] '
      '${ns.map((n) => '${name(n)}${n.type == 'whole'
          ? 'w'
          : n.type == 'half'
          ? 'h'
          : n.type == 'quarter'
          ? 'q'
          : n.type == 'eighth'
          ? 'e'
          : n.type == '16th'
          ? 's'
          : 't'}${'.' * n.dots}${n.triplet ? '3' : ''}${n.tie ? '~' : ''}').join(' ')}',
    );
  }
  if (Platform.environment['VOICES'] != null) {
    for (final (i, m) in score.measures.indexed) {
      final ns = byM[i] ?? const <ScoreNote>[];
      final groups = <(int, int), List<ScoreNote>>{};
      for (final n in ns) {
        groups.putIfAbsent((n.staff, n.voice), () => []).add(n);
      }
      final parts = <String>[];
      for (final e in groups.entries) {
        final end =
            e.value
                .map((n) => n.onset + n.duration)
                .reduce((a, b) => a > b ? a : b) -
            m.onset;
        if ((end - score.lengthOf(i)).abs() > 0.01) {
          parts.add(
            'st${e.key.$1}v${e.key.$2}=${end.toStringAsFixed(2)}: ${e.value.map((n) => '${name(n)}${n.type[0]}${n.dots > 0 ? '.' : ''}@${(n.onset - m.onset).toStringAsFixed(2)}').join(' ')}',
          );
        }
      }
      if (parts.isNotEmpty) print('V m${i + 1}: ${parts.join(' || ')}');
    }
  }
  for (final (pi, p) in pages.indexed) {
    final img = Uint8List(p.width * p.height * 3);
    for (var i = 0; i < p.width * p.height; i++) {
      final v = 150 + p.gray[i] * 105 ~/ 255;
      img[i * 3] = img[i * 3 + 1] = img[i * 3 + 2] = v;
    }
    void px(int x, int y, List<int> c) {
      if (x < 0 || y < 0 || x >= p.width || y >= p.height) return;
      final i = (y * p.width + x) * 3;
      img[i] = c[0];
      img[i + 1] = c[1];
      img[i + 2] = c[2];
    }

    for (final n in score.notes.where((n) => n.page == pi)) {
      final c = n.rest ? [0, 200, 200] : _colors[n.type]!;
      final b = n.box;
      for (var x = b.l.round(); x <= b.r.round(); x++) {
        px(x, b.t.round(), c);
        px(x, b.b.round(), c);
      }
      for (var y = b.t.round(); y <= b.b.round(); y++) {
        px(b.l.round(), y, c);
        px(b.r.round(), y, c);
      }
      for (var k = 0; k < n.dots; k++) {
        px(b.r.round() + 3 + k * 3, b.cy.round(), [0, 0, 0]);
      }
    }
    for (final m in score.measures.where((m) => m.page == pi)) {
      for (var y = m.box.t.round(); y < m.box.b.round(); y += 2) {
        px(m.box.l.round(), y, [255, 200, 0]);
      }
    }
    final f = File('$out/overlay-$pi.ppm').openSync(mode: FileMode.write);
    f.writeStringSync('P6\n${p.width} ${p.height}\n255\n');
    f.writeFromSync(img);
    f.closeSync();
  }
}
