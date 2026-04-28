import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/browse_item.dart';
import 'models/episode.dart';
import 'models/jellyfin_session.dart';
import 'models/movie.dart';
import 'models/series.dart';

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
  /// `Static=true`, which works for any codec the player can decode natively.
  /// Files that need transcoding will fail to play with this URL — adding the
  /// HLS/transcode endpoint is a follow-up.
  String streamUrl(String itemId) {
    final s = _session;
    return '${s.serverUrl}/Videos/$itemId/stream'
        '?Static=true&api_key=${s.accessToken}';
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
