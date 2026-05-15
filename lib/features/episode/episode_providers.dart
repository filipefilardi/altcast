import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';

final episodeProvider = FutureProvider.autoDispose.family<Episode, String>((
  ref,
  episodeId,
) {
  return ref.watch(jellyfinRepositoryProvider).getEpisode(episodeId);
});
