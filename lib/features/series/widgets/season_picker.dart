import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/data/jellyfin/models/series.dart';

/// Horizontal scrollable chip row of seasons. The currently-selected season's
/// chip uses the accent color; others use the neutral surface treatment.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Season> seasons;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = seasons[i];
          final selected = s.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelect(s.id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.divider,
                ),
              ),
              child: Text(
                s.name,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
