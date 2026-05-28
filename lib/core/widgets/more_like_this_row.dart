import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/features/home/widgets/poster_card.dart';
import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/skeleton.dart';

/// Horizontal poster row for "More like this" recommendations. Filters out
/// the current item so it never recommends itself, and falls back to a
/// skeleton row while loading.
class MoreLikeThisRow extends StatelessWidget {
  const MoreLikeThisRow({
    super.key,
    required this.itemsAsync,
    required this.currentItemId,
  });

  final AsyncValue<List<BrowseItem>> itemsAsync;
  final String currentItemId;

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      data: (items) {
        final filtered = items
            .where((item) => item.id != currentItemId)
            .toList(growable: false);
        if (filtered.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => PosterCard(
              item: filtered[i],
              onTap: () => openMediaDetail(context, filtered[i]),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 248, child: _PosterRowSkeleton()),
      error: (_, _) => const Text(
        'Could not load recommendations.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

/// Pushes the right detail route for [item] based on its [MediaKind]. Lives
/// next to [MoreLikeThisRow] because every detail screen routes its
/// recommendation taps the same way.
void openMediaDetail(BuildContext context, BrowseItem item) {
  switch (item.kind) {
    case MediaKind.movie:
      context.push('/movie/${item.id}');
    case MediaKind.series:
      context.push('/series/${item.id}');
    case MediaKind.season:
      context.push('/season/${item.id}');
    case MediaKind.episode:
      final seriesId = item.seriesId;
      if (seriesId != null && seriesId.isNotEmpty) {
        context.push('/series/$seriesId');
      }
    case MediaKind.person:
      context.push('/person/${item.id}');
    case MediaKind.collection:
      context.push(
        Uri(
          path: '/collection/${item.id}',
          queryParameters: {'title': item.name},
        ).toString(),
      );
  }
}

class _PosterRowSkeleton extends StatelessWidget {
  const _PosterRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => Skeleton.box(width: 132, height: 240),
      ),
    );
  }
}
