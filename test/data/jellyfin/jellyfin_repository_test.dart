import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

void main() {
  test('recentlyAddedEpisodes requests individual episode items', () async {
    final adapter = _RecordingAdapter((options) async {
      expect(options.path, '/Users/user-1/Items/Latest');
      expect(options.queryParameters['IncludeItemTypes'], 'Episode');
      expect(options.queryParameters['GroupItems'], isFalse);
      expect(options.queryParameters['Fields'], contains('SeriesName'));
      return _jsonResponse([
        {
          'Id': 'episode-7',
          'Name': 'The Seventh Episode',
          'Type': 'Episode',
          'SeriesId': 'series-1',
          'SeriesName': 'Example Series',
          'ParentIndexNumber': 2,
          'IndexNumber': 7,
        },
      ]);
    });
    final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);
    api.bind(
      const JellyfinSession(
        serverUrl: 'https://media.example.org',
        accessToken: 'token',
        userId: 'user-1',
        serverId: 'server-1',
        username: 'User',
      ),
    );

    final episodes = await JellyfinRepository(
      api,
    ).recentlyAddedEpisodes(limit: 30);

    expect(episodes, hasLength(1));
    expect(episodes.single.id, 'episode-7');
    expect(episodes.single.name, 'The Seventh Episode');
    expect(episodes.single.seriesName, 'Example Series');
    expect(episodes.single.episodeNumber, 7);
  });

  test('favoriteSeriesIds requests Jellyfin favorite series', () async {
    final adapter = _RecordingAdapter((options) async {
      expect(options.path, '/Users/user-1/Items');
      expect(options.queryParameters['IncludeItemTypes'], 'Series');
      expect(options.queryParameters['Filters'], 'IsFavorite');
      expect(options.queryParameters['Recursive'], isTrue);
      return _jsonResponse({
        'Items': [
          {'Id': 'series-1'},
          {'Id': 'series-2'},
        ],
        'TotalRecordCount': 2,
      });
    });
    final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);
    api.bind(
      const JellyfinSession(
        serverUrl: 'https://media.example.org',
        accessToken: 'token',
        userId: 'user-1',
        serverId: 'server-1',
        username: 'User',
      ),
    );

    final ids = await JellyfinRepository(api).favoriteSeriesIds();

    expect(ids, {'series-1', 'series-2'});
  });

  test(
    'favoriteSeriesIds checks favorite state for candidate series',
    () async {
      final adapter = _RecordingAdapter((options) async {
        expect(options.path, '/Users/user-1/Items');
        expect(options.queryParameters['IncludeItemTypes'], 'Series');
        expect(options.queryParameters['Ids'], 'series-1,series-2');
        expect(options.queryParameters['Fields'], 'UserData');
        expect(options.queryParameters, isNot(contains('Filters')));
        return _jsonResponse({
          'Items': [
            {
              'Id': 'series-1',
              'UserData': {'IsFavorite': true},
            },
            {
              'Id': 'series-2',
              'UserData': {'IsFavorite': false},
            },
          ],
          'TotalRecordCount': 2,
        });
      });
      final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);
      api.bind(
        const JellyfinSession(
          serverUrl: 'https://media.example.org',
          accessToken: 'token',
          userId: 'user-1',
          serverId: 'server-1',
          username: 'User',
        ),
      );

      final ids = await JellyfinRepository(
        api,
      ).favoriteSeriesIds(seriesIds: const ['series-1', 'series-2']);

      expect(ids, {'series-1'});
    },
  );

  test('watchHistory requests completed items by latest play date', () async {
    final adapter = _RecordingAdapter((options) async {
      expect(options.path, '/Users/user-1/Items');
      expect(options.queryParameters['IncludeItemTypes'], 'Movie,Episode');
      expect(options.queryParameters['Filters'], 'IsPlayed');
      expect(options.queryParameters['SortBy'], 'DatePlayed');
      expect(options.queryParameters['SortOrder'], 'Descending');
      expect(options.queryParameters['StartIndex'], 30);
      expect(options.queryParameters['Limit'], 30);
      final fields = options.queryParameters['Fields'] as String;
      expect(fields, contains('Genres'));
      expect(fields, contains('People'));
      return _jsonResponse({
        'Items': [
          {
            'Id': 'movie-1',
            'Name': 'Movie',
            'Type': 'Movie',
            'UserData': {
              'Played': true,
              'LastPlayedDate': '2026-06-21T18:30:00Z',
            },
          },
        ],
        'TotalRecordCount': 61,
      });
    });
    final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);
    api.bind(
      const JellyfinSession(
        serverUrl: 'https://media.example.org',
        accessToken: 'token',
        userId: 'user-1',
        serverId: 'server-1',
        username: 'User',
      ),
    );

    final page = await JellyfinRepository(
      api,
    ).watchHistory(startIndex: 30, limit: 30);

    expect(page.items.single.id, 'movie-1');
    expect(page.items.single.userData?.lastPlayedDate, isNotNull);
    expect(page.hasMore, isTrue);
  });

  test(
    'availableItemIds returns only visible ids in bounded batches',
    () async {
      var requestCount = 0;
      final adapter = _RecordingAdapter((options) async {
        requestCount++;
        expect(options.path, '/Users/user-1/Items');
        expect(options.queryParameters['Recursive'], isTrue);
        expect(options.queryParameters['EnableImages'], isFalse);
        final ids = (options.queryParameters['Ids'] as String).split(',');
        return _jsonResponse({
          'Items': [
            for (final id in ids)
              if (id != 'deleted') {'Id': id},
          ],
        });
      });
      final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);
      api.bind(
        const JellyfinSession(
          serverUrl: 'https://media.example.org',
          accessToken: 'token',
          userId: 'user-1',
          serverId: 'server-1',
          username: 'User',
        ),
      );

      final ids = await JellyfinRepository(api).availableItemIds(const [
        'movie-1',
        'deleted',
        'episode-1',
      ], batchSize: 2);

      expect(ids, {'movie-1', 'episode-1'});
      expect(requestCount, 2);
    },
  );
}

ResponseBody _jsonResponse(Object body) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  return ResponseBody.fromBytes(
    bytes,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
