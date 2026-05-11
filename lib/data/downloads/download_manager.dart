import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../jellyfin/jellyfin_repository.dart';
import '../jellyfin/models/episode.dart';
import '../jellyfin/models/intro_skipper_timestamps.dart';
import '../jellyfin/models/movie.dart';
import '../jellyfin/models/stream_source.dart';
import '../local/download_preferences.dart';
import 'downloaded_item.dart';

class DownloadsState {
  const DownloadsState({
    this.items = const {},
    this.progress = const {},
    this.failures = const {},
    this.queueLength = 0,
    this.pausedIds = const {},
    this.bootstrapped = false,
  });

  final Map<String, DownloadedItem> items;
  final Map<String, DownloadProgress> progress;
  final Map<String, DownloadFailure> failures;
  final int queueLength;
  final Set<String> pausedIds;
  final bool bootstrapped;

  DownloadsState copyWith({
    Map<String, DownloadedItem>? items,
    Map<String, DownloadProgress>? progress,
    Map<String, DownloadFailure>? failures,
    int? queueLength,
    Set<String>? pausedIds,
    bool? bootstrapped,
  }) {
    return DownloadsState(
      items: items ?? this.items,
      progress: progress ?? this.progress,
      failures: failures ?? this.failures,
      queueLength: queueLength ?? this.queueLength,
      pausedIds: pausedIds ?? this.pausedIds,
      bootstrapped: bootstrapped ?? this.bootstrapped,
    );
  }

  String? localPath(String itemId) => items[itemId]?.filePath;
  bool isDownloading(String itemId) => progress.containsKey(itemId);
  bool isPaused(String itemId) => pausedIds.contains(itemId);
}

final downloadManagerProvider =
    NotifierProvider<DownloadManager, DownloadsState>(DownloadManager.new);

class DownloadManager extends Notifier<DownloadsState> {
  final List<_QueueEntry> _queue = [];
  final Map<String, _QueueEntry> _paused = {};
  bool _draining = false;
  CancelToken? _activeCancel;
  String? _activeItemId;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  @override
  DownloadsState build() {
    _bootstrap();
    ref.onDispose(() {
      _netSub?.cancel();
      _activeCancel?.cancel('Disposed');
    });
    return const DownloadsState();
  }

  Future<void> _bootstrap() async {
    final dir = await _downloadsDir();
    await _restoreManifest(dir);
    await _restoreQueue(dir);
    state = state.copyWith(bootstrapped: true, queueLength: _queue.length);
    _drain();
  }

  Future<void> _restoreManifest(Directory dir) async {
    final manifest = File('${dir.path}/manifest.json');
    if (!manifest.existsSync()) return;
    try {
      final raw = await manifest.readAsString();
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final loaded = <String, DownloadedItem>{};
      for (final json in list) {
        final item = DownloadedItem.fromJson(json);
        if (File(item.filePath).existsSync()) loaded[item.id] = item;
      }
      state = state.copyWith(items: loaded);
    } catch (_) {}
  }

  Future<void> _restoreQueue(Directory dir) async {
    final queueFile = File('${dir.path}/queue.json');
    if (!queueFile.existsSync()) return;
    try {
      final raw = await queueFile.readAsString();
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final restored = list
          .map(_PersistedQueueEntry.fromJson)
          .where((entry) => !state.items.containsKey(entry.entry.itemId))
          .toList(growable: false);
      _queue.clear();
      _paused.clear();
      for (final item in restored) {
        if (item.paused) {
          _paused[item.entry.itemId] = item.entry;
        } else {
          _queue.add(item.entry);
        }
      }
      final progress = <String, DownloadProgress>{...state.progress};
      for (final item in restored) {
        final entry = item.entry;
        final partialBytes = await _partialSize(entry.itemId);
        progress[entry.itemId] = entry.toProgress(
          -1,
          downloadedBytes: partialBytes > 0 ? partialBytes : null,
        );
      }
      state = state.copyWith(progress: progress);
      state = state.copyWith(pausedIds: _paused.keys.toSet());
    } catch (_) {}
  }

