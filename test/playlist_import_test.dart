import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kgka_music_hl/controllers/auth_controller.dart';
import 'package:kgka_music_hl/core/api_client.dart';
import 'package:kgka_music_hl/models/music_models.dart';
import 'package:kgka_music_hl/services/cache_service.dart';
import 'package:kgka_music_hl/services/music_api.dart';
import 'package:kgka_music_hl/services/playlist_import_service.dart';
import 'package:kgka_music_hl/services/qq_playlist_service.dart';
import 'package:kgka_music_hl/ui/widgets/import_playlist_sheet.dart';

http.Response qqPage(List<Map<String, Object>> songs, {int total = 1}) =>
    http.Response(
      jsonEncode({
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'code': 0,
            'dirinfo': {'title': '测试歌单', 'songnum': total},
            'songlist': songs,
          },
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object> qqSong(String id, String artist) => {
  'mid': id,
  'name': '同名歌曲',
  'interval': 180,
  'singer': [
    {'name': artist},
  ],
};

const candidate = Song(
  id: '1',
  hash: 'HASH',
  title: '同名歌曲',
  artist: '歌手甲',
  duration: Duration(seconds: 180),
);
const sourceTrack = ExternalPlaylistTrack(
  title: '同名歌曲',
  artist: '歌手甲',
  duration: Duration(seconds: 180),
);

class ImportApi extends MusicApi {
  ImportApi() : super(ApiClient());
  List<Song> candidates = [candidate];
  final added = <Song>[];
  bool failAdd = false;
  final requestedListIds = <String>[];
  Future<List<Song>>? delayedSearch;
  @override
  Future<List<Song>> searchSongs(
    String keywords, {
    int page = 1,
    int pageSize = 30,
  }) async => delayedSearch ?? candidates;
  @override
  Future<void> addSongsToPlaylist(String listId, List<Song> songs) async {
    if (failAdd) throw StateError('write failed');
    requestedListIds.add(listId);
    added.addAll(songs);
  }

  @override
  Future<List<Song>> playlistSongs(
    String id, {
    int page = 1,
    int pageSize = 80,
    bool fetchAll = false,
  }) async => List.of(added);
  @override
  Future<ExternalPlaylistParseResult> parseExternalPlaylist(
    String sourceText,
  ) async => const ExternalPlaylistParseResult(
    sourcePlatform: 'QQ音乐',
    playlistName: '测试歌单',
    songNames: ['同名歌曲'],
    tracks: [sourceTrack],
  );
}

class ImportAuth extends AuthController {
  ImportAuth(super.api, super.cacheService) {
    session = const LoginSession(token: 'test-only');
  }
  var refreshes = 0;
  @override
  Future<void> createPlaylist(String name, {bool private = false}) async {
    playlists = [
      PlaylistSummary(
        id: 'global-id',
        title: name,
        listId: 'local-id',
        sourceGlobalId: 'global-id',
        type: 0,
      ),
    ];
  }

  @override
  Future<void> refreshImportedPlaylist(PlaylistSummary playlist) async {
    refreshes++;
  }
}

void main() {
  test(
    'QQ links in share text and Markdown are recognized, unrelated hosts excluded',
    () {
      expect(
        QqPlaylistService.shareUri(
          '[分享](https://c6.y.qq.com/base/fcgi-bin/u?__=abc)',
        )?.query,
        '__=abc',
      );
      expect(
        QqPlaylistService.shareUri(
          'https://y.qq.com.evil.example/playlist/123',
        ),
        isNull,
      );
      expect(
        QqPlaylistService.shareUri('https://music.163.com/playlist?id=123'),
        isNull,
      );
    },
  );

  test(
    'short link redirect resolves playlist ID before requesting a webpage',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        expect(request.headers.containsKey('X-Kg-Session-Id'), false);
        if (request.url.host == 'c6.y.qq.com') {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://i.y.qq.com/n2/m/share/details/taoge.html?id=123&openinqqmusic=1',
            },
          );
        }
        final payload = jsonDecode(request.url.queryParameters['data']!);
        expect(payload['req_0']['param']['disstid'], 123);
        return qqPage([qqSong('one', '歌手甲')]);
      });
      final result = await QqPlaylistService(
        client,
      ).load(Uri.parse('https://c6.y.qq.com/base/fcgi-bin/u?__=abc'));
      expect(hosts, ['c6.y.qq.com', 'u.y.qq.com']);
      expect(result.importTracks.single.artist, '歌手甲');
      expect(result.importTracks.single.duration, const Duration(seconds: 180));
    },
  );

  test('pagination retains same-title songs by different singers', () async {
    final offsets = <int>[];
    final client = MockClient((request) async {
      final offset =
          jsonDecode(
                request.url.queryParameters['data']!,
              )['req_0']['param']['song_begin']
              as int;
      offsets.add(offset);
      return offset == 0
          ? qqPage([qqSong('one', '歌手甲'), qqSong('two', '歌手乙')], total: 3)
          : qqPage([qqSong('three', '歌手丙')], total: 3);
    });
    final result = await QqPlaylistService(
      client,
    ).load(Uri.parse('https://y.qq.com/n/ryqq_v2/playlist/123'));
    expect(offsets, [0, 2]);
    expect(result.importTracks.length, 3);
    expect(result.songNames.toSet().length, 1);
  });

  test('private or unavailable playlist produces a useful error', () async {
    final client = MockClient(
      (_) async => http.Response('{"code":0,"req_0":{"code":1000}}', 200),
    );
    await expectLater(
      QqPlaylistService(
        client,
      ).load(Uri.parse('https://y.qq.com/n/ryqq/playlist/123')),
      throwsA(isA<FormatException>()),
    );
  });

  test('external redirects are rejected', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'https://example.com/playlist/123'},
      );
    });
    await expectLater(
      QqPlaylistService(
        client,
      ).load(Uri.parse('https://c6.y.qq.com/base/fcgi-bin/u?__=abc')),
      throwsA(isA<FormatException>()),
    );
    expect(calls, 1);
  });

  test('pagination stops if QQ repeats a page', () async {
    final client = MockClient(
      (_) async => qqPage([qqSong('one', '歌手甲')], total: 10),
    );
    await expectLater(
      QqPlaylistService(
        client,
      ).load(Uri.parse('https://y.qq.com/n/ryqq/playlist/123')),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'unavailable tracks keep the original total so the UI can disclose the difference',
    () async {
      var calls = 0;
      final client = MockClient(
        (_) async =>
            qqPage(calls++ == 0 ? [qqSong('one', '歌手甲')] : [], total: 2),
      );
      final result = await QqPlaylistService(
        client,
      ).load(Uri.parse('https://y.qq.com/n/ryqq/playlist/123'));
      expect(result.tracks.length, 1);
      expect(result.totalSongCount, 2);
    },
  );

  test(
    'matching rejects a cover, live version and different duration',
    () async {
      final api = ImportApi()
        ..candidates = [
          const Song(
            id: 'cover',
            hash: 'C',
            title: '同名歌曲',
            artist: '歌手乙',
            duration: Duration(seconds: 180),
          ),
          const Song(
            id: 'live',
            hash: 'L',
            title: '同名歌曲 (Live)',
            artist: '歌手甲',
            duration: Duration(seconds: 180),
          ),
          const Song(
            id: 'long',
            hash: 'D',
            title: '同名歌曲',
            artist: '歌手甲',
            duration: Duration(seconds: 250),
          ),
          candidate,
        ];
      expect(await PlaylistImportService(api).match(sourceTrack), candidate);
      api.candidates.removeLast();
      expect(await PlaylistImportService(api).match(sourceTrack), isNull);
    },
  );

  test(
    'legacy title-only imports do not take an unrelated first result',
    () async {
      final api = ImportApi();
      expect(
        await PlaylistImportService(
          api,
        ).match(const ExternalPlaylistTrack(title: '另一个歌名')),
        isNull,
      );
    },
  );

  test('duplicates in destination and source are skipped', () async {
    final api = ImportApi();
    final service = PlaylistImportService(api);
    var result = await service.import(
      listId: '1',
      tracks: [sourceTrack, sourceTrack],
      existingHashes: {},
      onProgress: (_) {},
      shouldCancel: () => false,
    );
    expect(result.added, 1);
    expect(result.duplicates, 1);
    expect(api.added.length, 1);
    result = await service.import(
      listId: '1',
      tracks: [sourceTrack],
      existingHashes: {'hash'},
      onProgress: (_) {},
      shouldCancel: () => false,
    );
    expect(result.added, 0);
    expect(result.duplicates, 1);
  });

  test(
    'failed writes are not reported as imported and do not stop later songs',
    () async {
      final api = ImportApi()..failAdd = true;
      final result = await PlaylistImportService(api).import(
        listId: '1',
        tracks: [sourceTrack, sourceTrack],
        existingHashes: {},
        onProgress: (_) {},
        shouldCancel: () => false,
      );
      expect(result.added, 0);
      expect(result.failed.length, 2);
      expect(result.processed, 2);
    },
  );

  test('cancel while searching prevents a subsequent write', () async {
    final search = Completer<List<Song>>();
    final api = ImportApi()..delayedSearch = search.future;
    var cancelled = false;
    final run = PlaylistImportService(api).import(
      listId: '1',
      tracks: [sourceTrack],
      existingHashes: {},
      onProgress: (_) {},
      shouldCancel: () => cancelled,
    );
    cancelled = true;
    search.complete([candidate]);
    final result = await run;
    expect(api.added, isEmpty);
    expect(result.processed, 0);
  });

  test('HTTP 200 business failure does not count as successful add', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => http.Response('{"status":0,"msg":"failed"}', 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      MusicApi(client).addSongsToPlaylist('1', [candidate]),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('import panel offers a new playlist when the library is empty', (
    tester,
  ) async {
    final api = ImportApi();
    final auth = AuthController(api, CacheService());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportPlaylistSheet(api: api, auth: auth),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://y.qq.com/n/ryqq/playlist/123',
    );
    await tester.tap(find.text('解析歌单'));
    await tester.pumpAndSettle();
    expect(find.text('新建歌单'), findsOneWidget);
    expect(find.text('新歌单名称'), findsOneWidget);
    expect(find.text('开始导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new playlist flow writes the selected list ID and displays completion',
    (tester) async {
      final api = ImportApi();
      final auth = ImportAuth(api, CacheService());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportPlaylistSheet(api: api, auth: auth),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://y.qq.com/n/ryqq/playlist/123',
      );
      await tester.tap(find.text('解析歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始导入'));
      await tester.pumpAndSettle();
      expect(api.requestedListIds, ['local-id']);
      expect(auth.refreshes, 1);
      expect(find.text('导入完成：1/1 首'), findsOneWidget);
      expect(find.text('新增 1 · 已存在 0 · 未匹配 0 · 失败 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
