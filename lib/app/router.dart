import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/movie/movie_screen.dart';
import '../features/player/video_player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
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
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
      GoRoute(
        path: '/movie/:id',
        builder: (_, st) => MovieScreen(movieId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/series/:id',
        builder: (_, st) => SeriesScreen(seriesId: st.pathParameters['id']!),
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
            preferredAudioLang: st.uri.queryParameters['audioLang'],
            // `subLang=off` is a sentinel meaning "explicitly disable subs".
            preferredSubLang: st.uri.queryParameters['subLang'],
          );
        },
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, __) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (_, __) => const LibraryScreen(),
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
