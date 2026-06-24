import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/core/widgets/edge_light_background.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/genre_chips.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';

final _movieGenresProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(jellyfinRepositoryProvider).getGenres(itemType: 'Movie');
});

final _showGenresProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(jellyfinRepositoryProvider).getGenres(itemType: 'Series');
});

class LibraryGenresScreen extends ConsumerWidget {
  const LibraryGenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieGenres = ref.watch(_movieGenresProvider);
    final showGenres = ref.watch(_showGenresProvider);
    final allFailed = movieGenres.hasError && showGenres.hasError;
    final allEmpty =
        movieGenres.value?.isEmpty == true && showGenres.value?.isEmpty == true;

    Future<void> refresh() async {
      ref.invalidate(_movieGenresProvider);
      ref.invalidate(_showGenresProvider);
      await Future.wait([
        ref
            .read(_movieGenresProvider.future)
            .catchError((error, stackTrace) => <String>[]),
        ref
            .read(_showGenresProvider.future)
            .catchError((error, stackTrace) => <String>[]),
      ]);
    }

    return EdgeLightBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Genres')),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              if (allFailed)
                ErrorStateView(
                  title: "Couldn't load genres",
                  message: userFacingNetworkMessage(
                    movieGenres.error ?? showGenres.error ?? Exception(),
                  ),
                  onRetry: refresh,
                )
              else if (allEmpty)
                const EmptyState(
                  icon: Icons.category_outlined,
                  title: 'No genres found',
                  message: 'No movie or TV genres are available right now.',
                )
              else ...[
                _GenreSection(
                  title: 'Movie Genres',
                  genresState: movieGenres,
                  onRetry: () => ref.invalidate(_movieGenresProvider),
                  onTapGenre: (genre) => context.push(
                    Uri(
                      path: '/library/movies',
                      queryParameters: {'genre': genre},
                    ).toString(),
                  ),
                ),
                const SizedBox(height: 24),
                _GenreSection(
                  title: 'TV Genres',
                  genresState: showGenres,
                  onRetry: () => ref.invalidate(_showGenresProvider),
                  onTapGenre: (genre) => context.push(
                    Uri(
                      path: '/library/shows',
                      queryParameters: {'genre': genre},
                    ).toString(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreSection extends StatelessWidget {
  const _GenreSection({
    required this.title,
    required this.genresState,
    required this.onRetry,
    required this.onTapGenre,
  });

  final String title;
  final AsyncValue<List<String>> genresState;
  final VoidCallback onRetry;
  final ValueChanged<String> onTapGenre;

  @override
  Widget build(BuildContext context) {
    final genres = genresState.value;
    final isEmpty = genres != null && genres.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        if (genresState.isLoading && genres == null)
          const Center(child: CircularProgressIndicator())
        else if (genresState.hasError && genres == null)
          ErrorStateView(title: "Couldn't load $title", onRetry: onRetry)
        else if (isEmpty)
          const EmptyState(
            icon: Icons.movie_filter_outlined,
            title: 'No genres yet',
            message: 'Try adding more media to your library.',
          )
        else
          GenreChips(genres: genres ?? const [], onTapGenre: onTapGenre),
      ],
    );
  }
}
