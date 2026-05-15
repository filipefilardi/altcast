import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/secure_storage.dart';

void main() {
  group('AuthRepository.login', () {
    test(
      'authenticates, then persists the session JSON under the v1 key',
      () async {
        final storage = _FakeSecureStorage();
        final api = JellyfinApi(
          dio: Dio()
            ..httpClientAdapter = _adapter(
              (_) => _ok({
                'AccessToken': 'tok',
                'ServerId': 'srv',
                'User': {'Id': 'uid', 'Name': 'Alice'},
              }),
            ),
        );
        final repo = AuthRepository(api: api, storage: storage);

        final session = await repo.login(
          serverUrl: 'media.example.org',
          username: 'alice',
          password: 'pw',
        );

        expect(session.username, 'Alice');
        // Exactly one key written; its content is the serialized session.
        expect(storage.store.keys, hasLength(1));
        final stored =
            jsonDecode(storage.store.values.single) as Map<String, dynamic>;
        expect(stored['accessToken'], 'tok');
        expect(stored['serverUrl'], 'https://media.example.org');
      },
    );
  });

  group('AuthRepository.restore', () {
    test('returns null when no session is stored', () async {
      final repo = AuthRepository(
        api: JellyfinApi(),
        storage: _FakeSecureStorage(),
      );
      expect(await repo.restore(), isNull);
    });

    test('rehydrates the session and binds it onto the API', () async {
      final storage = _FakeSecureStorage();
      // Pre-seed storage with a v1 session payload, using the same key the
      // repository uses (matches the const `_sessionKey` in source).
      final session = JellyfinSession(
        serverUrl: 'https://media.example.org',
        accessToken: 'tok',
        userId: 'uid',
        serverId: 'srv',
        username: 'Alice',
      );
      await storage.write('jellyfin_session_v1', jsonEncode(session.toJson()));

      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      final repo = AuthRepository(api: api, storage: storage);

      final restored = await repo.restore();

      expect(restored, isNotNull);
      expect(restored!.accessToken, 'tok');
      expect(dio.options.baseUrl, 'https://media.example.org');
      expect(dio.options.headers['Authorization'], contains('Token="tok"'));
    });

    test('drops corrupted payload and returns null (self-healing)', () async {
      final storage = _FakeSecureStorage();
      await storage.write('jellyfin_session_v1', '{not json');

      final repo = AuthRepository(api: JellyfinApi(), storage: storage);

      expect(await repo.restore(), isNull);
      // Corrupted entry must be cleared so the user lands on the login screen
      // cleanly next launch instead of looping on the same bad payload.
      expect(storage.store, isEmpty);
    });
  });

  group('AuthRepository.logout', () {
    test('calls api.logout and clears storage', () async {
      final storage = _FakeSecureStorage()
        ..store['jellyfin_session_v1'] = '{"any":"value"}';

      final api = JellyfinApi(
        dio: Dio()
          ..httpClientAdapter = _adapter((opts) {
            expect(opts.path, contains('/Sessions/Logout'));
            return _ok({});
          }),
      );
      api.bind(_dummySession());

      final repo = AuthRepository(api: api, storage: storage);
      await repo.logout();

      expect(api.session, isNull);
      expect(storage.store, isEmpty);
    });
  });
}

// ─── helpers ─────────────────────────────────────────────────────────────

JellyfinSession _dummySession() => const JellyfinSession(
  serverUrl: 'https://x.example',
  accessToken: 'tok',
  userId: 'u',
  serverId: 's',
  username: 'n',
);

class _FakeSecureStorage extends SecureStorage {
  // The inherited FlutterSecureStorage is never invoked — we override all
  // three accessor methods below to use the in-memory map instead.
  _FakeSecureStorage() : super(const FlutterSecureStorage());

  final Map<String, String> store = {};

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
  }
}

HttpClientAdapter _adapter(ResponseBody Function(RequestOptions) handler) =>
    _InlineAdapter(handler);

class _InlineAdapter implements HttpClientAdapter {
  _InlineAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok(Map<String, dynamic> body) => ResponseBody.fromBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(body))),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
