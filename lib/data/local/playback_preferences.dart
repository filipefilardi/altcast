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
    this.autoSkipIntroCredits = true,
    this.autoplayNextTvEpisode = true,
    this.autoplayCountdownSeconds = 8,
    this.androidSoftwareVideoDecode = true,
    this.defaultAudioMode = DefaultAudioMode.auto,
    this.defaultAudioLanguage,
    this.defaultSubtitleMode = DefaultSubtitleMode.auto,
    this.defaultSubtitleLanguage,
    this.subtitleFontScale = 1.0,
    this.subtitleBottomInset = 0.0,
  });

  final StreamingQuality streamingQuality;

  /// When true, seeks past intro/credits automatically after a short delay
  /// while playback stays inside a segment. Skip buttons still appear when
  /// this is off, as long as the server reports timings. No-op if the plugin
  /// is missing.
  final bool autoSkipIntroCredits;

  /// When true, shows the next-episode card with a countdown after an
  /// episode ends. When false, the card still appears but only manual play.
  final bool autoplayNextTvEpisode;

  /// Length of the countdown shown on the Next Up card before the player
  /// jumps to the next episode automatically. Only honored when
  /// [autoplayNextTvEpisode] is on. Allowed presets live in
  /// [autoplayCountdownPresets]; values outside it round to the nearest one.
  final int autoplayCountdownSeconds;

  /// When true on Android, libmpv uses software decode (`hwdec=no`) instead of
  /// MediaCodec. Helps with glitchy HEVC/HDR on some devices; higher CPU use.
  final bool androidSoftwareVideoDecode;

  final DefaultAudioMode defaultAudioMode;

  /// Used when [defaultAudioMode] is [DefaultAudioMode.fixedLanguage].
  final String? defaultAudioLanguage;
  final DefaultSubtitleMode defaultSubtitleMode;
  final String? defaultSubtitleLanguage;
  final double subtitleFontScale;
  final double subtitleBottomInset;

  /// Effective audio language code for playback prefs, from settings mode plus
  /// optional per-item metadata ([itemOriginalLanguage] from Jellyfin).
  String? resolvedAudioLanguage(String? itemOriginalLanguage) {
    switch (defaultAudioMode) {
      case DefaultAudioMode.auto:
        return null;
      case DefaultAudioMode.fixedLanguage:
        final code = defaultAudioLanguage?.trim();
        return (code == null || code.isEmpty) ? null : code;
      case DefaultAudioMode.originalLanguage:
        final code = itemOriginalLanguage?.trim();
        return (code == null || code.isEmpty) ? null : code;
    }
  }

  PlaybackPreferences copyWith({
    StreamingQuality? streamingQuality,
    bool? autoSkipIntroCredits,
    bool? autoplayNextTvEpisode,
    int? autoplayCountdownSeconds,
    bool? androidSoftwareVideoDecode,
    DefaultAudioMode? defaultAudioMode,
    String? defaultAudioLanguage,
    bool clearDefaultAudioLanguage = false,
    DefaultSubtitleMode? defaultSubtitleMode,
    String? defaultSubtitleLanguage,
    bool clearDefaultSubtitleLanguage = false,
    double? subtitleFontScale,
    double? subtitleBottomInset,
  }) {
    return PlaybackPreferences(
      streamingQuality: streamingQuality ?? this.streamingQuality,
      autoSkipIntroCredits: autoSkipIntroCredits ?? this.autoSkipIntroCredits,
      autoplayNextTvEpisode:
          autoplayNextTvEpisode ?? this.autoplayNextTvEpisode,
      autoplayCountdownSeconds:
          autoplayCountdownSeconds ?? this.autoplayCountdownSeconds,
      androidSoftwareVideoDecode:
          androidSoftwareVideoDecode ?? this.androidSoftwareVideoDecode,
      defaultAudioMode: defaultAudioMode ?? this.defaultAudioMode,
      defaultAudioLanguage: clearDefaultAudioLanguage
          ? null
          : (defaultAudioLanguage ?? this.defaultAudioLanguage),
      defaultSubtitleMode: defaultSubtitleMode ?? this.defaultSubtitleMode,
      defaultSubtitleLanguage: clearDefaultSubtitleLanguage
          ? null
          : (defaultSubtitleLanguage ?? this.defaultSubtitleLanguage),
      subtitleFontScale: subtitleFontScale ?? this.subtitleFontScale,
      subtitleBottomInset: subtitleBottomInset ?? this.subtitleBottomInset,
    );
  }

  Map<String, dynamic> toJson() => {
    'streamingQuality': streamingQuality.name,
    'autoSkipIntroCredits': autoSkipIntroCredits,
    'autoplayNextTvEpisode': autoplayNextTvEpisode,
    'autoplayCountdownSeconds': autoplayCountdownSeconds,
    'androidSoftwareVideoDecode': androidSoftwareVideoDecode,
    'defaultAudioMode': defaultAudioMode.name,
    'defaultAudioLanguage': defaultAudioLanguage,
    'defaultSubtitleMode': defaultSubtitleMode.name,
    'defaultSubtitleLanguage': defaultSubtitleLanguage,
    'subtitleFontScale': subtitleFontScale,
    'subtitleBottomInset': subtitleBottomInset,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) {
    final qualityName = json['streamingQuality'] as String?;
    final quality = StreamingQuality.values.firstWhere(
      (q) => q.name == qualityName,
      orElse: () => StreamingQuality.auto,
    );
    final subtitleModeName = json['defaultSubtitleMode'] as String?;
    final subtitleMode = DefaultSubtitleMode.values.firstWhere(
      (m) => m.name == subtitleModeName,
      orElse: () => DefaultSubtitleMode.auto,
    );
    final legacyLang = json['defaultAudioLanguage'] as String?;
    final modeName = json['defaultAudioMode'] as String?;
    final audioMode = DefaultAudioMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () {
        if (legacyLang != null && legacyLang.trim().isNotEmpty) {
          return DefaultAudioMode.fixedLanguage;
        }
        return DefaultAudioMode.auto;
      },
    );
    final trimmedLegacy = legacyLang?.trim();
    final langForFixed =
        audioMode == DefaultAudioMode.fixedLanguage &&
            trimmedLegacy != null &&
            trimmedLegacy.isNotEmpty
        ? trimmedLegacy
        : null;
    return PlaybackPreferences(
      streamingQuality: quality,
      autoSkipIntroCredits: json['autoSkipIntroCredits'] as bool? ?? true,
      autoplayNextTvEpisode: json['autoplayNextTvEpisode'] as bool? ?? true,
      autoplayCountdownSeconds: _normalizeAutoplayCountdown(
        json['autoplayCountdownSeconds'] as int?,
      ),
      androidSoftwareVideoDecode:
          json['androidSoftwareVideoDecode'] as bool? ?? true,
      defaultAudioMode: audioMode,
      defaultAudioLanguage: langForFixed,
      defaultSubtitleMode: subtitleMode,
      defaultSubtitleLanguage: json['defaultSubtitleLanguage'] as String?,
      subtitleFontScale: _normalizeSubtitleFontScale(
        (json['subtitleFontScale'] as num?)?.toDouble(),
      ),
      subtitleBottomInset: _normalizeSubtitleBottomInset(
        (json['subtitleBottomInset'] as num?)?.toDouble(),
      ),
    );
  }
}

