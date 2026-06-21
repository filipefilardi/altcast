import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/watch_history_store.dart';

void main() {
  late Directory directory;
  late WatchHistoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('altcast_history_test_');
    store = WatchHistoryStore(directoryProvider: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists history separately for each server user', () async {
    const firstSession = JellyfinSession(
      serverUrl: 'https://one.example',
      accessToken: 'token',
      userId: 'user-1',
      serverId: 'server-1',
      username: 'First',
    );
    const secondSession = JellyfinSession(
      serverUrl: 'https://two.example',
      accessToken: 'token',
      userId: 'user-2',
      serverId: 'server-2',
      username: 'Second',
    );
    final entry = WatchHistoryEntry(
      id: 'movie-1',
      name: 'Archived Movie',
      kind: MediaKind.movie,
      watchedAt: DateTime.utc(2026, 6, 21),
      isAvailable: false,
    );

    await store.write(firstSession, [entry]);

    final restored = await store.read(firstSession);
    expect(restored.single.name, 'Archived Movie');
    expect(restored.single.isAvailable, isFalse);
    expect(await store.read(secondSession), isEmpty);
  });

  test('merge keeps cached items and refreshes matching live metadata', () {
    final cached = [
      WatchHistoryEntry(
        id: 'old-movie',
        name: 'Old Movie',
        kind: MediaKind.movie,
        watchedAt: DateTime.utc(2025),
        isAvailable: false,
      ),
      WatchHistoryEntry(
        id: 'episode-1',
        name: 'Old Episode Name',
        kind: MediaKind.episode,
        watchedAt: DateTime.utc(2025, 2),
      ),
    ];
    final live = [
      BrowseItem(
        id: 'episode-1',
        name: 'Updated Episode Name',
        kind: MediaKind.episode,
        userData: UserData(played: true, lastPlayedDate: DateTime.utc(2026, 2)),
      ),
    ];

    final merged = mergeWatchHistory(cached, live);

    expect(merged, hasLength(2));
    expect(merged.first.name, 'Updated Episode Name');
    expect(merged.first.isAvailable, isTrue);
    expect(merged.last.id, 'old-movie');
  });
}
