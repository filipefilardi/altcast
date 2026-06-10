import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/features/home/home_providers.dart';
import 'package:altcast/features/series/widgets/episode_tile.dart';
import 'package:altcast/features/season/season_providers.dart';

class SeasonScreen extends ConsumerWidget {
  const SeasonScreen({required this.seasonId, super.key});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonAsync = ref.watch(seasonProvider(seasonId));
    return Scaffold(
      appBar: AppBar(
        title: seasonAsync.maybeWhen(
          data: (s) => Text(s.name),
          orElse: () => const Text('Season'),
        ),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: seasonAsync.when(
        data: (season) {
          if (season.seriesId == null || season.seriesId!.isEmpty) {
            return const Center(
              child: Text(
                'Season is missing series metadata.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          final episodesAsync = ref.watch(
            seasonEpisodesProvider((
              seriesId: season.seriesId!,
              seasonId: season.id,
            )),
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(seasonProvider(seasonId));
              ref.invalidate(
                seasonEpisodesProvider((
                  seriesId: season.seriesId!,
                  seasonId: season.id,
                )),
              );
            },
            child: episodesAsync.when(
              data: (episodes) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                children: [
                  if (season.seriesName != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        season.seriesName!,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  for (final ep in episodes)
                    EpisodeTile(
                      episode: ep,
                      seriesName: season.seriesName ?? 'Series',
                      seriesPosterTag: season.imageTag,
                      onTap: () => context.push('/series/${season.seriesId!}'),
                      onSetPlayed: (played) async {
                        await ref
                            .read(jellyfinRepositoryProvider)
                            .setPlayed(ep.id, played: played);
                        ref.invalidate(seasonProvider(seasonId));
                        ref.invalidate(
                          seasonEpisodesProvider((
                            seriesId: season.seriesId!,
                            seasonId: season.id,
                          )),
                        );
                        invalidateHomeShelves(ref);
                      },
                    ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                children: [
                  const SizedBox(height: 120),
                  ErrorStateView(
                    title: "Couldn't load episodes",
                    message: e.toString(),
                    onRetry: () => ref.invalidate(
                      seasonEpisodesProvider((
                        seriesId: season.seriesId!,
                        seasonId: season.id,
                      )),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: ErrorStateView(
            title: "Couldn't load season",
            message: e.toString(),
            onRetry: () => ref.invalidate(seasonProvider(seasonId)),
          ),
        ),
      ),
    );
  }
}
