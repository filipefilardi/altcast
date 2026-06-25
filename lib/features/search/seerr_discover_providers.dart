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

class SeerrRequestsFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  // ignore: use_setters_to_change_properties
  void setFilter(String value) => state = value;
}

final seerrRequestsFilterProvider =
    NotifierProvider<SeerrRequestsFilterNotifier, String>(
      SeerrRequestsFilterNotifier.new,
    );

final seerrRequestsProvider = FutureProvider.autoDispose<List<SeerrRequest>>((
  ref,
) async {
  final connection = await ref.watch(seerrConnectionProvider.future);
  if (connection == null) return const [];
  final filter = ref.watch(seerrRequestsFilterProvider);
  final repo = ref.watch(seerrRepositoryProvider);
  final result = await repo.requests(filter: filter, take: 30);
  return Future.wait(
    result.results.map((request) => _withRequestTitle(repo, request)),
  );
});

Future<SeerrRequest> _withRequestTitle(
  SeerrRepository repo,
  SeerrRequest request,
) async {
  final tmdbId = request.tmdbId;
  if (tmdbId == null ||
      (request.mediaType != SeerrMediaType.movie &&
          request.mediaType != SeerrMediaType.tv)) {
    return request;
  }
  final title = request.title;
  if (request.posterPath != null &&
      title != null &&
      !title.startsWith('TMDb #')) {
    return request;
  }
  try {
    final detail = await repo.details(id: tmdbId, mediaType: request.mediaType);
    return request.copyWith(
      title: detail.title,
      posterPath: detail.posterPath,
      backdropPath: detail.backdropPath,
    );
  } catch (_) {
    return request;
  }
}
