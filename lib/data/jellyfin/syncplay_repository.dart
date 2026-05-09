import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'jellyfin_api.dart';
import 'models/syncplay.dart';

final syncPlayRepositoryProvider = Provider<SyncPlayRepository>((ref) {
  return SyncPlayRepository(ref.watch(jellyfinApiProvider));
});

class SyncPlayRepository {
  SyncPlayRepository(this._api);

  final JellyfinApi _api;

  String? get username => _api.session?.username;

  Future<List<SyncPlayGroup>> listGroups() async {
    final res = await _api.dio.get<List<dynamic>>('/SyncPlay/List');
    return (res.data ?? const [])
        .whereType<Map>()
        .map((m) => SyncPlayGroup.fromJson(Map<String, dynamic>.from(m)))
        .where((g) => g.id.isNotEmpty && g.participants.isNotEmpty)
        .toList();
  }

  Future<void> createGroup(String groupName) {
    final safeName = groupName.trim().isEmpty ? 'AltCast group' : groupName;
    final truncatedName = safeName.substring(
      0,
      safeName.length > 80 ? 80 : safeName.length,
    );
    return _post('/SyncPlay/New', data: {'GroupName': truncatedName});
  }

  Future<void> joinGroup(String groupId) {
    return _post('/SyncPlay/Join', data: {'GroupId': groupId});
  }

  Future<void> leaveGroup() => _post('/SyncPlay/Leave');

  Future<void> setCurrentVideo(
    String itemId, {
    Duration startPosition = Duration.zero,
  }) {
    if (itemId.isEmpty) return Future.value();
    return _post(
      '/SyncPlay/SetNewQueue',
      data: {
        'PlayingQueue': [itemId],
        'PlayingItemPosition': 0,
        'StartPositionTicks': durationToJellyfinTicks(startPosition),
      },
    );
  }

  Future<void> pause() => _post('/SyncPlay/Pause');
  Future<void> unpause() => _post('/SyncPlay/Unpause');
  Future<void> stop() => _post('/SyncPlay/Stop');

  Future<void> seek(Duration position) {
    return _post(
      '/SyncPlay/Seek',
      data: {'PositionTicks': durationToJellyfinTicks(position)},
    );
  }

  Future<void> ready({
    required String playlistItemId,
    required Duration position,
    required bool isPlaying,
  }) {
    if (playlistItemId.isEmpty) return Future.value();
    return _post(
      '/SyncPlay/Ready',
      data: {
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': durationToJellyfinTicks(position),
        'IsPlaying': isPlaying,
        'PlaylistItemId': playlistItemId,
      },
    );
  }

  Future<void> _post(String path, {Object? data}) async {
    final response = await _api.dio.post<void>(path, data: data);
    if (kDebugMode && path != '/SyncPlay/Ready') {
      debugPrint('[SyncPlay] POST $path -> ${response.statusCode}');
    }
  }
}
