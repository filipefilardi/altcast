import 'dart:async';

import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/core/utils/navigation.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/core/widgets/empty_state.dart';
import 'package:altcast/core/widgets/error_state.dart';
import 'package:altcast/core/widgets/filter_chips_row.dart';
import 'package:altcast/core/widgets/glass_bottom_sheet.dart';
import 'package:altcast/core/widgets/glass_sheet_controls.dart';
import 'package:altcast/core/widgets/horizontal_shelf_with_arrows.dart';
import 'package:altcast/core/widgets/local_or_network_image.dart';
import 'package:altcast/core/widgets/skeleton.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/seerr/models.dart';
import 'package:altcast/data/seerr/seerr_repository.dart';
import 'package:altcast/features/home/widgets/poster_card.dart';
import 'package:altcast/features/search/search_providers.dart';
import 'package:altcast/features/search/seerr_discover_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class DiscoverShelfScreen extends ConsumerStatefulWidget {
  const DiscoverShelfScreen({super.key, required this.shelf});

  final SeerrDiscoverShelf shelf;

  @override
  ConsumerState<DiscoverShelfScreen> createState() =>
      _DiscoverShelfScreenState();
}

class _DiscoverShelfScreenState extends ConsumerState<DiscoverShelfScreen> {
  final _controller = ScrollController();
  final _items = <SeerrMediaItem>[];
  var _page = 0;
  var _totalPages = 1;
  var _loading = true;
  var _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || _loadingMore || _page >= _totalPages) {
      return;
    }
    final remaining =
        _controller.position.maxScrollExtent - _controller.position.pixels;
    if (remaining < 640) {
      _loadPage(_page + 1);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _page = 0;
      _totalPages = 1;
    });
    await _loadPage(1);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPage(int page) async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = page > 1;
      _error = null;
    });
    try {
      final connection = await ref.read(seerrConnectionProvider.future);
      if (connection == null) {
        throw const SeerrException('Connect Seerr in Settings first.');
      }
      final result = await ref
          .read(seerrRepositoryProvider)
          .discoverShelf(widget.shelf, page: page);
      if (!mounted) return;
      final seen = _items
          .map((item) => '${item.mediaType.apiValue}:${item.id}')
          .toSet();
      final fresh = result.results
          .where((item) => seen.add('${item.mediaType.apiValue}:${item.id}'))
          .toList(growable: false);
      setState(() {
        _items.addAll(fresh);
        _page = result.page;
        _totalPages = result.totalPages;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.shelf.title)),
      body: RefreshIndicator(onRefresh: _refresh, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.52,
        ),
        itemCount: 12,
        itemBuilder: (_, _) => Skeleton.group(
          child: Skeleton.box(width: double.infinity, height: double.infinity),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
          ErrorStateView(
            title: 'Discover failed',
            message: userFacingSeerrMessage(_error!),
            onRetry: _refresh,
          ),
        ],
      );
    }
    return GridView.builder(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 168,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, index) {
        if (index >= _items.length) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return _SeerrCard(item: _items[index]);
      },
    );
  }
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _libraryController = TextEditingController();
  final _discoverController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _libraryController.text = ref.read(searchQueryProvider);
    _discoverController.text = ref.read(seerrDiscoverQueryProvider);
    _libraryController.addListener(_onControllerChanged);
    _discoverController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _libraryController.removeListener(_onControllerChanged);
    _discoverController.removeListener(_onControllerChanged);
    _libraryController.dispose();
    _discoverController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_tabController.index == 0) {
        ref.read(searchQueryProvider.notifier).setQuery(value);
      } else {
        ref.read(seerrDiscoverQueryProvider.notifier).setQuery(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final discoverQuery = ref.watch(seerrDiscoverQueryProvider);
    final filters = ref.watch(searchFiltersProvider);
    final results = ref.watch(searchResultsProvider);
    final activeController = _tabController.index == 0
        ? _libraryController
        : _discoverController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              tooltip: 'Filters',
              onPressed: _showFilters,
              icon: const Icon(PiconsRegular.funnelSimple),
            )
          else
            IconButton(
              tooltip: 'Requests',
              onPressed: () => context.push('/requests'),
              icon: const Icon(PiconsRegular.queue),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(122),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                TextField(
                  controller: activeController,
                  onChanged: _onChanged,
                  autofocus: query.isEmpty && discoverQuery.isEmpty,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _tabController.index == 0
                        ? 'Search your library'
                        : 'Search Seerr requests',
                    prefixIcon: const Icon(PiconsRegular.magnifyingGlass),
                    suffixIcon: activeController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(PiconsRegular.x, size: 18),
                            onPressed: () {
                              activeController.clear();
                              if (_tabController.index == 0) {
                                ref
                                    .read(searchQueryProvider.notifier)
                                    .setQuery('');
                              } else {
                                ref
                                    .read(seerrDiscoverQueryProvider.notifier)
                                    .setQuery('');
                              }
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                _SearchModeSelector(
                  controller: _tabController,
                  onChanged: (index) {
                    _tabController.animateTo(index);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _Body(query: query, results: results, filters: filters),
          _DiscoverBody(query: discoverQuery),
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    if (!mounted) return;
    final current = ref.read(searchFiltersProvider);
    await showGlassBottomSheet<void>(
      context: context,
      // Required so the sheet can grow tall enough to host the keyboard
      // when a filter text field gains focus.
      isScrollControlled: true,
      builder: (context) {
        String? genre = current.genre;
        int? year = current.year;
        bool unwatched = current.unwatchedOnly;
        bool movies = current.includeMovies;
        bool shows = current.includeShows;
        bool people = current.includePeople;
        LibrarySort sort = current.sort;
        final yearController = TextEditingController(
          text: year?.toString() ?? '',
        );
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search filters',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      GlassSheetDropdown<LibrarySort>(
                        label: 'Sort',
                        value: sort,
                        items: const [
                          DropdownMenuItem(
                            value: LibrarySort.recentlyAdded,
                            child: Text('Most relevant/recent'),
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
                        onChanged: (v) => setModalState(() => sort = v ?? sort),
                      ),
                      const SizedBox(height: 14),
                      GlassSheetTextField(
                        label: 'Genre',
                        initialValue: genre ?? '',
                        onChanged: (v) =>
                            genre = v.trim().isEmpty ? null : v.trim(),
                      ),
                      const SizedBox(height: 14),
                      GlassSheetTextField(
                        label: 'Year',
                        controller: yearController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (v) => year = int.tryParse(v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Unwatched only'),
                        value: unwatched,
                        onChanged: (v) => setModalState(() => unwatched = v),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Movies'),
                        value: movies,
                        onChanged: (v) =>
                            setModalState(() => movies = v ?? true),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('TV Shows'),
                        value: shows,
                        onChanged: (v) =>
                            setModalState(() => shows = v ?? true),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('People'),
                        value: people,
                        onChanged: (v) =>
                            setModalState(() => people = v ?? true),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              ref.read(searchFiltersProvider.notifier).clear();
                              Navigator.of(context).pop();
                            },
                            child: const Text('Clear'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              ref
                                  .read(searchFiltersProvider.notifier)
                                  .set(
                                    SearchFilterState(
                                      genre: genre,
                                      year: year,
                                      unwatchedOnly: unwatched,
                                      includeMovies: movies,
                                      includeShows: shows,
                                      includePeople: people,
                                      sort: sort,
                                    ),
                                  );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.query,
    required this.results,
    required this.filters,
  });
  final String query;
  final AsyncValue<List<BrowseItem>> results;
  final SearchFilterState filters;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: EmptyState(
          icon: PiconsRegular.magnifyingGlass,
          title: 'Find something to watch',
          message: 'Type a movie, show, or cast member above.',
        ),
      );
    }
    return results.when(
      data: (items) {
        final sorted = [...items]
          ..sort((a, b) {
            switch (filters.sort) {
              case LibrarySort.nameAsc:
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              case LibrarySort.nameDesc:
                return b.name.toLowerCase().compareTo(a.name.toLowerCase());
              case LibrarySort.yearDesc:
                return (b.year ?? 0).compareTo(a.year ?? 0);
              case LibrarySort.recentlyAdded:
                return 0;
            }
          });
        if (sorted.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.magnifyingGlassMinus,
              title: 'No results',
              message: 'Nothing matched "$query".',
            ),
          );
        }
        final movies = sorted
            .where((i) => i.kind == MediaKind.movie)
            .toList(growable: false);
        final shows = sorted
            .where((i) => i.kind == MediaKind.series)
            .toList(growable: false);
        final people = sorted
            .where((i) => i.kind == MediaKind.person)
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            FilterChipsRow(labels: _searchFilterLabels(filters)),
            const SizedBox(height: 12),
            if (movies.isNotEmpty) ...[
              _SectionHeader(label: 'Movies', count: movies.length),
              const SizedBox(height: 12),
              _PosterGrid(items: movies),
              const SizedBox(height: 24),
            ],
            if (shows.isNotEmpty) ...[
              _SectionHeader(label: 'TV Shows', count: shows.length),
              const SizedBox(height: 12),
              _PosterGrid(items: shows),
              const SizedBox(height: 24),
            ],
            if (people.isNotEmpty) ...[
              _SectionHeader(label: 'People', count: people.length),
              const SizedBox(height: 12),
              _PeopleList(items: people),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: const [_SearchSkeleton()],
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ErrorStateView(
          title: 'Search failed',
          message: userFacingNetworkMessage(e),
        ),
      ),
    );
  }
}

class _SearchModeSelector extends StatelessWidget {
  const _SearchModeSelector({
    required this.controller,
    required this.onChanged,
  });

  final TabController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _SearchModeButton(
            label: 'Library',
            selected: controller.index == 0,
            onTap: () => onChanged(0),
          ),
          _SearchModeButton(
            label: 'Discover',
            selected: controller.index == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SearchModeButton extends StatelessWidget {
  const _SearchModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: selected ? null : onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverBody extends ConsumerWidget {
  const _DiscoverBody({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(seerrConnectionProvider);
    return connection.when(
      data: (session) {
        if (session == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyState(
              icon: PiconsRegular.sparkle,
              title: 'Connect Seerr',
              message: 'Add your Seerr server in Settings to request media.',
              action: TextButton.icon(
                onPressed: () => context.push('/settings'),
                icon: const Icon(PiconsRegular.gear),
                label: const Text('Open Settings'),
              ),
            ),
          );
        }
        final trimmed = query.trim();
        if (trimmed.isEmpty) return const _DiscoverHome();
        final results = ref.watch(seerrDiscoverResultsProvider);
        return results.when(
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: EmptyState(
                  icon: PiconsRegular.magnifyingGlassMinus,
                  title: trimmed.isEmpty ? 'Nothing trending' : 'No results',
                  message: trimmed.isEmpty
                      ? 'Seerr did not return any discovery items.'
                      : 'Nothing matched "$query".',
                ),
              );
            }
            final movies = items
                .where((item) => item.mediaType == SeerrMediaType.movie)
                .toList(growable: false);
            final shows = items
                .where((item) => item.mediaType == SeerrMediaType.tv)
                .toList(growable: false);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(seerrDiscoverResultsProvider);
                await Future<void>.delayed(const Duration(milliseconds: 250));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                children: [
                  if (movies.isNotEmpty) ...[
                    _SectionHeader(label: 'Movies', count: movies.length),
                    const SizedBox(height: 12),
                    _SeerrGrid(items: movies),
                    const SizedBox(height: 24),
                  ],
                  if (shows.isNotEmpty) ...[
                    _SectionHeader(label: 'TV Shows', count: shows.length),
                    const SizedBox(height: 12),
                    _SeerrGrid(items: shows),
                  ],
                ],
              ),
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: const [_SearchSkeleton()],
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ErrorStateView(
              title: 'Discover failed',
              message: userFacingSeerrMessage(e),
              onRetry: () {
                ref.invalidate(seerrDiscoverResultsProvider);
              },
            ),
          ),
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: const [_SearchSkeleton()],
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ErrorStateView(
          title: 'Seerr failed',
          message: userFacingSeerrMessage(e),
        ),
      ),
    );
  }
}

class _DiscoverHome extends ConsumerWidget {
  const _DiscoverHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        for (final shelf in SeerrDiscoverShelf.values) {
          ref.invalidate(seerrShelfProvider(shelf));
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: const [
          _DiscoverShelf(shelf: SeerrDiscoverShelf.trending),
          SizedBox(height: 28),
          _DiscoverShelf(shelf: SeerrDiscoverShelf.popularMovies),
          SizedBox(height: 28),
          _DiscoverShelf(shelf: SeerrDiscoverShelf.popularSeries),
        ],
      ),
    );
  }
}

class _DiscoverShelf extends ConsumerStatefulWidget {
  const _DiscoverShelf({required this.shelf});

  final SeerrDiscoverShelf shelf;

  @override
  ConsumerState<_DiscoverShelf> createState() => _DiscoverShelfState();
}

class _DiscoverShelfState extends ConsumerState<_DiscoverShelf> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shelf = widget.shelf;
    final state = ref.watch(seerrShelfProvider(shelf));
    return state.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final desktopMode = MediaQuery.sizeOf(context).width >= 700;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShelfHeader(
              title: shelf.title,
              onSeeAll: () => context.push('/discover/${shelf.routeValue}'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 276,
              child: HorizontalShelfWithArrows(
                controller: _controller,
                enabled: desktopMode,
                child: ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => SizedBox(
                    width: 136,
                    child: _SeerrCard(item: items[index]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShelfHeader(title: shelf.title),
          const SizedBox(height: 12),
          SizedBox(
            height: 276,
            child: Skeleton.group(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 6,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, _) => SizedBox(
                  width: 136,
                  child: Skeleton.box(width: 136, height: 268),
                ),
              ),
            ),
          ),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShelfHeader(title: shelf.title),
          const SizedBox(height: 8),
          ErrorStateView(
            title: 'Shelf failed',
            message: userFacingSeerrMessage(e),
            onRetry: () => ref.invalidate(seerrShelfProvider(shelf)),
          ),
        ],
      ),
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    );
  }
}

