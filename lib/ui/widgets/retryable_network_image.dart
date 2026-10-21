import 'package:flutter/material.dart';

import '../../services/cover_service.dart';
import '../../services/netease_image_provider.dart';

/// 带正确请求头的远程图片。
///
/// 分两条路：
/// - **网易云**（`music.126.net`）：走 [NeteaseImageProvider]，
///   在 HttpClient 层用 `set` 覆盖 User-Agent。不能走 `Image.network`，
///   因为它用 `headers.add` 追加，请求里会同时出现两个 User-Agent，
///   网易云 CDN 直接 403（实测：单浏览器 UA 200、双 UA 403）。
/// - 其它来源（酷狗 / 本地）：原样用 `Image.network`。
///
/// 另外两个坑：
/// - 不用 `loadingBuilder`：网易云图片走 chunked 传输时 `progress` 会一直非 null，
///   占位图永久盖住真图。
/// - 不用 `frameBuilder` 判断 `frame != null`：命中缓存时解码是异步的，
///   会出现 `frame == null && wasSynchronouslyLoaded == false`，
///   占位图再也不消失。
class RetryableNetworkImage extends StatelessWidget {
  const RetryableNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholderBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final int? cacheWidth;
  final int? cacheHeight;

  /// 仅在加载失败时显示。
  final WidgetBuilder? placeholderBuilder;

  /// 取图尺寸（控件边长，逻辑像素）。
  double get _targetSize {
    if (cacheWidth != null) return cacheWidth! / 2;
    if (width != null && width!.isFinite) return width!;
    return 512;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = CoverService.sized(url, _targetSize) ?? url;

    Widget fallback(BuildContext context) =>
        placeholderBuilder?.call(context) ?? const SizedBox.shrink();

    if (CoverService.isNeteaseImage(resolvedUrl)) {
      return Image(
        image: NeteaseImageProvider(resolvedUrl),
        fit: fit,
        width: width,
        height: height,
        alignment: alignment,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallback(context),
      );
    }

    return Image.network(
      resolvedUrl,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => fallback(context),
    );
  }
}
