import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';

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
