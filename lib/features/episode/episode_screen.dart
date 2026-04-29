import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/cast_crew_row.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
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
      floatingActionButton: const _BackChip(),
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
    final hasResume = (episode.userData?.resumePosition ?? Duration.zero) >
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
          metaRow: _MetaRow(
            runtime: episode.runTime,
            premiereDate: episode.premiereDate,
            communityRating: episode.communityRating,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PlayButton(
                    onPressed: () => _play(context, fromStart: false),
                    label: hasResume ? 'Resume' : 'Play',
                  ),
                  const Spacer(),
                  UserDataActions(
                    initialFavorite: episode.userData?.isFavorite ?? false,
                    initialPlayed: episode.userData?.played ?? false,
                    onSetFavorite: (v) async {
                      await repo.setFavorite(episode.id, favorite: v);
                      ref.invalidate(episodeProvider(episode.id));
                    },
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
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                Text(
                  'OVERVIEW',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  episode.overview!,
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
    final ticks =
        fromStart ? 0 : (episode.userData?.playbackPositionTicks ?? 0);
    final query = <String, String>{
      if (ticks > 0) 'resumeTicks': '$ticks',
      if (episode.seriesId.isNotEmpty) 'seriesId': episode.seriesId,
      if (episode.parentIndexNumber != null)
        'seasonNumber': '${episode.parentIndexNumber}',
      if (episode.indexNumber != null) 'episodeNumber': '${episode.indexNumber}',
    };
    final uri = Uri(
      path: '/play/${episode.id}',
      queryParameters: query.isEmpty ? null : query,
    );
    context.push(uri.toString());
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.runtime,
    required this.premiereDate,
    required this.communityRating,
  });

  final Duration? runtime;
  final DateTime? premiereDate;
  final double? communityRating;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (runtime != null) chips.add(_pill(formatLongDuration(runtime!)));
    if (premiereDate != null) chips.add(_pill(_formatAirDate(premiereDate!)));
    if (communityRating != null) {
      chips.add(_pill('★ ${communityRating!.toStringAsFixed(1)}'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
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
              const Icon(Icons.tv_outlined,
                  size: 20, color: AppColors.textSecondary),
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
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatAirDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
