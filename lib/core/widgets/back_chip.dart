import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Floating circular back button used on detail screens (movie, series,
/// episode, season). Sits on top of the edge-to-edge hero artwork via the
/// scaffold's `floatingActionButton` slot with `startTop` placement.
///
/// Sized to the platform 44 px touch-target minimum and given a slightly
/// stronger backdrop so the icon stays legible over bright artwork.
class BackChip extends StatelessWidget {
  const BackChip({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: AppColors.background.withValues(alpha: 0.7),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.pop(),
              child: const Icon(
                Icons.arrow_back,
                color: AppColors.textPrimary,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
