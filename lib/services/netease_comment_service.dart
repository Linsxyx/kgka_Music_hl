import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_models.dart';
import 'comment_models.dart';

/// 网易云评论数据源。
///
/// 接口：`https://music.163.com/api/v1/resource/comments/R_SO_4_<歌曲id>`
/// 一次返回「热门评论（hotComments）」+「普通评论（comments，可按 offset 翻页）」。
/// 字段处理：
/// - 正文里的 `[大笑]` 这类表情码还原成 emoji
/// - `beReplied[0]` 作为楼层引用展示
/// - 昵称 / 头像 / 点赞数 / 时间 / IP 属地
///
/// 限制：网易云的楼层回复（`showFloorComment`）要登录态 + weapi 加密才能取，
/// 这里只展示接口自带的引用与被回复内容，不做假数据。
class NeteaseCommentService implements MusicCommentService {
  NeteaseCommentService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint =
      'https://music.163.com/api/v1/resource/comments/R_SO_4_';

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const _timeout = Duration(seconds: 12);

  @override
  List<CommentTab> get tabs => const [
    CommentTab(CommentKind.hot, '热门'),
    CommentTab(CommentKind.all, '全部'),
  ];

  @override
  Future<CommentPageData> fetchComments({
    required Song song,
    required CommentKind kind,
    required int page,
    required int pageSize,
  }) async {
    final songId = (song.albumAudioId ?? song.id).trim();
    if (songId.isEmpty) {
      throw CommentException('缺少网易云歌曲 id，无法加载评论');
    }

    final offset = (page - 1) * pageSize;
    final uri = Uri.parse(
      '$_endpoint$songId?limit=$pageSize&offset=$offset'
      '&timestamp=${DateTime.now().millisecondsSinceEpoch}',
    );
    final json = await _getJson(uri);

    final code = _asInt(json['code']);
    if (code != null && code != 200) {
      throw CommentException('获取评论失败（code=$code）');
    }

    if (kind == CommentKind.hot) {
      final hot = _asList(json['hotComments'])
          .whereType<Map<String, dynamic>>()
          .map(_parseComment)
          .toList(growable: false);
      return CommentPageData(
        comments: hot,
        total: hot.length,
        page: 1,
        pageSize: hot.isEmpty ? pageSize : hot.length,
      );
    }

    final comments = _asList(json['comments'])
        .whereType<Map<String, dynamic>>()
        .map(_parseComment)
        .toList(growable: false);
    final total = _asInt(json['total']) ?? 0;
    // 有总量却解析不出任何评论，说明接口结构变了或被风控（返回空数组），
    // 直接把原因抛出来，避免界面上一句“还没有评论”把问题盖住。
    if (comments.isEmpty && total > 0) {
      throw CommentException('网易云返回空列表（total=$total，可能被风控）');
    }
    return CommentPageData(
      comments: comments,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }

  /// 网易云楼层回复需要登录 + weapi 加密，这里不做，交由引用区展示。
  @override
  Future<List<CommentItem>> fetchReplies({
    required Song song,
    required CommentItem comment,
    required int page,
    required int pageSize,
  }) async => const [];

  @override
  void dispose() => _client.close();

  // ===== 内部实现 =====

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': _userAgent,
              'Referer': 'https://music.163.com/',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw CommentException('请求超时，请稍后重试');
    } catch (error) {
      throw CommentException('网络请求失败：$error');
    }

    if (response.statusCode != 200) {
      throw CommentException('请求失败（HTTP ${response.statusCode}）');
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) {
      throw CommentException('接口返回内容为空');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw CommentException('接口返回格式异常');
    } on FormatException {
      throw CommentException('接口返回的不是合法 JSON');
    }
  }

  CommentItem _parseComment(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final ipLocation = _asMap(json['ipLocation']);
    final floor = _asMap(json['showFloorComment']);
    final quotedList = _asList(
      json['beReplied'],
    ).whereType<Map<String, dynamic>>().toList(growable: false);
    final quoted = quotedList.isEmpty ? null : quotedList.first;

    return CommentItem(
      id: _asString(json['commentId']) ?? '',
      content: _applyEmoji(_asString(json['content']) ?? ''),
      userName: _asString(user?['nickname']),
      avatar: _asString(user?['avatarUrl']),
      likedCount: _asInt(json['likedCount']),
      replyCount: _asInt(floor?['replyCount']),
      time: _formatTimestamp(json['time']),
      location: _asString(ipLocation?['location']),
      firstReply: quoted == null ? null : _parseQuoted(quoted),
    );
  }

  CommentItem _parseQuoted(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final ipLocation = _asMap(json['ipLocation']);
    return CommentItem(
      id: _asString(json['beRepliedCommentId']) ?? '',
      content: _applyEmoji(_asString(json['content']) ?? ''),
      userName: _asString(user?['nickname']),
      avatar: _asString(user?['avatarUrl']),
      location: _asString(ipLocation?['location']),
    );
  }

  /// 网易云时间字段是毫秒时间戳，这里统一成 `yyyy-MM-dd HH:mm:ss`。
  String? _formatTimestamp(Object? value) {
    final ms = _asInt(value);
    if (ms == null || ms <= 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${time.year}-${_two(time.month)}-${_two(time.day)} '
        '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// 网易云表情码 → emoji（`[大笑]` → 😄）。
  String _applyEmoji(String text) {
    if (!text.contains('[')) return text;
    var result = text;
    for (final entry in _neteaseEmojis.entries) {
      if (result.contains(entry.key)) {
        result = result.replaceAll(entry.key, entry.value);
      }
    }
    return result;
  }

  static const Map<String, String> _neteaseEmojis = {
    '[大笑]': '😄',
    '[可爱]': '😊',
    '[憨笑]': '😁',
    '[色]': '😍',
    '[亲亲]': '😘',
    '[惊恐]': '😱',
    '[流泪]': '😭',
    '[亲]': '😚',
    '[呆]': '😳',
    '[哀伤]': '😞',
    '[呲牙]': '😃',
    '[吐舌]': '😛',
    '[撇嘴]': '😒',
    '[怒]': '😡',
    '[奸笑]': '😏',
    '[汗]': '😓',
    '[痛苦]': '😖',
    '[惶恐]': '😨',
    '[生病]': '😷',
    '[大哭]': '😢',
    '[晕]': '😵',
    '[发怒]': '😤',
    '[开心]': '😆',
    '[鬼脸]': '😜',
    '[皱眉]': '😟',
    '[流感]': '🤧',
    '[爱心]': '❤️',
    '[心碎]': '💔',
    '[钟情]': '💕',
    '[星星]': '⭐',
    '[生气]': '😠',
    '[便便]': '💩',
    '[强]': '👍',
    '[弱]': '👎',
    '[抱拳]': '🙏',
    '[握手]': '🤝',
    '[胜利]': '✌️',
    '[禁止]': '⛔',
    '[这边]': '👉',
    '[示爱]': '💝',
    '[嘴唇]': '👄',
    '[狗]': '🐶',
    '[猫]': '🐱',
    '[猪]': '🐷',
    '[兔子]': '🐰',
    '[小鸡]': '🐤',
    '[公鸡]': '🐔',
    '[幽灵]': '👻',
    '[圣诞]': '🎅',
    '[外星]': '👽',
    '[钻石]': '💎',
    '[礼物]': '🎁',
    '[男孩]': '👦',
    '[女孩]': '👧',
    '[蛋糕]': '🍰',
    '[18]': '🔞',
    '[圈]': '⭕',
    '[叉]': '❌',
  };

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    return const [];
  }

  String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
