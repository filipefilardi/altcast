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

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

/// Search results for [searchQueryProvider]. autoDispose so leaving the
/// search tab drops the request.
final searchResultsProvider =
    FutureProvider.autoDispose<List<BrowseItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return Future.value(const <BrowseItem>[]);
  return ref.watch(jellyfinRepositoryProvider).search(query);
});