class _SeerrGrid extends StatelessWidget {
  const _SeerrGrid({required this.items});

  final List<SeerrMediaItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 168,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _SeerrCard(item: items[i]),
    );
  }
}

class _SeerrCard extends StatelessWidget {
  const _SeerrCard({required this.item});

  final SeerrMediaItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 136.0;
        final maxPosterHeight = (constraints.maxHeight - 62)
            .clamp(0.0, double.infinity)
            .toDouble();
        final posterHeight = (width * 1.5)
            .clamp(0.0, maxPosterHeight)
            .toDouble();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => item.canOpenInLibrary
                ? _openSeerrItemInLibrary(context, item)
                : showSeerrDetailsSheet(context, item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: posterHeight,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: AppColors.surfaceElevated,
                          child: LocalOrNetworkImage(
                            source: item.posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_) => const Center(
                              child: Icon(
                                PiconsRegular.televisionSimple,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusPill(label: item.statusLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 16,
                  child: Text(
                    [
                      item.mediaType.label,
                      if (item.year != null) '${item.year}',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Future<void> showSeerrDetailsSheet(BuildContext context, SeerrMediaItem item) {
  return showGlassBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final key = SeerrDetailsKey(id: item.id, mediaType: item.mediaType);
        final details = ref.watch(seerrDetailsProvider(key));
        return details.when(
          data: (detail) => _SeerrDetailsSheet(detail: detail),
          loading: () => const SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _SeerrDetailsSkeleton(),
            ),
          ),
          error: (e, _) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: ErrorStateView(
                title: 'Details failed',
                message: userFacingSeerrMessage(e),
                onRetry: () => ref.invalidate(seerrDetailsProvider(key)),
              ),
            ),
          ),
        );
      },
    ),
  );
}

