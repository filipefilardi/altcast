import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';

/// Bottom-right autoplay card previewing the next episode.
/// The full card is tappable to play now; close icon cancels/dismisses.
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
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );
    return Material(
      color: Colors.transparent,
      shape: shape,
      child: Ink(
        width: 356,
        decoration: ShapeDecoration(
          color: AppColors.surface.withValues(alpha: 0.94),
          shape: shape.copyWith(
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.28)),
          ),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          customBorder: shape,
          onTap: onPlayNow,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 142,
                      child: _NextUpThumb(
                        posterUrl: posterUrl,
                        countdownRemaining: countdownForAutoplay,
                        countdownTotal: countdownDuration,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NEXT UP',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _episodeLine(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            if (_autoplayRunning) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Autoplay in ${countdownForAutoplay!}s',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: IconButton(
                  splashRadius: 16,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onCancel,
                  tooltip: _autoplayRunning ? 'Cancel autoplay' : 'Dismiss',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _episodeLine() {
    if (episode.shortLabel.isEmpty) return episode.name;
    return '${episode.shortLabel} · ${episode.name}';
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
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: AspectRatio(
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
                    PiconsRegular.televisionSimple,
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
                    AppColors.surface.withValues(alpha: 0.72),
                  ],
                  stops: const [0.45, 1],
                ),
              ),
            ),
            if (countdownRemaining != null && countdownTotal > 0)
              Positioned(
                top: 6,
                right: 6,
                child: _CountdownRing(
                  remaining: countdownRemaining!,
                  total: countdownTotal,
                ),
              ),
          ],
        ),
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
                color: AppColors.primary.withValues(alpha: 0.2),
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
