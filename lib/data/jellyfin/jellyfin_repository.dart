import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/browse_item.dart';
import 'models/episode.dart';
import 'models/jellyfin_session.dart';
import 'models/media_stream.dart';
import 'models/movie.dart';
import 'models/series.dart';
import 'models/stream_source.dart';

class _NoSession implements Exception {
  @override
  String toString() => 'No active Jellyfin session';
}

final jellyfinRepositoryProvider = Provider<JellyfinRepository>((ref) {
  return JellyfinRepository(ref.watch(jellyfinApiProvider));
});

class JellyfinRepository {
  JellyfinRepository(this._api);

  final JellyfinApi _api;

  JellyfinSession get _session {
    final s = _api.session;
    if (s == null) throw _NoSession();
    return s;
  }

  /// Items the user has started but not finished. Mixed types (movies,
  /// episodes), ordered most-recently-played first.
  Future<List<BrowseItem>> continueWatching({int limit = 12}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/Resume',
      queryParameters: {
        'MediaTypes': 'Video',
        'Limit': limit,
        'Fields': 'Overview,UserData,PrimaryImageAspectRatio,SeriesPrimaryImage',
        'EnableImages': true,
      },
    );
    return ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<List<BrowseItem>> recentlyAddedMovies({int limit = 16}) async {
    final s = _session;
    final res = await _api.dio.get<List<dynamic>>(
      '/Users/${s.userId}/Items/Latest',
      queryParameters: {
        'IncludeItemTypes': 'Movie',
        'Limit': limit,
        'Fields': 'UserData,ProductionYear',
        'EnableImages': true,
      },
    );
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  /// Search across movies and series. Returns a single mixed list ordered
  /// by Jellyfin's relevance (the API doesn't expose a finer signal).
  /// Empty/blank queries short-circuit to an empty list — callers shouldn't
  /// have to special-case it.
  Future<List<BrowseItem>> search(String query, {int limit = 50}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'searchTerm': trimmed,
        'IncludeItemTypes': 'Movie,Series',
        'Recursive': true,
        'Limit': limit,
        'Fields': 'UserData,ProductionYear,ChildCount',
        'EnableImages': true,
      },
    );
    return ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<List<BrowseItem>> recentlyAddedShows({int limit = 16}) async {
    final s = _session;
    final res = await _api.dio.get<List<dynamic>>(
      '/Users/${s.userId}/Items/Latest',
      queryParameters: {
        'IncludeItemTypes': 'Series',
        'Limit': limit,
        'Fields': 'UserData,ProductionYear,ChildCount',
        'EnableImages': true,
      },
    );
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  /// Full movie metadata for the detail screen.
  Future<Movie> getMovie(String id) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$id',
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty response for movie $id');
    }
    return Movie.fromJson(data);
  }

  /// Full series metadata for the detail screen.
  Future<Series> getSeries(String id) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$id',
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty response for series $id');
    }
    return Series.fromJson(data);
  }

  /// Seasons for a given series, ordered by season number.
  Future<List<Season>> getSeasons(String seriesId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Seasons',
      queryParameters: {
        'UserId': s.userId,
        'Fields': 'ChildCount',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Season.fromJson)
        .toList();
    items.sort((a, b) =>
        (a.indexNumber ?? 1 << 30).compareTo(b.indexNumber ?? 1 << 30));
    return items;
  }

  /// Episodes belonging to a season, ordered by episode number.
  Future<List<Episode>> getEpisodes(String seriesId, String seasonId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Episodes',
      queryParameters: {
        'UserId': s.userId,
        'SeasonId': seasonId,
        'Fields': 'Overview,UserData,RunTimeTicks',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .toList();
    items.sort((a, b) =>
        (a.indexNumber ?? 1 << 30).compareTo(b.indexNumber ?? 1 << 30));
    return items;
  }

  /// Direct-stream URL for a movie or episode. Returns the original file via
  /// `Static=true`, used as a last-resort fallback when [getStreamSource]
  /// fails. Prefer [getStreamSource] — it lets the server decide whether to
  /// direct-stream or transcode.
  String streamUrl(String itemId, {String? mediaSourceId}) {
    final s = _session;
    final ms = mediaSourceId != null ? '&MediaSourceId=$mediaSourceId' : '';
    return '${s.serverUrl}/Videos/$itemId/stream'
        '?Static=true$ms&api_key=${s.accessToken}';
  }

  /// Negotiate playback with the server: ask Jellyfin to pick between
  /// direct-stream and HLS transcoding given a permissive device profile,
  /// then return a [StreamSource] the player can open.
  ///
  /// Falls back to the static [streamUrl] if `PlaybackInfo` errors out so a
  /// flaky negotiation never blocks playback entirely.
  Future<StreamSource> getStreamSource(String itemId) async {
    final s = _session;
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/Items/$itemId/PlaybackInfo',
        queryParameters: {'UserId': s.userId},
        data: {
          // 140 Mbps — effectively "no cap" for everything short of UHD raw.
          'MaxStreamingBitrate': 140000000,
          'EnableDirectPlay': true,
          'EnableDirectStream': true,
          'EnableTranscoding': true,
          'AutoOpenLiveStream': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
          'DeviceProfile': _libmpvDeviceProfile,
        },
      );
      final data = res.data;
      if (data == null) {
        return StreamSource(
          url: streamUrl(itemId),
          isTranscoding: false,
        );
      }

      final sources =
          (data['MediaSources'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      if (sources.isEmpty) {
        return StreamSource(
          url: streamUrl(itemId),
          isTranscoding: false,
        );
      }

      // Use the first source — Jellyfin orders these with the playable one
      // first when EnableDirectPlay/Stream are set.
      final src = sources.first;
      final mediaSourceId = src['Id'] as String?;
      final supportsDirectStream =
          (src['SupportsDirectStream'] as bool?) ?? false;
      final supportsDirectPlay =
          (src['SupportsDirectPlay'] as bool?) ?? false;
      final transcodingUrl = src['TranscodingUrl'] as String?;
      // PlaySessionId can live at the source or top level depending on server
      // version; check both.
      final playSessionId = (src['PlaySessionId'] as String?) ??
          (data['PlaySessionId'] as String?) ??
          const Uuid().v4();
      final externalSubs = _externalSubtitles(src, itemId);

      if (supportsDirectPlay || supportsDirectStream) {
        return StreamSource(
          url: streamUrl(itemId, mediaSourceId: mediaSourceId),
          isTranscoding: false,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          externalSubtitles: externalSubs,
        );
      }

      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        // The TranscodingUrl is server-relative; prepend the base. The URL
        // already carries DeviceId / MediaSourceId / PlaySessionId; we only
        // need to inject the auth token.
        final sep = transcodingUrl.contains('?') ? '&' : '?';
        return StreamSource(
          url: '${s.serverUrl}$transcodingUrl${sep}api_key=${s.accessToken}',
          isTranscoding: true,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          externalSubtitles: externalSubs,
        );
      }

      // Server gave us a media source but no usable URL — last-ditch static.
      return StreamSource(
        url: streamUrl(itemId, mediaSourceId: mediaSourceId),
        isTranscoding: false,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        externalSubtitles: externalSubs,
      );
    } catch (_) {
      // Negotiation failed — fall back to the simple static URL. Better to
      // try playback than to block on a server quirk.
      return StreamSource(
        url: streamUrl(itemId),
        isTranscoding: false,
      );
    }
  }

  /// Pulls subtitle streams Jellyfin can serve as a sidecar from a
  /// `MediaSources[]` entry. Truly-embedded subs (those mpv detects from the
  /// container itself) are intentionally skipped — they'd duplicate what
  /// libmpv already reports via `player.stream.tracks`.
  ///
  /// Filter criteria — broader than just `IsExternal`:
  ///   - `DeliveryMethod == 'External'`, OR
  ///   - `DeliveryUrl` is present (server is willing to extract on demand).
  ///
  /// This catches both true sidecar files (`movie.eng.srt` next to the .mkv)
  /// AND text subtitles embedded in the container that the server can pull
  /// out as VTT/SRT — which mpv often *can't* render correctly itself for
  /// HLS-transcoded streams.
  List<ExternalSubtitle> _externalSubtitles(
    Map<String, dynamic> src,
    String itemId,
  ) {
    final s = _session;
    final mediaSourceId = (src['Id'] as String?) ?? itemId;
    final streams = (src['MediaStreams'] as List?)?.cast<Map<String, dynamic>>();
    if (streams == null) return const [];

    final out = <ExternalSubtitle>[];
    for (final st in streams) {
      if (st['Type'] != 'Subtitle') continue;
      final deliveryMethod = st['DeliveryMethod'] as String?;
      final deliveryUrl = st['DeliveryUrl'] as String?;
      final isExternal = st['IsExternal'] == true;
      final isExtractable = deliveryMethod == 'External' ||
          (deliveryUrl != null && deliveryUrl.isNotEmpty) ||
          isExternal;
      if (!isExtractable) continue;

      final codec = (st['Codec'] as String?)?.toLowerCase();
      final index = st['Index'] as int?;
      final url = _resolveSubtitleUrl(
        deliveryUrl: deliveryUrl,
        itemId: itemId,
        mediaSourceId: mediaSourceId,
        index: index,
        codec: codec,
        token: s.accessToken,
        serverUrl: s.serverUrl,
      );
      if (url == null) continue;

      out.add(ExternalSubtitle(
        id: url,
        url: url,
        title: (st['DisplayTitle'] as String?) ?? (st['Title'] as String?),
        language: st['Language'] as String?,
        codec: codec,
      ));
    }
    return out;
  }

  /// Builds a fully-authenticated URL the player can fetch directly.
  ///
  /// We always ask Jellyfin to deliver the subtitle as **VTT**, even when
  /// the source is SRT/ASS/PGS — this is what the official jellyfin-web
  /// client does, and it's the only format mpv renders consistently across
  /// platforms (some PGS/ASS subs fail silently on iOS/Android). The server
  /// transcodes text-based subs on the fly; bitmap subs that can't be
  /// converted to text simply won't appear, which matches every other
  /// browser-based client's behaviour.
  ///
  /// We use the `/{startPositionTicks}/Stream.vtt` endpoint shape (with 0
  /// for full subs) since older Jellyfin versions don't recognize the
  /// shorter form without a position segment.
  ///
  /// Always ensures `api_key` is present without doubling up — some Jellyfin
  /// versions inline it in `DeliveryUrl`, others don't.
  String? _resolveSubtitleUrl({
    required String? deliveryUrl,
    required String itemId,
    required String mediaSourceId,
    required int? index,
    required String? codec,
    required String token,
    required String serverUrl,
  }) {
    String? raw;
    if (index != null) {
      // Construct directly — bypassing DeliveryUrl gives us full control over
      // the format (vtt) and ensures broken/legacy DeliveryUrls don't lead
      // mpv astray. We still keep DeliveryUrl-based fallback below for the
      // (rare) case where Index is missing.
      raw = '$serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$index/0/'
          'Stream.vtt';
    } else if (deliveryUrl != null && deliveryUrl.isNotEmpty) {
      raw = deliveryUrl.startsWith('http')
          ? deliveryUrl
          : '$serverUrl$deliveryUrl';
    }
    if (raw == null) return null;
    if (raw.contains('api_key=')) return raw;
    final sep = raw.contains('?') ? '&' : '?';
    return '$raw${sep}api_key=$token';
  }

  /// Fetches just the audio + subtitle stream listing for an item — used by
  /// the pre-play picker on detail screens. Read-only; doesn't touch
  /// PlaybackInfo, so no transcoder is spun up as a side effect.
  Future<ItemMediaStreams> getMediaStreams(String itemId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$itemId',
      queryParameters: {
        'Fields': 'MediaSources,MediaStreams',
      },
    );
    final data = res.data;
    if (data == null) {
      return const ItemMediaStreams(audio: [], subtitle: []);
    }

    // MediaStreams can come either flat at the item level or nested under the
    // first MediaSource — check both for robustness across server versions.
    final flat = (data['MediaStreams'] as List?)?.cast<Map<String, dynamic>>();
    final fromSources = ((data['MediaSources'] as List?)
                ?.cast<Map<String, dynamic>>()
                .firstOrNull?['MediaStreams'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    final raw = flat ?? fromSources;

    final audio = <MediaStream>[];
    final subs = <MediaStream>[];
    for (final json in raw) {
      final stream = MediaStream.fromJson(json);
      switch (stream.kind) {
        case MediaStreamKind.audio:
          audio.add(stream);
        case MediaStreamKind.subtitle:
          subs.add(stream);
        case MediaStreamKind.video:
        case MediaStreamKind.unknown:
          break;
      }
    }
    return ItemMediaStreams(audio: audio, subtitle: subs);
  }

  /// Tells the server to release a transcoding session so it can stop the
  /// FFmpeg process and free the segment cache. Best-effort; we never block
  /// dispose on this.
  Future<void> closeActiveEncoding({required String playSessionId}) async {
    try {
      await _api.dio.delete<void>(
        '/Videos/ActiveEncodings',
        queryParameters: {
          'DeviceId': _api.deviceId,
          'PlaySessionId': playSessionId,
        },
      );
    } catch (_) {
      // Swallow — the server cleans up idle transcoders on its own anyway.
    }
  }

  /// Build a poster URL (Primary image). For episodes, prefers the series
  /// poster when [seriesId] is provided since per-episode primary images are
  /// stills, not posters.
  String? posterUrl(
    String itemId,
    String? imageTag, {
    int width = 400,
    String? seriesId,
  }) {
    if (imageTag == null && seriesId == null) return null;
    final s = _session;
    final id = seriesId ?? itemId;
    final tag = imageTag;
    final tagParam = tag != null ? '&tag=$tag' : '';
    return '${s.serverUrl}/Items/$id/Images/Primary'
        '?fillWidth=$width$tagParam&api_key=${s.accessToken}';
  }

  /// Backdrop URL — for the resume card. Falls back to the primary image when
  /// no backdrop tag exists (common for episodes — their `Primary` image is
  /// already a 16:9 still).
  String backdropUrl(
    String itemId,
    String? backdropTag, {
    String? fallbackPrimaryTag,
    int width = 1280,
  }) {
    final s = _session;
    if (backdropTag != null) {
      return '${s.serverUrl}/Items/$itemId/Images/Backdrop'
          '?fillWidth=$width&tag=$backdropTag&api_key=${s.accessToken}';
    }
    final tagParam =
        fallbackPrimaryTag != null ? '&tag=$fallbackPrimaryTag' : '';
    return '${s.serverUrl}/Items/$itemId/Images/Primary'
        '?fillWidth=$width$tagParam&api_key=${s.accessToken}';
  }
}

