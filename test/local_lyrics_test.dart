import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/core/api_client.dart';
import 'package:kgka_music_hl/models/music_models.dart';
import 'package:kgka_music_hl/services/cache_service.dart';
import 'package:kgka_music_hl/services/local_lyrics_service.dart';
import 'package:kgka_music_hl/services/local_song_matcher.dart';
import 'package:kgka_music_hl/services/music_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const matchedSong = Song(
  id: 'online-id',
  title: 'Test Song',
  artist: 'Test Artist',
  hash: 'ONLINE_HASH',
  duration: Duration(seconds: 180),
);
const timedText = '[00:01.00]First test line\n[00:02.00]Second test line';

class FakeMusicApi extends MusicApi {
  FakeMusicApi() : super(ApiClient());
  List<Song> results = [matchedSong];
  final queries = <String>[];
  final lyricHashes = <String>[];
  bool offline = false;

  @override
  Future<List<Song>> searchSongs(
    String keywords, {
    int page = 1,
    int pageSize = 30,
  }) async {
    queries.add(keywords);
    if (offline) throw const SocketException('offline');
    return results;
  }

  @override
  Future<List<LyricLine>> lyrics(Song song) async {
    lyricHashes.add(song.hash);
    if (song.hash == 'EMPTY') return [];
    if (song.hash == 'ERROR') throw const SocketException('lyric unavailable');
    return parseLyrics(timedText);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cached KRC words preserve spaces and timing', () {
    final line = parseLyrics(
      '[1000,1000]<0,300,0>Hello<300,100,0> <400,600,0>world',
    ).single;
    final restored = LyricLine.fromCache(line.toCache());
    expect(restored.words.map((word) => word.text).join(), 'Hello world');
    expect(restored.words[1].time, const Duration(milliseconds: 1300));
    expect(restored.words[1].duration, const Duration(milliseconds: 100));
  });
  late Directory temp;
  late FakeMusicApi api;
  late Song local;
  late File audio;
  late File sidecar;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('local_lyrics_test_');
    audio = await File('${temp.path}/Test Song.mp3').writeAsBytes([1, 2, 3]);
    sidecar = File('${temp.path}/Test Song.lrc');
    local = Song(
      id: audio.path,
      hash: audio.path,
      title: 'Test Song',
      artist: 'Test Artist',
      source: SongSource.local,
      duration: const Duration(seconds: 180),
    );
    api = FakeMusicApi();
  });
  tearDown(() => temp.delete(recursive: true));

  LocalLyricsService service({String? embedded, bool useCache = true}) =>
      LocalLyricsService(
        api: api,
        cache: useCache ? CacheService() : null,
        embeddedLyricsReader: (_) async => embedded,
      );

  test(
    'matches online metadata rather than submitting a local path as a hash',
    () async {
      final lines = await service().load(local);
      expect(lines.map((line) => line.text), [
        'First test line',
        'Second test line',
      ]);
      expect(api.queries, ['Test Artist Test Song']);
      expect(api.lyricHashes, ['ONLINE_HASH']);
    },
  );

  test(
    'a new service instance reuses persistent lyrics with no network call',
    () async {
      await service().load(local);
      api.queries.clear();
      api.offline = true;
      final lines = await service().load(local);
      expect(lines, hasLength(2));
      expect(api.queries, isEmpty);
    },
  );

  test('valid sidecar overrides cached online lyrics', () async {
    await service().load(local);
    await sidecar.writeAsString('[00:03.00]Local override');
    api.queries.clear();
    final lines = await service().load(local);
    expect(lines.single.text, 'Local override');
    expect(api.queries, isEmpty);
  });

  test('empty LRC does not suppress embedded lyrics', () async {
    await sidecar.writeAsString('');
    final lines = await service(embedded: timedText).load(local);
    expect(lines, hasLength(2));
    expect(api.queries, isEmpty);
  });

  test('invalid LRC does not suppress online lookup', () async {
    await sidecar.writeAsString('[ar:Test Artist]');
    expect(await service().load(local), hasLength(2));
    expect(api.queries, hasLength(1));
  });

  test(
    'invalid UTF-8 falls back rather than displaying replacement characters',
    () async {
      await sidecar.writeAsBytes([...utf8.encode('[00:01.00]'), 0xff]);
      expect(await service().load(local), hasLength(2));
      expect(api.queries, hasLength(1));
    },
  );

  test('UTF-16 sidecar is decoded before parsing', () async {
    await sidecar.writeAsBytes([
      0xff,
      0xfe,
      for (final unit in timedText.codeUnits) ...[unit & 255, unit >> 8],
    ]);
    expect(await service().load(local), hasLength(2));
    expect(api.queries, isEmpty);
  });

  test('GBK Chinese sidecar is decoded without mojibake', () async {
    await sidecar.writeAsBytes([
      ...ascii.encode('[00:01.00]'),
      0xd6,
      0xd0,
      0xce,
      0xc4,
      0xb8,
      0xe8,
      0xb4,
      0xca,
    ]);
    expect((await service().load(local)).single.text, '中文歌词');
    expect(api.queries, isEmpty);
  });

  test('untimed embedded lyrics remain readable when offline', () async {
    api.offline = true;
    final lines = await service(
      embedded: 'First line\nSecond line',
    ).load(local);
    expect(lines.single.text, 'First line\nSecond line');
    expect(lines.single.time, Duration.zero);
  });

  test(
    'network failures are retried on a later play, not cached as empty',
    () async {
      api.offline = true;
      expect(await service().load(local), isEmpty);
      api.offline = false;
      expect(await service().load(local), hasLength(2));
      expect(api.queries, hasLength(2));
    },
  );

  test('replacing the audio file invalidates its old match', () async {
    await service().load(local);
    await audio.writeAsBytes([1, 2, 3, 4, 5]);
    await service().load(local);
    expect(api.queries, hasLength(2));
  });

  test(
    'a failed candidate does not suppress the next matching candidate',
    () async {
      api.results = [
        const Song(
          id: 'bad',
          title: 'Test Song',
          artist: 'Test Artist',
          hash: 'ERROR',
          duration: Duration(seconds: 180),
        ),
        matchedSong,
      ];
      expect(await service().load(local), hasLength(2));
      expect(api.lyricHashes, ['ERROR', 'ONLINE_HASH']);
    },
  );

  test(
    'rejects covers, live versions, and recordings with a different duration',
    () {
      final identity = LocalSongIdentity.fromSong(local);
      final candidates = [
        const Song(
          id: 'cover',
          title: 'Test Song',
          artist: 'Other Artist',
          hash: 'COVER',
        ),
        const Song(
          id: 'live',
          title: 'Test Song (Live)',
          artist: 'Test Artist',
          hash: 'LIVE',
        ),
        const Song(
          id: 'long',
          title: 'Test Song',
          artist: 'Test Artist',
          hash: 'LONG',
          duration: Duration(seconds: 200),
        ),
        matchedSong,
      ];
      expect(identity.matchCandidates(candidates), [matchedSong]);
    },
  );

  test('uses artist-title filename when tags are missing', () {
    final identity = LocalSongIdentity.fromSong(
      const Song(
        id: '/Music/Test Artist - Test Song.flac',
        title: '未知歌曲',
        artist: '<unknown>',
        hash: 'local',
        source: SongSource.local,
      ),
    );
    expect(identity.query, 'Test Artist Test Song');
    expect(identity.matchCandidates([matchedSong]), [matchedSong]);
  });

  test('unknown artist requires a close duration match', () {
    expect(
      const LocalSongIdentity(
        'Test Song',
        '',
        null,
      ).matchCandidates([matchedSong]),
      isEmpty,
    );
    expect(
      const LocalSongIdentity(
        'Test Song',
        '',
        Duration(seconds: 180),
      ).matchCandidates([matchedSong]),
      [matchedSong],
    );
    expect(
      const LocalSongIdentity(
        'Test Song',
        '',
        Duration(seconds: 184),
      ).matchCandidates([matchedSong]),
      isEmpty,
    );
  });

  for (final extension in ['mp3', 'flac']) {
    test('reads real $extension embedded lyric tags', () {
      final embedded = readEmbeddedLyricsMetadata(
        'test/fixtures/lyrics.$extension',
      );
      expect(parseLyrics(embedded).single.text, 'Embedded test line');
    });
  }

  test('default reader extracts embedded lyrics in an isolate', () async {
    const song = Song(
      id: 'test/fixtures/lyrics.flac',
      title: 'Test',
      artist: 'Test',
      hash: 'fixture',
      source: SongSource.local,
    );
    final lines = await LocalLyricsService(api: api).load(song);
    expect(lines.single.text, 'Embedded test line');
    expect(api.queries, isEmpty);
  });
}
