import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';
import 'package:altcast/data/seerr/models.dart';

const _seerrSessionKey = 'seerr_session_v1';

enum SeerrDiscoverShelf { trending, popularMovies, popularSeries }

extension SeerrDiscoverShelfMeta on SeerrDiscoverShelf {
  String get title => switch (this) {
    SeerrDiscoverShelf.trending => 'Trending',
    SeerrDiscoverShelf.popularMovies => 'Popular Movies',
    SeerrDiscoverShelf.popularSeries => 'Popular Series',
  };

  String get routeValue => switch (this) {
    SeerrDiscoverShelf.trending => 'trending',
    SeerrDiscoverShelf.popularMovies => 'popular-movies',
    SeerrDiscoverShelf.popularSeries => 'popular-series',
  };

  static SeerrDiscoverShelf? fromRouteValue(String value) {
    return switch (value) {
      'trending' => SeerrDiscoverShelf.trending,
      'popular-movies' => SeerrDiscoverShelf.popularMovies,
      'popular-series' => SeerrDiscoverShelf.popularSeries,
      _ => null,
    };
  }
}

final seerrRepositoryProvider = Provider<SeerrRepository>((ref) {
  return SeerrRepository(storage: ref.watch(secureStorageProvider));
});

class SeerrRepository {
  SeerrRepository({required this.storage, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
            ),
          );

  final SecureStorage storage;
  final Dio _dio;

  Future<SeerrSession?> restore() async {
    final raw = await storage.read(_seerrSessionKey);
    if (raw == null) return null;
    try {
      final session = SeerrSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return session.isValid ? session : null;
    } catch (_) {
      await storage.delete(_seerrSessionKey);
      return null;
    }
  }

