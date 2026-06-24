import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/download_preferences.dart';
import 'package:altcast/data/local/library_activity_state.dart';
import 'package:altcast/data/local/notification_preferences.dart';
import 'package:altcast/data/local/secure_storage.dart';
import 'package:altcast/data/notifications/app_notifications.dart';
import 'package:altcast/features/auth/auth_controller.dart';

final libraryNotificationMonitorProvider =
    NotifierProvider<LibraryNotificationMonitor, void>(
      LibraryNotificationMonitor.new,
    );

class LibraryNotificationMonitor extends Notifier<void> {
  static const _minimumCheckInterval = Duration(minutes: 10);
  static const _latestLimit = 30;
  static const _maxNotificationsPerCheck = 5;

  Future<void>? _activeCheck;
  DateTime? _lastCheckAt;

  @override
  void build() {}

  Future<void> checkForUpdates({
    bool force = false,
    NotificationPreferences? preferences,
    JellyfinSession? session,
  }) {
    final running = _activeCheck;
    if (running != null) return running;

    final future = _checkForUpdates(
      force: force,
      preferences: preferences,
      session: session,
    );
    _activeCheck = future.whenComplete(() => _activeCheck = null);
    return _activeCheck!;
  }

  Future<void> _checkForUpdates({
    required bool force,
    required NotificationPreferences? preferences,
    required JellyfinSession? session,
  }) async {
    final now = DateTime.now();
    final previousCheck = _lastCheckAt;
    if (!force &&
        previousCheck != null &&
        now.difference(previousCheck) < _minimumCheckInterval) {
      return;
    }

    final NotificationPreferences prefs =
        preferences ?? ref.read(notificationPreferencesProvider);
    final downloadPrefs = await DownloadPreferences.load(
      ref.read(secureStorageProvider),
    );
    final shouldKeepFavoritesReady = downloadPrefs.keepFavoriteShowsReady;
    if (!prefs.anyLibraryNotifications && !shouldKeepFavoritesReady) return;

    final activeSession = session ?? _authenticatedSession();
    if (activeSession == null) return;

    _lastCheckAt = now;

    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final store = ref.read(libraryActivityStoreProvider);
      var profile = await store.readProfile(activeSession);

      final moviesFuture = repo.recentlyAddedMovies(limit: _latestLimit);
      final episodesFuture = repo.recentlyAddedEpisodes(limit: _latestLimit);
      final favoriteSeriesIdsFuture = prefs.newEpisodesForFavoriteSeries
          ? episodesFuture.then(
              (episodes) => repo.favoriteSeriesIds(
                seriesIds: episodes.map((episode) => episode.seriesId),
              ),
            )
          : Future<Set<String>>.value(const <String>{});

      final movies = await moviesFuture;
      final episodes = await episodesFuture;
      final favoriteSeriesIds = await favoriteSeriesIdsFuture;
      final favoriteSyncFuture = shouldKeepFavoritesReady
          ? ref
                .read(downloadManagerProvider.notifier)
                .syncFavoriteShowsReady(force: true)
          : Future<int>.value(0);

      if (kDebugMode) {
        debugPrint(
          'Library notification latest movies: '
          '${_debugItems(movies, profile.seenMovieIds)}',
        );
        debugPrint(
          'Library notification latest episodes: '
          '${_debugItems(episodes, profile.seenEpisodeIds)}',
        );
        if (prefs.newEpisodesForFavoriteSeries) {
          debugPrint(
            'Library notification favorite series IDs: '
            '${favoriteSeriesIds.isEmpty ? 'none' : favoriteSeriesIds.join(', ')}',
          );
        }
      }

      if (profile.initialized &&
          profile.snapshotVersion < currentLibrarySnapshotVersion) {
        debugPrint(
          'Library notification snapshot migrated to individual episode IDs',
        );
        await favoriteSyncFuture;
        await store.writeProfile(
          activeSession,
          profile
              .mergeSeen(
                movieIds: movies.map((item) => item.id),
                episodeIds: episodes.map((item) => item.id),
              )
              .copyWith(snapshotVersion: currentLibrarySnapshotVersion),
        );
        return;
      }

      if (!profile.initialized) {
        debugPrint(
          'Library notification baseline created: '
          '${movies.length} movies, ${episodes.length} episodes',
        );
        await favoriteSyncFuture;
        await store.writeProfile(
          activeSession,
          profile
              .mergeSeen(
                movieIds: movies.map((item) => item.id),
                episodeIds: episodes.map((item) => item.id),
              )
              .copyWith(snapshotVersion: currentLibrarySnapshotVersion),
        );
        return;
      }

      final newMovies = movies
          .where((item) => !profile.seenMovieIds.contains(item.id))
          .toList(growable: false);
      final newEpisodes = episodes
          .where((item) => !profile.seenEpisodeIds.contains(item.id))
          .toList(growable: false);

      debugPrint(
        'Library notification changes detected: '
        '${newMovies.length} movies, ${newEpisodes.length} episodes',
      );

      if (newMovies.isEmpty && newEpisodes.isEmpty) {
        await favoriteSyncFuture;
        await store.writeProfile(
          activeSession,
          profile.mergeSeen(
            movieIds: movies.map((item) => item.id),
            episodeIds: episodes.map((item) => item.id),
          ),
        );
        return;
      }

      final notificationCount = await _notifyNewItems(
        prefs: prefs,
        favoriteSeriesIds: favoriteSeriesIds,
        newMovies: newMovies,
        newEpisodes: newEpisodes,
      );
      await favoriteSyncFuture;
      debugPrint('Library notifications posted: $notificationCount');

      await store.writeProfile(
        activeSession,
        profile.mergeSeen(
          movieIds: movies.map((item) => item.id),
          episodeIds: episodes.map((item) => item.id),
        ),
      );
    } catch (_) {
      // Keep failed checks retryable and let the background scheduler log them.
      rethrow;
    }
  }

  Future<int> _notifyNewItems({
    required NotificationPreferences prefs,
    required Set<String> favoriteSeriesIds,
    required List<BrowseItem> newMovies,
    required List<BrowseItem> newEpisodes,
  }) async {
    final notifications = <Future<void>>[];
    final notifiedEpisodeIds = <String>{};

    if (prefs.newEpisodesForFavoriteSeries) {
      for (final episode in newEpisodes) {
        if (notifications.length >= _maxNotificationsPerCheck) break;
        final seriesId = episode.seriesId;
        if (seriesId == null || !favoriteSeriesIds.contains(seriesId)) continue;
        notifiedEpisodeIds.add(episode.id);
        notifications.add(
          AppNotifications.showNewEpisode(
            itemId: episode.id,
            title: episode.name,
            seriesId: episode.seriesId,
            seriesName: episode.seriesName,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
          ),
        );
      }
    }

    if (prefs.newLibraryMovies) {
      for (final movie in newMovies) {
        if (notifications.length >= _maxNotificationsPerCheck) break;
        notifications.add(
          AppNotifications.showNewMovie(itemId: movie.id, title: movie.name),
        );
      }
    }

    if (prefs.newLibraryEpisodes) {
      for (final episode in newEpisodes) {
        if (notifications.length >= _maxNotificationsPerCheck) break;
        if (notifiedEpisodeIds.contains(episode.id)) continue;
        notifications.add(
          AppNotifications.showNewEpisode(
            itemId: episode.id,
            title: episode.name,
            seriesId: episode.seriesId,
            seriesName: episode.seriesName,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
          ),
        );
      }
    }

    if (notifications.isEmpty) return 0;
    await Future.wait(notifications);
    return notifications.length;
  }

  String _debugItems(List<BrowseItem> items, Set<String> seenIds) {
    if (items.isEmpty) return 'none';
    return items
        .take(10)
        .map(
          (item) =>
              '${item.name} (${seenIds.contains(item.id) ? 'seen' : 'new'})',
        )
        .join(' | ');
  }

  JellyfinSession? _authenticatedSession() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.session : null;
  }
}
