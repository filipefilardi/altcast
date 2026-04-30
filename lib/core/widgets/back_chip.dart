import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Floating circular back button used on detail screens (movie, series,
/// episode, season). Sits on top of the edge-to-edge hero artwork via the
/// scaffold's `floatingActionButton` slot with `startTop` placement.
class BackChip extends StatelessWidget {
  const BackChip({super.key});

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
          child: const BackButton(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
