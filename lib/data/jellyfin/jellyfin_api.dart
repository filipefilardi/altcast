import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

const _appName = 'AltCast';
const _fallbackDeviceName = 'Flutter';
const _fallbackAppVersion = '0.0.0';

class JellyfinApi {
  JellyfinApi({
    Dio? dio,
    String? deviceId,
    String? deviceName,
    String? appVersion,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
             ),
           ),
       _deviceId = deviceId ?? const Uuid().v4(),
       _deviceName = deviceName ?? _fallbackDeviceName,
       _appVersion = appVersion ?? _fallbackAppVersion;

  final Dio _dio;
  final String _deviceId;
  final String _deviceName;
  final String _appVersion;

  Dio get dio => _dio;

  /// Device id this app reports to Jellyfin in the `Authorization` header.
  /// Used to identify (and filter out) our own session in `/Sessions` listings.
  String get deviceId => _deviceId;

  String get authorizationHeader => _authHeader(token: _session?.accessToken);

  JellyfinSession? _session;

  void bind(JellyfinSession session) {
    _session = session;
    _dio.options.baseUrl = _normalizeBase(session.serverUrl);
    _dio.options.headers['Authorization'] = _authHeader(
      token: session.accessToken,
    );
  }

  void clear() {
    _session = null;
    _dio.options.baseUrl = '';
    _dio.options.headers.remove('Authorization');
  }

  JellyfinSession? get session => _session;

  String _authHeader({String? token}) {
    final parts = <String>[
      'Client="$_appName"',
      'Device="${_sanitize(_deviceName)}"',
      'DeviceId="$_deviceId"',
      'Version="${_sanitize(_appVersion)}"',
      if (token != null) 'Token="$token"',
    ];
    return 'MediaBrowser ${parts.join(', ')}';
  }

  /// Strip characters that would break the `MediaBrowser` header format
  /// (quotes and commas), since the value is wrapped in double quotes.
  static String _sanitize(String value) =>
      value.replaceAll('"', '').replaceAll(',', '');

  String _normalizeBase(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<JellyfinSession> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final base = _normalizeBase(serverUrl);
    final response = await _dio.post<Map<String, dynamic>>(
      '$base/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      options: Options(
        headers: {
          'Authorization': _authHeader(),
          'Content-Type': 'application/json',
        },
      ),
    );

    final data = response.data;
    if (data == null) {
      throw const JellyfinAuthException('Empty response from server');
    }

    final user = data['User'] as Map<String, dynamic>?;
    final accessToken = data['AccessToken'] as String?;
    final serverId = data['ServerId'] as String?;
    if (user == null || accessToken == null || serverId == null) {
      throw const JellyfinAuthException('Malformed response from server');
    }

    final session = JellyfinSession(
      serverUrl: base,
      accessToken: accessToken,
      userId: user['Id'] as String,
      serverId: serverId,
      username: user['Name'] as String? ?? username,
    );
    bind(session);
    return session;
  }

  Future<void> logout() async {
    if (_session == null) return;
    try {
      await _dio.post<void>('/Sessions/Logout');
    } catch (_) {
      // Best-effort: server may be unreachable; we still drop the local session.
    } finally {
      clear();
    }
  }
}

class JellyfinAuthException implements Exception {
  const JellyfinAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
