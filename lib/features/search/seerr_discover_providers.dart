import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/seerr/models.dart';
import 'package:altcast/data/seerr/seerr_repository.dart';

class SeerrDiscoverQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  // ignore: use_setters_to_change_properties
  void setQuery(String value) => state = value;
}

final seerrDiscoverQueryProvider =
    NotifierProvider<SeerrDiscoverQueryNotifier, String>(
      SeerrDiscoverQueryNotifier.new,
    );

final seerrDiscoverResultsProvider =
    FutureProvider.autoDispose<List<SeerrMediaItem>>((ref) async {
      final query = ref.watch(seerrDiscoverQueryProvider).trim();
      if (query.isEmpty) return const [];
      final connection = await ref.watch(seerrConnectionProvider.future);
      if (connection == null) return const [];
      final result = await ref.watch(seerrRepositoryProvider).search(query);
      return result.results;
    });

final seerrShelfProvider = FutureProvider.autoDispose
    .family<List<SeerrMediaItem>, SeerrDiscoverShelf>((ref, shelf) async {
      final connection = await ref.watch(seerrConnectionProvider.future);
      if (connection == null) return const [];
      final result = await ref
          .watch(seerrRepositoryProvider)
          .discoverShelf(shelf);
      return result.results.take(20).toList(growable: false);
    });

final seerrDetailsProvider = FutureProvider.autoDispose
    .family<SeerrMediaDetails, SeerrDetailsKey>((ref, key) {
      return ref
          .watch(seerrRepositoryProvider)
          .details(id: key.id, mediaType: key.mediaType);
    });

class SeerrDetailsKey {
  const SeerrDetailsKey({required this.id, required this.mediaType});

  final int id;
  final SeerrMediaType mediaType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeerrDetailsKey &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mediaType == other.mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}

final seerrRequestsProvider = FutureProvider.autoDispose<List<SeerrRequest>>((
  ref,
) async {
  final connection = await ref.watch(seerrConnectionProvider.future);
  if (connection == null || !ref.mounted) return const [];
  final repo = ref.watch(seerrRepositoryProvider);
  const pageSize = 100;
  final requests = <int, SeerrRequest>{};
  var skip = 0;
  while (ref.mounted) {
    final page = await repo.requests(skip: skip, take: pageSize);
    for (final request in page.results) {
      requests[request.id] = request;
    }
    skip += page.results.length;
    if (page.results.isEmpty || page.page >= page.totalPages) break;
  }
  return requests.values.toList(growable: false);
});
