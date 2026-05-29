import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';
import 'package:altcast/data/jellyfin/models/movie.dart';
import 'package:altcast/data/jellyfin/models/series.dart';

/// Generic three-state download control:
///  - idle: outlined download icon, taps [onEnqueue].
///  - downloading: circular progress overlay, taps cancel.
///  - downloaded: filled check icon in accent color, taps confirm-delete.
///
/// Specialized via [MovieDownloadButton] / [EpisodeDownloadButton] so the
/// consumer doesn't have to repeat the enqueue plumbing.
class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({
    required this.itemId,
    required this.itemName,
    required this.onEnqueue,
    this.iconSize = 22,
  });

  final String itemId;
  final String itemName;
  final Future<void> Function(BuildContext context, WidgetRef ref) onEnqueue;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final downloaded = state.items.containsKey(itemId);
    final progress = state.progress[itemId];
    final failed = state.failures.containsKey(itemId);

    if (downloaded) {
      return IconButton(
        iconSize: iconSize,
        icon: const Icon(PiconsRegular.checkCircle, color: AppColors.primary),
        tooltip: 'Downloaded — tap to remove',
        onPressed: () => _confirmDelete(context, ref),
      );
    }
    if (progress != null) {
      final pct = progress.fraction;
      final paused = state.isPaused(itemId);
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: iconSize - 2,
            height: iconSize - 2,
            child: CircularProgressIndicator(
              value: paused ? null : (pct > 0 ? pct : null),
              strokeWidth: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
            ),
          ),
          IconButton(
            iconSize: iconSize - 6,
            icon: Icon(paused ? PiconsFill.play : PiconsFill.pause),
            tooltip: paused ? 'Resume download' : 'Pause download',
            color: Colors.white,
            onPressed: () => paused
                ? ref.read(downloadManagerProvider.notifier).resume(itemId)
                : ref.read(downloadManagerProvider.notifier).pause(itemId),
          ),
        ],
      );
    }
    if (failed) {
      return IconButton(
        iconSize: iconSize,
        icon: const Icon(PiconsRegular.warningCircle, color: AppColors.error),
        tooltip: 'Download failed — tap to retry',
        onPressed: () {
          ref.read(downloadManagerProvider.notifier).retry(itemId);
          _showDownloadToast(context, 'Retrying "$itemName".');
        },
      );
    }
    return IconButton(
      iconSize: iconSize,
      icon: const Icon(PiconsRegular.downloadSimple),
      tooltip: 'Download for offline',
      onPressed: () => onEnqueue(context, ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Remove download?'),
        content: Text('"$itemName" will no longer be available offline.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(downloadManagerProvider.notifier).delete(itemId);
    }
  }
}

class MovieDownloadButton extends ConsumerWidget {
  const MovieDownloadButton({super.key, required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DownloadButton(
      itemId: movie.id,
      itemName: movie.name,
      onEnqueue: (context, ref) async {
        final queued = await ref
            .read(downloadManagerProvider.notifier)
            .enqueueMovie(movie);
        if (!context.mounted) return;
        _showDownloadToast(
          context,
          queued
              ? 'Queued "${movie.name}" for download.'
              : '"${movie.name}" is already downloaded or queued.',
        );
      },
    );
  }
}

/// Compact button for the episode list — same three-state behaviour as the
/// movie button, just smaller and pre-bound to [DownloadManager.enqueueEpisode].
/// Needs the parent series' name (and optionally its poster tag) so the
/// downloads screen can render "{Series} · S1·E03" instead of a bare title.
class EpisodeDownloadButton extends ConsumerWidget {
  const EpisodeDownloadButton({
    super.key,
    required this.episode,
    required this.seriesName,
    this.seriesPosterTag,
  });

  final Episode episode;
  final String seriesName;
  final String? seriesPosterTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DownloadButton(
      itemId: episode.id,
      itemName: '$seriesName — ${episode.name}',
      iconSize: 20,
      onEnqueue: (context, ref) async {
        final queued = await ref
            .read(downloadManagerProvider.notifier)
            .enqueueEpisode(
              episode,
              seriesName: seriesName,
              seriesPosterTag: seriesPosterTag,
            );
        if (!context.mounted) return;
        _showDownloadToast(
          context,
          queued
              ? 'Queued "$seriesName — ${episode.name}" for download.'
              : '"$seriesName — ${episode.name}" is already downloaded or queued.',
        );
      },
    );
  }
}

class SeriesDownloadButton extends ConsumerStatefulWidget {
  const SeriesDownloadButton({
    super.key,
    required this.series,
    required this.seasons,
  });

  final Series series;
  final List<Season> seasons;

  @override
  ConsumerState<SeriesDownloadButton> createState() =>
      _SeriesDownloadButtonState();
}

class _SeriesDownloadButtonState extends ConsumerState<SeriesDownloadButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      iconSize: 22,
      icon: const Icon(PiconsRegular.downloadSimple),
      tooltip: 'Download series',
      onPressed: widget.seasons.isEmpty ? null : _downloadSeries,
    );
  }

  Future<void> _downloadSeries() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final seasonEpisodes = await Future.wait(
        widget.seasons.map(
          (season) => repo.getEpisodes(widget.series.id, season.id),
        ),
      );
      final episodes = seasonEpisodes
          .expand((season) => season)
          .toList(growable: false);
      final queued = await ref
          .read(downloadManagerProvider.notifier)
          .enqueueEpisodes(
            episodes,
            seriesName: widget.series.name,
            seriesPosterTag: widget.series.imageTag,
          );
      if (!mounted) return;
      _showBatchQueuedSnackBar(context, queued, widget.series.name);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, "Couldn't queue ${widget.series.name}");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

void _showBatchQueuedSnackBar(BuildContext context, int queued, String label) {
  _showDownloadToast(
    context,
    queued == 0
        ? '$label is already downloaded or queued.'
        : 'Queued $queued episode${queued == 1 ? '' : 's'} from $label.',
  );
}

void _showDownloadToast(BuildContext context, String message) {
  showAppSnackBar(
    context,
    message,
    actionLabel: 'View',
    onAction: () => context.push('/downloads'),
  );
}
