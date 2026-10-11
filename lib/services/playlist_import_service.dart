import '../models/music_models.dart';
import 'local_song_matcher.dart';
import 'music_api.dart';

class PlaylistImportProgress {
  const PlaylistImportProgress({
    this.processed = 0,
    this.added = 0,
    this.duplicates = 0,
    this.unmatched = const [],
    this.failed = const [],
  });

  final int processed;
  final int added;
  final int duplicates;
  final List<String> unmatched;
  final List<String> failed;
}

class PlaylistImportService {
  PlaylistImportService(this._api);
  final MusicApi _api;

  Future<Song?> match(ExternalPlaylistTrack track) async {
    final identity = LocalSongIdentity(
      track.title,
      track.artist,
      track.duration,
    );
    final songs = await _api
        .searchSongs(identity.query, pageSize: 20)
        .timeout(const Duration(seconds: 20));
    if (track.artist.isNotEmpty || track.duration != null) {
      final candidates = identity.matchCandidates(songs);
      return candidates.isEmpty ? null : candidates.first;
    }
    // Older NetEase parser responses only contain titles. Require an exact title
    // instead of silently importing the first unrelated search result.
    final target = track.title.trim().toLowerCase();
    for (final song in songs) {
      if (song.source == SongSource.kugou &&
          song.hash.isNotEmpty &&
          song.title.trim().toLowerCase() == target) {
        return song;
      }
    }
    return null;
  }

  Future<PlaylistImportProgress> import({
    required String listId,
    required List<ExternalPlaylistTrack> tracks,
    required Set<String> existingHashes,
    required void Function(PlaylistImportProgress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    final hashes = existingHashes.map((hash) => hash.toLowerCase()).toSet();
    final unmatched = <String>[];
    final failed = <String>[];
    var processed = 0;
    var added = 0;
    var duplicates = 0;
    PlaylistImportProgress snapshot() => PlaylistImportProgress(
      processed: processed,
      added: added,
      duplicates: duplicates,
      unmatched: List.unmodifiable(unmatched),
      failed: List.unmodifiable(failed),
    );
    for (final track in tracks) {
      if (shouldCancel()) break;
      try {
        final song = await match(track);
        if (shouldCancel()) break;
        if (song == null) {
          unmatched.add(track.displayName);
        } else if (hashes.contains(song.hash.toLowerCase())) {
          duplicates++;
        } else {
          // Do not time out a write: its outcome would be unknown, and a retry
          // could add it twice. Stop requests take effect after it finishes.
          await _api.addSongsToPlaylist(listId, [song]);
          hashes.add(song.hash.toLowerCase());
          added++;
        }
      } catch (_) {
        failed.add(track.displayName);
      }
      processed++;
      onProgress(snapshot());
    }
    return snapshot();
  }
}
