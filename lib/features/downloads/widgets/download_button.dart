import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/episode.dart';
import '../../../data/jellyfin/models/movie.dart';
import '../../../data/jellyfin/models/series.dart';

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
  final VoidCallback onEnqueue;
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
        icon: const Icon(Icons.download_done_rounded, color: AppColors.primary),
        tooltip: 'Downloaded — tap to remove',
        onPressed: () => _confirmDelete(context, ref),
      );
    }
    if (progress != null) {
      final pct = progress.fraction;
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: iconSize - 2,
            height: iconSize - 2,
            child: CircularProgressIndicator(
              value: pct > 0 ? pct : null,
              strokeWidth: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
            ),
          ),
          IconButton(
            iconSize: iconSize - 6,
            icon: const Icon(Icons.close),
            tooltip: 'Cancel download',
            color: AppColors.textSecondary,
            onPressed: () =>
                ref.read(downloadManagerProvider.notifier).cancel(itemId),
          ),
        ],
      );
    }
    if (failed) {
      return IconButton(
        iconSize: iconSize,
        icon: const Icon(Icons.error_outline, color: AppColors.error),
        tooltip: 'Download failed — tap to retry',
        onPressed: () =>
            ref.read(downloadManagerProvider.notifier).retry(itemId),
      );
    }
    return IconButton(
      iconSize: iconSize,
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Download for offline',
      onPressed: onEnqueue,
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
      onEnqueue: () =>
          ref.read(downloadManagerProvider.notifier).enqueueMovie(movie),
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
      onEnqueue: () => ref
          .read(downloadManagerProvider.notifier)
          .enqueueEpisode(
            episode,
            seriesName: seriesName,
            seriesPosterTag: seriesPosterTag,
          ),
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
      icon: const Icon(Icons.download_outlined),
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
      _showBatchQueuedSnackBar(
        ScaffoldMessenger.of(context),
        queued,
        widget.series.name,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text("Couldn't queue ${widget.series.name}")),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

void _showBatchQueuedSnackBar(
  ScaffoldMessengerState messenger,
  int queued,
  String label,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          queued == 0
              ? '$label is already downloaded or queued.'
              : 'Queued $queued episode${queued == 1 ? '' : 's'} from $label.',
        ),
      ),
    );
}
