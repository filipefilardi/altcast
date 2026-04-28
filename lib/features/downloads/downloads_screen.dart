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
          : state.items.isEmpty && state.progress.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: EmptyState(
                    icon: Icons.download_outlined,
                    title: 'Nothing downloaded yet',
                    message:
                        'Tap the download icon on a movie to keep it offline.',
                  ),
                )
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    if (state.progress.isNotEmpty) ...[
                      Text(
                        'Downloading'.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in state.progress.entries)
                        _InProgressRow(itemId: entry.key, progress: entry.value),
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
    final poster = repo.posterUrl(item.id, item.imageTag);
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
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.year != null || item.runTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.year != null) '${item.year}',
                        if (item.runTime != null) formatLongDuration(item.runTime!),
                      ].join(' • '),
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
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textSecondary),
              tooltip: 'Remove download',
              onPressed: () =>
                  ref.read(downloadManagerProvider.notifier).delete(item.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _InProgressRow extends ConsumerWidget {
  const _InProgressRow({required this.itemId, required this.progress});
  final String itemId;
  final double progress;

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
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
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
                  itemId,
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
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            tooltip: 'Cancel',
            onPressed: () =>
                ref.read(downloadManagerProvider.notifier).cancel(itemId),
          ),
        ],
      ),
    );
  }
}
