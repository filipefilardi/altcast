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
