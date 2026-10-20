import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/music_models.dart';
import '../design_tokens.dart';

/// 打开歌曲详细信息页（与「查看评论」同层级，从歌曲操作弹层进入）。
void openSongDetailPage(BuildContext context, Song song) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SongDetailPage(song: song)),
  );
}

/// 歌曲详细信息页。
///
/// 版式沿用项目里列表页那一套：分组卡片 + [ListTile]（左图标、右文字），
/// 与歌曲操作弹层里的条目视觉一致。信息分三组，各自独立成卡。
class SongDetailPage extends StatelessWidget {
  const SongDetailPage({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: false, title: const Text('歌曲信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          _InfoGroup(
            title: '基本信息',
            tiles: [
              _InfoTile(
                icon: Icons.music_note_rounded,
                label: '歌名',
                value: song.title,
              ),
              _InfoTile(
                icon: Icons.person_rounded,
                label: '歌手',
                value: song.artist,
              ),
              _InfoTile(
                icon: Icons.album_rounded,
                label: '专辑',
                value: _orUnknown(song.albumName),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoGroup(
            title: '发行信息',
            tiles: [
              _InfoTile(
                icon: Icons.event_rounded,
                label: '发行日期',
                value: _releaseDateText,
              ),
              _InfoTile(
                icon: Icons.schedule_rounded,
                label: '时长',
                value: _durationText,
              ),
              _InfoTile(
                icon: Icons.source_rounded,
                label: '音源',
                value: _sourceText,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoGroup(
            title: '音源标识',
            tiles: [
              _InfoTile(
                icon: Icons.tag_rounded,
                label: '歌曲 ID',
                value: song.id,
                copyable: true,
              ),
              _InfoTile(
                icon: Icons.fingerprint_rounded,
                label: 'Hash',
                value: song.hash,
                copyable: true,
              ),
              if ((song.albumId ?? '').isNotEmpty)
                _InfoTile(
                  icon: Icons.album_outlined,
                  label: '专辑 ID',
                  value: song.albumId!,
                  copyable: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _orUnknown(String? value) =>
      value == null || value.isEmpty ? '未知' : value;

  String get _releaseDateText {
    final date = song.releaseDate;
    if (date == null) return '未知';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String get _durationText {
    final duration = song.duration;
    if (duration == null || duration <= Duration.zero) return '未知';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get _sourceText => switch (song.source) {
    SongSource.kugou => '酷狗音乐',
    SongSource.netease => '网易云音乐',
    SongSource.local => '本地文件',
  };
}

/// 一组信息卡片：分组标题 + 若干 [ListTile]。
class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.title, required this.tiles});

  final String title;
  final List<_InfoTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.sm),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 单条信息：左图标、右文字，与弹层里的操作条目同款。
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(label),
      subtitle: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
      ),
      trailing: copyable
          ? Icon(
              Icons.copy_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
            )
          : null,
      onTap: copyable
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('已复制$label'),
                    duration: const Duration(milliseconds: 1200),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            }
          : null,
    );
  }
}
