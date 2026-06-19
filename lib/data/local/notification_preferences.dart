import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';

const _notificationPrefsKey = 'notification_preferences_v1';

enum LibraryCheckInterval {
  fifteenMinutes(Duration(minutes: 15), 'Every 15 minutes'),
  oneHour(Duration(hours: 1), 'Every hour'),
  twelveHours(Duration(hours: 12), 'Every 12 hours'),
  daily(Duration(days: 1), 'Daily'),
  twoDays(Duration(days: 2), 'Every 2 days'),
  threeDays(Duration(days: 3), 'Every 3 days'),
  weekly(Duration(days: 7), 'Weekly');

  const LibraryCheckInterval(this.duration, this.label);

  final Duration duration;
  final String label;

  static Iterable<LibraryCheckInterval> selectable({
    required bool includeDebug,
  }) => values.where(
    (interval) =>
        includeDebug || interval != LibraryCheckInterval.fifteenMinutes,
  );

  static LibraryCheckInterval fromJson(Object? value) {
    if (value is! String) return LibraryCheckInterval.oneHour;
    final interval = LibraryCheckInterval.values.firstWhere(
      (interval) => interval.name == value,
      orElse: () => LibraryCheckInterval.oneHour,
    );
    if (!kDebugMode && interval == LibraryCheckInterval.fifteenMinutes) {
      return LibraryCheckInterval.oneHour;
    }
    return interval;
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    this.notificationsEnabled = true,
    this.downloadNotifications = true,
    this.newEpisodesForFavoriteSeries = true,
    this.newLibraryMovies = false,
    this.newLibraryEpisodes = false,
    this.libraryCheckInterval = LibraryCheckInterval.oneHour,
    this.isRestored = false,
  });

  final bool notificationsEnabled;
  final bool downloadNotifications;
  final bool newEpisodesForFavoriteSeries;
  final bool newLibraryMovies;
  final bool newLibraryEpisodes;
  final LibraryCheckInterval libraryCheckInterval;
  final bool isRestored;

  bool get anyLibraryNotifications =>
      newEpisodesForFavoriteSeries || newLibraryMovies || newLibraryEpisodes;

  bool get shouldCheckLibraryInBackground =>
      notificationsEnabled && anyLibraryNotifications;

  bool get shouldNotifyDownloads =>
      notificationsEnabled && downloadNotifications;

  NotificationPreferences copyWith({
    bool? notificationsEnabled,
    bool? downloadNotifications,
    bool? newEpisodesForFavoriteSeries,
    bool? newLibraryMovies,
    bool? newLibraryEpisodes,
    LibraryCheckInterval? libraryCheckInterval,
    bool? isRestored,
  }) {
    return NotificationPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      downloadNotifications:
          downloadNotifications ?? this.downloadNotifications,
      newEpisodesForFavoriteSeries:
          newEpisodesForFavoriteSeries ?? this.newEpisodesForFavoriteSeries,
      newLibraryMovies: newLibraryMovies ?? this.newLibraryMovies,
      newLibraryEpisodes: newLibraryEpisodes ?? this.newLibraryEpisodes,
      libraryCheckInterval: libraryCheckInterval ?? this.libraryCheckInterval,
      isRestored: isRestored ?? this.isRestored,
    );
  }

  Map<String, dynamic> toJson() => {
    'notificationsEnabled': notificationsEnabled,
    'downloadNotifications': downloadNotifications,
    'newEpisodesForFavoriteSeries': newEpisodesForFavoriteSeries,
    'newLibraryMovies': newLibraryMovies,
    'newLibraryEpisodes': newLibraryEpisodes,
    'libraryCheckInterval': libraryCheckInterval.name,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      downloadNotifications: json['downloadNotifications'] as bool? ?? true,
      newEpisodesForFavoriteSeries:
          json['newEpisodesForFavoriteSeries'] as bool? ??
          json['newEpisodesForWatchedSeries'] as bool? ??
          true,
      newLibraryMovies: json['newLibraryMovies'] as bool? ?? false,
      newLibraryEpisodes: json['newLibraryEpisodes'] as bool? ?? false,
      libraryCheckInterval: LibraryCheckInterval.fromJson(
        json['libraryCheckInterval'],
      ),
      isRestored: true,
    );
  }

  static Future<NotificationPreferences> load(SecureStorage storage) async {
    final raw = await storage.read(_notificationPrefsKey);
    if (raw == null) return const NotificationPreferences(isRestored: true);
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return NotificationPreferences.fromJson(data);
    } catch (_) {
      return const NotificationPreferences(isRestored: true);
    }
  }
}

final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
      NotificationPreferencesNotifier.new,
    );

class NotificationPreferencesNotifier
    extends Notifier<NotificationPreferences> {
  @override
  NotificationPreferences build() {
    _restore();
    return const NotificationPreferences();
  }

  Future<void> _restore() async {
    state = await NotificationPreferences.load(ref.read(secureStorageProvider));
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    await _persist();
  }

  Future<void> setDownloadNotifications(bool enabled) async {
    state = state.copyWith(downloadNotifications: enabled);
    await _persist();
  }

  Future<void> setNewEpisodesForFavoriteSeries(bool enabled) async {
    state = state.copyWith(newEpisodesForFavoriteSeries: enabled);
    await _persist();
  }

  Future<void> setNewLibraryMovies(bool enabled) async {
    state = state.copyWith(newLibraryMovies: enabled);
    await _persist();
  }

  Future<void> setNewLibraryEpisodes(bool enabled) async {
    state = state.copyWith(newLibraryEpisodes: enabled);
    await _persist();
  }

  Future<void> setLibraryCheckInterval(LibraryCheckInterval interval) async {
    state = state.copyWith(libraryCheckInterval: interval);
    await _persist();
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_notificationPrefsKey, jsonEncode(state.toJson()));
  }
}
