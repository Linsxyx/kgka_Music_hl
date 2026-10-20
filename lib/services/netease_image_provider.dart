import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import 'cover_service.dart';

/// 带自定义请求头的网络图片加载器。
///
/// 为什么不能用 `Image.network(headers: ...)`：
/// Flutter 内部是 `request.headers.add('user-agent', ...)` 的**追加**语义，
/// 请求里会同时出现 `Dart/3.x (dart:io)` 和浏览器 UA 两个 `User-Agent`，
/// 网易云图片 CDN 对这种情况直接返回 403（实测：单浏览器 UA 200，
/// 双 UA 403，仅 Dart UA 403）。必须用 `set` 覆盖。
///
/// 另外网易云图片还有两个坑：
/// - 行内 URL 是 `http://`，iOS ATS 会拦，这里统一升级为 https
/// - 支持 `?param=WxH` 按尺寸取图，原图动辄 1.5~2MB
class NeteaseImageProvider extends ImageProvider<NeteaseImageProvider> {
  const NeteaseImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  /// 网易云图片 CDN 只接受浏览器 UA。
  static const userAgent = CoverService.imageUserAgent;

  static final HttpClient _httpClient = HttpClient()
    ..autoUncompress = true;

  @override
  Future<NeteaseImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NeteaseImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NeteaseImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    NeteaseImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final Uri resolved = Uri.base.resolve(key.url);
    final HttpClientRequest request = await _httpClient.getUrl(resolved);
    // 关键：用 set 覆盖，不能用 add，否则会出现两个 User-Agent
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
    request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');

    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<List<int>>();
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: resolved,
      );
    }

    final Uint8List bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      throw Exception('图片内容为空: $resolved');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is NeteaseImageProvider && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);
}