/// Allowed values for [PlaybackPreferences.autoplayCountdownSeconds]. Kept
/// short so the picker stays compact and the chosen number maps to a clean
/// progress arc on the Next Up card.
const autoplayCountdownPresets = <int>[5, 8, 10, 15, 30];
const subtitleFontScalePresets = <double>[0.9, 1.0, 1.1, 1.2, 1.35, 1.5];
const subtitleBottomInsetPresets = <double>[-20, 0, 20, 40, 60, 80];

int _normalizeAutoplayCountdown(int? value) {
  if (value == null) return 8;
  // Snap to the nearest preset so persisted values from older builds (or a
  // future picker tweak) always land on a supported choice.
  var best = autoplayCountdownPresets.first;
  var bestDelta = (value - best).abs();
  for (final preset in autoplayCountdownPresets.skip(1)) {
    final d = (value - preset).abs();
    if (d < bestDelta) {
      best = preset;
      bestDelta = d;
    }
  }
  return best;
}

double _normalizeSubtitleFontScale(double? value) {
  if (value == null) return 1.0;
  var best = subtitleFontScalePresets.first;
  var bestDelta = (value - best).abs();
  for (final preset in subtitleFontScalePresets.skip(1)) {
    final d = (value - preset).abs();
    if (d < bestDelta) {
      best = preset;
      bestDelta = d;
    }
  }
  return best;
}

