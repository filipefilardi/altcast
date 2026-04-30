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

/// Home “Continue watching” block: section label, loading / error / hero, and
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

/// Full-width 16:9 hero with scrim, progress, and resume affordance; swipe
/// when there is more than one in-progress title.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final h = (c.maxWidth * 1.08).clamp(340.0, 520.0);
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
    final metadata = _heroMetadata(item, progress);
    final remaining = _heroRemaining(item);

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
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const [0, 0.45, 1],
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
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if (remaining.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  remaining,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
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
        ],
      ),
    );
  }
}

class _ResumePill extends StatelessWidget {
  const _ResumePill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
    return Skeleton.group(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: LayoutBuilder(
              builder: (context, c) {
                final h = (c.maxWidth * 1.08).clamp(340.0, 520.0);
                return Skeleton.box(width: c.maxWidth, height: h, radius: 0);
              },
            ),
          ),
        ],
      ),
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

String _heroMetadata(BrowseItem item, double progress) {
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

  final percent = (progress * 100).round();
  if (percent > 0) {
    parts.add('$percent% watched');
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
