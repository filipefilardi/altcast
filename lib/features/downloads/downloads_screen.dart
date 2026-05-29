import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/format.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/data/downloads/download_manager.dart';
import 'package:altcast/data/downloads/downloaded_item.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final grouped = _groupAvailableDownloads(state.items.values);
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
                icon: PiconsRegular.downloadSimple,
                title: 'Nothing downloaded yet',
                message:
                    'Tap the download icon on a movie or episode to keep it offline.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                if (state.progress.isNotEmpty) ...[
                  const _SectionHeader(title: 'Downloading'),
                  const SizedBox(height: 8),
                  for (final entry in state.progress.values)
                    _InProgressRow(progress: entry),
                  const SizedBox(height: 24),
                ],
                if (state.failures.isNotEmpty) ...[
                  const _SectionHeader(title: 'Needs Attention'),
                  const SizedBox(height: 8),
                  for (final failure in state.failures.values)
                    _FailedRow(failure: failure),
                  const SizedBox(height: 24),
                ],
                if (state.items.isNotEmpty) ...[
                  if (grouped.seriesGroups.isNotEmpty) ...[
                    const _SectionHeader(title: 'TV Shows'),
                    const SizedBox(height: 8),
                    for (final group in grouped.seriesGroups)
                      _SeriesDownloadsCard(group: group),
                  ],
                  if (grouped.movies.isNotEmpty) ...[
                    if (grouped.seriesGroups.isNotEmpty)
                      const SizedBox(height: 16),
                    const _SectionHeader(title: 'Movies'),
                    const SizedBox(height: 8),
                    for (final item in grouped.movies)
                      _DownloadedRow(item: item),
                  ],
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        letterSpacing: 1.0,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _DownloadedSeriesGroup {
  const _DownloadedSeriesGroup({
    required this.groupKey,
    required this.title,
    required this.posterSeriesId,
    required this.posterTag,
    required this.episodes,
  });

  final String groupKey;
  final String title;
  final String posterSeriesId;
  final String? posterTag;
  final List<DownloadedItem> episodes;
}

class _GroupedAvailableDownloads {
  const _GroupedAvailableDownloads({
    required this.movies,
    required this.seriesGroups,
  });

  final List<DownloadedItem> movies;
  final List<_DownloadedSeriesGroup> seriesGroups;
}

_GroupedAvailableDownloads _groupAvailableDownloads(
  Iterable<DownloadedItem> items,
) {
  final movies = <DownloadedItem>[];
  final episodesBySeries = <String, List<DownloadedItem>>{};

  for (final item in items) {
    if (item.kind == DownloadedItemKind.episode) {
      final groupKey = _seriesGroupKey(item);
      episodesBySeries.putIfAbsent(groupKey, () => []).add(item);
    } else {
      movies.add(item);
    }
  }

  movies.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final seriesGroups =
      episodesBySeries.entries.map((entry) {
        final episodes = entry.value.toList()..sort(_compareEpisodes);
        final first = episodes.first;
        return _DownloadedSeriesGroup(
          groupKey: entry.key,
          title: first.seriesName?.trim().isNotEmpty == true
              ? first.seriesName!.trim()
              : 'TV Show',
          posterSeriesId: first.seriesId?.trim().isNotEmpty == true
              ? first.seriesId!.trim()
              : first.id,
          posterTag: first.imageTag,
          episodes: episodes,
        );
      }).toList()..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

  return _GroupedAvailableDownloads(movies: movies, seriesGroups: seriesGroups);
}

String _seriesGroupKey(DownloadedItem item) {
  final seriesId = item.seriesId?.trim();
  if (seriesId != null && seriesId.isNotEmpty) return 'id:$seriesId';
  final seriesName = item.seriesName?.trim().toLowerCase();
  if (seriesName != null && seriesName.isNotEmpty) return 'name:$seriesName';
  return 'item:${item.id}';
}

int _compareEpisodes(DownloadedItem a, DownloadedItem b) {
  final bySeason = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
  if (bySeason != 0) return bySeason;
  final byEpisode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
  if (byEpisode != 0) return byEpisode;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

String _landscapeImageUrl(
  JellyfinRepository repo, {
  required String itemId,
  required String? imageTag,
}) {
  return repo.backdropUrl(
    itemId,
    null,
    fallbackPrimaryTag: imageTag,
    width: 560,
  );
}

class _LandscapeThumb extends StatelessWidget {
  const _LandscapeThumb({required this.source, this.overlay});

  final String? source;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 116,
        height: 66,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.surface,
              child: LocalOrNetworkImage(
                source: source,
                errorBuilder: (_) => const Center(
                  child: Icon(
                    PiconsRegular.televisionSimple,
                    color: AppColors.textTertiary,
                    size: 18,
                  ),
                ),
              ),
            ),
            ...(overlay != null ? [overlay!] : const <Widget>[]),
          ],
        ),
      ),
    );
  }
}

