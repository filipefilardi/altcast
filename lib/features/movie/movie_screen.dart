import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/utils/format.dart';
import 'package:altcast/core/widgets/back_chip.dart';
import 'package:altcast/core/widgets/detail_hero.dart';
import 'package:altcast/core/widgets/detail_sections.dart';
import 'package:altcast/core/widgets/detail_screen_skeleton.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/genre_chips.dart';
import 'package:altcast/core/widgets/media_detail_actions.dart';
import 'package:altcast/core/widgets/meta_pill_row.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/movie.dart';
import 'package:altcast/features/downloads/widgets/download_button.dart';
import 'package:altcast/features/remote/remote_providers.dart';
import 'package:altcast/features/remote/remote_sessions_sheet.dart';
import 'package:altcast/features/movie/movie_providers.dart';
import 'package:altcast/features/movie/widgets/track_preference_row.dart';

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

class _MovieBodyState extends ConsumerState<_MovieBody>
    with TrackPreferenceStateMixin<_MovieBody> {
  @override
  void initState() {
    super.initState();
    initTrackPreference(originalLanguage: widget.movie.originalLanguage);
  }

  @override
  void didUpdateWidget(covariant _MovieBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    refreshTrackPreferenceIfItemChanged(
      previousItemId: oldWidget.movie.id,
      nextItemId: widget.movie.id,
      originalLanguage: widget.movie.originalLanguage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final repo = ref.watch(jellyfinRepositoryProvider);
    final similarAsync = ref.watch(similarMoviesProvider(movie.id));
    final castActive = ref.watch(activeRemoteSessionIdProvider) != null;
    final backdrop = repo.backdropUrl(
      movie.id,
      movie.backdropTag,
      fallbackPrimaryTag: movie.imageTag,
    );
    final hasResume =
        (movie.userData?.resumePosition ?? Duration.zero) >
        const Duration(seconds: 5);
    final tagline = movie.tagline?.trim();
    final safeBottomInset = MediaQuery.paddingOf(context).bottom;

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
              MediaDetailActions(
                onPlay: () => _play(context, movie, fromStart: false),
                playLabel: hasResume ? 'Resume' : 'Play',
                onPlayFromStart: hasResume
                    ? () => _play(context, movie, fromStart: true)
                    : null,
                initialPlayed: movie.userData?.played ?? false,
                onSetPlayed: (v) async {
                  await repo.setPlayed(movie.id, played: v);
                  ref.invalidate(movieProvider(movie.id));
                },
                onCast: () => showRemoteSessionsSheet(
                  context,
                  itemId: movie.id,
                  startPositionTicks:
                      movie.userData?.playbackPositionTicks ?? 0,
                ),
                castActive: castActive,
                downloadAction: MovieDownloadButton(movie: movie),
              ),
              TrackPreferenceRow(
                itemId: movie.id,
                preference: preference,
                originalLanguageHint: movie.originalLanguage,
                onChanged: updateTrackPreference,
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
              DetailOverviewSection(
                overview: movie.overview,
                tagline: tagline,
                title: 'OVERVIEW',
              ),
              DetailCastCrewSection(people: movie.artists),
              DetailMoreLikeThisSection(
                itemsAsync: similarAsync,
                currentItemId: movie.id,
              ),
              SizedBox(height: 4 + safeBottomInset),
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
      ...preference.toQuery(),
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
    return const DetailScreenSkeleton(lineWidths: [200, null, null, 160]);
  }
}
