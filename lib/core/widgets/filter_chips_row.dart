import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';

/// Read-only horizontal Wrap of compact pill labels — used by Library and
/// Search to surface the currently-applied filters above the results. Empty
/// list collapses to nothing.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final label in labels) _FilterChip(text: label)],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
