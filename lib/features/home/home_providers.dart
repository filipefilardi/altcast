import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';

final continueWatchingProvider = FutureProvider.autoDispose<List<BrowseItem>>((
  ref,
) {
  return ref.watch(jellyfinRepositoryProvider).continueWatching();
});

final recentMoviesProvider = FutureProvider.autoDispose<List<BrowseItem>>((
  ref,
) {
  return ref.watch(jellyfinRepositoryProvider).recentlyAddedMovies();
});

final recentShowsProvider = FutureProvider.autoDispose<List<BrowseItem>>((ref) {
  return ref.watch(jellyfinRepositoryProvider).recentlyAddedShows();
});

final recommendedMoviesProvider = FutureProvider.autoDispose<List<BrowseItem>>((
  ref,
) {
  return ref.watch(jellyfinRepositoryProvider).recommendedMovies();
});

void invalidateHomeShelves(WidgetRef ref) {
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(recentMoviesProvider);
  ref.invalidate(recentShowsProvider);
  ref.invalidate(recommendedMoviesProvider);
}

void invalidateHomeShelvesFromContainer(ProviderContainer container) {
  container.invalidate(continueWatchingProvider);
  container.invalidate(recentMoviesProvider);
  container.invalidate(recentShowsProvider);
  container.invalidate(recommendedMoviesProvider);
}
