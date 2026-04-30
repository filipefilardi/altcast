import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Horizontal Wrap of small "pills" used in detail-screen hero areas to show
/// short metadata snippets (year, runtime, rating, etc). Empty/null entries
/// are skipped, and an empty list collapses to nothing.
class MetaPillRow extends StatelessWidget {
  const MetaPillRow({super.key, required this.labels});

  final List<String?> labels;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      for (final label in labels)
        if (label != null && label.isNotEmpty) MetaPill(text: label),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }
}

class MetaPill extends StatelessWidget {
  const MetaPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
