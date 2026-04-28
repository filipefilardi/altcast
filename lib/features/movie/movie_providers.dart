import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/movie.dart';

final movieProvider =
    FutureProvider.autoDispose.family<Movie, String>((ref, id) {
  return ref.watch(jellyfinRepositoryProvider).getMovie(id);
});
