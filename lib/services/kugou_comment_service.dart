import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/music_models.dart';
import 'comment_models.dart';

/// 酷狗评论数据源。
///
/// - 最新：`/r/v1/rank/newest`
/// - 热门：`/r/v1/rank/topliked`
/// - 楼层回复：`commentsv2/getReplyWithLike`
class KugouCommentService implements MusicCommentService {
  KugouCommentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _signKey = 'OIlwieks28dk2k092lksi2UIkp';
  static const _code = 'fc4be23b4e972707f36b8a828a93ba8a';
  static const _mid = '16249512204336365674023395779019';

  static const _webUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/107.0.0.0 Safari/537.36 Edg/107.0.1418.24';
  static const _commentUserAgent =
      'Android712-AndroidPhone-8983-18-0-COMMENT-wifi';

  static const _timeout = Duration(seconds: 12);

  @override
  List<CommentTab> get tabs => const [
    CommentTab(CommentKind.hot, '热门'),
    CommentTab(CommentKind.newest, '最新'),
  ];

  @override
  Future<CommentPageData> fetchComments({
    required Song song,
    required CommentKind kind,
    required int page,
    required int pageSize,
  }) async {
    final hash = song.hash.trim();
    if (hash.isEmpty) {
      throw CommentException('缺少歌曲 hash，无法加载评论');
    }
    final params = _listParams(hash, page, pageSize);
    final rank = kind == CommentKind.hot ? 'topliked' : 'newest';
    final uri = Uri.parse(
      'http://m.comment.service.kugou.com/r/v1/rank/$rank'
      '?$params&signature=${_signature(params)}',
    );
    final json = await _getJson(uri, _webUserAgent);

    final errCode = _asInt(json['err_code']);
    if (errCode != null && errCode != 0) {
      throw CommentException('获取评论失败（err_code=$errCode）');
    }

    final comments = _asList(json['list'])
        .whereType<Map<String, dynamic>>()
        .map((item) => _parseComment(item, withReply: true))
        .toList(growable: false);

    return CommentPageData(
      comments: comments,
      total: _asInt(json['count']) ?? 0,
      page: _asInt(json['current_page']) ?? page,
      pageSize: pageSize,
    );
  }

  /// 楼层回复：`childrenid` 取评论里的 `special_child_id`，`tid` 取评论 id。
  @override
  Future<List<CommentItem>> fetchReplies({
    required Song song,
    required CommentItem comment,
    required int page,
    required int pageSize,
  }) async {
    final childrenId = comment.childrenId ?? '';
    if (childrenId.isEmpty || comment.id.isEmpty) {
      return const [];
    }
    final uri = Uri.parse(
      'http://comment.service.kugou.com/index.php?r=commentsv2/getReplyWithLike'
      '&code=$_code&p=$page&pagesize=$pageSize&ver=1.01&clientver=8373'
      '&kugouid=687373022&need_show_image=1&appid=1001'
      '&childrenid=$childrenId&tid=${comment.id}',
    );
    final json = await _getJson(uri, _commentUserAgent);

    final errCode = _asInt(json['err_code']);
    if (errCode != null && errCode != 0) {
      throw CommentException('获取回复失败（err_code=$errCode）');
    }

    return _asList(json['list'])
        .whereType<Map<String, dynamic>>()
        .map((item) => _parseComment(item, withReply: false))
        .toList(growable: false);
  }

  @override
  void dispose() => _client.close();

  // ===== 内部实现 =====

