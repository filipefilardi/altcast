import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';

/// Primary "Play" / "Resume" CTA. Wide accent-gradient pill with a leading
/// triangle icon. Matches the brand identity of AltCast's [PlayPill] but is
/// a rectangular wide button suited to detail screens.
class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.onPressed,
    this.label = 'Play',
    this.icon = Icons.play_arrow_rounded,
    this.expanded = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  /// Stretch to fill the parent's width when true; otherwise sizes to content.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppGradients.accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.onAccent, size: 21),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.onAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Opacity(opacity: disabled ? 0.5 : 1, child: button);
  }
}
