import '../models/music_models.dart';

/// 评论页签的类型。
///
/// - [hot]：按热度/点赞数
/// - [newest]：按时间倒序（酷狗支持）
/// - [all]：平台默认排序（网易云的普通评论列表，接口不提供排序参数）
enum CommentKind { hot, newest, all }

/// 一个页签的定义（类型 + 显示文案）。
class CommentTab {
  const CommentTab(this.kind, this.label);

  final CommentKind kind;
  final String label;
}

/// 一条评论（酷狗 / 网易云共用）。
class CommentItem {
  const CommentItem({
    required this.id,
    required this.content,
    this.userName,
    this.avatar,
    this.likedCount,
    this.replyCount,
    this.time,
    this.location,
    this.levelLabel,
    this.images = const [],
    this.firstReply,
    this.childrenId,
  });

  /// 评论 id（酷狗楼层回复时作为 `tid`）。
  final String id;

  /// 评论正文，已做过表情 / `[at=xxx]` / HTML 实体处理。
  final String content;

  final String? userName;
  final String? avatar;

  /// 点赞数。
  final int? likedCount;

  /// 该评论下的回复总数。
  final int? replyCount;

  /// 发表时间，统一为 `yyyy-MM-dd HH:mm:ss`。
  final String? time;

  /// IP 属地。
  final String? location;

  /// 用户等级标签，如酷狗的 `LV.8`。
  final String? levelLabel;

  /// 评论配图。
  final List<String> images;

  /// 列表自带的第一条楼层回复 / 被引用的原评论。
  final CommentItem? firstReply;

  /// 楼层回复接口需要的额外 id（酷狗 `special_child_id`；网易云为空）。
  final String? childrenId;

  /// 是否还能展开更多回复（只有酷狗提供楼层回复接口）。
  bool get canLoadMoreReplies {
    final children = childrenId;
    if (children == null || children.isEmpty) return false;
    return (replyCount ?? 0) > (firstReply == null ? 0 : 1);
  }
}

/// 一页评论。
class CommentPageData {
  const CommentPageData({
    required this.comments,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<CommentItem> comments;
  final int total;
  final int page;
  final int pageSize;

  int get maxPage {
    if (pageSize <= 0 || total <= 0) return 1;
    return (total + pageSize - 1) ~/ pageSize;
  }
}

/// 评论请求异常。
class CommentException implements Exception {
  CommentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 评论数据源接口：酷狗 / 网易云各实现一份，评论页只依赖这个接口。
abstract class MusicCommentService {
  /// 页签定义（目前两边都是两个：热门 + 另一个）。
  List<CommentTab> get tabs;

  /// 拉取评论列表。
  Future<CommentPageData> fetchComments({
    required Song song,
    required CommentKind kind,
    required int page,
    required int pageSize,
  });

  /// 拉取某条评论的楼层回复；平台不支持时返回空列表。
  Future<List<CommentItem>> fetchReplies({
    required Song song,
    required CommentItem comment,
    required int page,
    required int pageSize,
  });

  void dispose();
}
