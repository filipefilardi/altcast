part of '../player_material_theme.dart';

class _TrickplayTileCache {
  static final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  static int _maxEntries = kDefaultPlayerMaterialTokens.cacheMaxEntries;

  static void configure(int maxEntries) {
    _maxEntries = maxEntries.clamp(1, 500).toInt();
    while (_memory.length > _maxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  static Future<void> prefetch(Dio dio, Iterable<String> urls) async {
    final unique = <String>{...urls};
    for (final url in unique) {
      unawaited(getOrFetch(dio, url));
    }
  }

  static Future<Uint8List?> getOrFetch(Dio dio, String url) async {
    final hit = _memory.remove(url);
    if (hit != null) {
      // Reinsert to mark as most recently used.
      _memory[url] = hit;
      return hit;
    }
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _fetch(dio, url);
    _inFlight[url] = future;
    try {
      final data = await future;
      if (data != null && data.isNotEmpty) {
        _memory[url] = data;
        while (_memory.length > _maxEntries) {
          _memory.remove(_memory.keys.first);
        }
      }
      return data;
    } finally {
      _inFlight.remove(url);
    }
  }

  static Future<Uint8List?> _fetch(Dio dio, String url) async {
    final uri = Uri.tryParse(url);
    if (!kIsWeb && uri != null && uri.scheme == 'file') {
      try {
        final file = File.fromUri(uri);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) return null;
        return bytes;
      } catch (e) {
        if (_trickplayDebugLogs) {
          debugPrintSynchronously(
            'Trickplay local file read failed url=$url error=$e',
          );
        }
        return null;
      }
    }

    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (_trickplayDebugLogs) {
        debugPrintSynchronously(
          'Trickplay image failed status=${e.response?.statusCode} url=$url',
        );
      }
      return null;
    }
  }
}
