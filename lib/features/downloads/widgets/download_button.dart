import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/jellyfin/models/movie.dart';

/// Three-state download control:
///  - idle: outlined download icon, taps enqueue.
///  - downloading: circular progress overlay, taps cancel.
///  - downloaded: filled check icon in accent color, taps prompt delete.
class MovieDownloadButton extends ConsumerWidget {
  const MovieDownloadButton({super.key, required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final downloaded = state.items.containsKey(movie.id);
    final progress = state.progress[movie.id];

    if (downloaded) {
      return IconButton(
        icon: const Icon(Icons.download_done_rounded, color: AppColors.primary),
        tooltip: 'Downloaded — tap to remove',
        onPressed: () => _confirmDelete(context, ref),
      );
    }
    if (progress != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel download',
            color: AppColors.textSecondary,
            onPressed: () =>
                ref.read(downloadManagerProvider.notifier).cancel(movie.id),
          ),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Download for offline',
      onPressed: () =>
          ref.read(downloadManagerProvider.notifier).enqueueMovie(movie),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Remove download?'),
        content: Text('"${movie.name}" will no longer be available offline.'),
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
      await ref.read(downloadManagerProvider.notifier).delete(movie.id);
    }
  }
}
