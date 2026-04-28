import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/remote_session.dart';

final remoteSessionsRepositoryProvider =
    Provider<RemoteSessionsRepository>((ref) {
  return RemoteSessionsRepository(ref.watch(jellyfinApiProvider));
});

/// Talks to Jellyfin's session/control endpoints. Filters out our own
/// device so we never try to remote-control ourselves.
class RemoteSessionsRepository {
  RemoteSessionsRepository(this._api);
  final JellyfinApi _api;

  /// All remote-controllable sessions other than ours, currently active.
  Future<List<RemoteSession>> listSessions() async {
    final res = await _api.dio.get<List<dynamic>>(
      '/Sessions',
      queryParameters: {'ActiveWithinSeconds': 360},
    );
    final mine = _api.deviceId;
    return (res.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(RemoteSession.fromJson)
        .where((s) => s.supportsRemoteControl)
        // Don't list our own session — picking it would be a no-op loop.
        .where((s) => s.id != mine)
        .toList();
  }

  /// Tell a remote session to start playing an item now.
  Future<void> playOnSession({
    required String sessionId,
    required String itemId,
    int startPositionTicks = 0,
  }) {
    return _api.dio.post<void>(
      '/Sessions/$sessionId/Playing',
      queryParameters: {
        'ItemIds': itemId,
        'PlayCommand': 'PlayNow',
        if (startPositionTicks > 0) 'StartPositionTicks': startPositionTicks,
      },
    );
  }

  /// Send a transport command. [command] is one of `PlayPause`, `Stop`,
  /// `NextTrack`, `PreviousTrack`. For seek use [seekOnSession].
  Future<void> sendCommand({
    required String sessionId,
    required String command,
  }) {
    return _api.dio.post<void>('/Sessions/$sessionId/Playing/$command');
  }

  Future<void> seekOnSession({
    required String sessionId,
    required int positionTicks,
  }) {
    return _api.dio.post<void>(
      '/Sessions/$sessionId/Playing/Seek',
      queryParameters: {'SeekPositionTicks': positionTicks},
    );
  }
}
