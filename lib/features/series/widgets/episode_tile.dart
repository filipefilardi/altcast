import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/format.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/core/widgets/glass_popover.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';
import 'package:altcast/features/downloads/widgets/download_button.dart';

class EpisodeTile extends ConsumerStatefulWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    required this.seriesName,
    this.seriesPosterTag,
    this.onTap,
    this.onSetPlayed,
  });

  final Episode episode;

  /// Threaded down so the download button can label this entry as
  /// "{Series} · S1·E03 · {Title}" in the offline list.
  final String seriesName;
  final String? seriesPosterTag;

  final VoidCallback? onTap;
  final Future<void> Function(bool played)? onSetPlayed;

  @override
  ConsumerState<EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<EpisodeTile> {
  static const double _actionsPopoverWidth = 240;
  static const double _actionsPopoverGap = 8;

  late bool _played = widget.episode.userData?.played ?? false;
  bool _playedBusy = false;
  Offset? _pressPosition;

  @override
  void didUpdateWidget(covariant EpisodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingPlayed = widget.episode.userData?.played ?? false;
    final oldPlayed = oldWidget.episode.userData?.played ?? false;
    if (!_playedBusy &&
        (widget.episode.id != oldWidget.episode.id ||
            incomingPlayed != oldPlayed)) {
      _played = incomingPlayed;
    }
  }

  Future<void> _togglePlayed() async {
    if (_playedBusy || widget.onSetPlayed == null) return;
    final next = !_played;
    setState(() {
      _played = next;
      _playedBusy = true;
    });
    try {
      await widget.onSetPlayed!(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _played = !next);
      showAppSnackBar(
        context,
        next ? "Couldn't mark as watched" : "Couldn't mark as unwatched",
      );
    } finally {
      if (mounted) setState(() => _playedBusy = false);
    }
  }

  Future<void> _showPlayedActions() {
    return showGlassPopover<void>(
      context: context,
      width: _actionsPopoverWidth,
      anchorRect: _pressAnchorRect(),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPopoverItem(
            icon: _played ? PiconsRegular.xCircle : PiconsRegular.checkCircle,
            label: _played ? 'Mark as unwatched' : 'Mark as watched',
            enabled: !_playedBusy,
            onTap: _togglePlayed,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Rect? _pressAnchorRect() {
    final position = _pressPosition;
    if (position == null) return null;
    return Rect.fromLTWH(
      position.dx + _actionsPopoverWidth + _actionsPopoverGap,
      position.dy,
      1,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final episode = widget.episode;
    final stillUrl = repo.posterUrl(episode.id, episode.imageTag);
    final progress = episode.userData?.progress ?? 0;

    return InkWell(
      onTap: widget.onTap,
      onTapDown: widget.onSetPlayed == null
          ? null
          : (details) => _pressPosition = details.globalPosition,
      onLongPress: widget.onSetPlayed == null ? null : _showPlayedActions,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: AppColors.surfaceElevated,
                        child: LocalOrNetworkImage(
                          source: stillUrl,
                          errorBuilder: (_) => const Center(
                            child: Icon(
                              PiconsRegular.televisionSimple,
                              color: AppColors.textTertiary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      if (progress > 0 && !_played)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 3,
                            color: AppColors.background.withValues(alpha: 0.5),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.toDouble(),
                              child: Container(color: AppColors.primary),
                            ),
                          ),
                        ),
                      if (_played)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(
                                alpha: 0.74,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                PiconsRegular.check,
                                size: 15,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (episode.indexNumber != null) ...[
                        Text(
                          '${episode.indexNumber}.',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          episode.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _played
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (episode.runTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatLongDuration(episode.runTime!),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (episode.overview != null &&
                      episode.overview!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      episode.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            EpisodeDownloadButton(
              episode: episode,
              seriesName: widget.seriesName,
              seriesPosterTag: widget.seriesPosterTag,
            ),
          ],
        ),
      ),
    );
  }
}
