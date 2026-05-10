import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/expandable_text.dart';
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
            ref
                .read(personItemsProvider(personId).future)
                .catchError((_) => <BrowseItem>[]),
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
    final infoRows = _personalInfoRows(person);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final photoSize = isDesktop ? 156.0 : 96.0;
        final photoUrl = repo.personImageUrl(
          person.id,
          person.imageTag,
          width: isDesktop ? 460 : 300,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
                  child: SizedBox.square(
                    dimension: photoSize,
                    child: ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: LocalOrNetworkImage(
                        source: photoUrl,
                        errorBuilder: (_) => Icon(
                          Icons.person_outline,
                          color: AppColors.textSecondary,
                          size: isDesktop ? 48 : 34,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isDesktop ? 20 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: isDesktop
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.titleLarge,
                      ),
                      if (infoRows.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...infoRows,
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (person.overview != null && person.overview!.isNotEmpty) ...[
              SizedBox(height: isDesktop ? 20 : 14),
              ExpandableText(
                text: person.overview!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: isDesktop ? 14 : null,
                  height: 1.5,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _personalInfoRows(PersonDetails person) {
    final rows = <Widget>[];
    final birthDate = person.birthDate != null
        ? _formatDate(person.birthDate!)
        : null;
    final place = person.placeOfBirth?.trim();
    final deathDate = person.deathDate != null
        ? _formatDate(person.deathDate!)
        : null;
    if (birthDate != null) {
      rows.add(_InfoRow(value: birthDate));
    }
    if (place != null && place.isNotEmpty) {
      rows.add(_InfoRow(value: place));
    }
    if (deathDate != null) {
      rows.add(_InfoRow(value: 'Died $deathDate'));
    }
    return rows;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = constraints.maxWidth >= 900 ? 190.0 : 168.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
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
      },
    );
  }
}

class _PersonHeaderSkeleton extends StatelessWidget {
  const _PersonHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final photoSize = isDesktop ? 156.0 : 96.0;
        return Skeleton.group(
          child: Row(
            children: [
              Skeleton.box(
                width: photoSize,
                height: photoSize,
                radius: isDesktop ? 16 : 12,
              ),
              SizedBox(width: isDesktop ? 20 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180),
                    const SizedBox(height: 8),
                    Skeleton.line(width: 130),
                    const SizedBox(height: 8),
                    Skeleton.line(width: 120),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorksSkeleton extends StatelessWidget {
  const _WorksSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = constraints.maxWidth >= 900 ? 190.0 : 168.0;
        return Skeleton.group(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.55,
            ),
            itemCount: 9,
            itemBuilder: (_, _) =>
                Skeleton.box(width: double.infinity, height: double.infinity),
          ),
        );
      },
    );
  }
}