  Future<void> enqueueMovie(Movie movie) async {
    if (state.items.containsKey(movie.id) || state.isDownloading(movie.id)) {
      return;
    }
    final entry = _QueueEntry.movie(movie);
    _queue.add(entry);
    _paused.remove(movie.id);
    state = state.copyWith(
      progress: {...state.progress, movie.id: entry.toProgress(0)},
      failures: Map<String, DownloadFailure>.from(state.failures)
        ..remove(movie.id),
      queueLength: _queue.length,
      pausedIds: _paused.keys.toSet(),
    );
    await _persistQueue();
    _drain();
  }

  Future<void> enqueueEpisode(
    Episode episode, {
    required String seriesName,
    String? seriesPosterTag,
  }) async {
    final entry = _QueueEntry.episode(
      episode,
      seriesName: seriesName,
      seriesPosterTag: seriesPosterTag,
    );
    _enqueueEntries([entry]);
  }

  Future<int> enqueueEpisodes(
    List<Episode> episodes, {
    required String seriesName,
    String? seriesPosterTag,
  }) async {
    final entries = episodes
        .map(
          (episode) => _QueueEntry.episode(
            episode,
            seriesName: seriesName,
            seriesPosterTag: seriesPosterTag,
          ),
        )
        .toList(growable: false);
    return _enqueueEntries(entries);
  }

  int _enqueueEntries(List<_QueueEntry> entries) {
    final fresh = entries
        .where((entry) => !state.items.containsKey(entry.itemId))
        .where((entry) => !state.isDownloading(entry.itemId))
        .toList(growable: false);
    if (fresh.isEmpty) return 0;

    _queue.addAll(fresh);
    for (final entry in fresh) {
      _paused.remove(entry.itemId);
    }
    state = state.copyWith(
      progress: {
        ...state.progress,
        for (final entry in fresh) entry.itemId: entry.toProgress(0),
      },
      failures: Map<String, DownloadFailure>.from(state.failures)
        ..removeWhere((id, _) => fresh.any((entry) => entry.itemId == id)),
      queueLength: _queue.length,
      pausedIds: _paused.keys.toSet(),
    );
    _persistQueue();
    _drain();
    return fresh.length;
  }

  Future<void> cancel(String itemId) async {
    _queue.removeWhere((e) => e.itemId == itemId);
    if (_activeItemId == itemId) {
      _activeCancel?.cancel('Cancelled by user');
    }
    final newProgress = Map<String, DownloadProgress>.from(state.progress)
      ..remove(itemId);
    _paused.remove(itemId);
    state = state.copyWith(
      progress: newProgress,
      queueLength: _queue.length,
      pausedIds: _paused.keys.toSet(),
    );
    await _cleanupPartial(itemId);
    await _persistQueue();
  }

  Future<void> pause(String itemId) async {
    final idx = _queue.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    _paused[itemId] = _queue.removeAt(idx);
    if (_activeItemId == itemId) {
      _activeCancel?.cancel('Paused by user');
    }
    state = state.copyWith(queueLength: _queue.length, pausedIds: _paused.keys.toSet());
    await _persistQueue();
  }

  Future<void> resume(String itemId) async {
    final entry = _paused.remove(itemId);
    if (entry == null) return;
    _queue.add(entry);
    state = state.copyWith(queueLength: _queue.length, pausedIds: _paused.keys.toSet());
    await _persistQueue();
    _drain();
  }

  Future<void> retry(String itemId) async {
    final failure = state.failures[itemId];
    if (failure == null) return;
    final newFailures = Map<String, DownloadFailure>.from(state.failures)
      ..remove(itemId);
    state = state.copyWith(failures: newFailures);
    _enqueueEntries([_QueueEntry.failure(failure)]);
  }

  void dismissFailure(String itemId) {
    final newFailures = Map<String, DownloadFailure>.from(state.failures)
      ..remove(itemId);
    state = state.copyWith(failures: newFailures);
  }

