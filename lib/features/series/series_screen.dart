import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/play_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/episode.dart';
import '../../data/jellyfin/models/person_credit.dart';
import '../../data/jellyfin/models/series.dart';
import '../home/widgets/poster_card.dart';
import 'series_providers.dart';
import 'widgets/episode_tile.dart';
import 'widgets/season_picker.dart';
import '../movie/widgets/track_preference_row.dart';

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({required this.seriesId, super.key});
  final String seriesId;

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedSeasonId;
  TrackPreference _preference = const TrackPreference();

  @override
  Widget build(BuildContext context) {
    final seriesAsync = ref.watch(seriesProvider(widget.seriesId));
    final seasonsAsync = ref.watch(seasonsProvider(widget.seriesId));

    // Auto-select the first season once they arrive.
    if (_selectedSeasonId == null && seasonsAsync.hasValue) {
      final seasons = seasonsAsync.requireValue;
      if (seasons.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedSeasonId = seasons.first.id);
        });
      }
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(seriesProvider(widget.seriesId));
          ref.invalidate(seasonsProvider(widget.seriesId));
          ref.invalidate(similarSeriesProvider(widget.seriesId));
          if (_selectedSeasonId != null) {
            ref.invalidate(
              episodesProvider((
                seriesId: widget.seriesId,
                seasonId: _selectedSeasonId!,
              )),
            );
          }
          await Future.wait([
            ref.read(seriesProvider(widget.seriesId).future).catchError((_) {
              return Series(id: widget.seriesId, name: '');
            }),
            ref.read(seasonsProvider(widget.seriesId).future).catchError((_) {
              return <Season>[];
            }),
            ref
                .read(similarSeriesProvider(widget.seriesId).future)
                .catchError((_) => <BrowseItem>[]),
          ]);
        },
        child: seriesAsync.when(
          data: (series) => _SeriesBody(
            series: series,
            seasonsAsync: seasonsAsync,
            selectedSeasonId: _selectedSeasonId,
            onSelectSeason: (id) => setState(() => _selectedSeasonId = id),
            preference: _preference,
            onPreferenceChanged: (next) =>
                setState(() => _preference = next),
          ),
          loading: () => const _SeriesSkeleton(),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              ErrorStateView(
                title: "Couldn't load series",
                message: e.toString(),
                onRetry: () => ref.invalidate(seriesProvider(widget.seriesId)),
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

class _SeriesBody extends ConsumerWidget {
  const _SeriesBody({
    required this.series,
    required this.seasonsAsync,
    required this.selectedSeasonId,
    required this.onSelectSeason,
    required this.preference,
    required this.onPreferenceChanged,
  });

  final Series series;
  final AsyncValue<List<Season>> seasonsAsync;
  final String? selectedSeasonId;
  final ValueChanged<String> onSelectSeason;
  final TrackPreference preference;
  final ValueChanged<TrackPreference> onPreferenceChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final similarAsync = ref.watch(similarSeriesProvider(series.id));
    final backdrop = repo.backdropUrl(
      series.id,
      series.backdropTag,
      fallbackPrimaryTag: series.imageTag,
    );

    final seasons = seasonsAsync.value ?? const <Season>[];
    final activeSeasonId =
        selectedSeasonId ?? (seasons.isNotEmpty ? seasons.first.id : null);

    // Watch episodes for the active season — drives both the Play CTA and
    // the list rendering, so they can't disagree on which episode is "next".
    final episodesAsync = activeSeasonId == null
        ? const AsyncValue<List<Episode>>.data(<Episode>[])
        : ref.watch(
            episodesProvider((seriesId: series.id, seasonId: activeSeasonId)),
          );
    final episodes = episodesAsync.value ?? const <Episode>[];
    final next = _nextEpisode(episodes);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        DetailHero(
          backdropUrl: backdrop,
          title: series.name,
          subtitle: _subtitle(series),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlayButton(
                onPressed: next == null
                    ? null
                    : () => _playEpisode(
                        context,
                        next,
                        preference: preference,
                      ),
                label: _playLabel(next),
                icon: Icons.play_arrow_rounded,
              ),
              TrackPreferenceRow(
                itemId: next?.id ?? series.id,
                preference: preference,
                onChanged: onPreferenceChanged,
              ),
              if (next != null && next.shortLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${next.shortLabel} • ${next.name}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (series.overview != null && series.overview!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  series.overview!,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (series.genres.isNotEmpty) ...[
                const SizedBox(height: 24),
                _GenreChips(
                  genres: series.genres,
                  onTapGenre: (genre) => context.push(
                    Uri(
                      path: '/library/shows',
                      queryParameters: {'genre': genre},
                    ).toString(),
                  ),
                ),
              ],
              if (series.artists.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'CAST & CREW',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                _CastCrewRow(people: series.artists),
              ],
              const SizedBox(height: 24),
              Text(
                'MORE LIKE THIS',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              _MoreLikeThisRow(
                itemsAsync: similarAsync,
                currentItemId: series.id,
              ),
              const SizedBox(height: 24),
              Text('EPISODES', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
            ],
          ),
        ),
        _SeasonsAndEpisodes(
          series: series,
          seasonsAsync: seasonsAsync,
          selectedSeasonId: selectedSeasonId,
          onSelectSeason: onSelectSeason,
          episodesAsync: episodesAsync,
          seriesName: series.name,
          seriesPosterTag: series.imageTag,
          preference: preference,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  String? _subtitle(Series s) {
    final parts = <String>[];
    if (s.yearLabel.isNotEmpty) parts.add(s.yearLabel);
    if (s.status != null) parts.add(s.status!);
    if (s.genres.isNotEmpty) parts.add(s.genres.take(2).join(' · '));
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Picks the episode the Play button should target:
  /// 1. Any episode with a resume position > 5 s (the "continue here" case).
  /// 2. Otherwise the first not-yet-played episode.
  /// 3. Otherwise the very first episode.
  /// Returns null if the list is empty.
  Episode? _nextEpisode(List<Episode> episodes) {
    if (episodes.isEmpty) return null;
    for (final e in episodes) {
      final ud = e.userData;
      if (ud != null &&
          ud.resumePosition > const Duration(seconds: 5) &&
          !ud.played) {
        return e;
      }
    }
    for (final e in episodes) {
      if (!(e.userData?.played ?? false)) return e;
    }
    return episodes.first;
  }

  String _playLabel(Episode? next) {
    if (next == null) return 'Play';
    final ud = next.userData;
    final hasResume =
        ud != null && ud.resumePosition > const Duration(seconds: 5);
    return hasResume ? 'Continue' : 'Play';
  }
}

class _SeasonsAndEpisodes extends ConsumerWidget {
  const _SeasonsAndEpisodes({
    required this.series,
    required this.seasonsAsync,
    required this.selectedSeasonId,
    required this.onSelectSeason,
    required this.episodesAsync,
    required this.seriesName,
    required this.seriesPosterTag,
    required this.preference,
  });

  final Series series;
  final AsyncValue<List<Season>> seasonsAsync;
  final String? selectedSeasonId;
  final ValueChanged<String> onSelectSeason;
  final AsyncValue<List<Episode>> episodesAsync;
  final String seriesName;
  final String? seriesPosterTag;
  final TrackPreference preference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return seasonsAsync.when(
      data: (seasons) {
        if (seasons.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Text(
              'No seasons available.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        final activeId = selectedSeasonId ?? seasons.first.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeasonPicker(
              seasons: seasons,
              selectedId: activeId,
              onSelect: onSelectSeason,
            ),
            const SizedBox(height: 8),
            _EpisodeList(
              seriesId: series.id,
              seasonId: activeId,
              episodesAsync: episodesAsync,
              seriesName: seriesName,
              seriesPosterTag: seriesPosterTag,
              preference: preference,
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _SeasonSkeleton(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ErrorStateView(
          title: "Couldn't load seasons",
          onRetry: () => ref.invalidate(seasonsProvider(series.id)),
        ),
      ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({
    required this.seriesId,
    required this.seasonId,
    required this.episodesAsync,
    required this.seriesName,
    required this.seriesPosterTag,
    required this.preference,
  });
  final String seriesId;
  final String seasonId;
  final AsyncValue<List<Episode>> episodesAsync;
  final String seriesName;
  final String? seriesPosterTag;
  final TrackPreference preference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return episodesAsync.when(
      data: (episodes) {
        if (episodes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Text(
              'No episodes in this season.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return Column(
          children: [
            for (final ep in episodes)
              EpisodeTile(
                episode: ep,
                seriesName: seriesName,
                seriesPosterTag: seriesPosterTag,
                onTap: () => _playEpisode(
                  context,
                  ep,
                  preference: preference,
                ),
              ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: _EpisodeListSkeleton(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ErrorStateView(
          title: "Couldn't load episodes",
          onRetry: () => ref.invalidate(
            episodesProvider((seriesId: seriesId, seasonId: seasonId)),
          ),
        ),
      ),
    );
  }
}

class _SeasonSkeleton extends StatelessWidget {
  const _SeasonSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Row(
        children: [
          Skeleton.box(width: 90, height: 32, radius: 16),
          const SizedBox(width: 8),
          Skeleton.box(width: 90, height: 32, radius: 16),
          const SizedBox(width: 8),
          Skeleton.box(width: 90, height: 32, radius: 16),
        ],
      ),
    );
  }
}

class _EpisodeListSkeleton extends StatelessWidget {
  const _EpisodeListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.box(width: 120, height: 68),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(width: 180),
                      const SizedBox(height: 8),
                      Skeleton.line(),
                      const SizedBox(height: 4),
                      Skeleton.line(width: 240),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _CastCrewRow extends ConsumerWidget {
  const _CastCrewRow({required this.people});

  final List<PersonCredit> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final shown = people.take(14).toList(growable: false);
    return SizedBox(
      height: 114,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final person = shown[i];
          final imageUrl = repo.personImageUrl(person.id, person.primaryImageTag);
          return InkWell(
            onTap: person.id == null || person.id!.isEmpty
                ? null
                : () => context.push('/person/${person.id}'),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 86,
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LocalOrNetworkImage(
                      source: imageUrl,
                      errorBuilder: (_) => const Icon(
                        Icons.person_outline,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    person.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.genres, required this.onTapGenre});

  final List<String> genres;
  final ValueChanged<String> onTapGenre;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          InkWell(
            onTap: () => onTapGenre(g),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                g,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MoreLikeThisRow extends StatelessWidget {
  const _MoreLikeThisRow({
    required this.itemsAsync,
    required this.currentItemId,
  });

  final AsyncValue<List<BrowseItem>> itemsAsync;
  final String currentItemId;

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      data: (items) {
        final filtered = items
            .where((item) => item.id != currentItemId)
            .toList(growable: false);
        if (filtered.isEmpty) {
          return const Text(
            'No recommendations yet.',
            style: TextStyle(color: AppColors.textSecondary),
          );
        }
        return SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => PosterCard(
              item: filtered[i],
              onTap: () => _openDetail(context, filtered[i]),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 248, child: _PosterRowSkeleton()),
      error: (_, _) => const Text(
        'Could not load recommendations.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _PosterRowSkeleton extends StatelessWidget {
  const _PosterRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => Skeleton.box(width: 132, height: 240),
      ),
    );
  }
}

class _SeriesSkeleton extends StatelessWidget {
  const _SeriesSkeleton();

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
                Skeleton.line(),
                const SizedBox(height: 8),
                Skeleton.line(),
                const SizedBox(height: 8),
                Skeleton.line(width: 200),
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

void _playEpisode(
  BuildContext context,
  Episode ep, {
  TrackPreference preference = const TrackPreference(),
}) {
  final ticks = ep.userData?.playbackPositionTicks ?? 0;
  final query = <String, String>{
    if (ticks > 0) 'resumeTicks': '$ticks',
    if (ep.seriesId.isNotEmpty) 'seriesId': ep.seriesId,
    if (ep.parentIndexNumber != null) 'seasonNumber': '${ep.parentIndexNumber}',
    if (ep.indexNumber != null) 'episodeNumber': '${ep.indexNumber}',
    ...preference.toQuery(),
  };
  final uri = Uri(
    path: '/play/${ep.id}',
    queryParameters: query.isEmpty ? null : query,
  );
  context.push(uri.toString());
}

void _openDetail(BuildContext context, BrowseItem item) {
  switch (item.kind) {
    case MediaKind.movie:
      context.push('/movie/${item.id}');
    case MediaKind.series:
      context.push('/series/${item.id}');
    case MediaKind.season:
      context.push('/season/${item.id}');
    case MediaKind.episode:
      context.push('/episode/${item.id}');
  }
}
