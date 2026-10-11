import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:charset/charset.dart';
import 'package:flutter/foundation.dart';

import '../models/music_models.dart';
import 'cache_service.dart';
import 'local_song_matcher.dart';
import 'music_api.dart';

/// Runs in an isolate: read the actual ID3/Vorbis/MP4 lyric tags, without images.
String? readEmbeddedLyricsMetadata(String path) =>
    readMetadata(File(path), getImage: false).lyrics;

class LocalLyricsService {
  LocalLyricsService({
    required MusicApi api,
    CacheService? cache,
    Future<String?> Function(String)? embeddedLyricsReader,
  }) : _api = api,
       _cache = cache,
       _embeddedLyricsReader =
           embeddedLyricsReader ??
           ((path) => compute(readEmbeddedLyricsMetadata, path));

  final MusicApi _api;
  final CacheService? _cache;
  final Future<String?> Function(String) _embeddedLyricsReader;
  static const _requestTimeout = Duration(seconds: 10);

  Future<List<LyricLine>> load(Song song) async {
    final file = File(song.id);
    final dot = file.path.lastIndexOf('.');
    final slash = file.path.lastIndexOf(RegExp(r'[/\\]'));
    final stem = dot > slash ? file.path.substring(0, dot) : file.path;
    for (final extension in ['.lrc', '.LRC']) {
      try {
        final lrc = File('$stem$extension');
        if (!await lrc.exists() || await lrc.length() > 2 * 1024 * 1024) {
          continue;
        }
        final content = decodeLocalLyricBytes(await lrc.readAsBytes());
        final lines = parseLyrics(content);
        // An empty/invalid sidecar must not suppress embedded or online lyrics.
        if (lines.isNotEmpty) return lines;
      } catch (e) {
        debugPrint('Could not read local lyric file: $e');
      }
    }

    String? plainLyrics;
    try {
      final embedded = await _embeddedLyricsReader(song.id);
      final lines = parseLyrics(embedded);
      if (lines.isNotEmpty) return lines;
      if (embedded != null && embedded.trim().isNotEmpty) {
        plainLyrics = embedded.trim();
      }
    } catch (e) {
      debugPrint('Could not read embedded lyrics: $e');
    }

    final cacheKey = 'cache_local_lyric_v1_${song.id}';
    // Replacing an audio file at the same path must invalidate its old match.
    final stat = await file.stat();
    final signature = jsonEncode([
      song.title,
      song.artist,
      song.duration?.inMilliseconds,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
    ]);
    try {
      final cached = await _cache?.read<List<LyricLine>>(
        cacheKey,
        decode: (json) => json['signature'] == signature
            ? (json['lines'] as List? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .map(LyricLine.fromCache)
                  .toList()
            : const [],
      );
      // Local recordings do not change when a TTL expires. Keep usable lyrics
      // available offline until the file changes or the user clears the cache.
      if (cached != null && cached.data.isNotEmpty) return cached.data;
    } catch (e) {
      debugPrint('Could not read local lyric cache: $e');
    }

    final identity = LocalSongIdentity.fromSong(song);
    if (identity.isSearchable) {
      try {
        final results = await _api
            .searchSongs(identity.query, pageSize: 20)
            .timeout(_requestTimeout);
        for (final candidate in identity.matchCandidates(results).take(3)) {
          try {
            // Only the matched online hash is sent to the lyric endpoint.
            final lines = await _api.lyrics(candidate).timeout(_requestTimeout);
            if (lines.isEmpty) continue;
            try {
              await _cache?.write(cacheKey, {
                'signature': signature,
                'matchedHash': candidate.hash,
                'lines': lines.map((line) => line.toCache()).toList(),
              });
            } catch (e) {
              debugPrint('Could not cache matched lyrics: $e');
            }
            return lines;
          } catch (e) {
            debugPrint('Could not fetch matched lyrics: $e');
          }
        }
      } catch (e) {
        debugPrint('Could not match local song lyrics: $e');
      }
    }

    // Untimed embedded text is still readable when a timed match is unavailable.
    // Do not invent timestamps for it.
    return plainLyrics == null
        ? const []
        : [LyricLine(time: Duration.zero, text: plainLyrics)];
  }
}

String decodeLocalLyricBytes(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) {
      throw const FormatException('Truncated UTF-16 lyric');
    }
    final littleEndian = bytes[0] == 0xff;
    return String.fromCharCodes([
      for (var i = 2; i + 1 < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
    ]);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Older Chinese LRC files often use GBK. Keep strict decoding so genuinely
    // corrupt files still fall through to embedded/online lyrics.
    return gbk.decode(bytes);
  }
}
