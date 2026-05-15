import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/remote_session.dart';

final remoteSessionSocketProvider = Provider.autoDispose<RemoteSessionSocket>((
  ref,
) {
  final socket = RemoteSessionSocket(ref.watch(jellyfinApiProvider));
  ref.onDispose(socket.dispose);
  return socket;
});

sealed class RemoteSessionSocketEvent {
  const RemoteSessionSocketEvent();
}

class RemoteSessionsEvent extends RemoteSessionSocketEvent {
  const RemoteSessionsEvent(this.sessions);
  final List<RemoteSession> sessions;
}

class RemoteSessionSocketStatusEvent extends RemoteSessionSocketEvent {
  const RemoteSessionSocketStatusEvent(this.connected);
  final bool connected;
}

class RemoteSessionSocket {
  RemoteSessionSocket(this._api);

  final JellyfinApi _api;
  final _events = StreamController<RemoteSessionSocketEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connectFuture;

  Stream<RemoteSessionSocketEvent> get events => _events.stream;

  bool get connected => _channel != null;

  Future<void> subscribeSessions() async {
    await connect();
    _send({'MessageType': 'SessionsStart', 'Data': '100,800'});
  }

  void unsubscribeSessions() {
    _send({'MessageType': 'SessionsStop'});
  }

  Future<void> connect() async {
    if (_channel != null) return;
    final pending = _connectFuture;
    if (pending != null) {
      await pending;
      return;
    }
    _connectFuture = _connect();
    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> _connect() async {
    final session = _api.session;
    if (session == null) return;
    try {
      final uri = _socketUri(session.serverUrl);
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': _api.authorizationHeader},
        connectTimeout: const Duration(seconds: 10),
      );
      if (kDebugMode) {
        debugPrint(
          '[RemoteSession] socket connecting: ${uri.replace(query: '...')}',
        );
      }
      await channel.ready.timeout(const Duration(seconds: 10));
      _channel = channel;
      _events.add(const RemoteSessionSocketStatusEvent(true));
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: true,
      );
      if (kDebugMode) debugPrint('[RemoteSession] socket ready');
    } catch (_) {
      _channel = null;
      if (!_events.isClosed) {
        _events.add(const RemoteSessionSocketStatusEvent(false));
      }
      rethrow;
    }
  }

  Uri _socketUri(String serverUrl) {
    final base = Uri.parse(serverUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final path = base.path.endsWith('/')
        ? '${base.path}socket'
        : '${base.path}/socket';
    return base.replace(
      scheme: scheme,
      path: path,
      queryParameters: {'deviceId': _api.deviceId},
    );
  }

  void _handleMessage(dynamic raw) {
    try {
      final decoded = raw is String
          ? jsonDecode(raw)
          : raw is List<int>
          ? jsonDecode(utf8.decode(raw))
          : null;
      if (decoded is! Map) return;
      final message = Map<String, dynamic>.from(decoded);
      final type =
          message['MessageType'] as String? ??
          message['messageType'] as String?;
      final data = message['Data'] ?? message['data'];
      if (type == 'ForceKeepAlive') {
        _send({'MessageType': 'KeepAlive'});
        return;
      }
      if (type == 'Sessions' && data is List) {
        _events.add(
          RemoteSessionsEvent(
            data
                .whereType<Map>()
                .map(
                  (s) => RemoteSession.fromJson(Map<String, dynamic>.from(s)),
                )
                .toList(growable: false),
          ),
        );
      }
    } catch (_) {
      // Ignore malformed or unsupported websocket messages.
    }
  }

  void _markDisconnected() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (!_events.isClosed) {
      _events.add(const RemoteSessionSocketStatusEvent(false));
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_events.isClosed) {
      _events.add(const RemoteSessionSocketStatusEvent(false));
    }
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    unsubscribeSessions();
    await disconnect();
    await _events.close();
  }
}
