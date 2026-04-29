import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/episode.dart';
import '../../data/jellyfin/models/series.dart';

final seasonProvider = FutureProvider.autoDispose.family<Season, String>((
  ref,
  seasonId,
) {
  return ref.watch(jellyfinRepositoryProvider).getSeason(seasonId);
});

final seasonEpisodesProvider = FutureProvider.autoDispose
    .family<List<Episode>, ({String seriesId, String seasonId})>((ref, key) {
      return ref
          .watch(jellyfinRepositoryProvider)
          .getEpisodes(key.seriesId, key.seasonId);
    });
