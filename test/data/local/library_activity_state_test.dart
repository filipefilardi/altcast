import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/local/library_activity_state.dart';

void main() {
  group('LibraryActivityProfile', () {
    test(
      'mergeSeen marks the profile initialized and keeps newest ids first',
      () {
        const profile = LibraryActivityProfile(
          seenMovieIds: {'old-movie'},
          seenEpisodeIds: {'old-episode'},
        );

        final merged = profile.mergeSeen(
          movieIds: ['new-movie'],
          episodeIds: ['new-episode'],
        );

        expect(merged.initialized, isTrue);
        expect(merged.seenMovieIds, containsAll(['new-movie', 'old-movie']));
        expect(
          merged.seenEpisodeIds,
          containsAll(['new-episode', 'old-episode']),
        );
      },
    );

    test('trimmed removes empty ids and caps all remembered id sets', () {
      final manyIds = List.generate(250, (index) => 'id-$index');
      final profile = LibraryActivityProfile(
        seenMovieIds: {...manyIds, ''},
        seenEpisodeIds: {...manyIds, '   '},
      );

      final trimmed = profile.trimmed();

      expect(trimmed.seenMovieIds, hasLength(200));
      expect(trimmed.seenEpisodeIds, hasLength(200));
      expect(trimmed.seenMovieIds, isNot(contains('')));
      expect(trimmed.seenEpisodeIds, isNot(contains('   ')));
    });

    test('fromJson tolerates missing or malformed id lists', () {
      final profile = LibraryActivityProfile.fromJson(const {
        'initialized': true,
        'seenMovieIds': ['movie-1', 7],
        'seenEpisodeIds': 'not-a-list',
      });

      expect(profile.initialized, isTrue);
      expect(profile.seenMovieIds, {'movie-1'});
      expect(profile.seenEpisodeIds, isEmpty);
      expect(profile.snapshotVersion, 1);
    });

    test('new profiles use the individual-episode snapshot version', () {
      const profile = LibraryActivityProfile();

      expect(profile.snapshotVersion, currentLibrarySnapshotVersion);
      expect(
        LibraryActivityProfile.fromJson(profile.toJson()).snapshotVersion,
        currentLibrarySnapshotVersion,
      );
    });
  });
}
