import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Wrap of pill-shaped genre chips. Each chip is tappable so callers can
/// route into a filtered library view.
class GenreChips extends StatelessWidget {
  const GenreChips({
    super.key,
    required this.genres,
    required this.onTapGenre,
  });

  final List<String> genres;
  final ValueChanged<String> onTapGenre;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          InkWell(
            onTap: () => onTapGenre(g),
            borderRadius: BorderRadius.circular(999),
            child: Container(
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
          ),
      ],
    );
  }
}
