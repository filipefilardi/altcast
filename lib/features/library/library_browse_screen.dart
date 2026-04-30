import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/dio_error_message.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/filter_chips_row.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../home/widgets/poster_card.dart';

class LibraryBrowseScreen extends ConsumerStatefulWidget {
  const LibraryBrowseScreen({
    required this.title,
    required this.itemType,
    this.initialGenre,
    super.key,
  });

  final String title;
  final String itemType; // Movie, Series, or BoxSet
  final String? initialGenre;

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
  bool _inflight = false;
  Object? _error;

  String? _genre;
  int? _year;
  bool _unwatchedOnly = false;
  LibrarySort _sort = LibrarySort.recentlyAdded;

  @override
  void initState() {
    super.initState();
    _genre = widget.initialGenre?.trim().isEmpty ?? true
        ? null
        : widget.initialGenre!.trim();
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
    if (_inflight || !_hasMore) return;
    _inflight = true;
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
      final page = switch (widget.itemType) {
        'Movie' => await repo.browseMovies(
          startIndex: _nextIndex,
          limit: _pageSize,
          filter: filter,
        ),
        'Series' => await repo.browseShows(
          startIndex: _nextIndex,
          limit: _pageSize,
          filter: filter,
        ),
        'BoxSet' => await repo.browseCollections(
          startIndex: _nextIndex,
          limit: _pageSize,
          filter: filter,
        ),
        _ => throw ArgumentError('Unsupported library type ${widget.itemType}'),
      };
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextIndex += page.items.length;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: BackButton(onPressed: () => context.pop()),
        actions: _filtersEnabled
            ? [
                IconButton(
                  tooltip: 'Filters',
                  onPressed: _showFilters,
                  icon: const Icon(Icons.tune),
                ),
              ]
            : null,
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

  /// Trigger the next page when the user scrolls within ~600 px of the
  /// bottom — replaces the old "Load more" button with infinite scrolling.
  /// `_loadMore` itself guards against overlapping calls via `_inflight`.
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
            title: "Couldn't load library",
            message: userFacingNetworkMessage(_error!),
            onRetry: _reload,
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: 'No items found',
              message: _filtersEnabled
                  ? 'Try changing filters.'
                  : 'No collections found.',
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (_filtersEnabled) ...[
          FilterChipsRow(labels: _filterLabels()),
          const SizedBox(height: 12),
        ],
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

  Future<void> _showFilters() async {
    if (!_filtersEnabled) return;
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<LibrarySort>(
                      initialValue: localSort,
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
                      initialValue: localGenre,
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
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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

  List<String> _filterLabels() => [
    _sortLabel(_sort),
    ?_genre,
    if (_year != null) '$_year',
    if (_unwatchedOnly) 'Unwatched',
  ];

  bool get _filtersEnabled => widget.itemType != 'BoxSet';
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
