import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

const _watchHistoryFileName = 'watch_history_v1.json';

final watchHistoryStoreProvider = Provider<WatchHistoryStore>((ref) {
  return WatchHistoryStore();
});

class WatchHistoryStore {
  WatchHistoryStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<List<WatchHistoryEntry>> read(JellyfinSession session) async {
    final profiles = await _readProfiles();
    return profiles[_profileKey(session)] ?? const <WatchHistoryEntry>[];
  }

  Future<void> write(
    JellyfinSession session,
    Iterable<WatchHistoryEntry> entries,
  ) async {
    final profiles = await _readProfiles();
    final sorted = entries.toList(growable: false)..sort(_newestFirst);
    profiles[_profileKey(session)] = sorted;

    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'profiles': profiles.map(
          (key, value) => MapEntry(
            key,
            value.map((entry) => entry.toJson()).toList(growable: false),
          ),
        ),
      }),
      flush: true,
    );
  }

  Future<Map<String, List<WatchHistoryEntry>>> _readProfiles() async {
    final file = await _file();
    if (!await file.exists()) {
      return <String, List<WatchHistoryEntry>>{};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return <String, List<WatchHistoryEntry>>{};
      }
      final rawProfiles = decoded['profiles'];
      if (rawProfiles is! Map<String, dynamic>) {
        return <String, List<WatchHistoryEntry>>{};
      }
      return rawProfiles.map((key, value) {
        final entries = value is List
            ? value
                  .whereType<Map>()
                  .map(
                    (entry) => WatchHistoryEntry.fromJson(
                      Map<String, dynamic>.from(entry),
                    ),
                  )
                  .toList()
            : <WatchHistoryEntry>[];
        entries.sort(_newestFirst);
        return MapEntry(key, entries);
      });
    } catch (_) {
      return <String, List<WatchHistoryEntry>>{};
    }
  }

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_watchHistoryFileName');
  }

  String _profileKey(JellyfinSession session) =>
      '${session.serverId}:${session.userId}';
}

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.id,
    required this.name,
    required this.kind,
    this.subtitle,
    this.imageTag,
    this.backdropTag,
    this.year,
    this.seriesId,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.watchedAt,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final MediaKind kind;
  final String? subtitle;
  final String? imageTag;
  final String? backdropTag;
  final int? year;
  final String? seriesId;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final DateTime? watchedAt;
  final bool isAvailable;

  factory WatchHistoryEntry.fromBrowseItem(BrowseItem item) {
    return WatchHistoryEntry(
      id: item.id,
      name: item.name,
      kind: item.kind,
      subtitle: item.subtitle,
      imageTag: item.imageTag,
      backdropTag: item.backdropTag,
      year: item.year,
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      watchedAt: item.userData?.lastPlayedDate,
    );
  }

  WatchHistoryEntry copyWith({bool? isAvailable}) {
    return WatchHistoryEntry(
      id: id,
      name: name,
      kind: kind,
      subtitle: subtitle,
      imageTag: imageTag,
      backdropTag: backdropTag,
      year: year,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      watchedAt: watchedAt,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  BrowseItem toBrowseItem() {
    return BrowseItem(
      id: id,
      name: name,
      kind: kind,
      subtitle: subtitle,
      imageTag: imageTag,
      backdropTag: backdropTag,
      year: year,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      userData: UserData(played: true, lastPlayedDate: watchedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (subtitle != null) 'subtitle': subtitle,
    if (imageTag != null) 'imageTag': imageTag,
    if (backdropTag != null) 'backdropTag': backdropTag,
    if (year != null) 'year': year,
    if (seriesId != null) 'seriesId': seriesId,
    if (seriesName != null) 'seriesName': seriesName,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
    if (watchedAt != null) 'watchedAt': watchedAt!.toIso8601String(),
    'isAvailable': isAvailable,
  };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WatchHistoryEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      kind: MediaKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => MediaKind.movie,
      ),
      subtitle: json['subtitle'] as String?,
      imageTag: json['imageTag'] as String?,
      backdropTag: json['backdropTag'] as String?,
      year: json['year'] as int?,
      seriesId: json['seriesId'] as String?,
      seriesName: json['seriesName'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      watchedAt: DateTime.tryParse(json['watchedAt'] as String? ?? ''),
      isAvailable: json['isAvailable'] as bool? ?? true,
    );
  }
}

int _newestFirst(WatchHistoryEntry a, WatchHistoryEntry b) {
  final aDate = a.watchedAt;
  final bDate = b.watchedAt;
  if (aDate == null && bDate == null) return a.name.compareTo(b.name);
  if (aDate == null) return 1;
  if (bDate == null) return -1;
  return bDate.compareTo(aDate);
}

List<WatchHistoryEntry> mergeWatchHistory(
  Iterable<WatchHistoryEntry> cached,
  Iterable<BrowseItem> live,
) {
  final byId = <String, WatchHistoryEntry>{
    for (final entry in cached) entry.id: entry,
  };
  for (final item in live) {
    byId[item.id] = WatchHistoryEntry.fromBrowseItem(item);
  }
  final merged = byId.values.toList()..sort(_newestFirst);
  return merged;
}
