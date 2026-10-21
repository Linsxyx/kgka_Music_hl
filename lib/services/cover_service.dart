import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_models.dart';

/// 封面获取服务：补取缺失的封面，并给网易云图片补上必要的请求头 / 尺寸。
///
/// 三件事：
/// 1. **缺封面时补取**：歌曲自身没有 `coverUrl` 时，按来源拉一次封面并缓存。
///    目前实现网易云：`/song/detail` → `songs[0].al.picUrl`。
/// 2. **请求头**：网易云图片 CDN 会把 `Dart/<版本> (dart:io)` 直接 403 掉
///    （实测：无 UA / 浏览器 UA 返回 200，`Dart/3.5 (dart:io)` 返回 403），
///    而 Flutter 的 `Image.network` 用的正是 dart:io 默认 UA，
///    所以网易云图片必须带上浏览器 UA。
/// 3. **尺寸**：网易云图片支持 `?param=宽y高`，原图动辄 1.5~2MB，
///    按显示尺寸取图能省一大截。酷狗靠 URL 里的 `{size}` 占位符，
///    由模型层的 [normalizeImageUrl] 处理。
///
/// 注意：`resolve()` 返回的是**原始地址**，尺寸拼接只发生在渲染层
/// （[sized]），避免同一张图被拼两次 `?param=` 变成非法 URL。
class CoverService {
  CoverService({http.Client? client}) : _client = client ?? http.Client();

  /// 全局单例：封面地址在内存里复用，列表滚动不会反复请求。
  static final CoverService instance = CoverService();

  final http.Client _client;

  /// songId → 补取到的封面地址（null 表示取不到，不再重试）。
  final _cache = <String, String?>{};
  final _inflight = <String, Future<String?>>{};

  static const _neteaseDetail = 'https://wyy.music.api.hoilai.cn/song/detail';
  static const _timeout = Duration(seconds: 10);

  /// 网易云接口请求用的浏览器 UA。
  ///
  /// 图片请求不在这里处理：图片必须用 [NeteaseImageProvider] 在 HttpClient
  /// 层覆盖 UA，因为 `NetworkImage(headers:)` 是追加语义，会产生两个
  /// User-Agent，网易云 CDN 会因此返回 403。
  static const imageUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 是否为网易云图片 CDN 的地址。
  static bool isNeteaseImage(String? url) =>
      url != null && url.contains('music.126.net');

  /// 把图片地址改写成适合当前显示尺寸的版本。
  ///
  /// [size] 是控件边长（逻辑像素，`double.infinity` 表示铺满容器），
  /// 内部按 2 倍取图并限制在 120~1024 像素之间。
  /// 网易云顺带把 `http://` 升级成 `https://`（iOS ATS 会拦 http）；
  /// 非网易云（酷狗 / 本地）原样返回。已带 `?param=` 的会先剥掉再拼，
  /// 保证重复调用是幂等的。
  static String? sized(String? url, double size) {
    if (url == null || url.isEmpty) return null;
    if (!url.contains('music.126.net')) return url;

    final normalized = url.startsWith('http://')
        ? 'https://${url.substring(7)}'
        : url;
    final pixels = ((size.isFinite && size > 0 ? size * 2 : 1024).round())
        .clamp(120, 1024);
    final base = normalized.split('?').first;
    return '$base?param=${pixels.toInt()}y${pixels.toInt()}';
  }

  /// 解析某首歌应显示的封面地址（缺封面时会发起补取）。
  ///
  /// 返回的是**原始地址**（未拼尺寸），尺寸交给渲染层。
  Future<String?> resolve(Song song) async {
    final own = song.coverUrl;
    if (own != null && own.isNotEmpty) return own;
    if (song.source != SongSource.netease) return own;

    final songId = (song.albumAudioId ?? song.id).trim();
    if (songId.isEmpty) return null;

    // 命中缓存就直接返回，包含"取不到"的负缓存（value 为 null）：
    // 用 containsKey 而不是 null 判断，否则失败过的歌曲每次都会重新请求。
    if (_cache.containsKey(songId)) return _cache[songId];

    final future = _inflight[songId] ??= _fetchNeteaseCover(
      songId,
    ).whenComplete(() => _inflight.remove(songId));
    final fetched = await future;
    _cache[songId] = fetched;
    return fetched;
  }

  /// 同步解析：只有"自带封面"或"已经补取过"时才有值。
  ///
  /// 列表里先用它渲染，避免出现一帧占位再跳成封面。
  String? resolveSync(Song song) {
    final own = song.coverUrl;
    if (own != null && own.isNotEmpty) return own;
    if (song.source != SongSource.netease) return null;
    final songId = (song.albumAudioId ?? song.id).trim();
    return _cache[songId];
  }

  Future<String?> _fetchNeteaseCover(String songId) async {
    try {
      final uri = Uri.parse('$_neteaseDetail?ids=$songId');
      final response = await _client
          .get(
            uri,
            headers: {'User-Agent': imageUserAgent, 'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map) return null;
      final songs = decoded['songs'];
      if (songs is! List || songs.isEmpty) return null;
      final first = songs.first;
      if (first is! Map) return null;
      final album = first['al'];
      if (album is! Map) return null;
      final picUrl = album['picUrl'];
      if (picUrl is String && picUrl.isNotEmpty) return picUrl;
      return null;
    } catch (_) {
      return null;
    }
  }
}
