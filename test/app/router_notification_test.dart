import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/app/router.dart';

void main() {
  group('notificationLocationForPayload', () {
    test('routes download payloads to downloads with focus', () {
      expect(
        notificationLocationForPayload(
          jsonEncode({'type': 'download', 'itemId': 'item-1'}),
        ),
        '/downloads?focus=item-1',
      );
    });

    test('routes movie and series payloads to their detail pages', () {
      expect(
        notificationLocationForPayload(
          jsonEncode({'type': 'movie', 'itemId': 'movie-1'}),
        ),
        '/movie/movie-1',
      );
      expect(
        notificationLocationForPayload(
          jsonEncode({'type': 'series', 'itemId': 'series-1'}),
        ),
        '/series/series-1',
      );
    });

    test(
      'routes episode payloads to the series when seriesId is available',
      () {
        expect(
          notificationLocationForPayload(
            jsonEncode({
              'type': 'episode',
              'itemId': 'episode-1',
              'seriesId': 'series-1',
            }),
          ),
          '/series/series-1',
        );
      },
    );

    test('supports legacy string payloads', () {
      expect(
        notificationLocationForPayload('download:item-1'),
        '/downloads?focus=item-1',
      );
      expect(notificationLocationForPayload('movie:movie-1'), '/movie/movie-1');
      expect(
        notificationLocationForPayload('series:series-1'),
        '/series/series-1',
      );
      expect(
        notificationLocationForPayload('episode:episode-1'),
        '/play/episode-1',
      );
    });

    test('ignores malformed structured payloads', () {
      expect(notificationLocationForPayload('{not json'), isNull);
      expect(
        notificationLocationForPayload(jsonEncode({'type': 'movie'})),
        isNull,
      );
    });
  });
}
