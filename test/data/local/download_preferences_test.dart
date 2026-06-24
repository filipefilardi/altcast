import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/local/download_preferences.dart';

void main() {
  group('DownloadPreferences', () {
    test('defaults to conservative automatic download behavior', () {
      const prefs = DownloadPreferences();

      expect(prefs.autoDownloadNextEpisode, isFalse);
      expect(prefs.removeWatchedDownloads, isFalse);
      expect(prefs.wifiOnlyDownloads, isTrue);
    });

    test('serializes remove watched downloads', () {
      const prefs = DownloadPreferences(removeWatchedDownloads: true);

      final restored = DownloadPreferences.fromJson(prefs.toJson());

      expect(restored.removeWatchedDownloads, isTrue);
      expect(restored.autoDownloadNextEpisode, isFalse);
    });
  });
}
