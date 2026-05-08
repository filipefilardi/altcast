import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/person_credit.dart';
import '../theme/app_colors.dart';
import 'cast_crew_row.dart';
import 'expandable_text.dart';
import 'more_like_this_row.dart';

class DetailOverviewSection extends StatelessWidget {
  const DetailOverviewSection({
    super.key,
    required this.overview,
    this.tagline,
    this.title,
  });

  final String? overview;
  final String? tagline;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final text = overview?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final tag = tagline?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        if (title != null) ...[
          Text(title!, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
        ],
        if (tag != null && tag.isNotEmpty) ...[
          Text(
            tag,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
        ],
        ExpandableText(
          text: text,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class DetailCastCrewSection extends StatelessWidget {
  const DetailCastCrewSection({super.key, required this.people});

  final List<PersonCredit> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('CAST & CREW', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        CastCrewRow(people: people),
      ],
    );
  }
}

class DetailMoreLikeThisSection extends StatelessWidget {
  const DetailMoreLikeThisSection({
    super.key,
    required this.itemsAsync,
    required this.currentItemId,
  });

  final AsyncValue<List<BrowseItem>> itemsAsync;
  final String currentItemId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('MORE LIKE THIS', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        MoreLikeThisRow(itemsAsync: itemsAsync, currentItemId: currentItemId),
      ],
    );
  }
}
