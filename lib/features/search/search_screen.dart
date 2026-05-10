import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/filter_chips_row.dart';
import '../../core/widgets/local_or_network_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../home/widgets/poster_card.dart';
import 'search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Pre-populate the field with the last query so coming back to the tab
    // restores state. The provider is non-autoDispose so this round-trips.
    _controller.text = ref.read(searchQueryProvider);
    // Drive the suffix-clear icon visibility from the controller itself,
    // so it appears/disappears as the user types — without this listener
    // the icon's `_controller.text.isEmpty` check is read once during build
    // and only updates when something else triggers a rebuild.
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).setQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final filters = ref.watch(searchFiltersProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _showFilters,
            icon: const Icon(Icons.tune),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              autofocus: query.isEmpty,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Movies, shows & cast',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchQueryProvider.notifier).setQuery('');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: _Body(query: query, results: results, filters: filters),
    );
  }

  Future<void> _showFilters() async {
    if (!mounted) return;
    final current = ref.read(searchFiltersProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
                      DropdownButtonFormField<LibrarySort>(
                        initialValue: sort,
                        decoration: const InputDecoration(labelText: 'Sort'),
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
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: genre ?? '',
                        decoration: const InputDecoration(labelText: 'Genre'),
                        onChanged: (v) =>
                            genre = v.trim().isEmpty ? null : v.trim(),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: yearController,
                        decoration: const InputDecoration(labelText: 'Year'),
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
          icon: Icons.search,
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
              icon: Icons.search_off_rounded,
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
        child: ErrorStateView(title: 'Search failed', message: e.toString()),
      ),
    );
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
                        Icons.person_outline,
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
                Icons.chevron_right,
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
