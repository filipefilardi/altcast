import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage.dart';

const _playbackPrefsKey = 'playback_preferences_v1';

enum StreamingQuality {
  auto('Auto', 'Let server/device choose best quality'),
  dataSaver('Data saver', 'Lower bandwidth, faster startup'),
  high('High quality', 'Prefer higher bitrate streams');

  const StreamingQuality(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

class PlaybackPreferences {
  const PlaybackPreferences({
    this.streamingQuality = StreamingQuality.auto,
    this.wifiOnlyStreaming = false,
  });

  final StreamingQuality streamingQuality;
  final bool wifiOnlyStreaming;

  PlaybackPreferences copyWith({
    StreamingQuality? streamingQuality,
    bool? wifiOnlyStreaming,
  }) {
    return PlaybackPreferences(
      streamingQuality: streamingQuality ?? this.streamingQuality,
      wifiOnlyStreaming: wifiOnlyStreaming ?? this.wifiOnlyStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
    'streamingQuality': streamingQuality.name,
    'wifiOnlyStreaming': wifiOnlyStreaming,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) {
    final qualityName = json['streamingQuality'] as String?;
    final quality = StreamingQuality.values.firstWhere(
      (q) => q.name == qualityName,
      orElse: () => StreamingQuality.auto,
    );
    return PlaybackPreferences(
      streamingQuality: quality,
      wifiOnlyStreaming: json['wifiOnlyStreaming'] as bool? ?? false,
    );
  }
}

final playbackPreferencesProvider =
    NotifierProvider<PlaybackPreferencesNotifier, PlaybackPreferences>(
      PlaybackPreferencesNotifier.new,
    );

class PlaybackPreferencesNotifier extends Notifier<PlaybackPreferences> {
  @override
  PlaybackPreferences build() {
    _restore();
    return const PlaybackPreferences();
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_playbackPrefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = PlaybackPreferences.fromJson(data);
    } catch (_) {}
  }

  Future<void> setStreamingQuality(StreamingQuality quality) async {
    state = state.copyWith(streamingQuality: quality);
    await _persist();
  }

  Future<void> setWifiOnlyStreaming(bool enabled) async {
    state = state.copyWith(wifiOnlyStreaming: enabled);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_playbackPrefsKey, jsonEncode(state.toJson()));
  }
}
