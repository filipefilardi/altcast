import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/back_chip.dart';
import '../../core/widgets/cast_crew_row.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/expandable_text.dart';
import '../../core/widgets/meta_pill_row.dart';
import '../../core/widgets/play_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/user_data_actions.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/episode.dart';
import '../downloads/widgets/download_button.dart';
import '../remote/remote_sessions_sheet.dart';
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
          data: (episode) => _EpisodeBody(episode: episode),
          loading: () => const _EpisodeSkeleton(),
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
      floatingActionButton: const BackChip(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }
}

class _EpisodeBody extends ConsumerWidget {
  const _EpisodeBody({required this.episode});

  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final backdrop = repo.backdropUrl(
      episode.id,
      null,
      fallbackPrimaryTag: episode.imageTag,
    );
    final ticks = episode.userData?.playbackPositionTicks ?? 0;
    final hasResume =
        (episode.userData?.resumePosition ?? Duration.zero) >
        const Duration(seconds: 5);
    final seriesName = episode.seriesName?.trim();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        DetailHero(
          backdropUrl: backdrop,
          title: episode.name,
          subtitle: _heroSubtitle(episode),
          metaRow: MetaPillRow(
            labels: [
              if (episode.runTime != null) formatLongDuration(episode.runTime!),
              if (episode.premiereDate != null)
                _formatAirDate(episode.premiereDate!),
              if (episode.communityRating != null)
                '★ ${episode.communityRating!.toStringAsFixed(1)}',
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  PlayButton(
                    onPressed: () => _play(context, fromStart: false),
                    label: hasResume ? 'Resume' : 'Play',
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserDataActions(
                        initialPlayed: episode.userData?.played ?? false,
                        onSetPlayed: (v) async {
                          await repo.setPlayed(episode.id, played: v);
                          ref.invalidate(episodeProvider(episode.id));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.cast),
                        tooltip: 'Play on…',
                        onPressed: () => showRemoteSessionsSheet(
                          context,
                          itemId: episode.id,
                          startPositionTicks: ticks,
                        ),
                      ),
                      if (seriesName != null && seriesName.isNotEmpty)
                        EpisodeDownloadButton(
                          episode: episode,
                          seriesName: seriesName,
                        ),
                    ],
                  ),
                ],
              ),
              if (hasResume)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        'Continues from ${formatDuration(episode.userData!.resumePosition)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                      InkWell(
                        onTap: () => _play(context, fromStart: true),
                        child: Text(
                          'Play from start',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (episode.seriesId.isNotEmpty) ...[
                const SizedBox(height: 12),
                _OpenSeriesTile(
                  seriesId: episode.seriesId,
                  seriesName: seriesName,
                ),
              ],
              if (episode.overview != null && episode.overview!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('OVERVIEW', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ExpandableText(
                  text: episode.overview!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (episode.artists.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'CAST & CREW',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                CastCrewRow(people: episode.artists),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  String? _heroSubtitle(Episode ep) {
    final parts = <String>[
      if (ep.seriesName != null && ep.seriesName!.isNotEmpty) ep.seriesName!,
      if (ep.shortLabel.isNotEmpty) ep.shortLabel,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  void _play(BuildContext context, {required bool fromStart}) {
    final ticks = fromStart
        ? 0
        : (episode.userData?.playbackPositionTicks ?? 0);
    final query = <String, String>{
      if (ticks > 0) 'resumeTicks': '$ticks',
      if (episode.seriesId.isNotEmpty) 'seriesId': episode.seriesId,
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
  }
}

class _OpenSeriesTile extends StatelessWidget {
  const _OpenSeriesTile({required this.seriesId, this.seriesName});

  final String seriesId;
  final String? seriesName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/series/$seriesId'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.tv_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  seriesName == null || seriesName!.isEmpty
                      ? 'Open series'
                      : 'Open ${seriesName!}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatAirDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Skeleton.group(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Skeleton.box(
              width: double.infinity,
              height: double.infinity,
              radius: 0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Skeleton.group(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.box(width: 140, height: 44),
                const SizedBox(height: 24),
                Skeleton.line(width: 200),
                const SizedBox(height: 8),
                Skeleton.line(),
                const SizedBox(height: 8),
                Skeleton.line(width: 240),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
