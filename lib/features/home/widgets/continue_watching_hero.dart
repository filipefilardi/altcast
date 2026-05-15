import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/local_or_network_image.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/jellyfin/jellyfin_repository.dart';
import '../../../data/jellyfin/models/browse_item.dart';
import '../home_providers.dart';

/// Home “Keep watching” block: section label, loading / error / content, and
/// trailing spacing (24 px) for the next shelf.
class ContinueWatchingShelf extends StatelessWidget {
  const ContinueWatchingShelf({
    super.key,
    required this.itemsAsync,
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<BrowseItem>> itemsAsync;
  final VoidCallback onRetry;
  final void Function(BrowseItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    if (itemsAsync.hasValue && itemsAsync.requireValue.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'KEEP WATCHING',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (itemsAsync.isLoading)
          const _ContinueWatchingHeroSkeleton()
        else if (itemsAsync.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ErrorStateView(
              title: "Couldn't load Continue Watching",
              onRetry: onRetry,
            ),
          )
        else if (itemsAsync.hasValue)
          ContinueWatchingHero(items: itemsAsync.requireValue, onOpen: onOpen),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Compact desktop shelf, plus a swipeable mobile hero when there is more than
/// one in-progress title.
class ContinueWatchingHero extends ConsumerStatefulWidget {
  const ContinueWatchingHero({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<BrowseItem> items;
  final void Function(BrowseItem item) onOpen;

  @override
  ConsumerState<ContinueWatchingHero> createState() =>
      _ContinueWatchingHeroState();
}

class _ContinueWatchingHeroState extends ConsumerState<ContinueWatchingHero> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 900) {
          return _ContinueWatchingRail(items: items, onOpen: widget.onOpen);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                final h = (c.maxWidth * 0.62).clamp(220.0, 360.0);
                return SizedBox(
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: items.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => _HeroSlide(
                          item: items[i],
                          onOpenDetail: () => widget.onOpen(items[i]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (items.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  items.length,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: i == _page
                            ? AppColors.primary
                            : AppColors.textTertiary.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ContinueWatchingRail extends StatelessWidget {
  const _ContinueWatchingRail({required this.items, required this.onOpen});

  final List<BrowseItem> items;
  final void Function(BrowseItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 12.0;
        final cardWidth = _desktopContinueCardWidth(c.maxWidth);

        return SizedBox(
          height: cardWidth * 9 / 16,
          child: ListView.separated(
            primary: false,
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: spacing),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: _ContinueWatchingCard(
                item: items[i],
                onOpenDetail: () => onOpen(items[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}

double _desktopContinueCardWidth(double availableWidth) {
  const spacing = 12.0;
  final visibleCards = availableWidth >= 1400 ? 5 : 4;
  final rawWidth =
      (availableWidth - (spacing * (visibleCards - 1))) / visibleCards;
  return rawWidth.clamp(260.0, 360.0);
}

class _ContinueWatchingCard extends ConsumerWidget {
  const _ContinueWatchingCard({required this.item, required this.onOpenDetail});

  final BrowseItem item;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final url = repo.backdropUrl(
      item.id,
      item.backdropTag,
      fallbackPrimaryTag: item.imageTag,
    );
    final progress = item.userData?.progress ?? 0;
    final title = _heroTitle(item);
    final remaining = _heroRemaining(item);
    final metadata = _heroMetadata(item, remaining);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: AppColors.surfaceElevated,
          child: InkWell(
            onTap: onOpenDetail,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LocalOrNetworkImage(
                  source: url,
                  fit: BoxFit.cover,
                  errorBuilder: (_) => const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      color: AppColors.textTertiary,
                      size: 32,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.2, 0.58, 1.0],
                      colors: [
                        AppColors.background.withValues(alpha: 0.02),
                        AppColors.background.withValues(alpha: 0.34),
                        AppColors.background.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _QueueMenuButton(item: item),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.18,
                              ),
                            ),
                            if (metadata.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _openContinueWatchingResume(
                          context,
                          item,
                          onOpenDetail,
                        ),
                        child: const _CompactResumeButton(),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: AppColors.background.withValues(alpha: 0.62),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0, 1).toDouble(),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppGradients.accentHorizontal,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _CompactResumeButton extends StatelessWidget {
  const _CompactResumeButton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(
        width: 38,
        height: 38,
        child: Icon(
          Icons.play_arrow_rounded,
          color: AppColors.onAccent,
          size: 25,
        ),
      ),
    );
  }
}

class _HeroSlide extends ConsumerWidget {
  const _HeroSlide({required this.item, required this.onOpenDetail});

  final BrowseItem item;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final url = repo.backdropUrl(
      item.id,
      item.backdropTag,
      fallbackPrimaryTag: item.imageTag,
    );
    final progress = item.userData?.progress ?? 0;
    final title = _heroTitle(item);
    final remaining = _heroRemaining(item);
    final metadata = _heroMetadata(item, remaining);

    return Material(
      color: AppColors.surfaceElevated,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LocalOrNetworkImage(
            source: url,
            fit: BoxFit.cover,
            errorBuilder: (_) => const Center(
              child: Icon(
                Icons.movie_outlined,
                color: AppColors.textTertiary,
                size: 40,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.15, 0.55, 0.82, 1.0],
                colors: [
                  AppColors.background.withValues(alpha: 0.0),
                  AppColors.background.withValues(alpha: 0.34),
                  AppColors.background.withValues(alpha: 0.8),
                  AppColors.background,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 1.15),
                radius: 1.08,
                colors: [
                  Colors.black.withValues(alpha: 0.46),
                  Colors.black.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenDetail,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onOpenDetail,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: AppColors.background.withValues(
                                alpha: 0.55,
                              ),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.clamp(0, 1).toDouble(),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppGradients.accentHorizontal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onOpenDetail,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                              if (metadata.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  metadata,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _openContinueWatchingResume(
                          context,
                          item,
                          onOpenDetail,
                        ),
                        child: const _ResumePill(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(top: 12, right: 12, child: _QueueMenuButton(item: item)),
        ],
      ),
    );
  }
}

class _QueueMenuButton extends ConsumerWidget {
  const _QueueMenuButton({required this.item});

  final BrowseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_QueueMenuAction>(
      tooltip: 'Queue actions',
      onSelected: (action) async {
        switch (action) {
          case _QueueMenuAction.removeFromQueue:
            try {
              await ref
                  .read(jellyfinRepositoryProvider)
                  .removeFromQueue(item.id);
              ref.invalidate(continueWatchingProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed "${item.name}" from queue.')),
              );
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Couldn't remove this item from queue. Please try again.",
                  ),
                ),
              );
            }
          case _QueueMenuAction.removeSeriesFromQueue:
            final seriesId = item.kind == MediaKind.series
                ? item.id
                : item.seriesId;
            if (seriesId == null || seriesId.trim().isEmpty) return;
            try {
              await ref
                  .read(jellyfinRepositoryProvider)
                  .removeSeriesFromQueue(seriesId);
              ref.invalidate(continueWatchingProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Removed series "${item.seriesName ?? item.name}" from queue.',
                  ),
                ),
              );
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Couldn't remove this series from queue. Please try again.",
                  ),
                ),
              );
            }
        }
      },
      color: AppColors.surfaceElevated,
      itemBuilder: (context) {
        final canRemoveSeries =
            item.kind == MediaKind.series ||
            (item.kind == MediaKind.episode &&
                item.seriesId != null &&
                item.seriesId!.trim().isNotEmpty);
        return [
          const PopupMenuItem<_QueueMenuAction>(
            value: _QueueMenuAction.removeFromQueue,
            child: Text('Remove from queue'),
          ),
          if (canRemoveSeries)
            const PopupMenuItem<_QueueMenuAction>(
              value: _QueueMenuAction.removeSeriesFromQueue,
              child: Text('Remove series from queue'),
            ),
        ];
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.textTertiary.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 18,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

enum _QueueMenuAction { removeFromQueue, removeSeriesFromQueue }

class _ResumePill extends StatelessWidget {
  const _ResumePill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, color: AppColors.onAccent, size: 22),
            SizedBox(width: 4),
            Text(
              'RESUME',
              style: TextStyle(
                color: AppColors.onAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueWatchingHeroSkeleton extends StatelessWidget {
  const _ContinueWatchingHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Skeleton.group(
          child: c.maxWidth >= 900
              ? SizedBox(
                  height: _desktopContinueCardWidth(c.maxWidth) * 9 / 16,
                  child: ListView.separated(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, _) {
                      final cardWidth = _desktopContinueCardWidth(c.maxWidth);
                      return Skeleton.box(
                        width: cardWidth,
                        height: cardWidth * 9 / 16,
                        radius: 12,
                      );
                    },
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Builder(
                    builder: (context) {
                      final h = (c.maxWidth * 0.62).clamp(220.0, 360.0);
                      return Skeleton.box(
                        width: c.maxWidth,
                        height: h,
                        radius: 0,
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}

/// Opens [VideoPlayerScreen] for movies and episodes (with Jellyfin resume
/// ticks and episode metadata). Other kinds fall back to [onOpenDetail].
void _openContinueWatchingResume(
  BuildContext context,
  BrowseItem item,
  VoidCallback onOpenDetail,
) {
  switch (item.kind) {
    case MediaKind.movie:
    case MediaKind.episode:
      final ticks = item.userData?.playbackPositionTicks ?? 0;
      final query = <String, String>{
        if (ticks > 0) 'resumeTicks': '$ticks',
        if (item.kind == MediaKind.episode) ...{
          if (item.seriesId != null && item.seriesId!.trim().isNotEmpty)
            'seriesId': item.seriesId!,
          if (item.seasonNumber != null) 'seasonNumber': '${item.seasonNumber}',
          if (item.episodeNumber != null)
            'episodeNumber': '${item.episodeNumber}',
        },
      };
      context.push(
        Uri(
          path: '/play/${item.id}',
          queryParameters: query.isEmpty ? null : query,
        ).toString(),
      );
      return;
    case MediaKind.series:
    case MediaKind.season:
    case MediaKind.person:
    case MediaKind.collection:
      onOpenDetail();
  }
}

String _heroTitle(BrowseItem item) {
  if (item.kind == MediaKind.episode && item.seriesName != null) {
    return '${item.seriesName} — ${item.name}';
  }
  return item.name;
}

String _heroMetadata(BrowseItem item, String remaining) {
  final parts = <String>[];
  if (item.kind == MediaKind.episode &&
      item.seasonNumber != null &&
      item.episodeNumber != null) {
    parts.add(
      'S${item.seasonNumber} E${item.episodeNumber.toString().padLeft(2, '0')}',
    );
  } else if (item.year != null) {
    parts.add('${item.year}');
  } else if (item.subtitle != null && item.subtitle!.isNotEmpty) {
    parts.add(item.subtitle!);
  }

  if (remaining.isNotEmpty) {
    parts.add(remaining);
  }
  return parts.join(' • ');
}

String _heroRemaining(BrowseItem item) {
  final ud = item.userData;
  final total = item.runTime;
  if (ud == null || total == null || total == Duration.zero) {
    return item.subtitle ?? '';
  }
  final watched = ud.resumePosition;
  final left = total - watched;
  if (left <= Duration.zero) return 'Finished';
  return '${formatLongDuration(left)} left';
}
