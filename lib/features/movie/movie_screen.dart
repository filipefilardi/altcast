import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/detail_hero.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/play_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/movie.dart';
import 'movie_providers.dart';

class MovieScreen extends ConsumerWidget {
  const MovieScreen({required this.movieId, super.key});
  final String movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieProvider(movieId));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(movieProvider(movieId).future),
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

class _MovieBody extends ConsumerWidget {
  const _MovieBody({required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
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
                    onPressed: () => _playStub(context),
                    label: hasResume ? 'Resume' : 'Play',
                  ),
                  if (hasResume) ...[
                    const SizedBox(width: 12),
                    Text(
                      'from ${formatDuration(movie.userData!.resumePosition)}',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                    ),
                  ],
                ],
              ),
              if (movie.genres.isNotEmpty) ...[
                const SizedBox(height: 24),
                _GenreChips(genres: movie.genres),
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
  const _GenreChips({required this.genres});
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          Container(
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
      ],
    );
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

void _playStub(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Player coming soon')),
    );
}
