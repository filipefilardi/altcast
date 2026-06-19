import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/local/notification_preferences.dart';

void main() {
  group('NotificationPreferences', () {
    test('defaults to hourly mobile library checks', () {
      const prefs = NotificationPreferences();

      expect(prefs.libraryCheckInterval, LibraryCheckInterval.oneHour);
      expect(prefs.shouldCheckLibraryInBackground, isTrue);
      expect(prefs.isRestored, isFalse);
    });

    test('serializes the library check interval', () {
      const prefs = NotificationPreferences(
        libraryCheckInterval: LibraryCheckInterval.twelveHours,
      );

      final restored = NotificationPreferences.fromJson(prefs.toJson());

      expect(restored.libraryCheckInterval, LibraryCheckInterval.twelveHours);
      expect(restored.isRestored, isTrue);
    });

    test('removed interval values migrate to hourly', () {
      final off = NotificationPreferences.fromJson(const {
        'libraryCheckInterval': 'off',
      });
      final thirtyMinutes = NotificationPreferences.fromJson(const {
        'libraryCheckInterval': 'thirtyMinutes',
      });

      expect(off.libraryCheckInterval, LibraryCheckInterval.oneHour);
      expect(thirtyMinutes.libraryCheckInterval, LibraryCheckInterval.oneHour);
    });

    test('production intervals exclude the debug-only option', () {
      final intervals = LibraryCheckInterval.selectable(includeDebug: false);

      expect(intervals, isNot(contains(LibraryCheckInterval.fifteenMinutes)));
      expect(intervals, contains(LibraryCheckInterval.weekly));
    });

    test('master switch gates download and library notifications', () {
      const prefs = NotificationPreferences(notificationsEnabled: false);

      expect(prefs.downloadNotifications, isTrue);
      expect(prefs.anyLibraryNotifications, isTrue);
      expect(prefs.shouldNotifyDownloads, isFalse);
      expect(prefs.shouldCheckLibraryInBackground, isFalse);
    });

    test('migrates the watched-series preference to favorite series', () {
      final prefs = NotificationPreferences.fromJson(const {
        'newEpisodesForWatchedSeries': false,
      });

      expect(prefs.newEpisodesForFavoriteSeries, isFalse);
    });
  });
}
