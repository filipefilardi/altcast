import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/features/auth/auth_controller.dart';
import 'package:altcast/features/collection/collection_screen.dart';
import 'package:altcast/features/auth/login_screen.dart';
import 'package:altcast/features/downloads/downloads_screen.dart';
import 'package:altcast/features/favorites/favorites_screen.dart';
import 'package:altcast/features/home/home_screen.dart';
import 'package:altcast/features/library/library_screen.dart';
import 'package:altcast/features/library/library_browse_screen.dart';
import 'package:altcast/features/library/library_genres_screen.dart';
import 'package:altcast/features/movie/movie_screen.dart';
import 'package:altcast/features/person/person_screen.dart';
import 'package:altcast/features/player/video_player_screen.dart';
import 'package:altcast/features/search/search_screen.dart';
import 'package:altcast/features/season/season_screen.dart';
import 'package:altcast/features/series/series_screen.dart';
import 'package:altcast/features/settings/settings_screen.dart';
import 'package:altcast/features/shell/app_shell.dart';
import 'package:altcast/features/watch_history/watch_history_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
String? _pendingNotificationLocation;

void openDownloadNotificationRoute(String? focusItemId) {
  final focus = focusItemId?.trim();
  final location = Uri(
    path: '/downloads',
    queryParameters: focus == null || focus.isEmpty ? null : {'focus': focus},
  ).toString();
  _openNotificationLocation(location);
}

void openNotificationRoute(String? payload) {
  final location = _notificationLocation(payload);
  if (location == null) return;
  _openNotificationLocation(location);
}

String? notificationLocationForPayload(String? payload) {
  return _notificationLocation(payload);
}

void _openNotificationLocation(String location) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) {
    _pendingNotificationLocation = location;
    return;
  }
  unawaited(context.push(location));
}

void flushPendingNotificationRoute() {
  final location = _pendingNotificationLocation;
  final context = rootNavigatorKey.currentContext;
  if (location == null || context == null) return;
  _pendingNotificationLocation = null;
  unawaited(context.push(location));
}

String? _notificationLocation(String? payload) {
  final raw = payload?.trim();
  if (raw == null || raw.isEmpty) return null;

  if (!raw.startsWith('{')) {
    if (raw.startsWith('download:')) {
      return _downloadLocation(raw.substring('download:'.length));
    }
    if (raw.startsWith('movie:')) {
      return _itemLocation('/movie', raw.substring('movie:'.length));
    }
    if (raw.startsWith('series:')) {
      return _itemLocation('/series', raw.substring('series:'.length));
    }
    if (raw.startsWith('episode:')) {
      return _itemLocation('/play', raw.substring('episode:'.length));
    }
    return _downloadLocation(raw);
  }

  try {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final type = decoded['type'] as String?;
    final itemId = decoded['itemId'] as String?;
    final seriesId = decoded['seriesId'] as String?;
    switch (type) {
      case 'download':
        return _downloadLocation(itemId);
      case 'movie':
        return _itemLocation('/movie', itemId);
      case 'series':
        return _itemLocation('/series', seriesId ?? itemId);
      case 'episode':
        if (seriesId != null && seriesId.trim().isNotEmpty) {
          return _itemLocation('/series', seriesId);
        }
        return _itemLocation('/play', itemId);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

String? _downloadLocation(String? itemId) {
  final focus = itemId?.trim();
  return Uri(
    path: '/downloads',
    queryParameters: focus == null || focus.isEmpty ? null : {'focus': focus},
  ).toString();
}

String? _itemLocation(String prefix, String? itemId) {
  final id = itemId?.trim();
  if (id == null || id.isEmpty) return null;
  return '$prefix/$id';
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen<AuthState>(
      authControllerProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth is AuthInitial) return null;
      final loggedIn = auth is AuthAuthenticated;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) {
        final serverUrl = auth is AuthUnauthenticated ? auth.serverUrl : null;
        return Uri(
          path: '/login',
          queryParameters: serverUrl == null || serverUrl.isEmpty
              ? null
              : {'serverUrl': serverUrl},
        ).toString();
      }
      if (loggedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, st) =>
            LoginScreen(initialServerUrl: st.uri.queryParameters['serverUrl']),
      ),
      GoRoute(
        path: '/downloads',
        builder: (_, st) =>
            DownloadsScreen(focusItemId: st.uri.queryParameters['focus']),
      ),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
      GoRoute(
        path: '/movie/:id',
        builder: (_, st) => MovieScreen(movieId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/series/:id',
        builder: (_, st) => SeriesScreen(seriesId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/person/:id',
        builder: (_, st) => PersonScreen(personId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/collection/:id',
        builder: (_, st) => CollectionScreen(
          collectionId: st.pathParameters['id']!,
          title: st.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        path: '/season/:id',
        builder: (_, st) => SeasonScreen(seasonId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/play/:id',
        builder: (_, st) {
          final ticks = int.tryParse(
            st.uri.queryParameters['resumeTicks'] ?? '',
          );
          return VideoPlayerScreen(
            itemId: st.pathParameters['id']!,
            resumeTicks: ticks,
            syncPlayStartPlaying:
                st.uri.queryParameters['syncPlayPlaying'] == null
                ? null
                : st.uri.queryParameters['syncPlayPlaying'] == '1',
            seriesId: st.uri.queryParameters['seriesId'],
            seasonNumber: int.tryParse(
              st.uri.queryParameters['seasonNumber'] ?? '',
            ),
            episodeNumber: int.tryParse(
              st.uri.queryParameters['episodeNumber'] ?? '',
            ),
          );
        },
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/watch-history',
        builder: (_, _) => const WatchHistoryScreen(),
      ),
      GoRoute(
        path: '/library/movies',
        builder: (_, st) {
          final genre = st.uri.queryParameters['genre'];
          return LibraryBrowseScreen(
            title: genre == null || genre.isEmpty ? 'Movies' : '$genre Movies',
            itemType: 'Movie',
            initialGenre: genre,
          );
        },
      ),
      GoRoute(
        path: '/library/shows',
        builder: (_, st) {
          final genre = st.uri.queryParameters['genre'];
          return LibraryBrowseScreen(
            title: genre == null || genre.isEmpty
                ? 'TV Shows'
                : '$genre TV Shows',
            itemType: 'Series',
            initialGenre: genre,
          );
        },
      ),
      GoRoute(
        path: '/library/genres',
        builder: (_, _) => const LibraryGenresScreen(),
      ),
      GoRoute(
        path: '/library/collections',
        builder: (_, _) =>
            const LibraryBrowseScreen(title: 'Collections', itemType: 'BoxSet'),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, _) => const LibraryScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});
