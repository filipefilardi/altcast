import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';

/// Bottom-right card that previews the next episode and offers a play CTA
/// matching the brand's accent-gradient pill. Shows a live countdown ring
/// while autoplay is running, otherwise a static play arrow.
class NextUpCard extends StatelessWidget {
  const NextUpCard({
    super.key,
    required this.episode,
    required this.posterUrl,
    required this.countdownForAutoplay,
    required this.countdownDuration,
    required this.onCancel,
    required this.onPlayNow,
  });

  final Episode episode;
  final String? posterUrl;

  /// Live remaining seconds — non-null means autoplay is running. Null means
  /// the card is offering only a manual "Play next" action.
  final int? countdownForAutoplay;

  /// Total countdown length, used to fill the progress arc.
  final int countdownDuration;

  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  bool get _autoplayRunning =>
      countdownForAutoplay != null && countdownForAutoplay! > 0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _NextUpThumb(
              posterUrl: posterUrl,
              countdownRemaining: countdownForAutoplay,
              countdownTotal: countdownDuration,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (b) => AppGradients.accent.createShader(b),
                    child: Text(
                      'NEXT UP',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (episode.shortLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        episode.shortLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  Text(
                    episode.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NextUpPlayPill(
                          label: _autoplayRunning ? 'Play now' : 'Play next',
                          onPressed: onPlayNow,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _NextUpCancelButton(
                        label: _autoplayRunning ? 'Cancel' : 'Dismiss',
                        onPressed: onCancel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextUpThumb extends StatelessWidget {
  const _NextUpThumb({
    required this.posterUrl,
    required this.countdownRemaining,
    required this.countdownTotal,
  });

  final String? posterUrl;
  final int? countdownRemaining;
  final int countdownTotal;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: AppColors.surfaceElevated,
            child: LocalOrNetworkImage(
              source: posterUrl,
              errorBuilder: (_) => const Center(
                child: Icon(
                  Icons.movie_outlined,
                  color: AppColors.textTertiary,
                  size: 28,
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.surface.withValues(alpha: 0.85),
                ],
                stops: const [0.55, 1],
              ),
            ),
          ),
          if (countdownRemaining != null && countdownTotal > 0)
            Positioned(
              right: 10,
              top: 10,
              child: _CountdownRing(
                remaining: countdownRemaining!,
                total: countdownTotal,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Sweep from full → empty as the countdown ticks down.
    final value = (remaining / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.background.withValues(alpha: 0.72),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          Text(
            '$remaining',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextUpPlayPill extends StatelessWidget {
  const _NextUpPlayPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.onAccent,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.onAccent,
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

class _NextUpCancelButton extends StatelessWidget {
  const _NextUpCancelButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.divider),
          ),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
