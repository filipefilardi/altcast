import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';

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
    this.includePeople = true,
    this.sort = LibrarySort.recentlyAdded,
  });

  final String? genre;
  final int? year;
  final bool unwatchedOnly;
  final bool includeMovies;
  final bool includeShows;
  final bool includePeople;
  final LibrarySort sort;

  SearchFilterState copyWith({
    String? genre,
    int? year,
    bool? unwatchedOnly,
    bool? includeMovies,
    bool? includeShows,
    bool? includePeople,
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
      includePeople: includePeople ?? this.includePeople,
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
) async {
  final query = ref.watch(searchQueryProvider);
  final filters = ref.watch(searchFiltersProvider);
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const <BrowseItem>[];
  final mediaTypes = [
    if (filters.includeMovies) 'Movie',
    if (filters.includeShows) 'Series',
  ].join(',');
  if (mediaTypes.isEmpty && !filters.includePeople) {
    return const <BrowseItem>[];
  }

  final repo = ref.watch(jellyfinRepositoryProvider);
  final results = await Future.wait([
    if (mediaTypes.isNotEmpty)
      repo.searchAdvanced(
        trimmed,
        genre: filters.genre,
        year: filters.year,
        unwatchedOnly: filters.unwatchedOnly,
        itemTypes: mediaTypes,
      )
    else
      Future.value(const <BrowseItem>[]),
    if (filters.includePeople)
      repo.searchPeople(trimmed)
    else
      Future.value(const <BrowseItem>[]),
  ]);
  final direct = [...results[0], ...results[1]];

  if (trimmed.length < 3) {
    return _dedupeResults(direct);
  }

  final fuzzyResults = await Future.wait([
    if (mediaTypes.isNotEmpty)
      repo
          .searchCandidates(
            itemTypes: mediaTypes,
            genre: filters.genre,
            year: filters.year,
            unwatchedOnly: filters.unwatchedOnly,
          )
          .then((items) => _fuzzyMatches(trimmed, items))
    else
      Future.value(const <BrowseItem>[]),
    if (filters.includePeople)
      repo.peopleCandidates().then((items) => _fuzzyMatches(trimmed, items))
    else
      Future.value(const <BrowseItem>[]),
  ]);

  return _dedupeResults([...direct, ...fuzzyResults[0], ...fuzzyResults[1]]);
});

List<BrowseItem> _dedupeResults(List<BrowseItem> items) {
  final seen = <String>{};
  final deduped = <BrowseItem>[];
  for (final item in items) {
    if (seen.add(item.id)) deduped.add(item);
  }
  return deduped;
}

List<BrowseItem> _fuzzyMatches(String query, List<BrowseItem> candidates) {
  final scored = <({BrowseItem item, int score})>[];
  for (final item in candidates) {
    final score = _fuzzyScore(query, item.name);
    if (score >= 62) scored.add((item: item, score: score));
  }
  scored.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
  });
  return scored.take(24).map((match) => match.item).toList(growable: false);
}

int _fuzzyScore(String query, String candidate) {
  final q = _normalizeForSearch(query);
  final c = _normalizeForSearch(candidate);
  if (q.isEmpty || c.isEmpty) return 0;
  if (q == c) return 120;
  if (c.startsWith(q)) return 108;
  final containsIndex = c.indexOf(q);
  if (containsIndex >= 0) return 100 - containsIndex.clamp(0, 25);

  final queryTokens = q.split(' ').where((t) => t.isNotEmpty).toList();
  final candidateTokens = c.split(' ').where((t) => t.isNotEmpty).toList();
  if (queryTokens.isEmpty || candidateTokens.isEmpty) return 0;

  var tokenScore = 0;
  for (final queryToken in queryTokens) {
    var best = 0;
    for (final candidateToken in candidateTokens) {
      best = best > _tokenScore(queryToken, candidateToken)
          ? best
          : _tokenScore(queryToken, candidateToken);
    }
    tokenScore += best;
  }
  final averageTokenScore = tokenScore ~/ queryTokens.length;
  final wholeScore = _tokenScore(q.replaceAll(' ', ''), c.replaceAll(' ', ''));
  return averageTokenScore > wholeScore ? averageTokenScore : wholeScore;
}

int _tokenScore(String query, String candidate) {
  if (query == candidate) return 100;
  if (candidate.startsWith(query)) return 92;
  if (candidate.contains(query)) return 86;
  if (!_isSubsequence(query, candidate)) {
    final distance = _levenshteinDistance(query, candidate);
    final longest = query.length > candidate.length
        ? query.length
        : candidate.length;
    final ratio = 1 - (distance / longest);
    return (ratio * 100).round();
  }

  final distance = _levenshteinDistance(query, candidate);
  final lengthPenalty = (candidate.length - query.length).abs().clamp(0, 20);
  return (84 - distance * 5 - lengthPenalty).clamp(0, 100);
}

bool _isSubsequence(String query, String candidate) {
  var index = 0;
  for (final codeUnit in candidate.codeUnits) {
    if (index < query.length && codeUnit == query.codeUnitAt(index)) {
      index++;
    }
  }
  return index == query.length;
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final insert = current[j] + 1;
      final delete = previous[j + 1] + 1;
      final replace = previous[j] + cost;
      current[j + 1] = [
        insert,
        delete,
        replace,
      ].reduce((value, element) => value < element ? value : element);
    }
    previous = current;
  }
  return previous[b.length];
}

String _normalizeForSearch(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final normalized = _accentFold[char] ?? char;
    if (RegExp(r'[a-z0-9]').hasMatch(normalized)) {
      buffer.write(normalized);
    } else if (buffer.isNotEmpty && !buffer.toString().endsWith(' ')) {
      buffer.write(' ');
    }
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

const _accentFold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'œ': 'oe',
  'š': 's',
  'ž': 'z',
};
