import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/core/shuffle_cycle.dart';

void main() {
  test('plays every item once before starting another shuffled round', () {
    final cycle = ShuffleCycle<String>(random: Random(42));
    final songs = List.generate(150, (index) => 'song-$index');
    cycle.reset(songs, current: songs.first);

    var current = songs.first;
    final firstRound = <String>{current};
    for (var i = 0; i < songs.length - 1; i++) {
      current = cycle.next(songs, current: current)!;
      expect(firstRound.add(current), isTrue);
    }
    expect(firstRound, songs.toSet());

    final secondRound = <String>{};
    for (var i = 0; i < songs.length; i++) {
      final previous = current;
      current = cycle.next(songs, current: current)!;
      if (i == 0) expect(current, isNot(previous));
      expect(secondRound.add(current), isTrue);
    }
    expect(secondRound, songs.toSet());
  });

  test('resets the round when the queue changes', () {
    final cycle = ShuffleCycle<String>(random: Random(7));
    cycle.reset(const ['a', 'b', 'c'], current: 'a');
    cycle.next(const ['a', 'b', 'c'], current: 'a');

    const replacement = ['x', 'y'];
    final next = cycle.next(replacement, current: 'x');

    expect(next, 'y');
  });

  test('a one-song queue keeps returning its only song', () {
    final cycle = ShuffleCycle<String>(random: Random(1));
    cycle.reset(const ['only'], current: 'only');

    expect(cycle.next(const ['only'], current: 'only'), 'only');
  });
}
