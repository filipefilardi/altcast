import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/models/browse_item.dart';

void main() {
  group('BrowseItem.fromJson — type → MediaKind mapping', () {
    test('maps each known Jellyfin Type to its MediaKind', () {
      const cases = <String, MediaKind>{
        'Movie': MediaKind.movie,
        'Series': MediaKind.series,
        'Season': MediaKind.season,
        'Episode': MediaKind.episode,
        'Person': MediaKind.person,
        'BoxSet': MediaKind.collection,
      };
      cases.forEach((type, kind) {
        final item = BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': type,
        });
        expect(item.kind, kind, reason: 'Type=$type');
      });
    });

    test(
      'unknown Type defaults to movie (safe fallback for new server types)',
      () {
        final item = BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': 'SomethingNew',
        });
        expect(item.kind, MediaKind.movie);
      },
    );
  });

  group('BrowseItem.fromJson — subtitle composition', () {
    test('movie subtitle is the production year', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Movie',
        'ProductionYear': 2024,
      });
      expect(item.subtitle, '2024');
    });

    test('movie with no year has no subtitle', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Movie',
      });
      expect(item.subtitle, isNull);
    });

    test('series subtitle pluralises seasons correctly', () {
      final one = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Series',
        'ProductionYear': 1999,
        'ChildCount': 1,
      });
      expect(one.subtitle, '1999 • 1 season');

      final many = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Series',
        'ProductionYear': 1999,
        'ChildCount': 3,
      });
      expect(many.subtitle, '1999 • 3 seasons');
    });

    test('series with zero ChildCount drops the seasons fragment', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Series',
        'ProductionYear': 2020,
        'ChildCount': 0,
      });
      expect(item.subtitle, '2020');
    });

    test('season subtitle uses ParentIndexNumber', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Season',
        'ParentIndexNumber': 2,
      });
      expect(item.subtitle, 'Season 2');
    });

    test('episode subtitle is the zero-padded S/E label', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Episode',
        'ParentIndexNumber': 1,
        'IndexNumber': 7,
      });
      expect(item.subtitle, 'S1 · E07');
    });

    test('collection subtitle pluralises items', () {
      expect(
        BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': 'BoxSet',
          'ChildCount': 1,
        }).subtitle,
        '1 item',
      );
      expect(
        BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': 'BoxSet',
          'ChildCount': 5,
        }).subtitle,
        '5 items',
      );
      expect(
        BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': 'BoxSet',
        }).subtitle,
        isNull,
      );
    });

    test('person never has a subtitle', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Person',
        'ProductionYear': 1970,
      });
      expect(item.subtitle, isNull);
    });
  });

  group('BrowseItem.fromJson — defensive parsing', () {
    test('falls back to "Untitled" when Name is missing', () {
      final item = BrowseItem.fromJson({'Id': 'x', 'Type': 'Movie'});
      expect(item.name, 'Untitled');
    });

    test('extracts Primary image tag and first backdrop tag', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Movie',
        'ImageTags': {'Primary': 'p-tag', 'Logo': 'l-tag'},
        'BackdropImageTags': ['bd-1', 'bd-2'],
      });
      expect(item.imageTag, 'p-tag');
      expect(item.backdropTag, 'bd-1');
    });

    test('image tags are null when fields are missing or wrong shape', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Movie',
        'BackdropImageTags': [],
      });
      expect(item.imageTag, isNull);
      expect(item.backdropTag, isNull);
    });

    test(
      'accepts ChildCount as a non-int num (Jellyfin sometimes returns doubles)',
      () {
        final item = BrowseItem.fromJson({
          'Id': 'x',
          'Name': 'N',
          'Type': 'BoxSet',
          'ChildCount': 4.0,
        });
        expect(item.childCount, 4);
        expect(item.subtitle, '4 items');
      },
    );

    test('RunTimeTicks converts to a Duration', () {
      // 1 second = 10_000_000 ticks (100ns units).
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'Movie',
        'RunTimeTicks': 60 * 10000000,
      });
      expect(item.runTime, const Duration(seconds: 60));
    });
  });

  group('BrowseItem.copyWithChildCount', () {
    test('updates childCount and refreshes the derived subtitle', () {
      final item = BrowseItem.fromJson({
        'Id': 'x',
        'Name': 'N',
        'Type': 'BoxSet',
        'ChildCount': 1,
      });
      expect(item.subtitle, '1 item');

      final updated = item.copyWithChildCount(7);
      expect(updated.childCount, 7);
      expect(updated.subtitle, '7 items');
    });
  });

  group('UserData', () {
    test('defaults are watch-not-started, no progress, not favorite', () {
      const data = UserData();
      expect(data.played, isFalse);
      expect(data.isFavorite, isFalse);
      expect(data.playbackPositionTicks, 0);
      expect(data.resumePosition, Duration.zero);
      expect(data.progress, 0);
    });

    test('progress is null-safe and clamped to [0, 1]', () {
      expect(const UserData(playedPercentage: 50).progress, closeTo(0.5, 1e-9));
      expect(const UserData(playedPercentage: 0).progress, 0);
      expect(const UserData(playedPercentage: 100).progress, 1);
      // Server has been observed to return slightly >100 near the end.
      expect(const UserData(playedPercentage: 101).progress, 1);
    });

    test('resumePosition converts ticks (100ns) to a Duration', () {
      // 1 tick = 100ns, so 5 minutes = 5 * 60 * 10_000_000 ticks.
      const data = UserData(playbackPositionTicks: 3000000000);
      expect(data.resumePosition, const Duration(minutes: 5));
    });

    test('fromJson tolerates missing fields', () {
      final data = UserData.fromJson(const {});
      expect(data.played, isFalse);
      expect(data.playbackPositionTicks, 0);
      expect(data.playedPercentage, isNull);
    });
  });
}
