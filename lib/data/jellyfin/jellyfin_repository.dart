import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/browse_item.dart';
import 'models/jellyfin_session.dart';

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
