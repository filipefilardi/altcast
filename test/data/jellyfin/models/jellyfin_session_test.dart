import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

void main() {
  // Round-tripping matters because the JSON shape is the on-disk format
  // persisted via flutter_secure_storage. A breaking change here would log
  // every existing user out at upgrade.
  test('JellyfinSession round-trips through toJson/fromJson losslessly', () {
    const original = JellyfinSession(
      serverUrl: 'https://media.example.org',
      accessToken: 'tok-xyz',
      userId: 'user-1',
      serverId: 'server-1',
      username: 'Alice',
    );

    final roundTripped = JellyfinSession.fromJson(original.toJson());

    expect(roundTripped.serverUrl, original.serverUrl);
    expect(roundTripped.accessToken, original.accessToken);
    expect(roundTripped.userId, original.userId);
    expect(roundTripped.serverId, original.serverId);
    expect(roundTripped.username, original.username);
  });

  test('fromJson rejects payloads missing a required field', () {
    expect(
      () => JellyfinSession.fromJson(const {
        'serverUrl': 'https://x',
        'accessToken': 'tok',
        // userId missing
        'serverId': 's',
        'username': 'n',
      }),
      throwsA(isA<TypeError>()),
    );
  });
}
