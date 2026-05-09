/// One row from `GET /Sessions` — another device logged into the same
/// Jellyfin server that we can target with remote-control commands.
class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.client,
    required this.userId,
    required this.userName,
    required this.supportsRemoteControl,
    required this.supportedCommands,
    this.nowPlayingItemId,
    this.nowPlayingTitle,
    this.isPaused = false,
    this.isMuted = false,
    this.volumeLevel,
    this.positionTicks,
    this.runTimeTicks,
    this.observedAt,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String client;
  final String userId;
  final String userName;
  final bool supportsRemoteControl;
  final Set<String> supportedCommands;

  final String? nowPlayingItemId;
  final String? nowPlayingTitle;
  final bool isPaused;
  final bool isMuted;
  final int? volumeLevel;

  /// Current playback position on the remote device, when it's playing.
  final int? positionTicks;
  final int? runTimeTicks;
  final DateTime? observedAt;

  bool get isPlayingSomething => nowPlayingItemId != null;

  Duration? get position => positionTicks == null
      ? null
      : Duration(microseconds: positionTicks! ~/ 10);

  Duration? get duration =>
      runTimeTicks == null ? null : Duration(microseconds: runTimeTicks! ~/ 10);

  Duration? estimatedPosition({DateTime? now}) {
    final base = position;
    if (base == null || isPaused || !isPlayingSomething || observedAt == null) {
      return base;
    }
    final elapsed = (now ?? DateTime.now()).difference(observedAt!);
    if (elapsed <= Duration.zero) return base;
    final estimate = base + elapsed;
    final total = duration;
    if (total != null && estimate > total) return total;
    return estimate;
  }

  factory RemoteSession.fromJson(Map<String, dynamic> json) {
    final nowPlaying = json['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = json['PlayState'] as Map<String, dynamic>?;
    final commands =
        (json['SupportedCommands'] as List?)?.cast<String>().toSet() ??
        const <String>{};
    return RemoteSession(
      id: json['Id'] as String,
      deviceId: json['DeviceId'] as String? ?? '',
      deviceName: json['DeviceName'] as String? ?? 'Unknown device',
      client: json['Client'] as String? ?? '',
      userId: json['UserId'] as String? ?? '',
      userName: json['UserName'] as String? ?? '',
      supportsRemoteControl: json['SupportsRemoteControl'] as bool? ?? false,
      supportedCommands: commands,
      nowPlayingItemId: nowPlaying?['Id'] as String?,
      nowPlayingTitle: nowPlaying?['Name'] as String?,
      isPaused: playState?['IsPaused'] as bool? ?? false,
      isMuted: playState?['IsMuted'] as bool? ?? false,
      volumeLevel: playState?['VolumeLevel'] as int?,
      positionTicks: playState?['PositionTicks'] as int?,
      runTimeTicks: nowPlaying?['RunTimeTicks'] as int?,
      observedAt: DateTime.now(),
    );
  }
}
