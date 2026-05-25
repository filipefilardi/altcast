import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';

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

  static bool useComposedLayout(double width, Orientation orientation) {
    return width >= 900 ||
        (orientation == Orientation.landscape && width >= 640);
  }

  static double heightForWidth(double width, Orientation orientation) {
    final isComposed = useComposedLayout(width, orientation);
    if (!isComposed) return width * 9 / 16;

    final isDesktop = width >= 900;
    final target = width * 0.44;
    if (!isDesktop) {
      if (target < 300) return 300;
      if (target > 420) return 420;
      return target;
    }
    if (target < 520) return 520;
    if (target > 760) return 760;
    return target;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final orientation = MediaQuery.orientationOf(context);
        final isComposed = DetailHero.useComposedLayout(width, orientation);
        final height = DetailHero.heightForWidth(width, orientation);

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
                      PiconsRegular.televisionSimple,
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
                    stops: isComposed
                        ? const [0.0, 0.42, 0.78, 1.0]
                        : const [0.15, 0.55, 0.82, 1.0],
                    colors: [
                      AppColors.background.withValues(
                        alpha: isComposed ? 0.08 : 0.0,
                      ),
                      AppColors.background.withValues(
                        alpha: isComposed ? 0.2 : 0.34,
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
                    center: isComposed
                        ? const Alignment(0, 0.56)
                        : const Alignment(0, 1.15),
                    radius: isComposed ? 0.78 : 1.08,
                    colors: [
                      Colors.black.withValues(alpha: isComposed ? 0.38 : 0.46),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: -2,
                height: isComposed ? 164 : 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withValues(alpha: 0.0),
                        AppColors.background,
                        AppColors.background,
                      ],
                      stops: const [0.0, 0.88, 1.0],
                    ),
                  ),
                ),
              ),
              _HeroCopy(
                title: title,
                subtitle: subtitle,
                metaRow: metaRow,
                isComposed: isComposed,
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
    required this.isComposed,
  });

  final String title;
  final String? subtitle;
  final Widget? metaRow;
  final bool isComposed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final align = isComposed ? Alignment.bottomCenter : Alignment.bottomLeft;
    final padding = EdgeInsets.fromLTRB(
      isComposed ? 48 : 20,
      0,
      isComposed ? 48 : 20,
      isComposed ? 72 : 16,
    );
    final crossAxisAlignment = isComposed
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = isComposed ? TextAlign.center : TextAlign.start;

    return Align(
      alignment: align,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isComposed ? 760 : double.infinity,
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
                style: isComposed
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
                    fontSize: isComposed ? 15 : null,
                  ),
                ),
              ],
              if (metaRow != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: isComposed
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