double _normalizeSubtitleBottomInset(double? value) {
  if (value == null) return 0.0;
  var best = subtitleBottomInsetPresets.first;
  var bestDelta = (value - best).abs();
  for (final preset in subtitleBottomInsetPresets.skip(1)) {
    final d = (value - preset).abs();
    if (d < bestDelta) {
      best = preset;
      bestDelta = d;
    }
  }
  return best;
}

enum DefaultAudioMode { auto, originalLanguage, fixedLanguage }

enum DefaultSubtitleMode { auto, off, byLanguage }

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

  Future<void> setAutoSkipIntroCredits(bool enabled) async {
    state = state.copyWith(autoSkipIntroCredits: enabled);
    await _persist();
  }

  Future<void> setAutoplayNextTvEpisode(bool enabled) async {
    state = state.copyWith(autoplayNextTvEpisode: enabled);
    await _persist();
  }

  Future<void> setAutoplayCountdownSeconds(int seconds) async {
    state = state.copyWith(
      autoplayCountdownSeconds: _normalizeAutoplayCountdown(seconds),
    );
    await _persist();
  }

  Future<void> setAndroidSoftwareVideoDecode(bool enabled) async {
    state = state.copyWith(androidSoftwareVideoDecode: enabled);
    await _persist();
  }

  Future<void> setDefaultAudioAuto() async {
    state = state.copyWith(
      defaultAudioMode: DefaultAudioMode.auto,
      clearDefaultAudioLanguage: true,
    );
    await _persist();
  }

  Future<void> setDefaultAudioOriginalLanguage() async {
    state = state.copyWith(
      defaultAudioMode: DefaultAudioMode.originalLanguage,
      clearDefaultAudioLanguage: true,
    );
    await _persist();
  }

  Future<void> setDefaultAudioFixedLanguage(String languageCode) async {
    state = state.copyWith(
      defaultAudioMode: DefaultAudioMode.fixedLanguage,
      defaultAudioLanguage: languageCode.trim(),
    );
    await _persist();
  }

  Future<void> setDefaultSubtitleAuto() async {
    state = state.copyWith(
      defaultSubtitleMode: DefaultSubtitleMode.auto,
      clearDefaultSubtitleLanguage: true,
    );
    await _persist();
  }

  Future<void> setDefaultSubtitleOff() async {
    state = state.copyWith(
      defaultSubtitleMode: DefaultSubtitleMode.off,
      clearDefaultSubtitleLanguage: true,
    );
    await _persist();
  }

  Future<void> setDefaultSubtitleLanguage(String languageCode) async {
    state = state.copyWith(
      defaultSubtitleMode: DefaultSubtitleMode.byLanguage,
      defaultSubtitleLanguage: languageCode.trim(),
    );
    await _persist();
  }

  Future<void> setSubtitleFontScale(double scale) async {
    state = state.copyWith(
      subtitleFontScale: _normalizeSubtitleFontScale(scale),
    );
    await _persist();
  }

  Future<void> setSubtitleBottomInset(double inset) async {
    state = state.copyWith(
      subtitleBottomInset: _normalizeSubtitleBottomInset(inset),
    );
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_playbackPrefsKey, jsonEncode(state.toJson()));
  }
}
