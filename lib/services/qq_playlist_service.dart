import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_models.dart';

/// Read public QQ playlist metadata, without sharing the Kugou login session.
class QqPlaylistService {
  QqPlaylistService(this._client);

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);
  static const _headers = {
    'Referer': 'https://y.qq.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  static Uri? shareUri(String text) {
    for (final match in RegExp(
      r'''https?://[^\s<>"'\]\[)），。]+''',
    ).allMatches(text)) {
      final uri = Uri.tryParse(match.group(0)!);
      if (uri != null && _isQq(uri)) return uri;
    }
    return null;
  }

  static bool _isQq(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.userInfo.isEmpty &&
      (uri.host == 'y.qq.com' || uri.host.endsWith('.y.qq.com'));

  static String? _playlistId(Uri uri) {
    final id =
        uri.queryParameters['disstid'] ??
        (RegExp(r'playlist|taoge|playsquare').hasMatch(uri.path)
            ? uri.queryParameters['id']
            : null) ??
        RegExp(r'/(?:playlist|playsquare)/(\d+)').firstMatch(uri.path)?.group(1);
    return id != null && RegExp(r'^\d+$').hasMatch(id) ? id : null;
  }

  Future<String> _resolveId(Uri uri) async {
    for (var hop = 0; hop < 6; hop++) {
      if (!_isQq(uri)) throw const FormatException('分享链接跳转到了非 QQ 音乐页面');
      final id = _playlistId(uri);
      if (id != null) return id;
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(_headers);
      final response = await _client.send(request).timeout(_timeout);
      await response.stream.drain<void>().timeout(_timeout);
      final location = response.headers['location'];
      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null) {
        uri = uri.resolve(location);
      } else {
        break;
      }
    }
    throw const FormatException('未找到 QQ 歌单编号，请在 QQ 音乐中重新复制歌单分享链接');
  }

  Future<ExternalPlaylistParseResult> load(Uri share) async {
    final id = await _resolveId(share);
    final tracks = <ExternalPlaylistTrack>[];
    final seen = <String>{};
    var offset = 0;
    var total = 0;
    var name = 'QQ 音乐歌单';
    for (var page = 0; page < 100; page++) {
      final uri = Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
        'data': jsonEncode({
          'comm': {'ct': 24, 'cv': 0},
          'req_0': {
            'module': 'music.srfDissInfo.aiDissInfo',
            'method': 'uniform_get_Dissinfo',
            'param': {
              'disstid': int.parse(id),
              'userinfo': 1,
              'tag': 1,
              'orderlist': 1,
              'song_begin': offset,
              'song_num': 100,
            },
          },
        }),
      });
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw const FormatException('QQ 音乐暂时无法访问，请稍后重试');
      }
      final root = asMap(jsonDecode(utf8.decode(response.bodyBytes)));
      final request = asMap(root['req_0']);
      final data = asMap(request['data']);
      if (asInt(root['code']) != 0 ||
          asInt(request['code']) != 0 ||
          (data['code'] != null && asInt(data['code']) != 0) ||
          data.isEmpty) {
        throw const FormatException('QQ 歌单不可读取，请确认歌单已公开且分享链接有效');
      }
      final info = asMap(data['dirinfo']);
      name = asString(info['title']) ?? name;
      total = asInt(info['songnum']) ?? total;
      final items = asList(data['songlist']);
      var newItems = 0;
      for (final item in items) {
        final song = asMap(item);
        final songId = asString(song['mid'] ?? song['id']);
        if (songId != null && !seen.add(songId)) continue;
        newItems++;
        final title = asString(song['name'] ?? song['title']);
        if (title == null) continue;
        final artist = asList(song['singer'])
            .map((s) => asString(asMap(s)['name']))
            .whereType<String>()
            .join(' / ');
        final seconds = asInt(song['interval']);
        tracks.add(
          ExternalPlaylistTrack(
            title: title,
            artist: artist,
            duration: seconds == null || seconds <= 0
                ? null
                : Duration(seconds: seconds),
          ),
        );
      }
      offset += items.length;
      if (items.isEmpty || offset >= total) {
        return ExternalPlaylistParseResult(
          sourcePlatform: 'QQ音乐',
          playlistName: name,
          songNames: tracks.map((track) => track.title).toList(),
          tracks: tracks,
          totalSongCount: total,
        );
      }
      if (newItems == 0) {
        throw const FormatException('QQ 音乐未返回后续歌曲，请稍后重试');
      }
    }
    throw const FormatException('歌单过大，请分成多个歌单后导入');
  }
}
