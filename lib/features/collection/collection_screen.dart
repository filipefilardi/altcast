import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/utils/navigation.dart';
import 'package:altcast/core/widgets/edge_light_background.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/features/home/widgets/poster_card.dart';

final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getCollectionItems(id);
    });

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({required this.collectionId, this.title, super.key});

  final String collectionId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(collectionItemsProvider(collectionId));

    Future<void> refresh() async {
      ref.invalidate(collectionItemsProvider(collectionId));
      await ref.read(collectionItemsProvider(collectionId).future);
    }

    return EdgeLightBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title == null || title!.isEmpty ? 'Collection' : title!),
          leading: BackButton(onPressed: () => context.pop()),
        ),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: itemsAsync.when(
            data: (items) => _CollectionBody(items: items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              children: [
                const SizedBox(height: 120),
                ErrorStateView(
                  title: "Couldn't load collection",
                  message: e.toString(),
                  onRetry: () =>
                      ref.invalidate(collectionItemsProvider(collectionId)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionBody extends StatelessWidget {
  const _CollectionBody({required this.items});

  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.folder,
              title: 'No items found',
              message: 'This collection is empty.',
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.55,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return PosterCard(
              item: item,
              width: double.infinity,
              onTap: () => openItemDetail(context, item),
            );
          },
        ),
      ],
    );
  }
}
