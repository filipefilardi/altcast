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
import '../../core/widgets/genre_chips.dart';
import '../../core/widgets/meta_pill_row.dart';
import '../../core/widgets/more_like_this_row.dart';
import '../../core/widgets/play_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/user_data_actions.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/movie.dart';
import '../../data/local/playback_preferences.dart';
import '../downloads/widgets/download_button.dart';
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
            ref
                .read(similarMoviesProvider(movieId).future)
                .catchError((_) => <BrowseItem>[]),
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
      floatingActionButton: const BackChip(),
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
  late TrackPreference _preference;

  @override
  void initState() {
    super.initState();
    _preference = TrackPreference.fromPlaybackPrefs(
      ref.read(playbackPreferencesProvider),
      itemOriginalLanguage: widget.movie.originalLanguage,
    );
  }

  @override
  void didUpdateWidget(covariant _MovieBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.id != widget.movie.id) {
      _preference = TrackPreference.fromPlaybackPrefs(
        ref.read(playbackPreferencesProvider),
        itemOriginalLanguage: widget.movie.originalLanguage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final similarAsync = ref.watch(similarMoviesProvider(movie.id));
    final backdrop = repo.backdropUrl(
      movie.id,
      movie.backdropTag,
      fallbackPrimaryTag: movie.imageTag,
    );
    final hasResume =
        (movie.userData?.resumePosition ?? Duration.zero) >
        const Duration(seconds: 5);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        DetailHero(
          backdropUrl: backdrop,
          title: movie.name,
          subtitle: _subtitle(movie),
          metaRow: MetaPillRow(
            labels: [
              movie.officialRating,
              if (movie.communityRating != null)
                '★ ${movie.communityRating!.toStringAsFixed(1)}',
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap so the secondary actions drop to a second line on
              // narrow phones (long "Resume" labels + 4 trailing icons can
              // otherwise overflow a single Row).
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  PlayButton(
                    onPressed: () => _play(context, movie, fromStart: false),
                    label: hasResume ? 'Resume' : 'Play',
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserDataActions(
                        initialPlayed: movie.userData?.played ?? false,
                        onSetPlayed: (v) async {
                          await repo.setPlayed(movie.id, played: v);
                          ref.invalidate(movieProvider(movie.id));
                        },
                      ),
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
                        'Continues from ${formatDuration(movie.userData!.resumePosition)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                      InkWell(
                        onTap: () => _play(context, movie, fromStart: true),
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
              TrackPreferenceRow(
                itemId: movie.id,
                preference: _preference,
                originalLanguageHint: movie.originalLanguage,
                onChanged: (next) => setState(() => _preference = next),
              ),
              if (movie.genres.isNotEmpty) ...[
                const SizedBox(height: 24),
                GenreChips(
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
                Text('OVERVIEW', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ExpandableText(
                  text: movie.overview!,
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
                CastCrewRow(people: movie.artists),
              ],
              const SizedBox(height: 24),
              Text(
                'MORE LIKE THIS',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              MoreLikeThisRow(
                itemsAsync: similarAsync,
                currentItemId: movie.id,
              ),
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
    final ticks = fromStart ? 0 : (movie.userData?.playbackPositionTicks ?? 0);
    final query = <String, String>{
      if (ticks > 0) 'resumeTicks': '$ticks',
      ..._preference.toQuery(),
    };
    final uri = Uri(
      path: '/play/${movie.id}',
      queryParameters: query.isEmpty ? null : query,
    );
    context.push(uri.toString());
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
