import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/back_chip.dart';
import 'package:altcast/core/widgets/detail_action_row.dart';
import 'package:altcast/core/widgets/detail_hero.dart';
import 'package:altcast/core/widgets/detail_sections.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/genre_chips.dart';
import 'package:altcast/core/widgets/play_button.dart';
import 'package:altcast/core/widgets/skeleton.dart';
import 'package:altcast/core/widgets/user_data_actions.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';
import 'package:altcast/data/jellyfin/models/series.dart';
import 'package:altcast/data/local/playback_preferences.dart';
import 'package:altcast/features/downloads/widgets/download_button.dart';
import 'package:altcast/features/remote/remote_providers.dart';
import 'package:altcast/features/remote/remote_sessions_sheet.dart';
import 'package:altcast/features/series/series_providers.dart';
import 'package:altcast/features/series/widgets/episode_tile.dart';
import 'package:altcast/features/series/widgets/season_picker.dart';
import 'package:altcast/features/movie/widgets/track_preference_row.dart';

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({required this.seriesId, super.key});
  final String seriesId;

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedSeasonId;

  @override
  Widget build(BuildContext context) {
    final seriesAsync = ref.watch(seriesProvider(widget.seriesId));
    final seasonsAsync = ref.watch(seasonsProvider(widget.seriesId));

    // Active season: user choice if set, otherwise the first season as soon
    // as the list arrives. Derived (not stored) so we don't end up scheduling
    // a post-frame setState on every build.
    final seasons = seasonsAsync.value ?? const [];
    final activeSeasonId =
        _selectedSeasonId ?? (seasons.isNotEmpty ? seasons.first.id : null);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(seriesProvider(widget.seriesId));
          ref.invalidate(seasonsProvider(widget.seriesId));
          ref.invalidate(similarSeriesProvider(widget.seriesId));
          if (activeSeasonId != null) {
            ref.invalidate(
              episodesProvider((
                seriesId: widget.seriesId,
                seasonId: activeSeasonId,
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
            selectedSeasonId: activeSeasonId,
            onSelectSeason: (id) => setState(() => _selectedSeasonId = id),
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
      floatingActionButton: const BackChip(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }
}

class _SeriesBody extends ConsumerStatefulWidget {
  const _SeriesBody({
    required this.series,
    required this.seasonsAsync,
    required this.selectedSeasonId,
    required this.onSelectSeason,
  });

  final Series series;
  final AsyncValue<List<Season>> seasonsAsync;
  final String? selectedSeasonId;
  final ValueChanged<String> onSelectSeason;

  @override
  ConsumerState<_SeriesBody> createState() => _SeriesBodyState();
}

class _SeriesBodyState extends ConsumerState<_SeriesBody> {
  late TrackPreference _preference;

  @override
  void initState() {
    super.initState();
    _preference = TrackPreference.fromPlaybackPrefs(
      ref.read(playbackPreferencesProvider),
      itemOriginalLanguage: widget.series.originalLanguage,
    );
  }

  @override
  void didUpdateWidget(covariant _SeriesBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.id != widget.series.id) {
      _preference = TrackPreference.fromPlaybackPrefs(
        ref.read(playbackPreferencesProvider),
        itemOriginalLanguage: widget.series.originalLanguage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final seasonsAsync = widget.seasonsAsync;
    final selectedSeasonId = widget.selectedSeasonId;
    final onSelectSeason = widget.onSelectSeason;
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
    final nextHasResume =
        (next?.userData?.resumePosition ?? Duration.zero) >
        const Duration(seconds: 5);
    final castActive = ref.watch(activeRemoteSessionIdProvider) != null;
    final tagline = series.tagline?.trim();

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
              DetailActionRow(
                primary: PlayButton(
                  onPressed: next == null
                      ? null
                      : () => _playEpisode(
                          context,
                          next,
                          preference: _preference,
                        ),
                  label: _playLabel(next),
                  icon: Icons.play_arrow_rounded,
                ),
                actions: [
                  if (next != null && nextHasResume)
                    IconButton(
                      iconSize: 22,
                      icon: const Icon(Icons.replay),
                      tooltip: 'Play from start',
                      onPressed: () => _playEpisode(
                        context,
                        next,
                        preference: _preference,
                        fromStart: true,
                      ),
                    ),
                  UserDataActions(
                    initialPlayed: series.userData?.played ?? false,
                    onSetPlayed: (v) async {
                      await repo.setPlayed(series.id, played: v);
                      ref.invalidate(seriesProvider(series.id));
                    },
                  ),
                  if (next != null)
                    IconButton(
                      iconSize: 22,
                      icon: Icon(
                        Icons.cast,
                        color: castActive ? AppColors.primary : null,
                      ),
                      tooltip: 'Play on…',
                      onPressed: () => showRemoteSessionsSheet(
                        context,
                        itemId: next.id,
                        startPositionTicks:
                            next.userData?.playbackPositionTicks ?? 0,
                      ),
                    ),
                  SeriesDownloadButton(series: series, seasons: seasons),
                ],
              ),
              TrackPreferenceRow(
                itemId: next?.id ?? series.id,
                preference: _preference,
                originalLanguageHint: series.originalLanguage,
                onChanged: (next) => setState(() => _preference = next),
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
              DetailOverviewSection(
                overview: series.overview,
                tagline: tagline,
              ),
              if (series.genres.isNotEmpty) ...[
                const SizedBox(height: 24),
                GenreChips(
                  genres: series.genres,
                  onTapGenre: (genre) => context.push(
                    Uri(
                      path: '/library/shows',
                      queryParameters: {'genre': genre},
                    ).toString(),
                  ),
                ),
              ],
              DetailCastCrewSection(people: series.artists),
              DetailMoreLikeThisSection(
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
          preference: _preference,
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
                onTap: () => _playEpisode(context, ep, preference: preference),
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

class _SeriesSkeleton extends StatelessWidget {
  const _SeriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Skeleton.group(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Skeleton.box(
                width: double.infinity,
                height: DetailHero.heightForWidth(
                  constraints.maxWidth,
                  MediaQuery.orientationOf(context),
                ),
                radius: 0,
              );
            },
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

void _playEpisode(
  BuildContext context,
  Episode ep, {
  TrackPreference preference = const TrackPreference(),
  bool fromStart = false,
}) {
  final ticks = fromStart ? 0 : (ep.userData?.playbackPositionTicks ?? 0);
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
