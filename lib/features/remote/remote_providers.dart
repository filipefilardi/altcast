import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/models/remote_session.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';

/// Polls Jellyfin for active remote-controllable sessions every 3 seconds
/// while watched. autoDispose so we stop polling as soon as no UI is open.
final remoteSessionsProvider = StreamProvider.autoDispose<List<RemoteSession>>((
  ref,
) async* {
  final repo = ref.watch(remoteSessionsRepositoryProvider);
  // First emit immediately so the picker doesn't flash a loading state for
  // the full poll interval.
  try {
    yield await repo.listSessions();
  } catch (_) {
    yield <RemoteSession>[];
  }
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      yield await repo.listSessions();
    } catch (_) {
      // Don't surface poll errors — the next tick may recover. Stale data
      // is better than an angry red banner.
    }
  }
});

final activeRemoteSessionIdProvider =
    NotifierProvider<ActiveRemoteSessionId, String?>(ActiveRemoteSessionId.new);

class ActiveRemoteSessionId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String id) => state = id;

  void clear() => state = null;
}