class _SeriesDownloadsCard extends ConsumerWidget {
  const _SeriesDownloadsCard({required this.group});
  final _DownloadedSeriesGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final poster = _landscapeImageUrl(
      repo,
      itemId: group.posterSeriesId,
      imageTag: group.posterTag,
    );
    final seasons = group.episodes
        .map((e) => e.seasonNumber)
        .whereType<int>()
        .toSet()
        .length;
    final episodeCount = group.episodes.length;
    final totalDuration = _sumRuntime(group.episodes);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _SeriesDownloadsScreen(
                groupKey: group.groupKey,
                seriesTitle: group.title,
              ),
            ),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surfaceHighlight, AppColors.surfaceElevated],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _LandscapeThumb(source: poster),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            '$episodeCount episode${episodeCount == 1 ? '' : 's'}',
                            if (seasons > 0)
                              '$seasons season${seasons == 1 ? '' : 's'}',
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (totalDuration != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            formatLongDuration(totalDuration),
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
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      PiconsRegular.caretRight,
                      color: AppColors.textSecondary,
                      size: 14,
                    ),
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

Duration? _sumRuntime(List<DownloadedItem> items) {
  var micros = 0;
  var hasRuntime = false;
  for (final item in items) {
    final runTime = item.runTime;
    if (runTime == null) continue;
    micros += runTime.inMicroseconds;
    hasRuntime = true;
  }
  if (!hasRuntime) return null;
  return Duration(microseconds: micros);
}

class _SeriesDownloadsScreen extends ConsumerWidget {
  const _SeriesDownloadsScreen({
    required this.groupKey,
    required this.seriesTitle,
  });