void _openSeerrItemInLibrary(
  BuildContext context,
  SeerrMediaItem item, {
  bool closeCurrent = false,
}) {
  final itemId = item.jellyfinItemId;
  if (itemId == null || itemId.isEmpty) return;
  final path = item.mediaType == SeerrMediaType.tv
      ? '/series/$itemId'
      : '/movie/$itemId';
  final router = GoRouter.of(context);
  if (closeCurrent) Navigator.of(context).pop();
  unawaited(router.push(path));
}

class _SeerrDetailsSkeleton extends StatelessWidget {
  const _SeerrDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton.box(width: 96, height: 144),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: double.infinity, height: 18),
                    const SizedBox(height: 10),
                    Skeleton.line(width: 148, height: 12),
                    const SizedBox(height: 18),
                    Skeleton.line(width: double.infinity, height: 12),
                    const SizedBox(height: 8),
                    Skeleton.line(width: double.infinity, height: 12),
                    const SizedBox(height: 8),
                    Skeleton.line(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Skeleton.box(width: double.infinity, height: 52),
        ],
      ),
    );
  }
}

class _SeerrDetailsSheet extends ConsumerStatefulWidget {
  const _SeerrDetailsSheet({required this.detail});

  final SeerrMediaDetails detail;

  @override
  ConsumerState<_SeerrDetailsSheet> createState() => _SeerrDetailsSheetState();
}

