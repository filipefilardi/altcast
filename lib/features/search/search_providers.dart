import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';

/// Holds the current search query. A small Notifier rather than the
/// (now-removed) StateProvider — same shape from the consumer side.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  // ignore: use_setters_to_change_properties
  void setQuery(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchFilterState {
  const SearchFilterState({
    this.genre,
    this.year,
    this.unwatchedOnly = false,
    this.includeMovies = true,
    this.includeShows = true,
    this.sort = LibrarySort.recentlyAdded,
  });

  final String? genre;
  final int? year;
  final bool unwatchedOnly;
  final bool includeMovies;
  final bool includeShows;
  final LibrarySort sort;

  SearchFilterState copyWith({
    String? genre,
    int? year,
    bool? unwatchedOnly,
    bool? includeMovies,
    bool? includeShows,
    LibrarySort? sort,
    bool clearGenre = false,
    bool clearYear = false,
  }) {
    return SearchFilterState(
      genre: clearGenre ? null : (genre ?? this.genre),
      year: clearYear ? null : (year ?? this.year),
      unwatchedOnly: unwatchedOnly ?? this.unwatchedOnly,
      includeMovies: includeMovies ?? this.includeMovies,
      includeShows: includeShows ?? this.includeShows,
      sort: sort ?? this.sort,
    );
  }
}

class SearchFiltersNotifier extends Notifier<SearchFilterState> {
  @override
  SearchFilterState build() => const SearchFilterState();

  void set(SearchFilterState next) => state = next;

  void clear() => state = const SearchFilterState();
}

final searchFiltersProvider =
    NotifierProvider<SearchFiltersNotifier, SearchFilterState>(
      SearchFiltersNotifier.new,
    );

/// Search results for [searchQueryProvider]. autoDispose so leaving the
/// search tab drops the request.
final searchResultsProvider = FutureProvider.autoDispose<List<BrowseItem>>((
  ref,
) {
  final query = ref.watch(searchQueryProvider);
  final filters = ref.watch(searchFiltersProvider);
  if (query.trim().isEmpty) return Future.value(const <BrowseItem>[]);
  final itemTypes = [
    if (filters.includeMovies) 'Movie',
    if (filters.includeShows) 'Series',
  ].join(',');
  if (itemTypes.isEmpty) return Future.value(const <BrowseItem>[]);
  return ref
      .watch(jellyfinRepositoryProvider)
      .searchAdvanced(
        query,
        genre: filters.genre,
        year: filters.year,
        unwatchedOnly: filters.unwatchedOnly,
        itemTypes: itemTypes,
      );
});
