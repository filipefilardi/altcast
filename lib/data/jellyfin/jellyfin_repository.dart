import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/browse_item.dart';
import 'models/episode.dart';
import 'models/intro_skipper_timestamps.dart';
import 'models/jellyfin_session.dart';
import 'models/media_stream.dart';
import 'models/movie.dart';
import 'models/person_details.dart';
import 'models/series.dart';
import 'models/stream_source.dart';
import '../local/playback_preferences.dart';

enum LibrarySort { recentlyAdded, nameAsc, nameDesc, yearDesc }

class LibraryFilter {
  const LibraryFilter({
    this.genre,
    this.year,
    this.unwatchedOnly = false,
    this.sort = LibrarySort.recentlyAdded,
  });

  final String? genre;
  final int? year;
  final bool unwatchedOnly;
  final LibrarySort sort;
}

class LibraryPage {
  const LibraryPage({
    required this.items,
    required this.startIndex,
    required this.limit,
    required this.totalRecordCount,
    this.fetchedItemCount,
  });

  final List<BrowseItem> items;
  final int startIndex;
  final int limit;
  final int totalRecordCount;
  final int? fetchedItemCount;

  bool get hasMore =>
      startIndex + (fetchedItemCount ?? items.length) < totalRecordCount;
}

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
        'Fields':
            'Overview,UserData,PrimaryImageAspectRatio,SeriesPrimaryImage',
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
    return searchAdvanced(query, limit: limit);
  }

  Future<List<BrowseItem>> searchAdvanced(
    String query, {
    int limit = 50,
    String? genre,
    int? year,
    bool unwatchedOnly = false,
    String itemTypes = 'Movie,Series',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final s = _session;
    final queryParameters = <String, dynamic>{
      'searchTerm': trimmed,
      'IncludeItemTypes': itemTypes,
      'Recursive': true,
      'Limit': limit,
      'Fields': 'UserData,ProductionYear,ChildCount',
      'EnableImages': true,
      if (genre != null && genre.trim().isNotEmpty) 'Genres': genre.trim(),
      if (year != null) 'Years': '$year',
      if (unwatchedOnly) 'Filters': 'IsUnplayed',
    };
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: queryParameters,
    );
    return ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
  }

  Future<LibraryPage> browseMovies({
    int startIndex = 0,
    int limit = 30,
    LibraryFilter filter = const LibraryFilter(),
  }) {
    return _browse(
      itemTypes: 'Movie',
      startIndex: startIndex,
      limit: limit,
      filter: filter,
    );
  }

  Future<LibraryPage> browseShows({
    int startIndex = 0,
    int limit = 30,
    LibraryFilter filter = const LibraryFilter(),
  }) {
    return _browse(
      itemTypes: 'Series',
      startIndex: startIndex,
      limit: limit,
      filter: filter,
    );
  }

  Future<LibraryPage> browseCollections({
    int startIndex = 0,
    int limit = 30,
    LibraryFilter filter = const LibraryFilter(),
  }) {
    return _browse(
      itemTypes: 'BoxSet',
      startIndex: startIndex,
      limit: limit,
      filter: filter,
    );
  }

  Future<List<String>> getGenres({required String itemType}) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Genres',
      queryParameters: {'UserId': s.userId, 'IncludeItemTypes': itemType},
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return items
        .map((e) => (e['Name'] as String?)?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  Future<LibraryPage> _browse({
    required String itemTypes,
    required int startIndex,
    required int limit,
    required LibraryFilter filter,
  }) async {
    final s = _session;
    final params = <String, dynamic>{
      'IncludeItemTypes': itemTypes,
      'Recursive': true,
      'StartIndex': startIndex,
      'Limit': limit,
      'Fields': 'UserData,ProductionYear,ChildCount',
      'EnableImages': true,
      ..._sortParams(filter.sort),
      if (filter.genre != null && filter.genre!.trim().isNotEmpty)
        'Genres': filter.genre!.trim(),
      if (filter.year != null) 'Years': '${filter.year}',
      if (filter.unwatchedOnly) 'Filters': 'IsUnplayed',
    };
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: params,
    );
    final data = res.data ?? const <String, dynamic>{};
    final items = ((data['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
    final resolvedItems = itemTypes == 'Series'
        ? await _resolveSeriesSeasonCounts(items)
        : items;
    return LibraryPage(
      items: resolvedItems,
      startIndex: startIndex,
      limit: limit,
      totalRecordCount:
          data['TotalRecordCount'] as int? ?? resolvedItems.length,
      fetchedItemCount: items.length,
    );
  }

  Map<String, String> _sortParams(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.nameAsc:
        return const {'SortBy': 'SortName', 'SortOrder': 'Ascending'};
      case LibrarySort.nameDesc:
        return const {'SortBy': 'SortName', 'SortOrder': 'Descending'};
      case LibrarySort.yearDesc:
        return const {
          'SortBy': 'ProductionYear,SortName',
          'SortOrder': 'Descending',
        };
      case LibrarySort.recentlyAdded:
        return const {
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending',
        };
    }
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
    final items = (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList();
    return _resolveSeriesSeasonCounts(items);
  }

  Future<List<BrowseItem>> _resolveSeriesSeasonCounts(
    List<BrowseItem> items,
  ) async {
    final resolved = await Future.wait(
      items.map((item) async {
        if (item.kind != MediaKind.series) return item;
        final stats = await _getSeriesAvailableStats(item);
        if (stats == null) return item;
        if (stats.episodeCount <= 0) return null;
        return item.copyWithChildCount(stats.seasonCount);
      }),
    );
    return resolved.whereType<BrowseItem>().toList(growable: false);
  }

  Future<({int seasonCount, int episodeCount})?> _getSeriesAvailableStats(
    BrowseItem item,
  ) async {
    try {
      final seasons = await getSeasons(item.id);
      if (seasons.isEmpty) return (seasonCount: 0, episodeCount: 0);

      var seasonCount = 0;
      var episodeCount = 0;
      final unknownSeasons = <Season>[];

      for (final season in seasons) {
        final count = season.episodeCount;
        if (count == null) {
          unknownSeasons.add(season);
          continue;
        }
        if (count > 0) {
          seasonCount++;
          episodeCount += count;
        }
      }

      if (unknownSeasons.isNotEmpty) {
        final resolvedCounts = await Future.wait(
          unknownSeasons.map((season) async {
            try {
              return (await getEpisodes(item.id, season.id)).length;
            } on DioException {
              return null;
            }
          }),
        );
        for (final count in resolvedCounts) {
          if (count == null || count <= 0) continue;
          seasonCount++;
          episodeCount += count;
        }
      }

      return (seasonCount: seasonCount, episodeCount: episodeCount);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return (seasonCount: 0, episodeCount: 0);
      }
      final existing = item.childCount;
      return existing == null || existing <= 0
          ? null
          : (seasonCount: existing, episodeCount: 1);
    }
  }

  Future<List<BrowseItem>> getCollectionItems(
    String collectionId, {
    int limit = 100,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'ParentId': collectionId,
        'IncludeItemTypes': 'Movie,Series,Season,Episode,BoxSet',
        'Recursive': false,
        'Limit': limit,
        'Fields': 'UserData,ProductionYear,ChildCount',
        'EnableImages': true,
        'SortBy': 'ProductionYear,SortName',
        'SortOrder': 'Ascending',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList(growable: false);
    return _resolveSeriesSeasonCounts(items);
  }

  /// Full movie metadata for the detail screen.
  Future<Movie> getMovie(String id) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$id',
      queryParameters: const {'Fields': 'People,OriginalLanguage,Tags'},
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
      queryParameters: const {'Fields': 'People,OriginalLanguage,Tags'},
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
      queryParameters: {'UserId': s.userId, 'Fields': 'ChildCount'},
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Season.fromJson)
        .toList();
    items.sort(
      (a, b) => (a.indexNumber ?? 1 << 30).compareTo(b.indexNumber ?? 1 << 30),
    );
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
    items.sort(
      (a, b) => (a.indexNumber ?? 1 << 30).compareTo(b.indexNumber ?? 1 << 30),
    );
    return items;
  }

  /// Toggle favorite (heart) for an item. Maps to Jellyfin's
  /// `POST/DELETE /Users/{userId}/FavoriteItems/{itemId}`.
  Future<void> setFavorite(String itemId, {required bool favorite}) async {
    final s = _session;
    final path = '/Users/${s.userId}/FavoriteItems/$itemId';
    if (favorite) {
      await _api.dio.post<void>(path);
    } else {
      await _api.dio.delete<void>(path);
    }
  }

  /// Mark an item as played / unplayed. Maps to Jellyfin's
  /// `POST/DELETE /Users/{userId}/PlayedItems/{itemId}`.
  Future<void> setPlayed(String itemId, {required bool played}) async {
    final s = _session;
    final path = '/Users/${s.userId}/PlayedItems/$itemId';
    if (played) {
      await _api.dio.post<void>(path);
    } else {
      await _api.dio.delete<void>(path);
    }
  }

  Future<List<BrowseItem>> getSimilarItems(
    String itemId, {
    int limit = 16,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Items/$itemId/Similar',
      queryParameters: {
        'UserId': s.userId,
        'Limit': limit,
        'Fields': 'UserData,ProductionYear,ChildCount',
        'EnableImages': true,
      },
    );
    return ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList(growable: false);
  }

  Future<PersonDetails> getPerson(String personId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$personId',
      queryParameters: const {
        'Fields': 'Overview,PremiereDate,EndDate,ProductionLocations',
      },
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty response for person $personId');
    }
    return PersonDetails.fromJson(data);
  }

  Future<List<BrowseItem>> getItemsByPerson(
    String personId, {
    int limit = 36,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items',
      queryParameters: {
        'PersonIds': personId,
        'IncludeItemTypes': 'Movie,Series',
        'Recursive': true,
        'Limit': limit,
        'Fields': 'UserData,ProductionYear,ChildCount',
        'EnableImages': true,
        'SortBy': 'PremiereDate,SortName',
        'SortOrder': 'Descending',
      },
    );
    return ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(BrowseItem.fromJson)
        .toList(growable: false);
  }

  Future<Season> getSeason(String seasonId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$seasonId',
      queryParameters: const {'Fields': 'ChildCount'},
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty response for season $seasonId');
    }
    return Season.fromJson(data);
  }

  Future<Episode> getEpisode(String episodeId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$episodeId',
      queryParameters: const {
        'Fields':
            'Overview,UserData,RunTimeTicks,SeriesId,SeasonId,People,PremiereDate,CommunityRating',
      },
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty response for episode $episodeId');
    }
    return Episode.fromJson(data);
  }

  /// Lightweight title lookup for the player chrome.
  Future<String> getItemDisplayTitle(String itemId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$itemId',
      queryParameters: const {
        'Fields':
            'SeriesName,ParentIndexNumber,IndexNumber,ProductionYear,PremiereDate',
      },
    );
    final data = res.data;
    if (data == null) return 'Now playing';
    final name = (data['Name'] as String?)?.trim();
    final seriesName = (data['SeriesName'] as String?)?.trim();
    final season = data['ParentIndexNumber'] as int?;
    final episode = data['IndexNumber'] as int?;
    final year =
        data['ProductionYear'] as int? ??
        DateTime.tryParse((data['PremiereDate'] as String?) ?? '')?.year;
    final title = name == null || name.isEmpty
        ? null
        : year == null
        ? name
        : '$name ($year)';
    if (seriesName != null &&
        seriesName.isNotEmpty &&
        name != null &&
        name.isNotEmpty) {
      final number = season != null && episode != null
          ? 'S$season E${episode.toString().padLeft(2, '0')}'
          : null;
      return [seriesName, ?number, title].join(' · ');
    }
    return title == null || title.isEmpty ? 'Now playing' : title;
  }

  /// Picks the episode that follows S[seasonNumber]E[episodeNumber] for
  /// autoplay/Next-Up. Searches the current season first, then falls back to
  /// the start of the next season — bounded queries so long-running shows
  /// (anime, soaps with hundreds of episodes) don't get clipped by a list cap.
  Future<Episode?> getNextEpisode({
    required String seriesId,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    final inSameSeason = await _firstEpisodeAfter(
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      afterEpisodeNumber: episodeNumber,
    );
    if (inSameSeason != null) return inSameSeason;
    return _firstEpisodeAfter(
      seriesId: seriesId,
      seasonNumber: seasonNumber + 1,
      afterEpisodeNumber: 0,
    );
  }

  Future<Episode?> _firstEpisodeAfter({
    required String seriesId,
    required int seasonNumber,
    required int afterEpisodeNumber,
  }) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Episodes',
      queryParameters: {
        'UserId': s.userId,
        'Season': seasonNumber,
        'Fields': 'Overview,UserData,RunTimeTicks,SeriesId,SeasonId',
      },
    );
    final items = ((res.data?['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .where((e) => e.indexNumber != null)
        .toList();
    items.sort((a, b) => a.indexNumber!.compareTo(b.indexNumber!));
    for (final ep in items) {
      if (ep.indexNumber! > afterEpisodeNumber) return ep;
    }
    return null;
  }

  /// Fetches Intro Skipper segment times for an episode or movie, if the
  /// server has a compatible plugin installed and analysis exists.
  ///
  /// Tries fork `GET …/Episode/{id}/Timestamps` (several URL prefixes), legacy
  /// `IntroTimestamps`, then merges. Any failure or empty segments yields only
  /// whatever other calls succeeded — playback never depends on this call.
  Future<IntroSkipperTimestamps?> getIntroSkipperTimestamps(
    String itemId,
  ) async {
    if (_api.session == null) return null;
    IntroSkipperTimestamps? merged;

    Future<void> mergeModern(String path) async {
      try {
        final res = await _api.dio.get<Map<String, dynamic>>(
          path,
          options: Options(validateStatus: (s) => s == 200 || s == 404),
        );
        if (res.statusCode == 200 && res.data != null) {
          final parsed = IntroSkipperTimestamps.fromPluginTimestampsJson(
            res.data!,
          );
          merged = merged == null ? parsed : merged!.mergePreferNonNull(parsed);
        }
      } catch (_) {}
    }

    Future<void> mergeLegacy(String path) async {
      try {
        final res = await _api.dio.get<Map<String, dynamic>>(
          path,
          options: Options(validateStatus: (s) => s == 200 || s == 404),
        );
        if (res.statusCode == 200 && res.data != null) {
          final fromLegacy = IntroSkipperTimestamps.fromLegacyIntroV1Json(
            res.data!,
          );
          merged = merged == null
              ? fromLegacy
              : merged!.mergePreferNonNull(fromLegacy);
        }
      } catch (_) {}
    }

    await mergeModern('/Episode/$itemId/Timestamps');
    await mergeModern('/IntroSkipper/Episode/$itemId/Timestamps');

    await mergeLegacy('/Episode/$itemId/IntroTimestamps/v1');
    await mergeLegacy('/Episode/$itemId/IntroTimestamps');

    return merged?.hasAny == true ? merged : null;
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
  Future<StreamSource> getStreamSource(
    String itemId, {
    StreamingQuality quality = StreamingQuality.auto,
  }) async {
    final s = _session;
    final maxBitrate = _maxStreamingBitrate(quality);
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/Items/$itemId/PlaybackInfo',
        queryParameters: {'UserId': s.userId},
        data: {
          'MaxStreamingBitrate': maxBitrate,
          'EnableDirectPlay': true,
          'EnableDirectStream': true,
          'EnableTranscoding': true,
          'AutoOpenLiveStream': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
          'DeviceProfile': {
            ..._libmpvDeviceProfile,
            'MaxStreamingBitrate': maxBitrate,
          },
        },
      );
      final data = res.data;
      if (data == null) {
        return StreamSource(url: streamUrl(itemId), isTranscoding: false);
      }

      final sources =
          (data['MediaSources'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      if (sources.isEmpty) {
        return StreamSource(url: streamUrl(itemId), isTranscoding: false);
      }

      // Use the first source — Jellyfin orders these with the playable one
      // first when EnableDirectPlay/Stream are set.
      final src = sources.first;
      final mediaSourceId = src['Id'] as String?;
      final supportsDirectStream =
          (src['SupportsDirectStream'] as bool?) ?? false;
      final supportsDirectPlay = (src['SupportsDirectPlay'] as bool?) ?? false;
      final transcodingUrl = src['TranscodingUrl'] as String?;
      // PlaySessionId can live at the source or top level depending on server
      // version; check both.
      final playSessionId =
          (src['PlaySessionId'] as String?) ??
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
      return StreamSource(url: streamUrl(itemId), isTranscoding: false);
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
    final streams = (src['MediaStreams'] as List?)
        ?.cast<Map<String, dynamic>>();
    if (streams == null) return const [];

    final out = <ExternalSubtitle>[];
    for (final st in streams) {
      if (st['Type'] != 'Subtitle') continue;
      final deliveryMethod = st['DeliveryMethod'] as String?;
      final deliveryUrl = st['DeliveryUrl'] as String?;
      final isExternal = st['IsExternal'] == true;
      final isExtractable =
          deliveryMethod == 'External' ||
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

      out.add(
        ExternalSubtitle(
          id: url,
          url: url,
          streamIndex: index,
          title: (st['DisplayTitle'] as String?) ?? (st['Title'] as String?),
          language: st['Language'] as String?,
          codec: codec,
        ),
      );
    }
    return out;
  }

  /// Builds a fully-authenticated URL the player can fetch directly.
  ///
  /// Mirrors the exact shape the official jellyfin-web client uses, which
  /// is the most-tested combination across server versions:
  ///
  ///   /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.vtt?api_key=…
  ///
  /// Prefer Jellyfin's `DeliveryUrl` whenever present because it already
  /// encodes the server-selected subtitle delivery format/path and tends to
  /// match what jellyfin-web uses.
  ///
  /// If `DeliveryUrl` is absent, text subtitle codecs fall back to a forced
  /// VTT path. Bitmap codecs (PGS/PGSSUB/DVDSub/VobSub) cannot be converted to
  /// VTT, so they require `DeliveryUrl`.
  ///
  /// Returning `null` for bitmap codecs without a `DeliveryUrl` keeps them out
  /// of the external-track picker instead of showing a selectable row that can
  /// never render text.
  ///
  /// `api_key` is URL-encoded (Jellyfin tokens are usually plain hex but
  /// we encode defensively) and only injected once.
  String? _resolveSubtitleUrl({
    required String? deliveryUrl,
    required String itemId,
    required String mediaSourceId,
    required int? index,
    required String? codec,
    required String token,
    required String serverUrl,
  }) {
    final normalizedCodec = codec?.toLowerCase();
    final isBitmapCodec =
        normalizedCodec == 'pgs' ||
        normalizedCodec == 'pgssub' ||
        normalizedCodec == 'dvdsub' ||
        normalizedCodec == 'vobsub';
    final hasDeliveryUrl = deliveryUrl != null && deliveryUrl.isNotEmpty;

    String? raw;
    if (hasDeliveryUrl) {
      raw = deliveryUrl.startsWith('http')
          ? deliveryUrl
          : '$serverUrl$deliveryUrl';
    } else if (isBitmapCodec) {
      return null;
    } else if (index != null) {
      raw =
          '$serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$index/'
          'Stream.vtt';
    }
    if (raw == null) return null;
    if (raw.contains('api_key=')) return raw;
    final sep = raw.contains('?') ? '&' : '?';
    return '$raw${sep}api_key=${Uri.encodeQueryComponent(token)}';
  }

  /// Fetches just the audio + subtitle stream listing for an item — used by
  /// the pre-play picker on detail screens. Read-only; doesn't touch
  /// PlaybackInfo, so no transcoder is spun up as a side effect.
  Future<ItemMediaStreams> getMediaStreams(String itemId) async {
    final s = _session;
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/Users/${s.userId}/Items/$itemId',
      queryParameters: {'Fields': 'MediaSources,MediaStreams'},
    );
    final data = res.data;
    if (data == null) {
      return const ItemMediaStreams(audio: [], subtitle: []);
    }

    // MediaStreams can come either flat at the item level or nested under the
    // first MediaSource — check both for robustness across server versions.
    final flat = (data['MediaStreams'] as List?)?.cast<Map<String, dynamic>>();
    final fromSources =
        ((data['MediaSources'] as List?)
                    ?.cast<Map<String, dynamic>>()
                    .firstOrNull?['MediaStreams']
                as List?)
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
    final tagParam = fallbackPrimaryTag != null
        ? '&tag=$fallbackPrimaryTag'
        : '';
    return '${s.serverUrl}/Items/$itemId/Images/Primary'
        '?fillWidth=$width$tagParam&api_key=${s.accessToken}';
  }

  String? personImageUrl(
    String? personId,
    String? imageTag, {
    int width = 160,
  }) {
    if (personId == null || personId.isEmpty) return null;
    final s = _session;
    final tagParam = (imageTag != null && imageTag.isNotEmpty)
        ? '&tag=$imageTag'
        : '';
    return '${s.serverUrl}/Items/$personId/Images/Primary'
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
    {'Type': 'Audio', 'Container': 'aac,mp3,opus,flac,wav,m4a,ogg,wma'},
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

int _maxStreamingBitrate(StreamingQuality quality) {
  switch (quality) {
    case StreamingQuality.dataSaver:
      return 4000000;
    case StreamingQuality.auto:
      return 20000000;
    case StreamingQuality.high:
      return 140000000;
  }
}
