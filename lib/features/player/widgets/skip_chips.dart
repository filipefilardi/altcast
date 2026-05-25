import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';

/// Stacked "Skip intro" / "Skip credits" chips shown over the player when
/// the current playback position falls inside an Intro Skipper segment.
///
/// Renders only the chips whose flags are set; both can co-exist (e.g. mid-
/// season recap → opening credits).
class SkipChipStack extends StatelessWidget {
  const SkipChipStack({
    super.key,
    required this.showIntro,
    required this.showCredits,
    required this.onSkipIntro,
    required this.onSkipCredits,
  });

  final bool showIntro;
  final bool showCredits;
  final VoidCallback onSkipIntro;
  final VoidCallback onSkipCredits;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showIntro)
          _SkipChip(
            label: 'Skip intro',
            icon: PiconsRegular.fastForward,
            onPressed: onSkipIntro,
          ),
        if (showIntro && showCredits) const SizedBox(height: 10),
        if (showCredits)
          _SkipChip(
            label: 'Skip credits',
            icon: PiconsFill.skipForward,
            onPressed: onSkipCredits,
          ),
      ],
    );
  }
}

/// Glass-style pill that matches AltCast's brand: dark navy fill, subtle
/// cyan stroke + glow, accent-coloured leading icon. Sized for a single
/// crisp tap target, never stretches edge-to-edge.
class _SkipChip extends StatelessWidget {
  const _SkipChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.55),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
