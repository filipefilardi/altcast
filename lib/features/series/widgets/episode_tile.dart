import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/local_or_network_image.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/episode.dart';
import '../../downloads/widgets/download_button.dart';

class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    required this.seriesName,
    this.seriesPosterTag,
    this.onTap,
  });

  final Episode episode;

  /// Threaded down so the download button can label this entry as
  /// "{Series} · S1·E03 · {Title}" in the offline list.
  final String seriesName;
  final String? seriesPosterTag;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final stillUrl = repo.posterUrl(episode.id, episode.imageTag);
    final played = episode.userData?.played ?? false;
    final progress = episode.userData?.progress ?? 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: AppColors.surfaceElevated,
                        child: LocalOrNetworkImage(
                          source: stillUrl,
                          errorBuilder: (_) => const Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: AppColors.textTertiary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      if (progress > 0 && !played)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 3,
                            color:
                                AppColors.background.withValues(alpha: 0.5),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.toDouble(),
                              child: Container(color: AppColors.primary),
                            ),
                          ),
                        ),
                      if (played)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.background.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (episode.indexNumber != null) ...[
                        Text(
                          '${episode.indexNumber}.',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          episode.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: played
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (episode.runTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatLongDuration(episode.runTime!),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (episode.overview != null &&
                      episode.overview!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      episode.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            EpisodeDownloadButton(
              episode: episode,
              seriesName: seriesName,
              seriesPosterTag: seriesPosterTag,
            ),
          ],
        ),
      ),
    );
  }
}