  Future<SeerrSession> loginWithJellyfin({
    required String seerrUrl,
    required String jellyfinUsername,
    required String jellyfinPassword,
  }) async {
    final baseUrl = _normalizeBase(seerrUrl);
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/auth/jellyfin',
      data: {'username': jellyfinUsername, 'password': jellyfinPassword},
    );
    final cookie = _cookieHeaderFrom(response.headers);
    if (cookie == null || cookie.isEmpty) {
      throw const SeerrException('Seerr did not return a session cookie.');
    }
    final username =
        response.data?['username'] as String? ??
        response.data?['jellyfinUsername'] as String? ??
        jellyfinUsername;
    final session = SeerrSession(
      serverUrl: baseUrl,
      cookieHeader: cookie,
      username: username,
    );
    await storage.write(_seerrSessionKey, jsonEncode(session.toJson()));
    return session;
  }

  Future<void> logout() async {
    final session = await restore();
    if (session != null) {
      try {
        await _request<void>(session, () => _dio.post('/auth/logout'));
      } catch (_) {
        // Best-effort; local session removal still matters most.
      }
    }
    await storage.delete(_seerrSessionKey);
  }

  Future<void> testConnection(SeerrSession session) async {
    await _request<Map<String, dynamic>>(session, () => _dio.get('/auth/me'));
  }

  Future<SeerrPagedResult<SeerrMediaItem>> search(
    String query, {
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SeerrPagedResult(
        results: [],
        page: 1,
        totalPages: 1,
        totalResults: 0,
      );
    }
    final session = await _requireSession();
    final response = await _request<Map<String, dynamic>>(
      session,
      () =>
          _dio.get(_pathWithQuery('/search', {'query': trimmed, 'page': page})),
    );
    return _pagedMediaItems(response.data);
  }

  Future<SeerrPagedResult<SeerrMediaItem>> trending({
    String mediaType = 'all',
    int page = 1,
  }) async {
    return discoverShelf(SeerrDiscoverShelf.trending, page: page);
  }

  Future<SeerrPagedResult<SeerrMediaItem>> discoverShelf(
    SeerrDiscoverShelf shelf, {
    int page = 1,
    String mediaType = 'all',
  }) async {
    final session = await _requireSession();
    final path = switch (shelf) {
      SeerrDiscoverShelf.trending => '/discover/trending',
      SeerrDiscoverShelf.popularMovies => '/discover/movies',
      SeerrDiscoverShelf.popularSeries => '/discover/tv',
    };
    final query = switch (shelf) {
      SeerrDiscoverShelf.trending => <String, Object>{
        'page': page,
        'mediaType': mediaType,
        'timeWindow': 'day',
      },
      SeerrDiscoverShelf.popularMovies ||
      SeerrDiscoverShelf.popularSeries => <String, Object>{'page': page},
    };
    final response = await _request<Map<String, dynamic>>(
      session,
      () => _dio.get(_pathWithQuery(path, query)),
    );
    return _pagedMediaItems(response.data);
  }

  Future<SeerrMediaDetails> details({
    required int id,
    required SeerrMediaType mediaType,
  }) async {
    final session = await _requireSession();
    final path = mediaType == SeerrMediaType.tv ? '/tv/$id' : '/movie/$id';
    final response = await _request<Map<String, dynamic>>(
      session,
      () => _dio.get(path),
    );
    final data = response.data;
    if (data == null) {
      throw const SeerrException('Empty Seerr detail response.');
    }
    return SeerrMediaDetails.fromJson(data, mediaType);
  }

  Future<void> requestMedia({
    required SeerrMediaDetails item,
    List<int>? seasons,
  }) async {
    final session = await _requireSession();
    final body = <String, dynamic>{
      'mediaType': item.mediaType.apiValue,
      'mediaId': item.id,
      if (item.mediaType == SeerrMediaType.tv)
        'seasons': seasons == null || seasons.isEmpty ? 'all' : seasons,
    };
    await _request<Map<String, dynamic>>(
      session,
      () => _dio.post('/request', data: body),
    );
  }

  Future<void> retryRequest(int requestId) async {
    final session = await _requireSession();
    await _request<Map<String, dynamic>>(
      session,
      () => _dio.post('/request/$requestId/retry'),
    );
  }

  Future<void> updateRequestStatus({
    required int requestId,
    required String status,
  }) async {
    final session = await _requireSession();
    await _request<Map<String, dynamic>>(
      session,
      () => _dio.post('/request/$requestId/$status'),
    );
  }

  Future<SeerrPagedResult<SeerrRequest>> requests({
    int skip = 0,
    int take = 20,
    String filter = 'all',
  }) async {
    final session = await _requireSession();
    final response = await _request<Map<String, dynamic>>(
      session,
      () => _dio.get(
        _pathWithQuery('/request', {
          'skip': skip,
          'take': take,
          if (filter != 'all') 'filter': filter,
        }),
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final pageInfo = data['pageInfo'] is Map
        ? Map<String, dynamic>.from(data['pageInfo'] as Map)
        : const <String, dynamic>{};
    final pageSize = pageInfo['pageSize'] is num
        ? (pageInfo['pageSize'] as num).toInt()
        : take;
    final resultCount = pageInfo['results'] is num
        ? (pageInfo['results'] as num).toInt()
        : 0;
    return SeerrPagedResult(
      results: ((data['results'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SeerrRequest.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      page: pageInfo['page'] is num ? (pageInfo['page'] as num).toInt() : 1,
      totalPages: pageInfo['pages'] is num
          ? (pageInfo['pages'] as num).toInt()
          : 1,
      totalResults: resultCount == 0 ? pageSize : resultCount,
    );
  }

  Future<SeerrSession> _requireSession() async {
    final session = await restore();
    if (session == null) {
      throw const SeerrException('Connect Seerr in Settings first.');
    }
    return session;
  }

  Future<Response<T>> _request<T>(
    SeerrSession session,
    Future<Response<T>> Function() request,
  ) async {
    _dio.options.baseUrl = '${session.serverUrl}/api/v1';
    _dio.options.headers.addAll({
      'Accept': 'application/json',
      'Cookie': session.cookieHeader,
    });
    return request();
  }

  SeerrPagedResult<SeerrMediaItem> _pagedMediaItems(
    Map<String, dynamic>? data,
  ) {
    final json = data ?? const <String, dynamic>{};
    return SeerrPagedResult(
      results: ((json['results'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => SeerrMediaItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.mediaType != SeerrMediaType.person)
          .toList(growable: false),
      page: json['page'] is num ? (json['page'] as num).toInt() : 1,
      totalPages: json['totalPages'] is num
          ? (json['totalPages'] as num).toInt()
          : 1,
      totalResults: json['totalResults'] is num
          ? (json['totalResults'] as num).toInt()
          : 0,
    );
  }

  String _normalizeBase(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/api/v1')) {
      normalized = normalized.substring(
        0,
        normalized.length - '/api/v1'.length,
      );
    }
    return normalized;
  }

  String? _cookieHeaderFrom(Headers headers) {
    final cookies = headers.map['set-cookie'];
    if (cookies == null || cookies.isEmpty) return null;
    return cookies
        .map((cookie) => cookie.split(';').first.trim())
        .where((cookie) => cookie.isNotEmpty)
        .join('; ');
  }

  String _pathWithQuery(String path, Map<String, Object?> query) {
    final entries = query.entries.where((entry) => entry.value != null);
    final queryString = entries
        .map(
          (entry) =>
              '${_encodeUriExtraParam(entry.key)}=${_encodeUriExtraParam('${entry.value}')}',
        )
        .join('&');
    return queryString.isEmpty ? path : '$path?$queryString';
  }

  String _encodeUriExtraParam(String value) {
    var encoded = Uri.encodeComponent(value);
    encoded = encoded
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll('!', '%21')
        .replaceAll('*', '%2A');
    return encoded;
  }
}

class SeerrException implements Exception {
  const SeerrException(this.message);
  final String message;

  @override
  String toString() => message;
}

String userFacingSeerrMessage(Object error) {
  if (error is SeerrException) return error.message;
  if (error is DioException) {
    final status = error.response?.statusCode;
    final hint = _responseBodyHint(error.response);
    if (hint != null) return hint;
    if (status == 400) {
      return 'Seerr rejected the request. Check that Seerr search/discovery works in its web UI, then try again.';
    }
    if (status == 401 || status == 403) {
      return 'Seerr session expired or access was denied. Reconnect Seerr in Settings.';
    }
    if (status == 404) {
      return 'Seerr endpoint was not found. Check the Seerr URL in Settings.';
    }
    if (status != null && status >= 500) {
      return 'Seerr returned a server error. Check Seerr logs and try again.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Could not reach Seerr. Check the URL and your network.';
    }
    return error.message ?? 'Seerr request failed.';
  }
  return error.toString();
}

String? _responseBodyHint(Response<dynamic>? response) {
  final data = response?.data;
  if (data is String) {
    final trimmed = data.trim();
    return trimmed.isEmpty ? null : _truncate(trimmed);
  }
  if (data is Map) {
    for (final key in ['message', 'error', 'title', 'Message']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return _truncate(value);
      }
    }
  }
  return null;
}

String _truncate(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 180) return normalized;
  return '${normalized.substring(0, 179)}…';
}

final seerrConnectionProvider =
    AsyncNotifierProvider<SeerrConnectionNotifier, SeerrSession?>(
      SeerrConnectionNotifier.new,
    );

class SeerrConnectionNotifier extends AsyncNotifier<SeerrSession?> {
  @override
  Future<SeerrSession?> build() {
    return ref.read(seerrRepositoryProvider).restore();
  }

  Future<void> connect({
    required String seerrUrl,
    required String jellyfinUsername,
    required String jellyfinPassword,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(seerrRepositoryProvider)
          .loginWithJellyfin(
            seerrUrl: seerrUrl,
            jellyfinUsername: jellyfinUsername,
            jellyfinPassword: jellyfinPassword,
          ),
    );
  }

  Future<void> disconnect() async {
    await ref.read(seerrRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}
