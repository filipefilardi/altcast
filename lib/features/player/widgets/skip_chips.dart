import 'dart:ui';

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

/// Compact glass-style pill: blurred background, semi-opaque black fill,
/// accent icon and uppercase label.
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
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );
    return Material(
      color: Colors.transparent,
      shape: shape,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Ink(
            decoration: ShapeDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: shape,
            ),
            child: InkWell(
              customBorder: shape,
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: AppColors.accent),
                    const SizedBox(width: 7),
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
        ),
      ),
    );
  }
}
