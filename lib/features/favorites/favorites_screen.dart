import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/core/utils/navigation.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/features/favorites/favorites_providers.dart';
import 'package:altcast/features/home/widgets/poster_card.dart';

enum _FavoriteType {
  all('All', 'Movie,Series'),
  movies('Movies', 'Movie'),
  shows('TV Shows', 'Series');

  const _FavoriteType(this.label, this.itemTypes);

  final String label;
  final String itemTypes;
}

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  static const _pageSize = 30;

  final List<BrowseItem> _items = [];
  int _nextIndex = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _inflight = false;
  Object? _error;
  _FavoriteType _type = _FavoriteType.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(favoritesRevisionProvider, (_, _) => _reload());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          PopupMenuButton<_FavoriteType>(
            tooltip: 'Filter',
            initialValue: _type,
            icon: const Icon(PiconsRegular.funnel),
            onSelected: (type) {
              if (type == _type) return;
              setState(() => _type = type);
              _reload();
            },
            itemBuilder: (context) => [
              for (final type in _FavoriteType.values)
                PopupMenuItem(value: type, child: Text(type.label)),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _nextIndex = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_inflight || !_hasMore) return;
    _inflight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(jellyfinRepositoryProvider)
          .favoriteItems(
            startIndex: _nextIndex,
            limit: _pageSize,
            itemTypes: _type.itemTypes,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextIndex += page.fetchedItemCount ?? page.items.length;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } finally {
      _inflight = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_hasMore || _inflight) return false;
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 600) {
      _loadMore();
    }
    return false;
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          ErrorStateView(
            title: "Couldn't load favorites",
            message: userFacingNetworkMessage(_error!),
            onRetry: _reload,
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.heart,
              title: 'No favorites yet',
              message: 'Tap the heart on a movie or show to save it here.',
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
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 168,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.55,
          ),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final item = _items[i];
            return PosterCard(
              item: item,
              width: double.infinity,
              onTap: () => openItemDetail(context, item),
            );
          },
        ),
        if (_hasMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}
