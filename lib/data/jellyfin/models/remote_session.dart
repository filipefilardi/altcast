/// One row from `GET /Sessions` — another device logged into the same
/// Jellyfin server that we can target with remote-control commands.
class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.deviceName,
    required this.client,
    required this.supportsRemoteControl,
    this.nowPlayingItemId,
    this.nowPlayingTitle,
    this.isPaused = false,
    this.positionTicks,
    this.runTimeTicks,
  });

  final String id;
  final String deviceName;
  final String client;
  final bool supportsRemoteControl;

  final String? nowPlayingItemId;
  final String? nowPlayingTitle;
  final bool isPaused;

  /// Current playback position on the remote device, when it's playing.
  final int? positionTicks;
  final int? runTimeTicks;

  bool get isPlayingSomething => nowPlayingItemId != null;

  factory RemoteSession.fromJson(Map<String, dynamic> json) {
    final nowPlaying = json['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = json['PlayState'] as Map<String, dynamic>?;
    return RemoteSession(
      id: json['Id'] as String,
      deviceName: json['DeviceName'] as String? ?? 'Unknown device',
      client: json['Client'] as String? ?? '',
      supportsRemoteControl:
          json['SupportsRemoteControl'] as bool? ?? false,
      nowPlayingItemId: nowPlaying?['Id'] as String?,
      nowPlayingTitle: nowPlaying?['Name'] as String?,
      isPaused: playState?['IsPaused'] as bool? ?? false,
      positionTicks: playState?['PositionTicks'] as int?,
      runTimeTicks: nowPlaying?['RunTimeTicks'] as int?,
    );
  }
}