/// Permissive playback profile for libmpv (the engine media_kit uses).
/// libmpv handles essentially every container/codec, so we tell Jellyfin we
/// can direct-play almost anything and offer HLS as the transcoding fallback
/// when that's not possible (e.g. the server has direct-play disabled, or a
/// codec isn't on the direct-play allow-list).
const Map<String, dynamic> _libmpvDeviceProfile = {
  'Name': 'AltCast (libmpv)',
  'MaxStreamingBitrate': 140000000,
  'MusicStreamingTranscodingBitrate': 256000,
  'TimelineOffsetSeconds': 5,
  'DirectPlayProfiles': [
    {
      'Type': 'Video',
      'Container': 'mp4,m4v,mkv,webm,mov,ts,avi,mpegts,wmv,asf,3gp,3g2,flv',
      'VideoCodec': 'h264,hevc,h265,av1,vp8,vp9,mpeg4,mpeg2video,vc1',
      'AudioCodec':
          'aac,ac3,eac3,mp3,mp2,opus,flac,vorbis,pcm,truehd,dts,dca,wav,wma',
    },
    {
      'Type': 'Audio',
      'Container': 'aac,mp3,opus,flac,wav,m4a,ogg,wma',
    },
  ],
  'TranscodingProfiles': [
    {
      'Type': 'Video',
      'Container': 'ts',
      'Protocol': 'hls',
      'VideoCodec': 'h264',
      'AudioCodec': 'aac,ac3,mp3',
      'Context': 'Streaming',
      'MaxAudioChannels': '6',
      'MinSegments': 1,
      'BreakOnNonKeyFrames': true,
    },
    {
      'Type': 'Audio',
      'Container': 'aac',
      'Protocol': 'http',
      'AudioCodec': 'aac',
      'Context': 'Streaming',
    },
  ],
  'ContainerProfiles': [],
  'CodecProfiles': [],
  'ResponseProfiles': [],
  'SubtitleProfiles': [
    {'Format': 'srt', 'Method': 'External'},
    {'Format': 'ass', 'Method': 'External'},
    {'Format': 'ssa', 'Method': 'External'},
    {'Format': 'vtt', 'Method': 'External'},
    {'Format': 'subrip', 'Method': 'Embed'},
    {'Format': 'pgs', 'Method': 'Embed'},
    {'Format': 'pgssub', 'Method': 'Embed'},
  ],
};
