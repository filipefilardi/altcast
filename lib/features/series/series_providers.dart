import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';
import 'package:altcast/data/jellyfin/models/series.dart';

final seriesProvider = FutureProvider.autoDispose.family<Series, String>((
  ref,
  id,
) {
  return ref.watch(jellyfinRepositoryProvider).getSeries(id);
});

final seasonsProvider = FutureProvider.autoDispose.family<List<Season>, String>(
  (ref, seriesId) {
    return ref.watch(jellyfinRepositoryProvider).getSeasons(seriesId);
  },
);

/// Family keyed on a `(seriesId, seasonId)` record — Dart records carry value
/// equality, which Riverpod uses to dedupe family arguments.
typedef EpisodesKey = ({String seriesId, String seasonId});

final episodesProvider = FutureProvider.autoDispose
    .family<List<Episode>, EpisodesKey>((ref, key) {
      return ref
          .watch(jellyfinRepositoryProvider)
          .getEpisodes(key.seriesId, key.seasonId);
    });

final similarSeriesProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getSimilarItems(id);
    });
