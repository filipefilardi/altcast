import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../jellyfin/jellyfin_repository.dart';
import '../jellyfin/models/episode.dart';
import '../jellyfin/models/movie.dart';
import 'downloaded_item.dart';

/// Snapshot of the offline library + in-flight downloads.
class DownloadsState {
  const DownloadsState({
    this.items = const {},
    this.progress = const {},
    this.queueLength = 0,
    this.bootstrapped = false,
  });

  /// All completed downloads, keyed by Jellyfin item id.
  final Map<String, DownloadedItem> items;

  /// Active download progress, keyed by Jellyfin item id. An entry here
  /// means the file is downloading right now or queued.
  final Map<String, DownloadProgress> progress;

  /// Total queue size, including the in-flight item.
  final int queueLength;

  /// True once we've read the manifest off disk at least once. Useful so the
  /// downloads screen can distinguish "no downloads yet" from "still loading".
  final bool bootstrapped;

  DownloadsState copyWith({
    Map<String, DownloadedItem>? items,
    Map<String, DownloadProgress>? progress,
    int? queueLength,
    bool? bootstrapped,
  }) {
    return DownloadsState(
      items: items ?? this.items,
      progress: progress ?? this.progress,
      queueLength: queueLength ?? this.queueLength,
      bootstrapped: bootstrapped ?? this.bootstrapped,
    );
  }

  /// Local file path for [itemId] if it's already downloaded — used by the
  /// player to skip the network round-trip.
  String? localPath(String itemId) => items[itemId]?.filePath;

  /// True when [itemId] is downloading right now (in queue or in flight).
  bool isDownloading(String itemId) => progress.containsKey(itemId);
}

final downloadManagerProvider =
    NotifierProvider<DownloadManager, DownloadsState>(DownloadManager.new);

/// Owns the queue, drives downloads sequentially, and persists the manifest
/// so downloads survive app restarts.
///
/// Single-flight by design — one Dio download at a time. Trying to pull
/// multiple in parallel is a footgun for both server load and end-user
/// throughput, and the UX rarely benefits.
class DownloadManager extends Notifier<DownloadsState> {
  final List<_QueueEntry> _queue = [];
  bool _draining = false;
  CancelToken? _activeCancel;

  @override
  DownloadsState build() {
    _bootstrap();
    return const DownloadsState();
  }

  Future<void> _bootstrap() async {
    final dir = await _downloadsDir();
    final manifest = File('${dir.path}/manifest.json');
    if (!manifest.existsSync()) {
      state = state.copyWith(bootstrapped: true);
      return;
    }
    try {
      final raw = await manifest.readAsString();
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final loaded = <String, DownloadedItem>{};
      for (final json in list) {
        final item = DownloadedItem.fromJson(json);
        // Drop entries whose file vanished — keeps the manifest honest.
        if (File(item.filePath).existsSync()) {
          loaded[item.id] = item;
        }
      }
      state = state.copyWith(items: loaded, bootstrapped: true);
    } catch (_) {
      // Corrupted manifest — start clean rather than crash the app.
      state = state.copyWith(bootstrapped: true);
    }
  }

  /// Enqueue a movie for offline use. No-op if already downloaded or in queue.
  Future<void> enqueueMovie(Movie movie) async {
    if (state.items.containsKey(movie.id)) return;
    if (state.isDownloading(movie.id)) return;
    final entry = _QueueEntry.movie(movie);
    _queue.add(entry);
    state = state.copyWith(
      progress: {...state.progress, movie.id: entry.toProgress(0)},
      queueLength: state.queueLength + 1,
    );
    _drain();
  }

  /// Enqueue a single episode. [seriesName] is required so the downloads list
  /// can render "{Series} · S1·E03" instead of just the episode title.
  Future<void> enqueueEpisode(
    Episode episode, {
    required String seriesName,
    String? seriesPosterTag,
  }) async {
    if (state.items.containsKey(episode.id)) return;
    if (state.isDownloading(episode.id)) return;
    final entry = _QueueEntry.episode(
      episode,
      seriesName: seriesName,
      seriesPosterTag: seriesPosterTag,
    );
    _queue.add(entry);
    state = state.copyWith(
      progress: {...state.progress, episode.id: entry.toProgress(0)},
      queueLength: state.queueLength + 1,
    );
    _drain();
  }

