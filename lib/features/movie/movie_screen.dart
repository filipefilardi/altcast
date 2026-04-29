import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/play_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/movie.dart';
import '../../data/jellyfin/models/person_credit.dart';
import '../../data/local/playback_preferences.dart';
import '../downloads/widgets/download_button.dart';
import '../home/widgets/poster_card.dart';
import '../remote/remote_sessions_sheet.dart';
import 'movie_providers.dart';
import 'widgets/track_preference_row.dart';

class MovieScreen extends ConsumerWidget {
  const MovieScreen({required this.movieId, super.key});
  final String movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieProvider(movieId));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(movieProvider(movieId));
          ref.invalidate(similarMoviesProvider(movieId));
          await Future.wait([
            ref.read(movieProvider(movieId).future),
            ref.read(similarMoviesProvider(movieId).future).catchError((_) => <BrowseItem>[]),
          ]);
        },
        child: async.when(
          data: (movie) => _MovieBody(movie: movie),
          loading: () => const _MovieSkeleton(),
          error: (e, _) => ListView(
            // ListView so RefreshIndicator stays draggable on errors.
            children: [
              const SizedBox(height: 120),
              ErrorStateView(
                title: "Couldn't load movie",
                message: e.toString(),
                onRetry: () => ref.invalidate(movieProvider(movieId)),
              ),
            ],
          ),
        ),
      ),
      // Floating back button so the hero artwork stays edge-to-edge at the top.
      floatingActionButton: const _BackChip(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }
}

class _MovieBody extends ConsumerStatefulWidget {
  const _MovieBody({required this.movie});
  final Movie movie;

  @override
  ConsumerState<_MovieBody> createState() => _MovieBodyState();
}

class _MovieBodyState extends ConsumerState<_MovieBody> {
  TrackPreference _preference = const TrackPreference();
  bool _initializedFromDefaults = false;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final playbackPrefs = ref.watch(playbackPreferencesProvider);
    if (!_initializedFromDefaults) {
      _preference = TrackPreference(
        audioLang:
            playbackPrefs.resolvedAudioLanguage(movie.originalLanguage),
        subKind: switch (playbackPrefs.defaultSubtitleMode) {
          DefaultSubtitleMode.auto => SubPreferenceKind.serverDefault,
          DefaultSubtitleMode.off => SubPreferenceKind.off,
          DefaultSubtitleMode.byLanguage => SubPreferenceKind.byLang,
        },
        subLang: playbackPrefs.defaultSubtitleLanguage,
      );
      _initializedFromDefaults = true;
    }
    final similarAsync = ref.watch(similarMoviesProvider(movie.id));
    final backdrop = repo.backdropUrl(
      movie.id,
      movie.backdropTag,
      fallbackPrimaryTag: movie.imageTag,
    );
    final hasResume = (movie.userData?.resumePosition ?? Duration.zero) >
        const Duration(seconds: 5);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        DetailHero(
          backdropUrl: backdrop,
          title: movie.name,
          subtitle: _subtitle(movie),
          metaRow: _MetaRow(
            year: movie.year,
            runtime: movie.runTime,
            officialRating: movie.officialRating,
            communityRating: movie.communityRating,
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
                    onPressed: () => _play(context, movie, fromStart: false),
                    label: hasResume ? 'Resume' : 'Play',
                  ),
                  if (hasResume) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () =>
                          _play(context, movie, fromStart: true),
                      child: Text(
                        'from start',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.cast),
                    tooltip: 'Play on…',
                    onPressed: () => showRemoteSessionsSheet(
                      context,
                      itemId: movie.id,
                      startPositionTicks:
                          movie.userData?.playbackPositionTicks ?? 0,
                    ),
                  ),
                  MovieDownloadButton(movie: movie),
                ],
              ),
              TrackPreferenceRow(
                itemId: movie.id,
                preference: _preference,
                originalLanguageHint: movie.originalLanguage,
                onChanged: (next) => setState(() => _preference = next),
              ),
              if (hasResume)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Continues from ${formatDuration(movie.userData!.resumePosition)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                  ),
                ),
              if (movie.genres.isNotEmpty) ...[
                const SizedBox(height: 24),
                _GenreChips(
                  genres: movie.genres,
                  onTapGenre: (genre) => context.push(
                    Uri(
                      path: '/library/movies',
                      queryParameters: {'genre': genre},
                    ).toString(),
                  ),
                ),
              ],
              if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'OVERVIEW',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  movie.overview!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (movie.artists.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'CAST & CREW',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                _CastCrewRow(people: movie.artists),
              ],
              const SizedBox(height: 24),
              Text(
                'MORE LIKE THIS',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              _MoreLikeThisRow(itemsAsync: similarAsync, currentItemId: movie.id),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  String? _subtitle(Movie m) {
    final parts = <String>[];
    if (m.year != null) parts.add(m.year.toString());
    if (m.runTime != null) parts.add(formatLongDuration(m.runTime!));
    return parts.isEmpty ? null : parts.join(' • ');
  }

  void _play(BuildContext context, Movie movie, {required bool fromStart}) {
    final ticks =
        fromStart ? 0 : (movie.userData?.playbackPositionTicks ?? 0);
    final query = <String, String>{
      if (ticks > 0) 'resumeTicks': '$ticks',
      ..._preference.toQuery(),
    };
    final uri = Uri(path: '/play/${movie.id}', queryParameters: query.isEmpty ? null : query);
    context.push(uri.toString());
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.year,
    required this.runtime,
    required this.officialRating,
    required this.communityRating,
  });
  final int? year;
  final Duration? runtime;
  final String? officialRating;
  final double? communityRating;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (officialRating != null && officialRating!.isNotEmpty) {
      chips.add(_pill(officialRating!));
    }
    if (communityRating != null) {
      chips.add(_pill('★ ${communityRating!.toStringAsFixed(1)}'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
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
        itemBuilder: (context, i) {
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
      loading: () => const SizedBox(
        height: 248,
        child: _PosterRowSkeleton(),
      ),
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
    case MediaKind.person:
      context.push('/person/${item.id}');
  }
}

class _MovieSkeleton extends StatelessWidget {
  const _MovieSkeleton();

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
                Skeleton.line(),
                const SizedBox(height: 8),
                Skeleton.line(width: 160),
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

