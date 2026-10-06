import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/downloads/downloaded_item.dart';

void main() {
  group('DownloadedItem playback position', () {
    test('defaults to zero for existing manifests', () {
      final item = DownloadedItem.fromJson({
        'id': 'movie-1',
        'name': 'Movie',
        'filePath': '/tmp/movie.video',
      });

      expect(item.playbackPosition, Duration.zero);
      expect(item.playbackPositionTicks, isNull);
    });

    test('round-trips a saved offline resume position', () {
      const item = DownloadedItem(
        id: 'movie-1',
        name: 'Movie',
        filePath: '/tmp/movie.video',
      );
      final updated = item.copyWithPlaybackPosition(
        const Duration(minutes: 12, seconds: 34),
      );

      final restored = DownloadedItem.fromJson(updated.toJson());

      expect(
        restored.playbackPosition,
        const Duration(minutes: 12, seconds: 34),
      );
      expect(restored.id, item.id);
      expect(restored.filePath, item.filePath);
    });

    test('persists a cleared position separately from missing progress', () {
      const item = DownloadedItem(
        id: 'episode-1',
        name: 'Episode',
        filePath: '/tmp/episode.video',
        playbackPositionTicks: 123,
      );

      final cleared = item.copyWithPlaybackPosition(Duration.zero);

      expect(cleared.toJson()['playbackPositionTicks'], 0);
      expect(
        DownloadedItem.fromJson(cleared.toJson()).playbackPositionTicks,
        0,
      );
    });
  });
}
