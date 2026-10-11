import '../models/music_models.dart';

/// A local path is not a Kugou hash. Match metadata before requesting lyrics.
class LocalSongIdentity {
  const LocalSongIdentity(this.title, this.artist, this.duration);

  factory LocalSongIdentity.fromSong(Song song) {
    var title = song.title.trim();
    var artist = song.artist.trim();
    if (_isUnknown(artist)) artist = '';
    if (_isUnknown(title)) {
      title = song.id.replaceAll('\\', '/').split('/').last;
    }
    title = title.replaceFirst(
      RegExp(
        r'\.(mp3|flac|m4a|ogg|opus|wav|aac|ape|wma)$',
        caseSensitive: false,
      ),
      '',
    );
    if (artist.isNotEmpty) {
      title = stripArtistNamePrefix(title, artist);
    } else {
      // MediaStore sometimes exposes the filename instead of ID3 tags.
      final parts = title.split(' - ');
      if (parts.length == 2 && parts.every((part) => part.trim().isNotEmpty)) {
        artist = parts.first.trim();
        title = parts.last.trim();
      }
    }
    return LocalSongIdentity(title.trim(), artist, song.duration);
  }

  final String title;
  final String artist;
  final Duration? duration;

  String get query => [artist, title].where((s) => s.isNotEmpty).join(' ');
  bool get isSearchable => !_isUnknown(title) && _normalize(title).isNotEmpty;

  List<Song> matchCandidates(List<Song> songs) {
    final ranked = <({Song song, int delta})>[];
    final seen = <String>{};
    for (final song in songs) {
      if (song.source != SongSource.kugou ||
          song.hash.isEmpty ||
          !seen.add(song.hash) ||
          _normalize(song.title) != _normalize(title)) {
        continue;
      }
      final expectedArtists = _artists(artist);
      final actualArtists = _artists(song.artist);
      if (expectedArtists.isNotEmpty &&
          !actualArtists.containsAll(expectedArtists)) {
        continue;
      }
      final hasDurations =
          duration != null &&
          duration! > Duration.zero &&
          song.duration != null &&
          song.duration! > Duration.zero;
      final delta = hasDurations
          ? (duration! - song.duration!).inMilliseconds.abs()
          : 1 << 30;
      // Unknown singers need a close duration match; otherwise prefer no lyric
      // to displaying lyrics for an unrelated recording with the same title.
      if (expectedArtists.isEmpty && (!hasDurations || delta > 3000)) continue;
      if (hasDurations && delta > 8000) continue;
      ranked.add((song: song, delta: delta));
    }
    ranked.sort((a, b) => a.delta.compareTo(b.delta));
    return ranked.map((entry) => entry.song).toList();
  }

  static Set<String> _artists(String value) => value
      .split(RegExp(r'\s*[/、&;；]\s*'))
      .where((name) => !_isUnknown(name))
      .map(_normalize)
      .where((name) => name.isNotEmpty)
      .toSet();

  static bool _isUnknown(String value) => const {
    '',
    '未知歌曲',
    '未知艺人',
    '未知歌手',
    '未知艺术家',
    '<unknown>',
    'unknown',
  }.contains(value.trim().toLowerCase());

  // Keep version words such as Live/伴奏/Remix; only ignore punctuation.
  static String _normalize(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s\-_.·,，。:：'"“”‘’!！?？()（）\[\]【】]'''), '');
}
