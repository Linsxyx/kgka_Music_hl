import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/music_models.dart';
import '../../services/cover_service.dart';
import 'artwork.dart';

/// 歌曲封面：在 [Artwork] 外面加了一层"封面获取"。
///
/// - 歌曲自带封面：直接用，并按控件尺寸取合适分辨率（网易云走 `?param=WxH`）
/// - 没有封面：异步补取（目前支持网易云），拿到后自动刷新
///
/// 用法与 [Artwork] 基本一致，只是把 `url` 换成 `song`。
class SongArtwork extends StatefulWidget {
  const SongArtwork({
    super.key,
    required this.song,
    required this.size,
    this.borderRadius = 8,
    this.icon = Icons.music_note_rounded,
  });

  final Song song;
  final double size;
  final double borderRadius;
  final IconData icon;

  @override
  State<SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<SongArtwork> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = CoverService.instance.resolveSync(widget.song);
    unawaited(_fetchIfNeeded());
  }

  @override
  void didUpdateWidget(covariant SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final songChanged =
        oldWidget.song.hash != widget.song.hash ||
        oldWidget.song.id != widget.song.id ||
        oldWidget.song.coverUrl != widget.song.coverUrl;
    if (!songChanged && oldWidget.size == widget.size) return;
    // didUpdateWidget 之后一定会 rebuild，这里不需要再 setState。
    _url = CoverService.instance.resolveSync(widget.song);
    unawaited(_fetchIfNeeded());
  }

  Future<void> _fetchIfNeeded() async {
    if (_url != null && _url!.isNotEmpty) return;
    final song = widget.song;
    final url = await CoverService.instance.resolve(song);
    if (!mounted || url == null || url.isEmpty) return;
    // 期间切歌了就丢弃这次结果，避免封面错位。
    if (widget.song.hash != song.hash || widget.song.id != song.id) return;
    setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    return Artwork(
      url: _url,
      size: widget.size,
      borderRadius: widget.borderRadius,
      icon: widget.icon,
    );
  }
}
