import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/movie.dart';

final movieProvider = FutureProvider.autoDispose.family<Movie, String>((
  ref,
  id,
) {
  return ref.watch(jellyfinRepositoryProvider).getMovie(id);
});

final similarMoviesProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getSimilarItems(id);
    });
