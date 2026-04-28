import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'local_or_network_image.dart';

/// Full-width 16:9 backdrop with a bottom-up gradient that fades into the
/// scaffold background. Used as the header of movie / series detail screens.
class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.backdropUrl,
    required this.title,
    this.subtitle,
    this.metaRow,
  });

  final String? backdropUrl;
  final String title;
  final String? subtitle;

  /// Optional small chip-row rendered under the subtitle (year, runtime,
  /// rating, etc.).
  final Widget? metaRow;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: AppColors.surfaceElevated,
            child: LocalOrNetworkImage(
              source: backdropUrl,
              errorBuilder: (_) => const Center(
                child: Icon(
                  Icons.movie_outlined,
                  color: AppColors.textTertiary,
                  size: 40,
                ),
              ),
            ),
          ),
          // Bottom-up gradient — fades the image into the scaffold background
          // so the title sits on a solid color regardless of artwork brightness.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1.0],
                colors: [
                  AppColors.background.withValues(alpha: 0.0),
                  AppColors.background,
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (metaRow != null) ...[
                  const SizedBox(height: 10),
                  metaRow!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
