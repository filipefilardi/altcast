import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

void main() {
  group('JellyfinApi.bind / baseUrl normalization', () {
    test('schemeless host gets https prefix and trailing slash stripped', () {
      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session(serverUrl: 'jellyfin.example.com/'));
      expect(dio.options.baseUrl, 'https://jellyfin.example.com');
    });

    test('http scheme is preserved (self-hosted LAN servers)', () {
      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session(serverUrl: 'http://192.168.1.50:8096'));
      expect(dio.options.baseUrl, 'http://192.168.1.50:8096');
    });

    test('https scheme is preserved', () {
      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session(serverUrl: 'https://media.example.org/'));
      expect(dio.options.baseUrl, 'https://media.example.org');
    });

    test('whitespace around URL is trimmed', () {
      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session(serverUrl: '  https://media.example.org  '));
      expect(dio.options.baseUrl, 'https://media.example.org');
    });
  });

  group('JellyfinApi.authorizationHeader', () {
    test('without a token, includes Client/Device/DeviceId/Version only', () {
      final api = JellyfinApi(
        deviceId: 'abc-123',
        deviceName: 'Pixel 9',
        appVersion: '1.2.3',
      );
      final header = api.authorizationHeader;
      expect(header, startsWith('MediaBrowser '));
      expect(header, contains('Client="AltCast"'));
      expect(header, contains('Device="Pixel 9"'));
      expect(header, contains('DeviceId="abc-123"'));
      expect(header, contains('Version="1.2.3"'));
      expect(header, isNot(contains('Token=')));
    });

    test('after bind(), Token attribute is appended', () {
      final api = JellyfinApi(deviceId: 'abc-123');
      api.bind(_session(accessToken: 'token-xyz'));
      expect(api.authorizationHeader, contains('Token="token-xyz"'));
    });

    test('sanitizes quotes and commas from device name and version', () {
      // Both would break the comma-separated quoted-value format.
      final api = JellyfinApi(
        deviceId: 'd',
        deviceName: 'Bob"s, iPad',
        appVersion: '1,0"beta',
      );
      final header = api.authorizationHeader;
      expect(header, contains('Device="Bobs iPad"'));
      expect(header, contains('Version="10beta"'));
    });
  });

  group('JellyfinApi.authenticate', () {
    test(
      'POSTs username/password to /Users/AuthenticateByName, parses session, binds Authorization',
      () async {
        final adapter = _RecordingAdapter((options) async {
          expect(
            options.uri.toString(),
            'https://media.example.org/Users/AuthenticateByName',
          );
          expect(options.method, 'POST');
          expect(options.data, {'Username': 'alice', 'Pw': 'hunter2'});
          // Pre-auth Authorization header must NOT carry a token.
          final auth = options.headers['Authorization'] as String;
          expect(auth, contains('Client="AltCast"'));
          expect(auth, isNot(contains('Token=')));
          return _jsonResponse({
            'AccessToken': 'tok-1',
            'ServerId': 'server-1',
            'User': {'Id': 'user-1', 'Name': 'Alice'},
          });
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final api = JellyfinApi(dio: dio, deviceId: 'dev-1');

        final session = await api.authenticate(
          serverUrl: 'media.example.org/',
          username: 'alice',
          password: 'hunter2',
        );

        expect(session.serverUrl, 'https://media.example.org');
        expect(session.accessToken, 'tok-1');
        expect(session.userId, 'user-1');
        expect(session.serverId, 'server-1');
        expect(session.username, 'Alice');

        // bind() should have wired Authorization onto the shared Dio.
        expect(dio.options.baseUrl, 'https://media.example.org');
        expect(dio.options.headers['Authorization'], contains('Token="tok-1"'));
      },
    );

    test(
      'falls back to provided username when server omits User.Name',
      () async {
        final adapter = _RecordingAdapter((_) async {
          return _jsonResponse({
            'AccessToken': 'tok',
            'ServerId': 'server',
            'User': {'Id': 'uid'},
          });
        });
        final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);

        final session = await api.authenticate(
          serverUrl: 'https://x.example',
          username: 'fallback-name',
          password: 'p',
        );
        expect(session.username, 'fallback-name');
      },
    );

    test('throws JellyfinAuthException when AccessToken is missing', () async {
      final adapter = _RecordingAdapter((_) async {
        return _jsonResponse({
          'ServerId': 'server-1',
          'User': {'Id': 'user-1', 'Name': 'Alice'},
        });
      });
      final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);

      expect(
        () => api.authenticate(
          serverUrl: 'https://x.example',
          username: 'a',
          password: 'b',
        ),
        throwsA(isA<JellyfinAuthException>()),
      );
    });
  });

  group('JellyfinApi.clear', () {
    test('drops baseUrl and Authorization header', () {
      final dio = Dio();
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session(serverUrl: 'https://x.example'));
      expect(dio.options.headers['Authorization'], isNotNull);

      api.clear();
      expect(dio.options.baseUrl, '');
      expect(dio.options.headers.containsKey('Authorization'), isFalse);
      expect(api.session, isNull);
    });
  });

  group('JellyfinApi.logout', () {
    test('clears local session even when server logout fails', () async {
      final adapter = _RecordingAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/Sessions/Logout'),
          type: DioExceptionType.connectionError,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session());

      await api.logout();

      expect(api.session, isNull);
      expect(dio.options.baseUrl, '');
      expect(dio.options.headers.containsKey('Authorization'), isFalse);
    });

    test('is a no-op when no session is bound', () async {
      var called = false;
      final adapter = _RecordingAdapter((_) async {
        called = true;
        return _jsonResponse({});
      });
      final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);

      await api.logout();
      expect(called, isFalse);
    });
  });
}

// ─── helpers ─────────────────────────────────────────────────────────────

JellyfinSession _session({
  String serverUrl = 'https://x.example',
  String accessToken = 'tok',
}) => JellyfinSession(
  serverUrl: serverUrl,
  accessToken: accessToken,
  userId: 'u',
  serverId: 's',
  username: 'n',
);

ResponseBody _jsonResponse(Map<String, dynamic> body, {int status = 200}) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  return ResponseBody.fromBytes(
    bytes,
    status,
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
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
