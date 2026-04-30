import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/person_details.dart';
import '../home/widgets/poster_card.dart';
import 'person_providers.dart';

class PersonScreen extends ConsumerWidget {
  const PersonScreen({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personAsync = ref.watch(personProvider(personId));
    final itemsAsync = ref.watch(personItemsProvider(personId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: personAsync.maybeWhen(
          data: (p) => Text(p.name),
          orElse: () => const Text('Cast & Crew'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(personProvider(personId));
          ref.invalidate(personItemsProvider(personId));
          await Future.wait([
            ref.read(personProvider(personId).future),
            ref.read(personItemsProvider(personId).future).catchError((_) => <BrowseItem>[]),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            personAsync.when(
              data: (person) => _PersonHeader(person: person),
              loading: () => const _PersonHeaderSkeleton(),
              error: (e, _) => ErrorStateView(
                title: "Couldn't load person",
                message: e.toString(),
                onRetry: () => ref.invalidate(personProvider(personId)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'FILMS & SHOWS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            itemsAsync.when(
              data: (items) => _WorksGrid(items: items),
              loading: () => const _WorksSkeleton(),
              error: (_, _) => ErrorStateView(
                title: "Couldn't load works",
                onRetry: () => ref.invalidate(personItemsProvider(personId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonHeader extends ConsumerWidget {
  const _PersonHeader({required this.person});

  final PersonDetails person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final photoUrl = repo.personImageUrl(person.id, person.imageTag, width: 300);
    final life = _lifeLabel(person);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 96,
                height: 96,
                child: ColoredBox(
                  color: AppColors.surfaceElevated,
                  child: LocalOrNetworkImage(
                    source: photoUrl,
                    errorBuilder: (_) => const Icon(
                      Icons.person_outline,
                      color: AppColors.textSecondary,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: Theme.of(context).textTheme.titleLarge),
                  if (person.placeOfBirth != null &&
                      person.placeOfBirth!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      person.placeOfBirth!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (life != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      life,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (person.overview != null && person.overview!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            person.overview!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  String? _lifeLabel(PersonDetails p) {
    final born = p.birthDate;
    final died = p.deathDate;
    if (born == null && died == null) return null;
    final b = born != null ? '${born.year}' : '?';
    final d = died != null ? '${died.year}' : 'present';
    return '$b - $d';
  }
}

class _WorksGrid extends StatelessWidget {
  const _WorksGrid({required this.items});

  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No items found for this person.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.55,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => PosterCard(
        item: items[i],
        width: double.infinity,
        onTap: () => openItemDetail(context, items[i]),
      ),
    );
  }
}

class _PersonHeaderSkeleton extends StatelessWidget {
  const _PersonHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Row(
        children: [
          Skeleton.box(width: 96, height: 96, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.line(width: 180),
                SizedBox(height: 8),
                Skeleton.line(width: 130),
                SizedBox(height: 8),
                Skeleton.line(width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorksSkeleton extends StatelessWidget {
  const _WorksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        itemCount: 9,
        itemBuilder: (_, _) => Skeleton.box(width: double.infinity, height: 180),
      ),
    );
  }
}
