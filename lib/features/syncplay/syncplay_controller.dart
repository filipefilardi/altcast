import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/models/syncplay.dart';
import '../../data/jellyfin/syncplay_repository.dart';
import 'syncplay_socket.dart';

final syncPlayControllerProvider =
    NotifierProvider<SyncPlayController, SyncPlayState>(SyncPlayController.new);

class SyncPlayState {
  const SyncPlayState({
    this.activeGroup,
    this.groups = const [],
    this.loading = false,
    this.connected = false,
    this.error,
    this.currentItemId,
    this.currentPlaylistItemId,
    this.queueEvent,
    this.commandEvent,
  });

  final SyncPlayGroup? activeGroup;
  final List<SyncPlayGroup> groups;
  final bool loading;
  final bool connected;
  final String? error;
  final String? currentItemId;
  final String? currentPlaylistItemId;
  final SyncPlayVideoQueueEvent? queueEvent;
  final SyncPlayVideoCommandEvent? commandEvent;

  bool get isActive => activeGroup != null;

  SyncPlayState copyWith({
    SyncPlayGroup? activeGroup,
    bool clearActiveGroup = false,
    List<SyncPlayGroup>? groups,
    bool? loading,
    bool? connected,
    String? error,
    bool clearError = false,
    String? currentItemId,
    bool clearCurrentItemId = false,
    String? currentPlaylistItemId,
    bool clearCurrentPlaylistItemId = false,
    SyncPlayVideoQueueEvent? queueEvent,
    SyncPlayVideoCommandEvent? commandEvent,
  }) {
    return SyncPlayState(
      activeGroup: clearActiveGroup ? null : activeGroup ?? this.activeGroup,
      groups: groups ?? this.groups,
      loading: loading ?? this.loading,
      connected: connected ?? this.connected,
      error: clearError ? null : error ?? this.error,
      currentItemId: clearCurrentItemId
          ? null
          : currentItemId ?? this.currentItemId,
      currentPlaylistItemId: clearCurrentPlaylistItemId
          ? null
          : currentPlaylistItemId ?? this.currentPlaylistItemId,
      queueEvent: queueEvent ?? this.queueEvent,
      commandEvent: commandEvent ?? this.commandEvent,
    );
  }
}

class SyncPlayController extends Notifier<SyncPlayState> {
  @override
  SyncPlayState build() {
    _repo = ref.watch(syncPlayRepositoryProvider);
    _socket = ref.watch(syncPlaySocketProvider);
    _socketSub = _socket.events.listen(_handleSocketEvent);
    ref.onDispose(() {
      _socketSub?.cancel();
    });
    return const SyncPlayState();
  }

  late final SyncPlayRepository _repo;
  late final SyncPlaySocket _socket;
  StreamSubscription<SyncPlaySocketEvent>? _socketSub;
  int _queueSerial = 0;
  int _commandSerial = 0;

  Future<void> attach() => _socket.connect();

  Future<void> disconnect() async {
    state = const SyncPlayState();
    await _socket.disconnect();
  }

