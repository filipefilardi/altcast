import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/models/remote_session.dart';
import '../../data/jellyfin/remote_sessions_repository.dart';
import 'remote_session_socket.dart';

/// Mirrors active remote-controllable sessions.
///
/// Jellyfin's web client uses the session websocket (`SessionsStart` /
/// `Sessions`) for low-latency updates, with REST polling as a fallback when
/// the socket is unavailable. Keep the same shape here so cast controls react
/// quickly to changes made on the target device.
final remoteSessionsProvider = StreamProvider.autoDispose<List<RemoteSession>>((
  ref,
) {
  final repo = ref.watch(remoteSessionsRepositoryProvider);
  final socket = ref.watch(remoteSessionSocketProvider);

  final controller = StreamController<List<RemoteSession>>();
  StreamSubscription<RemoteSessionSocketEvent>? socketSub;
  Timer? timer;
  var disposed = false;
  var socketConnected = false;

  Future<void> poll() async {
    if (socketConnected) return;
    try {
      final sessions = await repo.listSessions();
      if (!disposed) controller.add(sessions);
    } catch (e, st) {
      if (!disposed) controller.addError(e, st);
    }
  }

  socketSub = socket.events.listen((event) {
    switch (event) {
      case RemoteSessionsEvent(:final sessions):
        if (!disposed) controller.add(repo.filterSessions(sessions));
      case RemoteSessionSocketStatusEvent(:final connected):
        socketConnected = connected;
        if (!connected) unawaited(poll());
    }
  });

  socket.subscribeSessions().catchError((Object e, StackTrace st) {
    if (!disposed) controller.addError(e, st);
    unawaited(poll());
  });
  unawaited(poll());
  timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());

  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    socket.unsubscribeSessions();
    socketSub?.cancel();
    controller.close();
  });

  return controller.stream;
});

final activeRemoteSessionIdProvider =
    NotifierProvider<ActiveRemoteSessionId, String?>(ActiveRemoteSessionId.new);

class ActiveRemoteSessionId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String id) => state = id;

  void clear() => state = null;
}

final activeRemoteSessionProvider = StreamProvider.autoDispose<RemoteSession?>((
  ref,
) {
  final id = ref.watch(activeRemoteSessionIdProvider);
  if (id == null) return Stream.value(null);
  final repo = ref.watch(remoteSessionsRepositoryProvider);
  final socket = ref.watch(remoteSessionSocketProvider);

  final controller = StreamController<RemoteSession?>();
  StreamSubscription<RemoteSessionSocketEvent>? socketSub;
  Timer? timer;
  var disposed = false;
  var socketConnected = false;

  RemoteSession? select(List<RemoteSession> sessions) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  Future<void> poll() async {
    if (socketConnected) return;
    try {
      final sessions = await repo.listSessions();
      if (!disposed) controller.add(select(sessions));
    } catch (e, st) {
      if (!disposed) controller.addError(e, st);
    }
  }

  socketSub = socket.events.listen((event) {
    switch (event) {
      case RemoteSessionsEvent(:final sessions):
        if (!disposed) {
          controller.add(select(repo.filterSessions(sessions)));
        }
      case RemoteSessionSocketStatusEvent(:final connected):
        socketConnected = connected;
        if (!connected) unawaited(poll());
    }
  });

  socket.subscribeSessions().catchError((Object e, StackTrace st) {
    if (!disposed) controller.addError(e, st);
    unawaited(poll());
  });
  unawaited(poll());
  timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());

  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    socket.unsubscribeSessions();
    socketSub?.cancel();
    controller.close();
  });

  return controller.stream;
});
