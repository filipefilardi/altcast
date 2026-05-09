const jellyfinTicksPerMillisecond = 10000;

Duration durationFromJellyfinTicks(num? ticks) {
  if (ticks == null) return Duration.zero;
  return Duration(microseconds: ticks.toInt() ~/ 10);
}

int durationToJellyfinTicks(Duration duration) =>
    duration.inMilliseconds * jellyfinTicksPerMillisecond;

class SyncPlayGroup {
  const SyncPlayGroup({
    required this.id,
    required this.name,
    required this.state,
    required this.participants,
    this.lastUpdatedAt,
  });

  final String id;
  final String name;
  final String? state;
  final List<String> participants;
  final DateTime? lastUpdatedAt;

  SyncPlayGroup copyWith({
    String? state,
    List<String>? participants,
    DateTime? lastUpdatedAt,
  }) {
    return SyncPlayGroup(
      id: id,
      name: name,
      state: state ?? this.state,
      participants: participants ?? this.participants,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  factory SyncPlayGroup.fromJson(Map<String, dynamic> json) {
    return SyncPlayGroup(
      id: _string(json, 'GroupId') ?? '',
      name: _string(json, 'GroupName') ?? 'SyncPlay group',
      state: _string(json, 'State'),
      participants:
          (_value(json, 'Participants') as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      lastUpdatedAt: DateTime.tryParse(_string(json, 'LastUpdatedAt') ?? ''),
    );
  }
}

class SyncPlayQueueItem {
  const SyncPlayQueueItem({required this.itemId, required this.playlistItemId});

  final String itemId;
  final String playlistItemId;

  factory SyncPlayQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncPlayQueueItem(
      itemId: _string(json, 'ItemId') ?? '',
      playlistItemId: _string(json, 'PlaylistItemId') ?? '',
    );
  }
}

class SyncPlayQueueUpdate {
  const SyncPlayQueueUpdate({
    required this.reason,
    required this.playlist,
    required this.playingItemIndex,
    required this.startPosition,
    required this.isPlaying,
  });

  final String? reason;
  final List<SyncPlayQueueItem> playlist;
  final int playingItemIndex;
  final Duration startPosition;
  final bool isPlaying;

  SyncPlayQueueItem? get playingItem {
    if (playingItemIndex < 0 || playingItemIndex >= playlist.length) {
      return playlist.isEmpty ? null : playlist.first;
    }
    return playlist[playingItemIndex];
  }

  factory SyncPlayQueueUpdate.fromJson(Map<String, dynamic> json) {
    final rawIndex = _value(json, 'PlayingItemIndex');
    return SyncPlayQueueUpdate(
      reason: _string(json, 'Reason'),
      playlist:
          (_value(json, 'Playlist') as List?)
              ?.whereType<Map>()
              .map(
                (m) => SyncPlayQueueItem.fromJson(Map<String, dynamic>.from(m)),
              )
              .where((item) => item.itemId.isNotEmpty)
              .toList() ??
          const [],
      playingItemIndex: rawIndex is int ? rawIndex : 0,
      startPosition: durationFromJellyfinTicks(
        _value(json, 'StartPositionTicks') as num?,
      ),
      isPlaying: _value(json, 'IsPlaying') == true,
    );
  }
}

class SyncPlayCommand {
  const SyncPlayCommand({
    required this.command,
    required this.playlistItemId,
    required this.position,
    this.when,
  });

  final String command;
  final String? playlistItemId;
  final Duration? position;
  final DateTime? when;

  factory SyncPlayCommand.fromJson(Map<String, dynamic> json) {
    final whenRaw = _string(json, 'When');
    return SyncPlayCommand(
      command: _string(json, 'Command') ?? '',
      playlistItemId: _string(json, 'PlaylistItemId'),
      position: _containsKey(json, 'PositionTicks')
          ? durationFromJellyfinTicks(_value(json, 'PositionTicks') as num?)
          : null,
      when: whenRaw == null ? null : DateTime.tryParse(whenRaw)?.toUtc(),
    );
  }
}

class SyncPlayVideoQueueEvent {
  const SyncPlayVideoQueueEvent({
    required this.serial,
    required this.itemId,
    required this.playlistItemId,
    required this.position,
    required this.isPlaying,
  });

  final int serial;
  final String itemId;
  final String playlistItemId;
  final Duration position;
  final bool isPlaying;
}

class SyncPlayVideoCommandEvent {
  const SyncPlayVideoCommandEvent({
    required this.serial,
    required this.command,
  });

  final int serial;
  final SyncPlayCommand command;
}

dynamic _value(Map<String, dynamic> json, String pascalKey) {
  final camelKey = pascalKey[0].toLowerCase() + pascalKey.substring(1);
  return json[pascalKey] ?? json[camelKey];
}

String? _string(Map<String, dynamic> json, String pascalKey) {
  final value = _value(json, pascalKey);
  return value is String ? value : null;
}

bool _containsKey(Map<String, dynamic> json, String pascalKey) {
  final camelKey = pascalKey[0].toLowerCase() + pascalKey.substring(1);
  return json.containsKey(pascalKey) || json.containsKey(camelKey);
}
