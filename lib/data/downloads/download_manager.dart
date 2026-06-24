import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';

import 'package:altcast/data/downloads/download_runtime.dart';
import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/episode.dart';
import 'package:altcast/data/jellyfin/models/intro_skipper_timestamps.dart';
import 'package:altcast/data/jellyfin/models/movie.dart';
import 'package:altcast/data/jellyfin/models/stream_source.dart';
import 'package:altcast/data/jellyfin/models/trickplay.dart';
import 'package:altcast/data/local/download_preferences.dart';
import 'package:altcast/data/local/notification_preferences.dart';
import 'package:altcast/data/notifications/app_notifications.dart';
import 'package:altcast/data/downloads/downloaded_item.dart';

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
  static const int _maxAutoRetries = 4;
  static const Duration _baseRetryDelay = Duration(seconds: 3);
  static const Duration _nativeTaskPollInterval = Duration(seconds: 1);
  static const String _nativeTaskPrefix = 'altcast-download-';
  final List<_QueueEntry> _queue = [];
  final Map<String, _QueueEntry> _paused = {};
  final Map<String, int> _retryAttempts = {};
  final Set<String> _runningNotificationShown = <String>{};
  final Set<String> _userCancelled = <String>{};
  bool _draining = false;
  DownloadTask? _activeDownloadTask;
  String? _activeItemId;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  @override
  DownloadsState build() {
    _bootstrap();
    ref.onDispose(() {
      _netSub?.cancel();
      final task = _activeDownloadTask;
      if (task != null) FileDownloader().cancel(task);
    });
    return const DownloadsState();
  }

  Future<void> _bootstrap() async {
    await DownloadRuntime.initialize();
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

  Future<bool> enqueueMovie(Movie movie) async {
    if (state.items.containsKey(movie.id) || state.isDownloading(movie.id)) {
      return false;
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
    return true;
  }

  Future<bool> enqueueEpisode(
    Episode episode, {
    required String seriesName,
    String? seriesPosterTag,
    bool autoQueuedNext = false,
  }) async {
    final entry = _QueueEntry.episode(
      episode,
      seriesName: seriesName,
      seriesPosterTag: seriesPosterTag,
      autoQueuedNext: autoQueuedNext,
    );
    return _enqueueEntries([entry]) > 0;
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
      _retryAttempts.remove(entry.itemId);
      _userCancelled.remove(entry.itemId);
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
    _userCancelled.add(itemId);
    _QueueEntry? cancelledEntry;
    for (final entry in [..._queue, ..._paused.values]) {
      if (entry.itemId == itemId) {
        cancelledEntry = entry;
        break;
      }
    }
    _queue.removeWhere((e) => e.itemId == itemId);
    if (_activeItemId == itemId) {
      final task = _activeDownloadTask;
      if (task != null) await FileDownloader().cancel(task);
    }
    await _forgetCancelledDownload(itemId, updateQueueLength: true);
    if (cancelledEntry != null) {
      await _showDownloadCanceledNotification(cancelledEntry);
    }
    await _persistQueue();
  }

  Future<void> pause(String itemId) async {
    final idx = _queue.indexWhere((e) => e.itemId == itemId);
    if (idx < 0) return;
    _paused[itemId] = _queue.removeAt(idx);
    if (_activeItemId == itemId) {
      final task = _activeDownloadTask;
      if (task != null) {
        final paused = await FileDownloader().pause(task);
        if (!paused) await FileDownloader().cancel(task);
      }
    }
    state = state.copyWith(
      queueLength: _queue.length,
      pausedIds: _paused.keys.toSet(),
    );
    await _persistQueue();
  }

  Future<void> resume(String itemId) async {
    final entry = _paused.remove(itemId);
    if (entry == null) return;
    _queue.add(entry);
    state = state.copyWith(
      queueLength: _queue.length,
      pausedIds: _paused.keys.toSet(),
    );
    await _persistQueue();
    _drain();
  }

  Future<void> retry(String itemId) async {
    final failure = state.failures[itemId];
    if (failure == null) return;
    final newFailures = Map<String, DownloadFailure>.from(state.failures)
      ..remove(itemId);
    state = state.copyWith(failures: newFailures);
    _retryAttempts.remove(itemId);
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
    final dir = await _downloadsDir();
    await _deleteDownloadedAssets(item);
    await _deleteResidualFiles(itemId, dir);
    final newItems = Map<String, DownloadedItem>.from(state.items)
      ..remove(itemId);
    _retryAttempts.remove(itemId);
    _runningNotificationShown.remove(itemId);
    _userCancelled.remove(itemId);
    state = state.copyWith(items: newItems);
    await _persist();
  }

  Future<void> deleteAll() async {
    final itemIdSet = <String>{
      ...state.items.keys,
      ...state.progress.keys,
      ...state.failures.keys,
      ..._queue.map((entry) => entry.itemId),
      ..._paused.keys,
      ?_activeItemId,
    };

    _queue.clear();
    _paused.clear();
    _retryAttempts.clear();
    _runningNotificationShown.clear();
    if (_activeItemId != null) {
      _userCancelled
        ..clear()
        ..add(_activeItemId!);
    } else {
      _userCancelled.clear();
    }
    final task = _activeDownloadTask;
    if (task != null) await FileDownloader().cancel(task);

    final dir = await _downloadsDir();
    for (final item in state.items.values) {
      await _deleteDownloadedAssets(item);
    }
    for (final itemId in itemIdSet) {
      await _deleteResidualFiles(itemId, dir);
    }

    state = state.copyWith(
      items: const {},
      progress: const {},
      failures: const {},
      queueLength: 0,
      pausedIds: const {},
    );
    await _persist();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final entry = _queue.first;
        final outcome = await _download(entry);
        switch (outcome.kind) {
          case _DownloadOutcomeKind.success:
          case _DownloadOutcomeKind.failed:
          case _DownloadOutcomeKind.cancelled:
            _queue.removeWhere((e) => e.itemId == entry.itemId);
            _retryAttempts.remove(entry.itemId);
            break;
          case _DownloadOutcomeKind.paused:
            _queue.removeWhere((e) => e.itemId == entry.itemId);
            break;
          case _DownloadOutcomeKind.retry:
            _queue.removeWhere((e) => e.itemId == entry.itemId);
            _queue.add(entry);
            await Future<void>.delayed(outcome.retryDelay ?? _baseRetryDelay);
            break;
        }
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

  Future<_DownloadOutcome> _download(_QueueEntry entry) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final sidecarSubs = await _resolveExternalSubs(entry.itemId);
    final dir = await _downloadsDir();
    final finalPath = '${dir.path}/${entry.itemId}.video';
    final url = await _resolveDownloadUrl(repo, entry.itemId);

    final task = DownloadTask(
      taskId: _nativeTaskId(entry.itemId),
      url: url,
      filename: '${entry.itemId}.video',
      directory: dir.path,
      baseDirectory: BaseDirectory.root,
      displayName: entry.displayLabel,
      metaData: entry.itemId,
      updates: Updates.statusAndProgress,
      requiresWiFi: ref.read(downloadPreferencesProvider).wifiOnlyDownloads,
      retries: _maxAutoRetries,
      allowPause: true,
      priority: 3,
    );

    _activeDownloadTask = task;
    _activeItemId = entry.itemId;

    try {
      if (File(finalPath).existsSync()) {
        return _finishDownloadedVideo(
          entry: entry,
          finalPath: finalPath,
          sidecarSubs: sidecarSubs,
          dir: dir,
        );
      }

      await _configureNotificationsForTask(task);
      await _guardDownloadNetwork();
      await _guardFreeSpace(minBytes: 200 * 1024 * 1024);
      await _watchNetworkPolicy();

      final existingRecord = await FileDownloader().database.recordForId(
        task.taskId,
      );
      final activeTask = await FileDownloader().taskForId(task.taskId);
      final TaskStatusUpdate result;
      if (activeTask is DownloadTask &&
          _shouldReattachToTask(existingRecord?.status)) {
        _activeDownloadTask = activeTask;
        await _configureNotificationsForTask(activeTask);
        result = await _waitForExistingNativeTask(
          entry: entry,
          task: activeTask,
          finalPath: finalPath,
        );
      } else {
        if (activeTask != null ||
            (existingRecord != null &&
                !_isReattachableStatus(existingRecord.status))) {
          await _forgetNativeDownloadState(entry.itemId);
        }
        result = await FileDownloader().download(
          task,
          onStatus: (status) => _handleNativeDownloadStatus(entry, status),
          onProgress: (progress) {
            _handleNativeDownloadProgress(entry, progress);
          },
          onElapsedTime: (_) => _markDownloadRunning(entry),
          elapsedTimeInterval: const Duration(seconds: 1),
        );
      }

      switch (result.status) {
        case TaskStatus.complete:
          break;
        case TaskStatus.paused:
          _paused.putIfAbsent(entry.itemId, () => entry);
          await _showDownloadPausedNotification(entry);
          return const _DownloadOutcome.paused();
        case TaskStatus.canceled:
          await _forgetCancelledDownload(entry.itemId);
          await _showDownloadCanceledNotification(entry);
          return const _DownloadOutcome.cancelled();
        case TaskStatus.notFound:
          const message = 'Server returned HTTP 404.';
          state = state.copyWith(
            progress: Map<String, DownloadProgress>.from(state.progress)
              ..remove(entry.itemId),
            failures: {
              ...state.failures,
              entry.itemId: entry.toFailure(message),
            },
          );
          _runningNotificationShown.remove(entry.itemId);
          await _showDownloadFailedNotification(entry, message);
          return const _DownloadOutcome.failed();
        case TaskStatus.failed:
          throw result;
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          throw result;
      }

      final taskPath = await task.filePath();
      if (taskPath != finalPath) {
        final downloadedFile = File(taskPath);
        if (downloadedFile.existsSync()) {
          try {
            await downloadedFile.rename(finalPath);
          } catch (_) {
            await downloadedFile.copy(finalPath);
            await downloadedFile.delete();
          }
        }
      }

      return _finishDownloadedVideo(
        entry: entry,
        finalPath: finalPath,
        sidecarSubs: sidecarSubs,
        dir: dir,
      );
    } catch (e) {
      final paused = _paused.containsKey(entry.itemId);
      final cancelledByUser = _userCancelled.remove(entry.itemId);
      final newProgress = Map<String, DownloadProgress>.from(state.progress);
      if (!paused) {
        newProgress.remove(entry.itemId);
      }
      if (paused) {
        state = state.copyWith(progress: newProgress);
        await _showDownloadPausedNotification(entry);
        return const _DownloadOutcome.paused();
      }
      if (cancelledByUser) {
        await _forgetCancelledDownload(entry.itemId);
        await _showDownloadCanceledNotification(entry);
        return const _DownloadOutcome.cancelled();
      }

      if (_shouldAutoRetry(e)) {
        final attempt = (_retryAttempts[entry.itemId] ?? 0) + 1;
        _retryAttempts[entry.itemId] = attempt;
        final blockedByPolicyOrOffline = e is _DownloadBlockedException;
        if (blockedByPolicyOrOffline || attempt <= _maxAutoRetries) {
          state = state.copyWith(
            progress: {...state.progress, entry.itemId: entry.toProgress(-1)},
          );
          return _DownloadOutcome.retry(
            retryDelay: _retryDelayForAttempt(attempt),
          );
        }
      }

      state = state.copyWith(
        progress: newProgress,
        failures: {
          ...state.failures,
          entry.itemId: entry.toFailure(_downloadFailureMessage(e)),
        },
      );
      _runningNotificationShown.remove(entry.itemId);
      await _showDownloadFailedNotification(entry, _downloadFailureMessage(e));
      return const _DownloadOutcome.failed();
    } finally {
      _activeItemId = null;
      _activeDownloadTask = null;
      await _netSub?.cancel();
      _netSub = null;
    }
  }

  String _nativeTaskId(String itemId) => '$_nativeTaskPrefix$itemId';

  bool _isReattachableStatus(TaskStatus status) {
    return switch (status) {
      TaskStatus.enqueued ||
      TaskStatus.running ||
      TaskStatus.waitingToRetry => true,
      TaskStatus.complete ||
      TaskStatus.paused ||
      TaskStatus.canceled ||
      TaskStatus.failed ||
      TaskStatus.notFound => false,
    };
  }

  bool _shouldReattachToTask(TaskStatus? status) =>
      status != null && _isReattachableStatus(status);

  Future<TaskStatusUpdate> _waitForExistingNativeTask({
    required _QueueEntry entry,
    required DownloadTask task,
    required String finalPath,
  }) async {
    while (true) {
      if (File(finalPath).existsSync()) {
        _handleNativeDownloadProgress(entry, 1);
        return TaskStatusUpdate(task, TaskStatus.complete);
      }

      final record = await FileDownloader().database.recordForId(task.taskId);
      if (record != null) {
        _handleNativeDownloadStatus(entry, record.status);
        _handleNativeDownloadProgress(entry, record.progress);
        if (record.status.isFinalState) {
          return TaskStatusUpdate(
            task,
            record.status,
            record.exception,
            null,
            null,
            record.exception is TaskHttpException
                ? (record.exception as TaskHttpException).httpResponseCode
                : null,
          );
        }
      }

      final stillActive = await FileDownloader().taskForId(task.taskId);
      if (stillActive == null && record == null) {
        return TaskStatusUpdate(
          task,
          TaskStatus.failed,
          TaskException('Native download task disappeared.'),
        );
      }

      await Future<void>.delayed(_nativeTaskPollInterval);
    }
  }

  void _handleNativeDownloadStatus(_QueueEntry entry, TaskStatus status) {
    if (!state.progress.containsKey(entry.itemId)) return;
    if (status == TaskStatus.enqueued || status == TaskStatus.waitingToRetry) {
      state = state.copyWith(
        progress: {...state.progress, entry.itemId: entry.toProgress(0)},
      );
    } else if (status == TaskStatus.running) {
      _markDownloadRunning(entry);
    }
  }

  void _markDownloadRunning(_QueueEntry entry) {
    final existing = state.progress[entry.itemId];
    if (existing == null) return;
    if (existing.fraction <= 0) {
      state = state.copyWith(
        progress: {
          ...state.progress,
          entry.itemId: existing.copyWithFraction(-1),
        },
      );
    }
    if (_runningNotificationShown.add(entry.itemId)) {
      unawaited(_showDownloadRunningNotification(entry));
    }
  }

  void _handleNativeDownloadProgress(_QueueEntry entry, double progress) {
    if (progress < 0) return;
    final existing = state.progress[entry.itemId];
    if (existing == null) return;
    state = state.copyWith(
      progress: {
        ...state.progress,
        entry.itemId: existing.copyWithFraction(progress),
      },
    );
  }

  Future<_DownloadOutcome> _finishDownloadedVideo({
    required _QueueEntry entry,
    required String finalPath,
    required List<ExternalSubtitle> sidecarSubs,
    required Directory dir,
  }) async {
    final downloadedSubs = await _downloadExternalSubs(
      itemId: entry.itemId,
      subs: sidecarSubs,
      dir: dir,
    );
    final offlineTrickplay = await _downloadOfflineTrickplay(
      itemId: entry.itemId,
      dir: dir,
    );
    final skipper = await _resolveIntroSkipperTimestamps(entry.itemId);
    final downloaded = entry.toDownloadedItem(
      filePath: finalPath,
      introSkipper: skipper,
      externalSubtitles: downloadedSubs,
      offlineTrickplay: offlineTrickplay,
    );
    final newItems = {...state.items, downloaded.id: downloaded};
    final newProgress = Map<String, DownloadProgress>.from(state.progress)
      ..remove(entry.itemId);
    state = state.copyWith(items: newItems, progress: newProgress);
    await _persist();
    _retryAttempts.remove(entry.itemId);
    _userCancelled.remove(entry.itemId);
    _runningNotificationShown.remove(entry.itemId);
    await _deleteNativeTaskRecord(entry.itemId);
    await _showDownloadCompleteNotification(entry);

    _maybeAutoDownloadNext(entry);
    return const _DownloadOutcome.success();
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
        final task = _activeDownloadTask;
        if (task != null) FileDownloader().pause(task);
      }
    });
  }

  Future<void> _configureNotificationsForTask(DownloadTask task) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }

    await AppNotifications.configureDownloadTaskNotifications(task);
    unawaited(
      AppNotifications.requestDownloadPermissions().catchError((_) => false),
    );
  }

  Future<void> _showDownloadCompleteNotification(_QueueEntry entry) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }
    await AppNotifications.showDownloadComplete(
      itemId: entry.itemId,
      title: entry.displayLabel,
    );
  }

  Future<void> _showDownloadRunningNotification(_QueueEntry entry) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }
    await AppNotifications.showDownloadRunning(
      itemId: entry.itemId,
      title: entry.displayLabel,
    );
  }

  Future<void> _showDownloadPausedNotification(_QueueEntry entry) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }
    await AppNotifications.showDownloadPaused(
      itemId: entry.itemId,
      title: entry.displayLabel,
    );
  }

  Future<void> _showDownloadCanceledNotification(_QueueEntry entry) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }
    await AppNotifications.showDownloadCanceled(
      itemId: entry.itemId,
      title: entry.displayLabel,
    );
  }

  Future<void> _showDownloadFailedNotification(
    _QueueEntry entry,
    String message,
  ) async {
    if (!ref.read(notificationPreferencesProvider).shouldNotifyDownloads) {
      return;
    }
    await AppNotifications.showDownloadFailed(
      itemId: entry.itemId,
      title: entry.displayLabel,
      message: message,
    );
  }

  Future<String> _resolveDownloadUrl(
    JellyfinRepository repo,
    String itemId,
  ) async {
    final prefs = ref.read(downloadPreferencesProvider);
    final bitrate = prefs.offlineVideoQuality.maxBitrate;
    if (bitrate == null) {
      return repo.streamUrl(itemId, staticStream: true);
    }
    return repo.streamUrl(itemId, staticStream: false, maxBitrate: bitrate);
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

  Future<void> _forgetCancelledDownload(
    String itemId, {
    bool updateQueueLength = false,
  }) async {
    final newProgress = Map<String, DownloadProgress>.from(state.progress)
      ..remove(itemId);
    _paused.remove(itemId);
    _retryAttempts.remove(itemId);
    _userCancelled.remove(itemId);
    _runningNotificationShown.remove(itemId);
    state = state.copyWith(
      progress: newProgress,
      queueLength: updateQueueLength ? _queue.length : state.queueLength,
      pausedIds: _paused.keys.toSet(),
    );
    await _cleanupPartial(itemId);
    await _forgetNativeDownloadState(itemId);
  }

  Future<void> _cleanupPartial(String itemId) async {
    final dir = await _downloadsDir();
    final f = File('${dir.path}/$itemId.partial');
    if (f.existsSync()) await f.delete();
    if (state.items.containsKey(itemId)) return;
    final video = File('${dir.path}/$itemId.video');
    if (video.existsSync()) await video.delete();
  }

  Future<void> _deleteNativeTaskRecord(String itemId) async {
    try {
      await FileDownloader().database.deleteRecordWithId(_nativeTaskId(itemId));
    } catch (_) {}
  }

  Future<void> _forgetNativeDownloadState(String itemId) async {
    final taskId = _nativeTaskId(itemId);
    try {
      await FileDownloader().cancelTaskWithId(taskId);
    } catch (_) {}
    await _deleteNativeTaskRecord(itemId);
  }

  Future<void> _deleteDownloadedAssets(DownloadedItem item) async {
    try {
      final f = File(item.filePath);
      if (f.existsSync()) await f.delete();
      for (final sub in item.externalSubtitles) {
        final sf = File(sub.filePath);
        if (sf.existsSync()) await sf.delete();
      }
      if (item.offlineTrickplay != null) {
        for (final p in item.offlineTrickplay!.tileFilesByIndex.values) {
          final tf = File(p);
          if (tf.existsSync()) await tf.delete();
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteResidualFiles(String itemId, Directory dir) async {
    final prefix = '$itemId.';
    try {
      for (final entity in dir.listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name != itemId && !name.startsWith(prefix)) continue;
        try {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
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
            isForced: sub.isForced,
            isHearingImpaired: sub.isHearingImpaired,
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

  Future<OfflineTrickplayData?> _downloadOfflineTrickplay({
    required String itemId,
    required Directory dir,
  }) async {
    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final session = await repo.getTrickplaySession(itemId);
      if (session == null) return null;
      final tileCount = session.manifest.tileCount;
      if (tileCount <= 0) return null;

      final trickDir = Directory('${dir.path}/$itemId.trickplay');
      if (!trickDir.existsSync()) {
        await trickDir.create(recursive: true);
      }

      final downloaded = <int, String>{};
      final dio = Dio();
      for (var i = 0; i < tileCount; i++) {
        final urls = session.tileUrlsForIndex(i);
        if (urls.isEmpty) continue;
        List<int>? bytes;
        for (final url in urls) {
          try {
            final res = await dio.get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes),
            );
            final data = res.data;
            if (data != null && data.isNotEmpty) {
              bytes = data;
              break;
            }
          } catch (_) {}
        }
        if (bytes == null) continue;
        final path = '${trickDir.path}/$i.jpg';
        await File(path).writeAsBytes(bytes, flush: true);
        downloaded[i] = path;
      }
      if (downloaded.isEmpty) return null;

      return OfflineTrickplayData(
        manifest: session.manifest,
        tileFilesByIndex: downloaded,
      );
    } catch (_) {
      // Trickplay is optional. Video download should still succeed.
      return null;
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
    if (error is TaskStatusUpdate) {
      final status = error.responseStatusCode;
      final detail = error.exception?.description.trim();
      if (status != null && detail != null && detail.isNotEmpty) {
        return 'Server returned HTTP $status ($detail).';
      }
      if (status != null) return 'Server returned HTTP $status.';
      if (detail != null && detail.isNotEmpty) {
        return 'Download failed: $detail';
      }
      return 'Download failed with status ${error.status.name}.';
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Connection timed out.';
      }
      if (CancelToken.isCancel(error)) {
        return 'Download was interrupted.';
      }
      final status = error.response?.statusCode;
      if (status == 416) {
        return 'Resume failed, try re-downloading.';
      }
      final detail = error.error?.toString().trim();
      if (status != null && detail != null && detail.isNotEmpty) {
        return 'Server returned HTTP $status ($detail).';
      }
      if (status != null) return 'Server returned HTTP $status.';
      if (detail != null && detail.isNotEmpty) {
        return 'Network error: $detail';
      }
      return 'Network error while downloading.';
    }
    return 'Download failed: $error';
  }

  bool _shouldAutoRetry(Object error) {
    if (error is _DownloadBlockedException) return true;
    if (error is TaskStatusUpdate) {
      if (error.status == TaskStatus.notFound) return false;
      if (error.status == TaskStatus.failed) {
        final status = error.responseStatusCode;
        if (status == null) return true;
        if (status >= 500) return true;
        return status == 429 || status == 408 || status == 409;
      }
      return error.status == TaskStatus.canceled;
    }
    if (error is DioException) {
      if (CancelToken.isCancel(error)) return true;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        return true;
      }
      final status = error.response?.statusCode;
      if (status == null) return true;
      if (status >= 500) return true;
      if (status == 429 || status == 408 || status == 409) return true;
      if (status == 416) return true;
    }
    return false;
  }

  Duration _retryDelayForAttempt(int attempt) {
    final multiplier = attempt <= 1 ? 1 : (1 << (attempt - 1));
    final seconds = _baseRetryDelay.inSeconds * multiplier;
    final clamped = seconds.clamp(3, 60);
    return Duration(seconds: clamped);
  }

  Future<void> _maybeAutoDownloadNext(_QueueEntry entry) async {
    final prefs = ref.read(downloadPreferencesProvider);
    if (!prefs.autoDownloadNextEpisode) return;
    if (entry.kind != DownloadedItemKind.episode) return;
    if (entry.autoQueuedNext) return;

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
          autoQueuedNext: true,
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
      for (final q in _queue)
        _PersistedQueueEntry(entry: q, paused: false).toJson(),
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
    final writable = dirs
        .where((dir) {
          final path = dir.path;
          return !path.contains('/emulated/0/') &&
              !path.contains('/data/user/0/');
        })
        .toList(growable: false);
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
    this.autoQueuedNext = false,
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
    bool autoQueuedNext = false,
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
      autoQueuedNext: autoQueuedNext,
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
      autoQueuedNext: f.autoQueuedNext,
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
      autoQueuedNext: json['autoQueuedNext'] as bool? ?? false,
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
  final bool autoQueuedNext;

  String get displayLabel {
    if (kind != DownloadedItemKind.episode) return name;
    final show = seriesName == null || seriesName!.isEmpty
        ? 'Episode'
        : seriesName!;
    final season = seasonNumber;
    final episode = episodeNumber;
    if (season == null || episode == null) return '$show - $name';
    return '$show - S$season E${episode.toString().padLeft(2, '0')}';
  }

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
    if (autoQueuedNext) 'autoQueuedNext': true,
  };

  DownloadedItem toDownloadedItem({
    required String filePath,
    IntroSkipperTimestamps? introSkipper,
    List<DownloadedExternalSubtitle> externalSubtitles = const [],
    OfflineTrickplayData? offlineTrickplay,
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
      offlineTrickplay: offlineTrickplay,
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
    autoQueuedNext: autoQueuedNext,
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

  Map<String, dynamic> toJson() => {'entry': entry.toJson(), 'paused': paused};

  factory _PersistedQueueEntry.fromJson(Map<String, dynamic> json) {
    final entryJson = Map<String, dynamic>.from(json['entry'] as Map);
    return _PersistedQueueEntry(
      entry: _QueueEntry.fromJson(entryJson),
      paused: json['paused'] == true,
    );
  }
}

enum _DownloadOutcomeKind { success, paused, cancelled, retry, failed }

class _DownloadOutcome {
  const _DownloadOutcome._(this.kind, {this.retryDelay});

  const _DownloadOutcome.success() : this._(_DownloadOutcomeKind.success);
  const _DownloadOutcome.paused() : this._(_DownloadOutcomeKind.paused);
  const _DownloadOutcome.cancelled() : this._(_DownloadOutcomeKind.cancelled);
  const _DownloadOutcome.failed() : this._(_DownloadOutcomeKind.failed);
  const _DownloadOutcome.retry({Duration? retryDelay})
    : this._(_DownloadOutcomeKind.retry, retryDelay: retryDelay);

  final _DownloadOutcomeKind kind;
  final Duration? retryDelay;
}
