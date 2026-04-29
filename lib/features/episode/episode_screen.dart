import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/play_button.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import 'episode_providers.dart';

class EpisodeScreen extends ConsumerWidget {
  const EpisodeScreen({required this.episodeId, super.key});

  final String episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(episodeProvider(episodeId));
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(episodeProvider(episodeId).future),
        child: async.when(
          data: (episode) {
            final repo = ref.watch(jellyfinRepositoryProvider);
            final backdrop = repo.backdropUrl(
              episode.id,
              null,
              fallbackPrimaryTag: episode.imageTag,
            );
            final ticks = episode.userData?.playbackPositionTicks ?? 0;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                DetailHero(
                  backdropUrl: backdrop,
                  title: episode.name,
                  subtitle: episode.shortLabel.isEmpty
                      ? null
                      : episode.shortLabel,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PlayButton(
                        onPressed: () {
                          final query = <String, String>{
                            if (ticks > 0) 'resumeTicks': '$ticks',
                            if (episode.seriesId.isNotEmpty)
                              'seriesId': episode.seriesId,
                            if (episode.parentIndexNumber != null)
                              'seasonNumber': '${episode.parentIndexNumber}',
                            if (episode.indexNumber != null)
                              'episodeNumber': '${episode.indexNumber}',
                          };
                          final uri = Uri(
                            path: '/play/${episode.id}',
                            queryParameters: query.isEmpty ? null : query,
                          );
                          context.push(uri.toString());
                        },
                        label: ticks > 0 ? 'Resume' : 'Play',
                      ),
                      if (episode.seriesId.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              context.push('/series/${episode.seriesId}'),
                          child: const Text('Open series'),
                        ),
                      if (episode.overview != null &&
                          episode.overview!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          episode.overview!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              ErrorStateView(
                title: "Couldn't load episode",
                message: e.toString(),
                onRetry: () => ref.invalidate(episodeProvider(episodeId)),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: const _BackChip(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: BackButton(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
