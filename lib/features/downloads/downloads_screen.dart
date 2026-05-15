import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/downloaded_item.dart';
import '../../data/jellyfin/jellyfin_repository.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: !state.bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : state.items.isEmpty &&
                state.progress.isEmpty &&
                state.failures.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: EmptyState(
                icon: Icons.download_outlined,
                title: 'Nothing downloaded yet',
                message:
                    'Tap the download icon on a movie or episode to keep it offline.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                _QueueSummary(state: state),
                const SizedBox(height: 16),
                if (state.progress.isNotEmpty) ...[
                  Text(
                    'Downloading'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final entry in state.progress.values)
                    _InProgressRow(progress: entry),
                  const SizedBox(height: 24),
                ],
                if (state.failures.isNotEmpty) ...[
                  Text(
                    'Needs attention'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final failure in state.failures.values)
                    _FailedRow(failure: failure),
                  const SizedBox(height: 24),
                ],
                if (state.items.isNotEmpty) ...[
                  Text(
                    'Available offline'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final item in state.items.values)
                    _DownloadedRow(item: item),
                ],
              ],
            ),
    );
  }
}

class _DownloadedRow extends ConsumerWidget {
  const _DownloadedRow({required this.item});
  final DownloadedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    // For episodes, prefer the series poster (set in the queue entry); we
    // already swapped to it at enqueue time, so [item.imageTag] is correct.
    final poster = repo.posterUrl(
      item.kind == DownloadedItemKind.episode
          ? (item.seriesId ?? item.id)
          : item.id,
      item.imageTag,
    );
    return InkWell(
      onTap: () => context.push('/play/${item.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 78,
                child: ColoredBox(
                  color: AppColors.surfaceElevated,
                  child: LocalOrNetworkImage(
                    source: poster,
                    errorBuilder: (_) => const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _primaryLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_secondaryLabel(item) != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _secondaryLabel(item)!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.textSecondary,
              ),
              tooltip: 'Remove download',
              onPressed: () =>
                  ref.read(downloadManagerProvider.notifier).delete(item.id),
            ),
          ],
        ),
      ),
    );
  }

  String _primaryLabel(DownloadedItem item) {
    if (item.kind == DownloadedItemKind.episode && item.seriesName != null) {
      return '${item.seriesName} — ${item.name}';
    }
    return item.name;
  }

  String? _secondaryLabel(DownloadedItem item) {
    final parts = <String>[
      if (item.episodeLabel != null) item.episodeLabel!,
      if (item.year != null && item.kind == DownloadedItemKind.movie)
        '${item.year}',
      if (item.runTime != null) formatLongDuration(item.runTime!),
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }
}

class _FailedRow extends ConsumerWidget {
  const _FailedRow({required this.failure});
  final DownloadFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(failure),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _secondary(failure),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            tooltip: 'Retry download',
            onPressed: () => ref
                .read(downloadManagerProvider.notifier)
                .retry(failure.itemId),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            tooltip: 'Dismiss',
            onPressed: () => ref
                .read(downloadManagerProvider.notifier)
                .dismissFailure(failure.itemId),
          ),
        ],
      ),
    );
  }

  String _label(DownloadFailure f) {
    if (f.kind == DownloadedItemKind.episode && f.seriesName != null) {
      return '${f.seriesName} — ${f.name}';
    }
    return f.name;
  }

  String _secondary(DownloadFailure f) {
    if (f.episodeLabel != null) return '${f.episodeLabel} • ${f.message}';
    return f.message;
  }
}

class _InProgressRow extends ConsumerWidget {
  const _InProgressRow({required this.progress});
  final DownloadProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final paused = downloads.isPaused(progress.itemId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 78,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: paused
                    ? null
                    : (progress.fraction > 0 ? progress.fraction : null),
                strokeWidth: 2,
                color: AppColors.primary,
                backgroundColor: AppColors.divider,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(progress),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _secondary(progress),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              paused ? Icons.play_arrow : Icons.pause,
              color: AppColors.textSecondary,
            ),
            tooltip: paused ? 'Resume' : 'Pause',
            onPressed: () => paused
                ? ref
                      .read(downloadManagerProvider.notifier)
                      .resume(progress.itemId)
                : ref
                      .read(downloadManagerProvider.notifier)
                      .pause(progress.itemId),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            tooltip: 'Cancel',
            onPressed: () => ref
                .read(downloadManagerProvider.notifier)
                .cancel(progress.itemId),
          ),
        ],
      ),
    );
  }

  String _label(DownloadProgress p) {
    if (p.kind == DownloadedItemKind.episode && p.seriesName != null) {
      return '${p.seriesName} — ${p.name}';
    }
    return p.name;
  }

  String _secondary(DownloadProgress p) {
    final bytes = p.totalBytes != null && p.downloadedBytes != null
        ? '${formatBytes(p.downloadedBytes!)} / ${formatBytes(p.totalBytes!)}'
        : (p.downloadedBytes != null ? formatBytes(p.downloadedBytes!) : null);
    final pct = p.fraction > 0
        ? '${(p.fraction * 100).toStringAsFixed(0)}%'
        : 'Queued';
    final line = bytes != null ? '$pct • $bytes' : pct;
    if (p.episodeLabel != null) return '${p.episodeLabel} • $line';
    return line;
  }
}

class _QueueSummary extends StatelessWidget {
  const _QueueSummary({required this.state});

  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    final paused = state.pausedIds.length;
    final downloading = state.progress.length - paused;
    final available = state.items.length;
    final failed = state.failures.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        [
          if (available > 0) '$available offline',
          if (downloading > 0) '$downloading active',
          if (paused > 0) '$paused paused',
          if (failed > 0) '$failed failed',
        ].join(' • '),
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
