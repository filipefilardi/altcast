import '../../data/jellyfin/jellyfin_api.dart';

/// Posts playback events to Jellyfin's `/Sessions/Playing*` endpoints so
/// resume positions, watched-state, and Continue Watching stay in sync.
///
/// All posts are best-effort: failures are swallowed because scrobbling
/// must never crash playback. Tied 1-to-1 with a `VideoPlayerScreen`
/// instance — there's no global scrobbler today (unlike AltSound, where
/// audio plays outside the now-playing screen).
class Scrobbler {
  Scrobbler({
    required this.api,
    required this.itemId,
    required this.playMethod,
    this.playSessionId,
  });

  final JellyfinApi api;
  final String itemId;

  /// `'DirectStream'` or `'Transcode'` — comes from the negotiated
  /// `StreamSource`. Some Jellyfin housekeeping (e.g. transcoder cleanup
  /// on stop) keys off this value.
  final String playMethod;

  final String? playSessionId;

  Future<void> start({required int positionTicks}) {
    return _post('/Sessions/Playing', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      'IsPaused': false,
      'PlayMethod': playMethod,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> progress({
    required int positionTicks,
    required bool isPaused,
    required String eventName,
  }) {
    return _post('/Sessions/Playing/Progress', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      'IsPaused': isPaused,
      'EventName': eventName,
      'PlayMethod': playMethod,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> stop({required int positionTicks}) {
    return _post('/Sessions/Playing/Stopped', {
      'ItemId': itemId,
      'PositionTicks': positionTicks,
      if (playSessionId != null) 'PlaySessionId': playSessionId,
    });
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    if (api.session == null) return;
    try {
      await api.dio.post<dynamic>(path, data: body);
    } catch (_) {
      // Swallow: scrobbling is best-effort.
    }
  }
}
