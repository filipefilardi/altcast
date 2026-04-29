import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../home/widgets/poster_card.dart';

class LibraryBrowseScreen extends ConsumerStatefulWidget {
  const LibraryBrowseScreen({
    required this.title,
    required this.itemType,
    super.key,
  });

  final String title;
  final String itemType; // Movie or Series

  @override
  ConsumerState<LibraryBrowseScreen> createState() =>
      _LibraryBrowseScreenState();
}

class _LibraryBrowseScreenState extends ConsumerState<LibraryBrowseScreen> {
  static const _pageSize = 30;

  final List<BrowseItem> _items = [];
  int _nextIndex = 0;
  bool _hasMore = true;
  bool _loading = true;
  Object? _error;

  String? _genre;
  int? _year;
  bool _unwatchedOnly = false;
  LibrarySort _sort = LibrarySort.recentlyAdded;

  @override
  void initState() {
    super.initState();
    _reload();
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
    if (!_hasMore || _loading && _items.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final filter = LibraryFilter(
        genre: _genre,
        year: _year,
        unwatchedOnly: _unwatchedOnly,
        sort: _sort,
      );
      final page = widget.itemType == 'Movie'
          ? await repo.browseMovies(
              startIndex: _nextIndex,
              limit: _pageSize,
              filter: filter,
            )
          : await repo.browseShows(
              startIndex: _nextIndex,
              limit: _pageSize,
              filter: filter,
            );
      setState(() {
        _items.addAll(page.items);
        _nextIndex += page.items.length;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _showFilters,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _reload, child: _buildBody(context)),
    );
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
            title: "Couldn't load library",
            message: _error.toString(),
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
              icon: Icons.video_library_outlined,
              title: 'No items found',
              message: 'Try changing filters.',
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _FilterSummary(
          genre: _genre,
          year: _year,
          unwatchedOnly: _unwatchedOnly,
          sort: _sort,
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
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
              onTap: () => _openDetail(context, item),
            );
          },
        ),
        const SizedBox(height: 20),
        if (_hasMore)
          OutlinedButton(
            onPressed: _loading ? null : _loadMore,
            child: Text(_loading ? 'Loading...' : 'Load more'),
          ),
      ],
    );
  }

  Future<void> _showFilters() async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final genres = await repo.getGenres(itemType: widget.itemType);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        String? localGenre = _genre;
        int? localYear = _year;
        bool localUnwatched = _unwatchedOnly;
        LibrarySort localSort = _sort;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LibrarySort>(
                      value: localSort,
                      decoration: const InputDecoration(labelText: 'Sort'),
                      items: const [
                        DropdownMenuItem(
                          value: LibrarySort.recentlyAdded,
                          child: Text('Recently added'),
                        ),
                        DropdownMenuItem(
                          value: LibrarySort.nameAsc,
                          child: Text('Name A-Z'),
                        ),
                        DropdownMenuItem(
                          value: LibrarySort.nameDesc,
                          child: Text('Name Z-A'),
                        ),
                        DropdownMenuItem(
                          value: LibrarySort.yearDesc,
                          child: Text('Year (newest first)'),
                        ),
                      ],
                      onChanged: (v) =>
                          setModalState(() => localSort = v ?? localSort),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: localGenre,
                      decoration: const InputDecoration(labelText: 'Genre'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Any'),
                        ),
                        ...genres.map(
                          (g) => DropdownMenuItem<String?>(
                            value: g,
                            child: Text(g),
                          ),
                        ),
                      ],
                      onChanged: (v) => setModalState(() => localGenre = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: localYear?.toString() ?? '',
                      decoration: const InputDecoration(labelText: 'Year'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => localYear = int.tryParse(v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Unwatched only'),
                      value: localUnwatched,
                      onChanged: (v) => setModalState(() => localUnwatched = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _genre = null;
                              _year = null;
                              _unwatchedOnly = false;
                              _sort = LibrarySort.recentlyAdded;
                            });
                            Navigator.of(context).pop();
                            _reload();
                          },
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _genre = localGenre;
                              _year = localYear;
                              _unwatchedOnly = localUnwatched;
                              _sort = localSort;
                            });
                            Navigator.of(context).pop();
                            _reload();
                          },
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openDetail(BuildContext context, BrowseItem item) {
    switch (item.kind) {
      case MediaKind.movie:
        context.push('/movie/${item.id}');
      case MediaKind.series:
        context.push('/series/${item.id}');
      case MediaKind.season:
        context.push('/season/${item.id}');
      case MediaKind.episode:
        context.push('/episode/${item.id}');
    }
  }
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({
    required this.genre,
    required this.year,
    required this.unwatchedOnly,
    required this.sort,
  });

  final String? genre;
  final int? year;
  final bool unwatchedOnly;
  final LibrarySort sort;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      _sortLabel(sort),
      if (genre != null) genre!,
      if (year != null) '$year',
      if (unwatchedOnly) 'Unwatched',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map(
            (label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _sortLabel(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.recentlyAdded:
        return 'Recent';
      case LibrarySort.nameAsc:
        return 'A-Z';
      case LibrarySort.nameDesc:
        return 'Z-A';
      case LibrarySort.yearDesc:
        return 'Year';
    }
  }
}
