import 'package:bilingual_projector/autoscroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('song durations', () {
    expect(parseDuration('3:45'), 225);
    expect(parseDuration('1:02:30'), 3750);
    expect(parseDuration('225'), 225);
    expect(parseDuration('3m 45s'), 225);
    expect(parseDuration('4 min'), 240);
    expect(parseDuration('90 sec'), 90);
    expect(parseDuration(' 0:07 '), 7);
    expect(parseDuration(''), isNull);
    expect(parseDuration('3:75'), isNull);
    expect(parseDuration('slow'), isNull);
    expect(formatDuration(90), '1:30');
    expect(formatDuration(7), '0:07');
    expect(formatDuration(3750), '1:02:30');
  });

  test('time per song: duration, else 1:30; changes kept per song', () {
    final a = Autoscroll();
    a.setSong('a', '');
    expect(a.seconds, 90);
    a.add(30);
    expect(a.seconds, 120);
    a.add(-200);
    expect(a.seconds, Autoscroll.minSeconds);
    a.setSong('b', '4:10');
    expect(a.seconds, 250);
    a.start();
    expect(a.running, isTrue);
    a.setSong('a', '');
    expect(a.running, isFalse, reason: 'stops when the song changes');
    expect(a.seconds, Autoscroll.minSeconds, reason: 'remembered');
    a.reset();
    expect(a.seconds, 90);
  });

  test('time left follows the page; − / + and typing change it', () {
    final a = Autoscroll()..setSong('a', '2:00');
    a.progress.value = 0.5;
    expect(a.remaining, 60);
    a.addRemaining(30);
    expect(a.remaining, 90);
    expect(a.seconds, 180, reason: 'slower pace for the rest');
    a.setRemaining(20);
    expect(a.remaining, 20);
  });
}
