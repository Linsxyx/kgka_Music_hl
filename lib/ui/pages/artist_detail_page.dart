import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import '../widgets/now_playing_badge.dart';

class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.api,
    required this.artist,
    required this.player,
  });

  final MusicApi api;
  final ArtistRef artist;
  final PlayerController player;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  late final Future<_ArtistDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ArtistDetailData> _load() async {
    final results = await Future.wait([
      widget.api.artistDetail(widget.artist.id),
      widget.api.artistAudios(widget.artist.id, pageSize: 30, sort: 'hot'),
    ]);
    return _ArtistDetailData(
      detail: results[0] as ArtistDetail,
      songs: results[1] as List<Song>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const SizedBox.shrink(),
      ),
      body: FutureBuilder<_ArtistDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ArtistDetailSkeleton();
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _ArtistHeader(
                  detail: data.detail,
                  fallback: widget.artist,
                ),
              ),
              SliverToBoxAdapter(
                child: _SongSectionHeader(
                  count: data.songs.length,
                  onPlayAll: data.songs.isEmpty
                      ? null
                      : () => widget.player.playSong(
                          data.songs.first,
                          queue: List<Song>.of(data.songs),
                        ),
                ),
              ),
              if (data.songs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyArtistSongs(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 26),
                  sliver: SliverList.separated(
                    itemCount: data.songs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final song = data.songs[index];
                      return _ArtistSongRow(
                        song: song,
                        player: widget.player,
                        onTap: () => widget.player.playSong(
                          song,
                          queue: List<Song>.of(data.songs),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ArtistDetailData {
  const _ArtistDetailData({required this.detail, required this.songs});

  final ArtistDetail detail;
  final List<Song> songs;
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.detail, required this.fallback});

  final ArtistDetail detail;
  final ArtistRef fallback;

  @override
  Widget build(BuildContext context) {
    final avatar = detail.avatarUrl ?? fallback.avatarUrl;
    final topPadding = MediaQuery.paddingOf(context).top;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: SizedBox(
        height: topPadding + 286,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (avatar == null)
              const _ArtistPosterFallback()
            else
              Image.network(
                avatar,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) =>
                    const _ArtistPosterFallback(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .20),
                    Colors.black.withValues(alpha: .06),
                    Colors.black.withValues(alpha: .58),
                  ],
                  stops: const [0, .48, 1],
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 26,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    detail.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .22),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        detail.birthday?.isNotEmpty == true
                            ? '生日 ${detail.birthday}'
                            : '歌手 ID ${detail.id}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .88),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistPosterFallback extends StatelessWidget {
  const _ArtistPosterFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: .90),
            const Color(0xFF70D6FF),
            colorScheme.secondary.withValues(alpha: .80),
          ],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: 88,
        color: Colors.white.withValues(alpha: .86),
      ),
    );
  }
}

class _SongSectionHeader extends StatelessWidget {
  const _SongSectionHeader({required this.count, required this.onPlayAll});

  final int count;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 0 ? '歌曲' : '热门歌曲 $count',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          TextButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistSongRow extends StatelessWidget {
  const _ArtistSongRow({
    required this.song,
    required this.player,
    required this.onTap,
  });

  final Song song;
  final PlayerController player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final active = player.currentSong?.hash == song.hash;
        final activeColor = colorScheme.primary;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: .09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Artwork(url: song.coverUrl, size: 50, borderRadius: 9),
                    if (active)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: .9),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: NowPlayingBadge(
                              active: active,
                              playing: player.isPlaying,
                              color: activeColor,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: active ? activeColor : null,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          song.artist,
                          if (song.albumName?.isNotEmpty == true)
                            song.albumName!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active
                              ? activeColor.withValues(alpha: .72)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatDuration(song.duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: active
                        ? activeColor.withValues(alpha: .72)
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArtistDetailSkeleton extends StatelessWidget {
  const _ArtistDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return ListView(
      padding: EdgeInsets.fromLTRB(18, topPadding + 18, 18, 30),
      children: [
        const _SkeletonBox(width: double.infinity, height: 286, radius: 28),
        const SizedBox(height: 24),
        const _SkeletonBox(width: 110, height: 22, radius: 8),
        const SizedBox(height: 18),
        for (var index = 0; index < 8; index++) ...[
          const _SkeletonSongRow(),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SkeletonSongRow extends StatelessWidget {
  const _SkeletonSongRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _SkeletonBox(width: 50, height: 50, radius: 9),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBox(width: double.infinity, height: 16, radius: 6),
              SizedBox(height: 8),
              _SkeletonBox(width: 150, height: 14, radius: 6),
            ],
          ),
        ),
        SizedBox(width: 12),
        _SkeletonBox(width: 42, height: 14, radius: 6),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _EmptyArtistSongs extends StatelessWidget {
  const _EmptyArtistSongs();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        '暂无歌曲',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
