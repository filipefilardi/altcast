import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage.dart';

const _downloadPrefsKey = 'download_preferences_v1';

enum DownloadLocation {
  internal('Internal Storage'),
  external('SD Card / External');

  const DownloadLocation(this.label);
  final String label;
}

class DownloadPreferences {
  const DownloadPreferences({
    this.autoDownloadNextEpisode = false,
    this.wifiOnlyDownloads = true,
    this.downloadLocation = DownloadLocation.internal,
  });

  final bool autoDownloadNextEpisode;
  final bool wifiOnlyDownloads;
  final DownloadLocation downloadLocation;

  DownloadPreferences copyWith({
    bool? autoDownloadNextEpisode,
    bool? wifiOnlyDownloads,
    DownloadLocation? downloadLocation,
  }) {
    return DownloadPreferences(
      autoDownloadNextEpisode:
          autoDownloadNextEpisode ?? this.autoDownloadNextEpisode,
      wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
      downloadLocation: downloadLocation ?? this.downloadLocation,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoDownloadNextEpisode': autoDownloadNextEpisode,
    'wifiOnlyDownloads': wifiOnlyDownloads,
    'downloadLocation': downloadLocation.name,
  };

  factory DownloadPreferences.fromJson(Map<String, dynamic> json) {
    final locationName = json['downloadLocation'] as String?;
    final location = DownloadLocation.values.firstWhere(
      (l) => l.name == locationName,
      orElse: () => DownloadLocation.internal,
    );
    return DownloadPreferences(
      autoDownloadNextEpisode:
          json['autoDownloadNextEpisode'] as bool? ?? false,
      wifiOnlyDownloads: json['wifiOnlyDownloads'] as bool? ?? true,
      downloadLocation: location,
    );
  }
}

final downloadPreferencesProvider =
    NotifierProvider<DownloadPreferencesNotifier, DownloadPreferences>(
      DownloadPreferencesNotifier.new,
    );

class DownloadPreferencesNotifier extends Notifier<DownloadPreferences> {
  @override
  DownloadPreferences build() {
    _restore();
    return const DownloadPreferences();
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_downloadPrefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = DownloadPreferences.fromJson(data);
    } catch (_) {}
  }

  Future<void> setAutoDownloadNextEpisode(bool enabled) async {
    state = state.copyWith(autoDownloadNextEpisode: enabled);
    await _persist();
  }

  Future<void> setWifiOnlyDownloads(bool enabled) async {
    state = state.copyWith(wifiOnlyDownloads: enabled);
    await _persist();
  }

  Future<void> setDownloadLocation(DownloadLocation location) async {
    state = state.copyWith(downloadLocation: location);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_downloadPrefsKey, jsonEncode(state.toJson()));
  }
}
