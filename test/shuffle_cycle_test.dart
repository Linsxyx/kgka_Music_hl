import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/core/shuffle_cycle.dart';
import 'package:kgka_music_hl/services/music_api.dart';

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

  test('previous steps back through shuffled history without reshuffling', () {
    final cycle = ShuffleCycle<String>(random: Random(99));
    const songs = ['a', 'b', 'c', 'd', 'e'];
    cycle.reset(songs, current: 'a');

    final second = cycle.next(songs, current: 'a')!;
    cycle.markPlayed(second);
    final third = cycle.next(songs, current: second)!;
    cycle.markPlayed(third);

    final backToSecond = cycle.previous(songs, current: third)!;
    cycle.markPlayed(backToSecond);
    expect(backToSecond, second);

    final backToFirst = cycle.previous(songs, current: backToSecond)!;
    cycle.markPlayed(backToFirst);
    expect(backToFirst, 'a');

    final forwardToSecond = cycle.next(songs, current: backToFirst)!;
    cycle.markPlayed(forwardToSecond);
    expect(forwardToSecond, second);

    final forwardToThird = cycle.next(songs, current: forwardToSecond)!;
    cycle.markPlayed(forwardToThird);
    expect(forwardToThird, third);
  });

  test('KRC language tag preserves empty rows and romanization word spaces', () {
    final languageJson = {
      'content': [
        {
          'type': 1,
          'lyricContent': [
            <String>[],
            ['第一句翻译'],
            [''],
            ['第三句翻译'],
          ],
        },
        {
          'type': 0,
          'lyricContent': [
            <String>[],
            ['Day ', 'by ', 'day ', 'u', 'n', 'za', 'ri'],
            [' '],
            ['sa ', 'yo', 'na', 'ra'],
          ],
        },
      ],
    };
    final languageBase64 = base64.encode(utf8.encode(jsonEncode(languageJson)));
    final krc = '''
[language:$languageBase64]
[0,1000]<0,500,0>作词：测试
[1000,2000]<0,500,0>Day by day うんざり
[3000,1500]<0,500,0>(I say I say my heaven)
[4500,2000]<0,500,0>さよなら
''';

    final parsed = parseLyrics(krc);
    expect(parsed.length, 4);
    expect(parsed[0].translation, isNull);
    expect(parsed[0].romanization, isNull);
    expect(parsed[1].translation, '第一句翻译');
    expect(parsed[1].romanization, 'Day by day unzari');
    expect(parsed[2].translation, isNull);
    expect(parsed[2].romanization, isNull);
    expect(parsed[3].translation, '第三句翻译');
    expect(parsed[3].romanization, 'sa yonara');
  });
}