  Future<void> refreshGroups() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      final groups = await _repo.listGroups();
      state = state.copyWith(
        groups: groups,
        loading: false,
        connected: _socket.connected,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> createGroup({
    required String name,
    String? itemId,
    Duration startPosition = Duration.zero,
    bool publishCurrentVideo = true,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      final groupName = _safeGroupName(name);
      await _repo.createGroup(groupName);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final group = state.activeGroup ?? await _findJoinedGroup(groupName);
      state = state.copyWith(
        activeGroup: group ?? state.activeGroup,
        groups: group == null
            ? state.groups
            : [group, ...state.groups.where((g) => g.id != group.id)],
        loading: false,
        connected: _socket.connected,
      );
      if (publishCurrentVideo && itemId != null && itemId.isNotEmpty) {
        await setCurrentVideo(itemId, startPosition: startPosition);
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> joinGroup(String groupId) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _socket.connect();
      await _repo.joinGroup(groupId);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final group = state.activeGroup ?? await _findGroupById(groupId);
      state = state.copyWith(
        activeGroup: group ?? state.activeGroup,
        loading: false,
        connected: _socket.connected,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> leaveGroup() async {
    try {
      await _repo.leaveGroup();
    } finally {
      state = state.copyWith(
        clearActiveGroup: true,
        clearCurrentItemId: true,
        clearCurrentPlaylistItemId: true,
        clearError: true,
      );
      await _socket.disconnect();
    }
  }

  Future<void> setCurrentVideo(
    String itemId, {
    Duration startPosition = Duration.zero,
  }) async {
    await _repo.setCurrentVideo(itemId, startPosition: startPosition);
    state = state.copyWith(currentItemId: itemId);
  }

  Future<void> pause() => _repo.pause();
  Future<void> unpause() => _repo.unpause();
  Future<void> stop() => _repo.stop();
  Future<void> seek(Duration position) => _repo.seek(position);

  Future<void> ready({
    required Duration position,
    required bool isPlaying,
  }) async {
    final playlistItemId = state.currentPlaylistItemId;
    if (playlistItemId == null || playlistItemId.isEmpty) return;
    try {
      await _repo.ready(
        playlistItemId: playlistItemId,
        position: position,
        isPlaying: isPlaying,
      );
    } catch (_) {
      // SyncPlay readiness is best-effort; playback should keep working.
    }
  }

  void _handleSocketEvent(SyncPlaySocketEvent event) {
    switch (event) {
      case SyncPlaySocketStatusEvent(:final connected):
        state = state.copyWith(connected: connected);
      case SyncPlayCommandSocketEvent(:final command):
        _commandSerial += 1;
        state = state.copyWith(
          commandEvent: SyncPlayVideoCommandEvent(
            serial: _commandSerial,
            command: command,
          ),
        );
      case SyncPlayGroupUpdateSocketEvent(:final type, :final data):
        _handleGroupUpdate(type, data);
    }
  }

  void _handleGroupUpdate(String type, Map<String, dynamic> data) {
    final rawGroup = data['Data'] ?? data['data'];
    final groupId = _groupIdFromUpdate(data);
    if (type == 'GroupJoined' && rawGroup is Map) {
      state = state.copyWith(
        activeGroup: SyncPlayGroup.fromJson(
          Map<String, dynamic>.from(rawGroup),
        ),
        clearError: true,
      );
      return;
    }
    if (type == 'GroupLeft' || type == 'NotInGroup') {
      state = state.copyWith(
        clearActiveGroup: true,
        clearCurrentItemId: true,
        clearCurrentPlaylistItemId: true,
      );
      return;
    }
    if (type == 'PlayQueue') {
      final raw = data['Data'] ?? data['data'];
      if (raw is Map) {
        _applyQueueUpdate(
          SyncPlayQueueUpdate.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
      return;
    }
    if (type == 'UserJoined' || type == 'UserLeft') {
      _applyParticipantUpdate(type, data, groupId);
      return;
    }
    if (type == 'StateUpdate') {
      final raw = data['Data'] ?? data['data'];
      if (raw is Map) {
        final stateName = raw['State'] as String? ?? raw['state'] as String?;
        final active = state.activeGroup;
        if (active != null && stateName != null) {
          state = state.copyWith(
            activeGroup: active.copyWith(state: stateName),
          );
        }
      }
    }
  }

  void _applyQueueUpdate(SyncPlayQueueUpdate update) {
    final item = update.playingItem;
    if (item == null || item.itemId.isEmpty) return;
    _queueSerial += 1;
    state = state.copyWith(
      currentItemId: item.itemId,
      currentPlaylistItemId: item.playlistItemId,
      queueEvent: SyncPlayVideoQueueEvent(
        serial: _queueSerial,
        itemId: item.itemId,
        playlistItemId: item.playlistItemId,
        position: update.startPosition,
        isPlaying: update.isPlaying,
      ),
    );
  }

  String _safeGroupName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final username = _repo.username;
    return username == null || username.isEmpty
        ? 'AltCast group'
        : "$username's group";
  }

  Future<SyncPlayGroup?> _findJoinedGroup(String groupName) async {
    final groups = await _repo.listGroups();
    final username = _repo.username;
    final matches = groups.where((group) {
      final nameMatches = group.name == groupName;
      final userMatches =
          username == null || group.participants.contains(username);
      return nameMatches && userMatches;
    }).toList();
    if (matches.isNotEmpty) return matches.first;
    if (username != null) {
      final ownGroups = groups
          .where((group) => group.participants.contains(username))
          .toList();
      if (ownGroups.isNotEmpty) return ownGroups.first;
    }
    return null;
  }

  Future<SyncPlayGroup?> _findGroupById(String groupId) async {
    final groups = await _repo.listGroups();
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  String? _groupIdFromUpdate(Map<String, dynamic> data) {
    final raw = data['GroupId'] ?? data['groupId'];
    return raw is String ? raw : null;
  }

  void _applyParticipantUpdate(
    String type,
    Map<String, dynamic> data,
    String? groupId,
  ) {
    final active = state.activeGroup;
    if (active == null || (groupId != null && groupId != active.id)) return;
    final raw = data['Data'] ?? data['data'];
    if (raw is! String || raw.isEmpty) return;
    final participants = [...active.participants];
    if (type == 'UserJoined') {
      if (!participants.contains(raw)) participants.add(raw);
    } else {
      participants.remove(raw);
    }
    state = state.copyWith(
      activeGroup: active.copyWith(participants: participants),
    );
  }
}