  String _listParams(String hash, int page, int pageSize) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'dfid=0&mid=$_mid&clienttime=$timestamp&uuid=0&extdata=$hash'
        '&appid=1005&code=$_code&schash=$hash&clientver=11409&p=$page'
        '&clienttoken=&pagesize=$pageSize&ver=10&kugouid=0';
  }

  /// 酷狗签名：把参数按 `&` 拆开排序拼接后做 MD5。
  String _signature(String params) {
    final parts = params.split('&')..sort();
    final raw = '$_signKey${parts.join()}$_signKey';
    return md5.convert(utf8.encode(raw)).toString();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, String userAgent) async {
    http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': userAgent})
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
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw CommentException('接口返回格式异常');
    } on FormatException {
      throw CommentException('接口返回的不是合法 JSON');
    }
  }

  CommentItem _parseComment(
    Map<String, dynamic> json, {
    required bool withReply,
  }) {
    final replies = _asList(json['replys']).whereType<Map<String, dynamic>>();
    return CommentItem(
      id: _asString(json['id']) ?? '',
      content: _decodeContent(json),
      userName: _asString(json['user_name']),
      avatar: _asString(json['user_pic']),
      likedCount: _likeCount(json['like']),
      replyCount: _asInt(json['reply_num']) ?? _asInt(json['comments_num']),
      time: _asString(json['addtime']),
      location: _locationOf(json),
      levelLabel: _levelOf(json['uinfo']),
      images: _parseImages(json['images']),
      childrenId: _asString(json['special_child_id']),
      firstReply: withReply && replies.isNotEmpty
          ? _parseComment(replies.first, withReply: false)
          : null,
    );
  }

  /// 正文里把 `[at=xxx]` 还原成 `@昵称`，并解码 HTML 实体。
  String _decodeContent(Map<String, dynamic> json) {
    var raw = _asString(json['content']) ?? '';
    for (final at in _asList(json['atlist']).whereType<Map<String, dynamic>>()) {
      final id = _asString(at['id']);
      final name = _asString(at['name']);
      if (id == null || id.isEmpty || name == null) continue;
      raw = raw.replaceAll('[at=$id]', '@$name ');
    }
    return _decodeEntities(raw);
  }

  String? _locationOf(Map<String, dynamic> json) {
    final direct = _asString(json['location']);
    if (direct != null && direct.isNotEmpty) return direct;

    final rawExt = json['extdata'];
    Object? decoded = rawExt;
    if (rawExt is String && rawExt.trimLeft().startsWith('{')) {
      try {
        decoded = jsonDecode(rawExt);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is Map) {
      final city = _asString(decoded['city']);
      if (city != null && city.isNotEmpty) return city;
    }
    return null;
  }

  String? _levelOf(Object? uinfo) {
    for (final item in _asList(uinfo)) {
      if (item is Map) {
        final label = _asString(item['v']);
        if (label != null && label.isNotEmpty) return label;
      }
    }
    return null;
  }

  int? _likeCount(Object? like) {
    if (like is Map) {
      return _asInt(like['likenum']) ??
          _asInt(like['count']) ??
          _asInt(like['num']);
    }
    return _asInt(like);
  }

  List<String> _parseImages(Object? value) {
    if (value is List) {
      final urls = <String>[];
      for (final item in value) {
        if (item is String && item.isNotEmpty) {
          urls.add(item);
        } else if (item is Map) {
          final url = _asString(item['url']);
          if (url != null && url.isNotEmpty) urls.add(url);
        }
      }
      return urls;
    }
    if (value is String && value.isNotEmpty) {
      final trimmed = value.trim();
      if (trimmed.startsWith('[')) {
        try {
          return _parseImages(jsonDecode(trimmed));
        } catch (_) {
          return const [];
        }
      }
      if (trimmed.startsWith('http')) return [trimmed];
    }
    return const [];
  }

  static final _entityPattern = RegExp(r'&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);');

  String _decodeEntities(String input) {
    if (!input.contains('&')) return input;
    return input.replaceAllMapped(_entityPattern, (match) {
      final entity = match.group(1) ?? '';
      switch (entity) {
        case 'quot':
          return '"';
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
      }
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        final code = int.tryParse(entity.substring(2), radix: 16);
        if (code != null) return String.fromCharCode(code);
      }
      if (entity.startsWith('#')) {
        final code = int.tryParse(entity.substring(1));
        if (code != null) return String.fromCharCode(code);
      }
      return match.group(0) ?? '';
    });
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    if (value is Map) return value.values.toList(growable: false);
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
