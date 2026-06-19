import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';
import 'package:altcast/data/local/secure_storage.dart';

const _libraryActivityStateKey = 'library_activity_state_v1';
const _maxRememberedIds = 200;
const currentLibrarySnapshotVersion = 2;

final libraryActivityStoreProvider = Provider<LibraryActivityStore>((ref) {
  return LibraryActivityStore(ref.watch(secureStorageProvider));
});

class LibraryActivityStore {
  const LibraryActivityStore(this._storage);

  final SecureStorage _storage;

  Future<LibraryActivityProfile> readProfile(JellyfinSession session) async {
    final state = await _readState();
    return state[_profileKey(session)] ?? const LibraryActivityProfile();
  }

  Future<void> writeProfile(
    JellyfinSession session,
    LibraryActivityProfile profile,
  ) async {
    final state = await _readState();
    state[_profileKey(session)] = profile.trimmed();
    await _storage.write(
      _libraryActivityStateKey,
      jsonEncode({
        'profiles': state.map((key, value) => MapEntry(key, value.toJson())),
      }),
    );
  }

  Future<Map<String, LibraryActivityProfile>> _readState() async {
    final raw = await _storage.read(_libraryActivityStateKey);
    if (raw == null) return <String, LibraryActivityProfile>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final profiles = decoded['profiles'] as Map<String, dynamic>? ?? const {};
      return profiles.map((key, value) {
        return MapEntry(
          key,
          LibraryActivityProfile.fromJson(value as Map<String, dynamic>),
        );
      });
    } catch (_) {
      return <String, LibraryActivityProfile>{};
    }
  }

  String _profileKey(JellyfinSession session) {
    return '${session.serverId}:${session.userId}';
  }
}

class LibraryActivityProfile {
  const LibraryActivityProfile({
    this.initialized = false,
    this.snapshotVersion = currentLibrarySnapshotVersion,
    this.seenMovieIds = const <String>{},
    this.seenEpisodeIds = const <String>{},
  });

  final bool initialized;
  final int snapshotVersion;
  final Set<String> seenMovieIds;
  final Set<String> seenEpisodeIds;

  LibraryActivityProfile copyWith({
    bool? initialized,
    int? snapshotVersion,
    Set<String>? seenMovieIds,
    Set<String>? seenEpisodeIds,
  }) {
    return LibraryActivityProfile(
      initialized: initialized ?? this.initialized,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      seenMovieIds: seenMovieIds ?? this.seenMovieIds,
      seenEpisodeIds: seenEpisodeIds ?? this.seenEpisodeIds,
    );
  }

  LibraryActivityProfile mergeSeen({
    required Iterable<String> movieIds,
    required Iterable<String> episodeIds,
  }) {
    return copyWith(
      initialized: true,
      seenMovieIds: _trimIds([...movieIds, ...seenMovieIds]),
      seenEpisodeIds: _trimIds([...episodeIds, ...seenEpisodeIds]),
    );
  }

  LibraryActivityProfile trimmed() {
    return copyWith(
      seenMovieIds: _trimIds(seenMovieIds),
      seenEpisodeIds: _trimIds(seenEpisodeIds),
    );
  }

  Map<String, dynamic> toJson() => {
    'initialized': initialized,
    'snapshotVersion': snapshotVersion,
    'seenMovieIds': seenMovieIds.toList(growable: false),
    'seenEpisodeIds': seenEpisodeIds.toList(growable: false),
  };

  factory LibraryActivityProfile.fromJson(Map<String, dynamic> json) {
    return LibraryActivityProfile(
      initialized: json['initialized'] as bool? ?? false,
      snapshotVersion: json['snapshotVersion'] as int? ?? 1,
      seenMovieIds: _stringSet(json['seenMovieIds']),
      seenEpisodeIds: _stringSet(json['seenEpisodeIds']),
    );
  }

  static Set<String> _stringSet(Object? value) {
    if (value is! List) return <String>{};
    return value.whereType<String>().toSet();
  }

  static Set<String> _trimIds(Iterable<String> ids) {
    return ids
        .where((id) => id.trim().isNotEmpty)
        .take(_maxRememberedIds)
        .toSet();
  }
}
