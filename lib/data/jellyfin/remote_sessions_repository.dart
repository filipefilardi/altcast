import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/remote_session.dart';

final remoteSessionsRepositoryProvider = Provider<RemoteSessionsRepository>((
  ref,
) {
  return RemoteSessionsRepository(ref.watch(jellyfinApiProvider));
});

/// Talks to Jellyfin's session/control endpoints. Filters out our own
/// device so we never try to remote-control ourselves.
class RemoteSessionsRepository {
  RemoteSessionsRepository(this._api);
  final JellyfinApi _api;

  /// All remote-controllable sessions for this user, excluding this device.
  Future<List<RemoteSession>> listSessions() async {
    final ownUserId = _api.session?.userId;
    if (ownUserId == null) return const [];
    final res = await _api.dio.get<List<dynamic>>(
      '/Sessions',
      queryParameters: {'ControllableByUserId': ownUserId},
    );
    return filterSessions(
      (res.data ?? const []).cast<Map<String, dynamic>>().map(
        RemoteSession.fromJson,
      ),
    );
  }

  List<RemoteSession> filterSessions(Iterable<RemoteSession> sessions) {
    final ownUserId = _api.session?.userId;
    if (ownUserId == null) return const [];
    final ownDeviceId = _api.deviceId;
    return sessions
        .where(
          (s) =>
              s.supportsRemoteControl &&
              s.deviceId != ownDeviceId &&
              s.userId == ownUserId,
        )
        .toList(growable: false);
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
        'itemIds': itemId,
        'playCommand': 'PlayNow',
        if (startPositionTicks > 0) 'startPositionTicks': startPositionTicks,
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

  Future<void> playPause(String sessionId) =>
      sendCommand(sessionId: sessionId, command: 'PlayPause');

  Future<void> stop(String sessionId) =>
      sendCommand(sessionId: sessionId, command: 'Stop');

  Future<void> seek(String sessionId, Duration position) {
    return seekOnSession(
      sessionId: sessionId,
      positionTicks: position.inMicroseconds * 10,
    );
  }

  Future<void> seekOnSession({
    required String sessionId,
    required int positionTicks,
  }) {
    return _api.dio.post<void>(
      '/Sessions/$sessionId/Playing/Seek',
      queryParameters: {'seekPositionTicks': positionTicks},
    );
  }

  Future<void> setVolume(String sessionId, int volume) {
    return _generalCommand(sessionId, 'SetVolume', {
      'Volume': volume.clamp(0, 100).toString(),
    });
  }

  Future<void> setMute(String sessionId, {required bool muted}) {
    return _generalCommand(sessionId, muted ? 'Mute' : 'Unmute');
  }

  Future<void> _generalCommand(
    String sessionId,
    String name, [
    Map<String, String>? arguments,
  ]) {
    return _api.dio.post<void>(
      '/Sessions/$sessionId/Command',
      data: {
        'Name': name,
        ...?arguments == null ? null : {'Arguments': arguments},
      },
    );
  }
}
