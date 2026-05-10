import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'local_or_network_image.dart';

/// Full-width backdrop with a bottom-up gradient that fades into the scaffold
/// background. Used as the header of movie / series detail screens.
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

  static double heightForWidth(double width) {
    final isDesktop = width >= 900;
    if (!isDesktop) return width * 9 / 16;

    final target = width * 0.44;
    if (target < 520) return 520;
    if (target > 760) return 760;
    return target;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= 900;
        final height = DetailHero.heightForWidth(width);

        return SizedBox(
          height: height,
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
              // Bottom-up gradient fades the image into the scaffold
              // background so metadata stays readable over bright artwork.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: isDesktop
                        ? const [0.0, 0.42, 0.78, 1.0]
                        : const [0.15, 0.55, 0.82, 1.0],
                    colors: [
                      AppColors.background.withValues(
                        alpha: isDesktop ? 0.08 : 0.0,
                      ),
                      AppColors.background.withValues(
                        alpha: isDesktop ? 0.2 : 0.34,
                      ),
                      AppColors.background.withValues(alpha: 0.8),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
              // Soft vignette to tame bright backdrops near the title while
              // keeping enough detail visible above.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: isDesktop
                        ? const Alignment(0, 0.56)
                        : const Alignment(0, 1.15),
                    radius: isDesktop ? 0.78 : 1.08,
                    colors: [
                      Colors.black.withValues(alpha: isDesktop ? 0.38 : 0.46),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
              _HeroCopy(
                title: title,
                subtitle: subtitle,
                metaRow: metaRow,
                isDesktop: isDesktop,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.title,
    required this.subtitle,
    required this.metaRow,
    required this.isDesktop,
  });

  final String title;
  final String? subtitle;
  final Widget? metaRow;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final align = isDesktop ? Alignment.bottomCenter : Alignment.bottomLeft;
    final padding = EdgeInsets.fromLTRB(
      isDesktop ? 48 : 20,
      0,
      isDesktop ? 48 : 20,
      isDesktop ? 88 : 16,
    );
    final crossAxisAlignment = isDesktop
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = isDesktop ? TextAlign.center : TextAlign.start;

    return Align(
      alignment: align,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 760 : double.infinity,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: isDesktop
                    ? theme.displayMedium?.copyWith(
                        color: AppColors.textPrimary,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 2),
                            blurRadius: 14,
                          ),
                        ],
                      )
                    : theme.headlineLarge,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: textAlign,
                  style: theme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: isDesktop ? 15 : null,
                  ),
                ),
              ],
              if (metaRow != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: isDesktop
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: metaRow!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
