import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/seerr/models.dart';

void main() {
  group('SeerrMediaItem', () {
    test('available media with Jellyfin id can open in local library', () {
      final item = SeerrMediaItem.fromJson({
        'id': 123,
        'mediaType': 'movie',
        'title': 'Available Movie',
        'mediaInfo': {'status': 5, 'jellyfinMediaId': 'movie-1'},
      });

      expect(item.statusLabel, 'Available');
      expect(item.jellyfinItemId, 'movie-1');
      expect(item.canOpenInLibrary, isTrue);
    });
  });

  group('SeerrRequest', () {
    test('failed request status wins over processing media status', () {
      final request = SeerrRequest.fromJson({
        'id': 42,
        'type': 'movie',
        'status': 4,
        'media': {'status': 3, 'tmdbId': 100},
      });

      expect(request.status, SeerrRequestStatus.failed);
      expect(request.mediaStatus, SeerrMediaStatus.processing);
      expect(request.statusLabel, 'Failed');
      expect(request.canRetry, isTrue);
    });

    test('parses requester and poster fields from request payload', () {
      final request = SeerrRequest.fromJson({
        'id': 7,
        'type': 'tv',
        'status': 2,
        'media': {'status': 5, 'tmdbId': 200, 'posterPath': '/poster.jpg'},
        'requestedBy': {'displayName': 'Filipe'},
      });

      expect(request.requestedByName, 'Filipe');
      expect(request.posterUrl, 'https://image.tmdb.org/t/p/w185/poster.jpg');
    });

    test('pending requests expose empty progress', () {
      final request = SeerrRequest.fromJson({
        'id': 8,
        'type': 'movie',
        'status': 1,
        'media': {'status': 2, 'tmdbId': 300},
      });

      expect(request.statusLabel, 'Pending');
      expect(request.progress, 0);
    });

    test('processing progress comes from Seerr download status', () {
      final request = SeerrRequest.fromJson({
        'id': 9,
        'type': 'movie',
        'status': 2,
        'media': {
          'status': 3,
          'tmdbId': 400,
          'downloadStatus': [
            {
              'size': 1000,
              'sizeLeft': 250,
              'title': 'Movie download',
              'timeLeft': '10 minutes',
              'status': 'downloading',
            },
          ],
        },
      });

      expect(request.statusLabel, 'Processing');
      expect(request.progress, 0.75);
      expect(request.processingDetail, '75% downloaded • ETA 10 minutes');
    });

    test('available requests expose Jellyfin item navigation id', () {
      final request = SeerrRequest.fromJson({
        'id': 10,
        'type': 'tv',
        'status': 2,
        'media': {'status': 5, 'tmdbId': 500, 'jellyfinMediaId': 'series-1'},
      });

      expect(request.statusLabel, 'Available');
      expect(request.progress, 1);
      expect(request.canOpenInLibrary, isTrue);
      expect(request.jellyfinItemId, 'series-1');
    });
  });
}