class _SeerrDetailsSheetState extends ConsumerState<_SeerrDetailsSheet> {
  late final Set<int> _selectedSeasons = widget.detail.seasons
      .map((season) => season.seasonNumber)
      .toSet();
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 144,
                      child: ColoredBox(
                        color: AppColors.surfaceElevated,
                        child: LocalOrNetworkImage(
                          source: detail.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_) => const Icon(
                            PiconsRegular.televisionSimple,
                            color: AppColors.textSecondary,
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
                        Text(
                          detail.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            detail.mediaType.label,
                            if (detail.year != null) '${detail.year}',
                            detail.statusLabel,
                          ].join(' • '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (detail.overview?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text(
                            detail.overview!,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (detail.mediaType == SeerrMediaType.tv &&
                  detail.seasons.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Seasons',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedSeasons.length ==
                              detail.seasons.length) {
                            _selectedSeasons.clear();
                          } else {
                            _selectedSeasons
                              ..clear()
                              ..addAll(
                                detail.seasons.map(
                                  (season) => season.seasonNumber,
                                ),
                              );
                          }
                        });
                      },
                      child: Text(
                        _selectedSeasons.length == detail.seasons.length
                            ? 'Clear'
                            : 'All',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final season in detail.seasons)
                      FilterChip(
                        label: Text(
                          season.episodeCount == null
                              ? season.name
                              : '${season.name} (${season.episodeCount})',
                        ),
                        selected: _selectedSeasons.contains(
                          season.seasonNumber,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedSeasons.add(season.seasonNumber);
                            } else {
                              _selectedSeasons.remove(season.seasonNumber);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: detail.canOpenInLibrary
                      ? () => _openSeerrItemInLibrary(
                          context,
                          detail,
                          closeCurrent: true,
                        )
                      : detail.canRequest && !_requesting
                      ? () => _request(detail)
                      : null,
                  icon: _requesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          detail.canOpenInLibrary
                              ? PiconsRegular.caretRight
                              : PiconsRegular.plus,
                        ),
                  label: Text(
                    detail.canOpenInLibrary
                        ? 'Open in library'
                        : detail.canRequest
                        ? 'Request'
                        : detail.statusLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _request(SeerrMediaDetails detail) async {
    if (detail.mediaType == SeerrMediaType.tv && _selectedSeasons.isEmpty) {
      showAppSnackBar(context, 'Select at least one season.');
      return;
    }
    setState(() => _requesting = true);
    try {
      await ref
          .read(seerrRepositoryProvider)
          .requestMedia(
            item: detail,
            seasons: detail.mediaType == SeerrMediaType.tv
                ? (_selectedSeasons.toList()..sort())
                : null,
          );
      ref.invalidate(
        seerrDetailsProvider(
          SeerrDetailsKey(id: detail.id, mediaType: detail.mediaType),
        ),
      );
      ref.invalidate(seerrDiscoverResultsProvider);
      for (final shelf in SeerrDiscoverShelf.values) {
        ref.invalidate(seerrShelfProvider(shelf));
      }
      ref.invalidate(seerrRequestsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(context, 'Request sent to Seerr.');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Request failed: ${userFacingSeerrMessage(error)}',
      );
      setState(() => _requesting = false);
    }
  }
}

List<String> _searchFilterLabels(SearchFilterState filters) => [
  if (filters.genre != null) filters.genre!,
  if (filters.year != null) '${filters.year}',
  if (filters.unwatchedOnly) 'Unwatched',
  if (!filters.includeMovies) 'No Movies',
  if (!filters.includeShows) 'No Shows',
  if (!filters.includePeople) 'No People',
  switch (filters.sort) {
    LibrarySort.nameAsc => 'A-Z',
    LibrarySort.nameDesc => 'Z-A',
    LibrarySort.yearDesc => 'Year',
    LibrarySort.recentlyAdded => 'Recent',
  },
];

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(width: 10),
        Text(
          count.toString(),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});
  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 168,
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
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton.line(width: 120, height: 11),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 168,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.55,
            ),
            itemCount: 6,
            itemBuilder: (_, _) =>
                Skeleton.box(width: double.infinity, height: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.items});

  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PersonTile(item: item),
          ),
      ],
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.item});

  final BrowseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(jellyfinRepositoryProvider);
    final image = repo.personImageUrl(item.id, item.imageTag, width: 140);
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openItemDetail(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: ColoredBox(
                    color: AppColors.surfaceHighlight,
                    child: LocalOrNetworkImage(
                      source: image,
                      errorBuilder: (_) => const Icon(
                        PiconsRegular.user,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                PiconsRegular.caretRight,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
