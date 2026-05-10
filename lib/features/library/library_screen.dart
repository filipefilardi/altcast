import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/downloads/download_manager.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          _LibraryTile(
            icon: Icons.download_outlined,
            label: 'Downloads',
            subtitle: _downloadsSubtitle(downloads),
            onTap: () => context.push('/downloads'),
          ),
          // Placeholder for future entries — Movies / Shows / Collections.
          _LibraryTile(
            icon: Icons.movie_outlined,
            label: 'Movies',
            subtitle: 'Browse all movies',
            onTap: () => context.push('/library/movies'),
          ),
          _LibraryTile(
            icon: Icons.tv_outlined,
            label: 'TV Shows',
            subtitle: 'Browse all shows',
            onTap: () => context.push('/library/shows'),
          ),
          _LibraryTile(
            icon: Icons.collections_bookmark_outlined,
            label: 'Collections',
            subtitle: 'Browse movie collections',
            onTap: () => context.push('/library/collections'),
          ),
        ],
      ),
    );
  }

  String _downloadsSubtitle(DownloadsState s) {
    if (!s.bootstrapped) return 'Loading…';
    final pending = s.progress.length;
    final failed = s.failures.length;
    final done = s.items.length;
    if (done == 0 && pending == 0 && failed == 0) return 'Nothing offline yet';
    final parts = [
      if (done > 0) '$done available offline',
      if (pending > 0) '$pending downloading',
      if (failed > 0) '$failed failed',
    ];
    return parts.join(' • ');
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Opacity(
              opacity: disabled ? 0.55 : 1,
              child: Row(
                children: [
                  Icon(icon, color: AppColors.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!disabled)
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
