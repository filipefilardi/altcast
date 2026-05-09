import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/collection/collection_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/episode/episode_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/library_browse_screen.dart';
import '../features/movie/movie_screen.dart';
import '../features/person/person_screen.dart';
import '../features/player/video_player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/season/season_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';

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
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth is AuthInitial) return null;
      final loggedIn = auth is AuthAuthenticated;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
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
        path: '/episode/:id',
        builder: (_, st) => EpisodeScreen(episodeId: st.pathParameters['id']!),
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
            preferredAudioLang: st.uri.queryParameters['audioLang'],
            // `subLang=off` is a sentinel meaning "explicitly disable subs".
            preferredSubLang: st.uri.queryParameters['subLang'],
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