  Future<void> delete(String itemId) async {
    final item = state.items[itemId];
    if (item == null) return;
    try {
      final f = File(item.filePath);
      if (f.existsSync()) await f.delete();
      for (final sub in item.externalSubtitles) {
        final sf = File(sub.filePath);
        if (sf.existsSync()) await sf.delete();
      }
    } catch (_) {}
    final newItems = Map<String, DownloadedItem>.from(state.items)
      ..remove(itemId);
    state = state.copyWith(items: newItems);
    await _persist();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final entry = _queue.first;
        await _download(entry);
        _queue.removeWhere((e) => e.itemId == entry.itemId);
        state = state.copyWith(queueLength: _queue.length);
        await _persistQueue();
      }
    } finally {
      _activeItemId = null;
      await _netSub?.cancel();
      _netSub = null;
      _draining = false;
      state = state.copyWith(queueLength: _queue.length);
    }
  }

  Future<void> _download(_QueueEntry entry) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final sidecarSubs = await _resolveExternalSubs(entry.itemId);
    final dir = await _downloadsDir();
    final tempPath = '${dir.path}/${entry.itemId}.partial';
    final finalPath = '${dir.path}/${entry.itemId}.video';
    final tempFile = File(tempPath);
    final existingBytes = tempFile.existsSync() ? await tempFile.length() : 0;
    final url = await _resolveDownloadUrl(repo, entry.itemId);

    _activeCancel = CancelToken();
    _activeItemId = entry.itemId;

    try {
      await _guardDownloadNetwork();
      await _guardFreeSpace(minBytes: 200 * 1024 * 1024);
      await _watchNetworkPolicy();

      await Dio().download(
        url,
        tempPath,
        cancelToken: _activeCancel,
        options: Options(
          followRedirects: true,
          headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : {},
        ),
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          final downloaded = existingBytes + received;
          final expected = total > 0 ? existingBytes + total : null;
          final existing = state.progress[entry.itemId];
          if (existing == null) return;
          state = state.copyWith(
            progress: {
              ...state.progress,
              entry.itemId: existing.copyWithBytes(
                downloaded: downloaded,
                total: expected,
              ),
            },
          );
        },
      );

      try {
        await tempFile.rename(finalPath);
      } catch (_) {
        await tempFile.copy(finalPath);
        await tempFile.delete();
      }

      final downloadedSubs = await _downloadExternalSubs(
        itemId: entry.itemId,
        subs: sidecarSubs,
        dir: dir,
      );
      final skipper = await _resolveIntroSkipperTimestamps(entry.itemId);
      final downloaded = entry.toDownloadedItem(
        filePath: finalPath,
        introSkipper: skipper,
        externalSubtitles: downloadedSubs,
      );
      final newItems = {...state.items, downloaded.id: downloaded};
      final newProgress = Map<String, DownloadProgress>.from(state.progress)
        ..remove(entry.itemId);
      state = state.copyWith(items: newItems, progress: newProgress);
      await _persist();

      _maybeAutoDownloadNext(entry);
    } catch (e) {
      final wasCancelled = e is DioException && CancelToken.isCancel(e);
      final paused = _paused.containsKey(entry.itemId);
      final newProgress = Map<String, DownloadProgress>.from(state.progress);
      if (!paused) {
        newProgress.remove(entry.itemId);
      }
      state = state.copyWith(
        progress: newProgress,
        failures: wasCancelled
            ? state.failures
            : {
                ...state.failures,
                entry.itemId: entry.toFailure(_downloadFailureMessage(e)),
              },
      );
    } finally {
      _activeItemId = null;
      _activeCancel = null;
      await _netSub?.cancel();
      _netSub = null;
    }
  }

  Future<void> _watchNetworkPolicy() async {
    await _netSub?.cancel();
    _netSub = Connectivity().onConnectivityChanged.listen((_) async {
      final prefs = ref.read(downloadPreferencesProvider);
      if (!prefs.wifiOnlyDownloads) return;
      final connectivity = await Connectivity().checkConnectivity();
      final hasUnmetered =
          connectivity.contains(ConnectivityResult.wifi) ||
          connectivity.contains(ConnectivityResult.ethernet);
      final offline = connectivity.contains(ConnectivityResult.none);
      if (!hasUnmetered || offline) {
        _activeCancel?.cancel('Network policy changed');
      }
    });
  }

  Future<String> _resolveDownloadUrl(JellyfinRepository repo, String itemId) async {
    final prefs = ref.read(downloadPreferencesProvider);
    final bitrate = prefs.offlineVideoQuality.maxBitrate;
    if (bitrate == null) {
      return repo.streamUrl(itemId, staticStream: true);
    }
    return repo.streamUrl(
      itemId,
      staticStream: false,
      maxBitrate: bitrate,
    );
  }

  Future<void> _guardFreeSpace({required int minBytes}) async {
    final dir = await _downloadsDir();
    final stat = await dir.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw const _DownloadBlockedException('Storage location unavailable.');
    }
    // We cannot read exact free-space cross-platform in pure Dart reliably.
    // This preflight catches disconnected or invalid storage roots.
    final testFile = File('${dir.path}/.write_test');
    try {
      await testFile.writeAsString('ok', flush: true);
      await testFile.delete();
    } catch (_) {
      throw const _DownloadBlockedException('Storage is not writable.');
    }
    if (minBytes <= 0) return;
  }

  Future<int> _partialSize(String itemId) async {
    final dir = await _downloadsDir();
    final f = File('${dir.path}/$itemId.partial');
    if (!f.existsSync()) return 0;
    return f.length();
  }

  Future<void> _cleanupPartial(String itemId) async {
    final dir = await _downloadsDir();
    final f = File('${dir.path}/$itemId.partial');
    if (f.existsSync()) await f.delete();
  }

  Future<List<DownloadedExternalSubtitle>> _downloadExternalSubs({
    required String itemId,
    required List<ExternalSubtitle> subs,
    required Directory dir,
  }) async {
    final out = <DownloadedExternalSubtitle>[];
    for (var i = 0; i < subs.length; i++) {
      final sub = subs[i];
      final ext = _subtitleExt(sub);
      final tempPath = '${dir.path}/$itemId.sub.$i.partial';
      final finalPath = '${dir.path}/$itemId.sub.$i.$ext';
      try {
        await Dio().download(
          sub.url,
          tempPath,
          options: Options(followRedirects: true),
        );
        final tempFile = File(tempPath);
        try {
          await tempFile.rename(finalPath);
        } catch (_) {
          await tempFile.copy(finalPath);
          await tempFile.delete();
        }
        out.add(
          DownloadedExternalSubtitle(
            id: sub.id,
            filePath: finalPath,
            streamIndex: sub.streamIndex,
            title: sub.title,
            language: sub.language,
            codec: sub.codec,
          ),
        );
      } catch (_) {
        try {
          final tf = File(tempPath);
          if (tf.existsSync()) await tf.delete();
        } catch (_) {}
      }
    }
    return out;
  }

  Future<List<ExternalSubtitle>> _resolveExternalSubs(String itemId) async {
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final source = await repo.getStreamSource(itemId);
      return source.externalSubtitles;
    } catch (_) {
      return const [];
    }
  }

  Future<IntroSkipperTimestamps?> _resolveIntroSkipperTimestamps(
    String itemId,
  ) async {
    try {
      return await ref
          .read(jellyfinRepositoryProvider)
          .getIntroSkipperTimestamps(itemId);
    } catch (_) {
      return null;
    }
  }

  String _subtitleExt(ExternalSubtitle sub) {
    final codec = (sub.codec ?? '').toLowerCase();
    if (codec.isNotEmpty) return codec;
    final uri = Uri.tryParse(sub.url);
    if (uri == null) return 'vtt';
    final segs = uri.pathSegments;
    if (segs.isEmpty) return 'vtt';
    final last = segs.last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return 'vtt';
    return last.substring(dot + 1).toLowerCase();
  }

  Future<void> _guardDownloadNetwork() async {
    final prefs = ref.read(downloadPreferencesProvider);
    if (!prefs.wifiOnlyDownloads) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      throw const _DownloadBlockedException('No network connection.');
    }
    final hasUnmeteredNetwork =
        connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet);
    final mobileOnly =
        connectivity.contains(ConnectivityResult.mobile) &&
        !hasUnmeteredNetwork;
    if (mobileOnly) {
      throw const _DownloadBlockedException('Waiting for Wi-Fi to download.');
    }
  }

  String _downloadFailureMessage(Object error) {
    if (error is _DownloadBlockedException) return error.message;
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Connection timed out.';
      }
      final status = error.response?.statusCode;
      if (status == 416) {
        return 'Resume failed, try re-downloading.';
      }
      if (status != null) return 'Server returned HTTP $status.';
      return 'Network error while downloading.';
    }
    return 'Download failed.';
  }

  Future<void> _maybeAutoDownloadNext(_QueueEntry entry) async {
    final prefs = ref.read(downloadPreferencesProvider);
    if (!prefs.autoDownloadNextEpisode) return;
    if (entry.kind != DownloadedItemKind.episode) return;

    final seriesId = entry.seriesId;
    final seasonNum = entry.seasonNumber;
    final episodeNum = entry.episodeNumber;
    if (seriesId == null || seasonNum == null || episodeNum == null) return;

    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final next = await repo.getNextEpisode(
        seriesId: seriesId,
        seasonNumber: seasonNum,
        episodeNumber: episodeNum,
      );

      if (next != null) {
        await enqueueEpisode(
          next,
          seriesName: entry.seriesName ?? 'Series',
          seriesPosterTag: entry.imageTag,
        );
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final dir = await _downloadsDir();
    final manifest = File('${dir.path}/manifest.json');
    final list = state.items.values.map((i) => i.toJson()).toList();
    await manifest.writeAsString(jsonEncode(list));
    await _persistQueue();
  }

  Future<void> _persistQueue() async {
    final dir = await _downloadsDir();
    final queueFile = File('${dir.path}/queue.json');
    final data = <Map<String, dynamic>>[
      for (final q in _queue) _PersistedQueueEntry(entry: q, paused: false).toJson(),
      for (final q in _paused.values)
        _PersistedQueueEntry(entry: q, paused: true).toJson(),
    ];
    await queueFile.writeAsString(jsonEncode(data));
  }

  Future<Directory> _downloadsDir() async {
    final prefs = ref.read(downloadPreferencesProvider);

    Directory? baseDir;
    if (Platform.isAndroid &&
        prefs.downloadLocation == DownloadLocation.external) {
      final externals = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (externals != null && externals.isNotEmpty) {
        baseDir = _pickBestExternal(externals);
      }
    }

    baseDir ??= await getApplicationDocumentsDirectory();

    final dir = Directory('${baseDir.path}/downloads');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Directory _pickBestExternal(List<Directory> dirs) {
    final writable = dirs.where((dir) {
      final path = dir.path;
      return !path.contains('/emulated/0/') && !path.contains('/data/user/0/');
    }).toList(growable: false);
    return writable.isNotEmpty ? writable.first : dirs.last;
  }
}

class _QueueEntry {
  _QueueEntry._({
    required this.itemId,
    required this.name,
    required this.kind,
    this.year,
    this.runTimeTicks,
    this.imageTag,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory _QueueEntry.movie(Movie m) {
    return _QueueEntry._(
      itemId: m.id,
      name: m.name,
      kind: DownloadedItemKind.movie,
      year: m.year,
      runTimeTicks: m.runTime?.inMicroseconds == null
          ? null
          : m.runTime!.inMicroseconds * 10,
      imageTag: m.imageTag,
    );
  }

  factory _QueueEntry.episode(
    Episode e, {
    required String seriesName,
    String? seriesPosterTag,
  }) {
    return _QueueEntry._(
      itemId: e.id,
      name: e.name,
      kind: DownloadedItemKind.episode,
      runTimeTicks: e.runTime?.inMicroseconds == null
          ? null
          : e.runTime!.inMicroseconds * 10,
      imageTag: seriesPosterTag ?? e.imageTag,
      seriesId: e.seriesId,
      seriesName: seriesName,
      seasonNumber: e.parentIndexNumber,
      episodeNumber: e.indexNumber,
    );
  }

  factory _QueueEntry.failure(DownloadFailure f) {
    return _QueueEntry._(
      itemId: f.itemId,
      name: f.name,
      kind: f.kind,
      year: f.year,
      runTimeTicks: f.runTimeTicks,
      imageTag: f.imageTag,
      seriesId: f.seriesId,
      seriesName: f.seriesName,
      seasonNumber: f.seasonNumber,
      episodeNumber: f.episodeNumber,
    );
  }

  factory _QueueEntry.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'] as String?;
    return _QueueEntry._(
      itemId: json['itemId'] as String,
      name: json['name'] as String,
      kind: rawKind == 'episode'
          ? DownloadedItemKind.episode
          : DownloadedItemKind.movie,
      year: json['year'] as int?,
      runTimeTicks: json['runTimeTicks'] as int?,
      imageTag: json['imageTag'] as String?,
      seriesId: json['seriesId'] as String?,
      seriesName: json['seriesName'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
    );
  }

  final String itemId;
  final String name;
  final DownloadedItemKind kind;
  final int? year;
  final int? runTimeTicks;
  final String? imageTag;
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'name': name,
    'kind': kind.name,
    if (year != null) 'year': year,
    if (runTimeTicks != null) 'runTimeTicks': runTimeTicks,
    if (imageTag != null) 'imageTag': imageTag,
    if (seriesId != null) 'seriesId': seriesId,
    if (seriesName != null) 'seriesName': seriesName,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
  };

  DownloadedItem toDownloadedItem({
    required String filePath,
    IntroSkipperTimestamps? introSkipper,
    List<DownloadedExternalSubtitle> externalSubtitles = const [],
  }) {
    return DownloadedItem(
      id: itemId,
      name: name,
      filePath: filePath,
      kind: kind,
      year: year,
      runTimeTicks: runTimeTicks,
      imageTag: imageTag,
      serverItemId: itemId,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      introStartTicks: _toTicks(introSkipper?.introduction?.start),
      introEndTicks: _toTicks(introSkipper?.introduction?.end),
      creditsStartTicks: _toTicks(introSkipper?.credits?.start),
      creditsEndTicks: _toTicks(introSkipper?.credits?.end),
      externalSubtitles: externalSubtitles,
    );
  }

  int? _toTicks(Duration? value) {
    if (value == null) return null;
    return value.inMicroseconds * 10;
  }

  DownloadProgress toProgress(
    double fraction, {
    int? downloadedBytes,
    int? totalBytes,
  }) => DownloadProgress(
    itemId: itemId,
    name: name,
    fraction: fraction,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    kind: kind,
    imageTag: imageTag,
    seriesId: seriesId,
    seriesName: seriesName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );

  DownloadFailure toFailure(String message) => DownloadFailure(
    itemId: itemId,
    name: name,
    message: message,
    kind: kind,
    year: year,
    runTimeTicks: runTimeTicks,
    imageTag: imageTag,
    seriesId: seriesId,
    seriesName: seriesName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
  );
}

class _DownloadBlockedException implements Exception {
  const _DownloadBlockedException(this.message);

  final String message;
}

class _PersistedQueueEntry {
  const _PersistedQueueEntry({required this.entry, required this.paused});

  final _QueueEntry entry;
  final bool paused;

  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'paused': paused,
  };

  factory _PersistedQueueEntry.fromJson(Map<String, dynamic> json) {
    final entryJson = Map<String, dynamic>.from(json['entry'] as Map);
    return _PersistedQueueEntry(
      entry: _QueueEntry.fromJson(entryJson),
      paused: json['paused'] == true,
    );
  }
}
