import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/local_or_network_image.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/browse_item.dart';

/// 16:9 backdrop card with a progress bar — used in "Continue Watching".
class ResumeCard extends ConsumerWidget {
  const ResumeCard({
    required this.item,
    this.width = 240,
    this.onTap,
    super.key,
  });

  final BrowseItem item;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final url = repo.backdropUrl(
      item.id,
      item.backdropTag,
      fallbackPrimaryTag: item.imageTag,
    );
    final progress = item.userData?.progress ?? 0;
    final remaining = _remainingLabel(item);

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: LocalOrNetworkImage(
                        source: url,
                        errorBuilder: (_) => const Center(
                          child: Icon(
                            Icons.movie_outlined,
                            color: AppColors.textTertiary,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 4,
                        color: AppColors.background.withValues(alpha: 0.5),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0, 1).toDouble(),
                          child: Container(color: AppColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _displayTitle(item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              remaining,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayTitle(BrowseItem item) {
    if (item.kind == MediaKind.episode && item.seriesName != null) {
      return '${item.seriesName} — ${item.name}';
    }
    return item.name;
  }

  String _remainingLabel(BrowseItem item) {
    final ud = item.userData;
    final total = item.runTime;
    if (ud == null || total == null || total == Duration.zero) {
      return item.subtitle ?? '';
    }
    final watched = ud.resumePosition;
    final left = total - watched;
    if (left <= Duration.zero) return 'Finished';
    return '${formatLongDuration(left)} left';
  }
}
