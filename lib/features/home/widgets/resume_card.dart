import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/utils/format.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';

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
            Expanded(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
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
                                PiconsRegular.televisionSimple,
                                color: AppColors.textTertiary,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.42),
                                ],
                                stops: const [0.52, 1],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: AppColors.background.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress
                                        .clamp(0, 1)
                                        .toDouble(),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: AppGradients.accentHorizontal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
