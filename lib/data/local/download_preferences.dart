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

enum OfflineVideoQuality {
  original('Original', null),
  balanced('Balanced (720p)', 4000000),
  dataSaver('Data saver (480p)', 1800000);

  const OfflineVideoQuality(this.label, this.maxBitrate);
  final String label;
  final int? maxBitrate;
}

class DownloadPreferences {
  const DownloadPreferences({
    this.autoDownloadNextEpisode = false,
    this.wifiOnlyDownloads = true,
    this.downloadLocation = DownloadLocation.internal,
    this.offlineVideoQuality = OfflineVideoQuality.original,
  });

  final bool autoDownloadNextEpisode;
  final bool wifiOnlyDownloads;
  final DownloadLocation downloadLocation;
  final OfflineVideoQuality offlineVideoQuality;

  DownloadPreferences copyWith({
    bool? autoDownloadNextEpisode,
    bool? wifiOnlyDownloads,
    DownloadLocation? downloadLocation,
    OfflineVideoQuality? offlineVideoQuality,
  }) {
    return DownloadPreferences(
      autoDownloadNextEpisode:
          autoDownloadNextEpisode ?? this.autoDownloadNextEpisode,
      wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      offlineVideoQuality: offlineVideoQuality ?? this.offlineVideoQuality,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoDownloadNextEpisode': autoDownloadNextEpisode,
    'wifiOnlyDownloads': wifiOnlyDownloads,
    'downloadLocation': downloadLocation.name,
    'offlineVideoQuality': offlineVideoQuality.name,
  };

  factory DownloadPreferences.fromJson(Map<String, dynamic> json) {
    final locationName = json['downloadLocation'] as String?;
    final location = DownloadLocation.values.firstWhere(
      (l) => l.name == locationName,
      orElse: () => DownloadLocation.internal,
    );
    final qualityName = json['offlineVideoQuality'] as String?;
    final quality = OfflineVideoQuality.values.firstWhere(
      (q) => q.name == qualityName,
      orElse: () => OfflineVideoQuality.original,
    );
    return DownloadPreferences(
      autoDownloadNextEpisode:
          json['autoDownloadNextEpisode'] as bool? ?? false,
      wifiOnlyDownloads: json['wifiOnlyDownloads'] as bool? ?? true,
      downloadLocation: location,
      offlineVideoQuality: quality,
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

  Future<void> setOfflineVideoQuality(OfflineVideoQuality quality) async {
    state = state.copyWith(offlineVideoQuality: quality);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_downloadPrefsKey, jsonEncode(state.toJson()));
  }
}