  final String groupKey;
  final String seriesTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final grouped = _groupAvailableDownloads(state.items.values);
    _DownloadedSeriesGroup? group;
    for (final candidate in grouped.seriesGroups) {
      if (candidate.groupKey == groupKey) {
        group = candidate;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(seriesTitle)),
      body: group == null
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: EmptyState(
                icon: PiconsRegular.televisionSimple,
                title: 'No downloaded episodes',
                message: 'This show currently has no offline episodes.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                for (final seasonGroup in _groupEpisodesBySeason(
                  group.episodes,
                )) ...[
                  _SectionHeader(title: seasonGroup.label),
                  const SizedBox(height: 8),
                  for (final episode in seasonGroup.episodes)
                    _SeriesEpisodeRow(item: episode),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _SeasonEpisodesGroup {
  const _SeasonEpisodesGroup({required this.label, required this.episodes});

  final String label;
  final List<DownloadedItem> episodes;
}

List<_SeasonEpisodesGroup> _groupEpisodesBySeason(
  List<DownloadedItem> episodes,
) {
  final buckets = <int?, List<DownloadedItem>>{};
  for (final item in episodes) {
    buckets.putIfAbsent(item.seasonNumber, () => []).add(item);
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    });
  return keys
      .map(
        (key) => _SeasonEpisodesGroup(
          label: key == null ? 'Season Unknown' : 'Season $key',
          episodes: (buckets[key]!..sort(_compareEpisodes)),
        ),
      )
      .toList(growable: false);
}

class _SeriesEpisodeRow extends ConsumerWidget {
  const _SeriesEpisodeRow({required this.item});
  final DownloadedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final image = _landscapeImageUrl(
      repo,
      itemId: item.id,
      imageTag: item.imageTag,
    );
    final subtitle = <String>[
      if (item.episodeLabel != null) item.episodeLabel!,
      if (item.runTime != null) formatLongDuration(item.runTime!),
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/play/${item.id}'),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _LandscapeThumb(source: image),
                  const SizedBox(width: 10),
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
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
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
                  _ActionCircleButton(
                    icon: PiconsRegular.trash,
                    tooltip: 'Remove download',
                    onPressed: () => ref
                        .read(downloadManagerProvider.notifier)
                        .delete(item.id),
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

class _DownloadedRow extends ConsumerWidget {
  const _DownloadedRow({required this.item});
  final DownloadedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final poster = _landscapeImageUrl(
      repo,
      itemId: item.id,
      imageTag: item.imageTag,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/play/${item.id}'),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _LandscapeThumb(source: poster),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _primaryLabel(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
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
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ActionCircleButton(
                    icon: PiconsRegular.trash,
                    tooltip: 'Remove download',
                    onPressed: () => ref
                        .read(downloadManagerProvider.notifier)
                        .delete(item.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _primaryLabel(DownloadedItem item) {
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
    final repo = ref.watch(jellyfinRepositoryProvider);
    final image = _landscapeImageUrl(
      repo,
      itemId: failure.itemId,
      imageTag: failure.imageTag,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          _LandscapeThumb(
            source: image,
            overlay: Container(
              color: AppColors.error.withValues(alpha: 0.24),
              alignment: Alignment.center,
              child: const Icon(
                PiconsRegular.warningCircle,
                color: AppColors.error,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(failure),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
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
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              _ActionCircleButton(
                icon: PiconsRegular.arrowsClockwise,
                tooltip: 'Retry download',
                onPressed: () => ref
                    .read(downloadManagerProvider.notifier)
                    .retry(failure.itemId),
              ),
              const SizedBox(height: 8),
              _ActionCircleButton(
                icon: PiconsRegular.x,
                tooltip: 'Dismiss',
                onPressed: () => ref
                    .read(downloadManagerProvider.notifier)
                    .dismissFailure(failure.itemId),
              ),
            ],
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
    final repo = ref.watch(jellyfinRepositoryProvider);
    final paused = downloads.isPaused(progress.itemId);
    final image = _landscapeImageUrl(
      repo,
      itemId: progress.itemId,
      imageTag: progress.imageTag,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          _LandscapeThumb(
            source: image,
            overlay: Container(
              color: AppColors.background.withValues(alpha: 0.28),
              alignment: Alignment.center,
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  value: paused
                      ? null
                      : (progress.fraction > 0 ? progress.fraction : null),
                  strokeWidth: 3,
                  color: AppColors.primary,
                  backgroundColor: AppColors.divider,
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
                  _label(progress),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _secondary(progress),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              _ActionCircleButton(
                icon: paused ? PiconsFill.play : PiconsFill.pause,
                iconColor: AppColors.textPrimary,
                tooltip: paused ? 'Resume' : 'Pause',
                onPressed: () => paused
                    ? ref
                          .read(downloadManagerProvider.notifier)
                          .resume(progress.itemId)
                    : ref
                          .read(downloadManagerProvider.notifier)
                          .pause(progress.itemId),
              ),
              const SizedBox(height: 8),
              _ActionCircleButton(
                icon: PiconsRegular.x,
                tooltip: 'Cancel',
                onPressed: () => ref
                    .read(downloadManagerProvider.notifier)
                    .cancel(progress.itemId),
              ),
            ],
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

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor = AppColors.textSecondary,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}