  /// Cancel a running or queued download.
  Future<void> cancel(String itemId) async {
    _queue.removeWhere((e) => e.itemId == itemId);
    if (_queue.isEmpty || _queue.first.itemId == itemId) {
      _activeCancel?.cancel('Cancelled by user');
    }
    final newProgress = Map<String, DownloadProgress>.from(state.progress)
      ..remove(itemId);
    state = state.copyWith(
      progress: newProgress,
      queueLength: state.queueLength > 0 ? state.queueLength - 1 : 0,
    );
  }

  /// Delete a completed download from disk and the manifest.
  Future<void> delete(String itemId) async {
    final item = state.items[itemId];
    if (item == null) return;
    try {
      final f = File(item.filePath);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Ignore — manifest update is the source of truth either way.
    }
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
      }
    } finally {
      _draining = false;
      // Reset queueLength once it drains so the UI can clear any "downloading
      // 1 of 2" hints if we add them later.
      state = state.copyWith(queueLength: 0);
    }
  }

  Future<void> _download(_QueueEntry entry) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final url = repo.streamUrl(entry.itemId);
    final dir = await _downloadsDir();
    final tempPath = '${dir.path}/${entry.itemId}.partial';
    final finalPath = '${dir.path}/${entry.itemId}.video';
    _activeCancel = CancelToken();

    try {
      await Dio().download(
        url,
        tempPath,
        cancelToken: _activeCancel,
        options: Options(
          followRedirects: true,
          // Token already in the URL; no auth header needed for download.
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final pct = received / total;
          final existing = state.progress[entry.itemId];
          if (existing == null) return;
          state = state.copyWith(
            progress: {
              ...state.progress,
              entry.itemId: existing.copyWithFraction(pct),
            },
          );
        },
      );

      // Move into place atomically — if the rename fails (e.g. cross-device)
      // copy + delete instead.
      final tempFile = File(tempPath);
      try {
        await tempFile.rename(finalPath);
      } catch (_) {
        await tempFile.copy(finalPath);
        await tempFile.delete();
      }

      final downloaded = entry.toDownloadedItem(filePath: finalPath);
      final newItems = {...state.items, downloaded.id: downloaded};
      final newProgress = Map<String, DownloadProgress>.from(state.progress)
        ..remove(entry.itemId);
      state = state.copyWith(items: newItems, progress: newProgress);
      await _persist();
    } catch (e) {
      // Cancellations and errors both land here — clean up either way.
      try {
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) await tempFile.delete();
      } catch (_) {}
      final newProgress = Map<String, DownloadProgress>.from(state.progress)
        ..remove(entry.itemId);
      state = state.copyWith(progress: newProgress);
    } finally {
      _activeCancel = null;
    }
  }

  Future<void> _persist() async {
    final dir = await _downloadsDir();
    final manifest = File('${dir.path}/manifest.json');
    final list = state.items.values.map((i) => i.toJson()).toList();
    await manifest.writeAsString(jsonEncode(list));
  }

  Future<Directory> _downloadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/downloads');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
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
      // Prefer the series poster — the per-episode primary image is a still,
      // not a portrait poster, so it looks wrong in the downloads list.
      imageTag: seriesPosterTag ?? e.imageTag,
      seriesId: e.seriesId,
      seriesName: seriesName,
      seasonNumber: e.parentIndexNumber,
      episodeNumber: e.indexNumber,
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

  DownloadedItem toDownloadedItem({required String filePath}) {
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
    );
  }

  DownloadProgress toProgress(double fraction) => DownloadProgress(
        itemId: itemId,
        name: name,
        fraction: fraction,
        kind: kind,
        imageTag: imageTag,
        seriesId: seriesId,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
}
