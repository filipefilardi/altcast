import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/person_credit.dart';
import '../theme/app_colors.dart';
import 'local_or_network_image.dart';

/// Horizontal scroller of circular cast/crew avatars used on detail screens.
/// Caps at [maxShown] to keep first paint cheap; callers should provide a
/// "See all" affordance at the screen level if they want full coverage.
class CastCrewRow extends ConsumerWidget {
  const CastCrewRow({
    super.key,
    required this.people,
    this.maxShown = 14,
  });

  final List<PersonCredit> people;
  final int maxShown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final shown = people.take(maxShown).toList(growable: false);
    return SizedBox(
      height: 114,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final person = shown[i];
          final imageUrl = repo.personImageUrl(person.id, person.primaryImageTag);
          return InkWell(
            onTap: person.id == null || person.id!.isEmpty
                ? null
                : () => context.push('/person/${person.id}'),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 86,
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LocalOrNetworkImage(
                      source: imageUrl,
                      errorBuilder: (_) => const Icon(
                        Icons.person_outline,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    person.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
