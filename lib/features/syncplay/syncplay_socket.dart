import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/syncplay.dart';

final syncPlaySocketProvider = Provider<SyncPlaySocket>((ref) {
  final socket = SyncPlaySocket(ref.watch(jellyfinApiProvider));
  ref.onDispose(socket.dispose);
  return socket;
});

sealed class SyncPlaySocketEvent {
  const SyncPlaySocketEvent();
}

class SyncPlayCommandSocketEvent extends SyncPlaySocketEvent {
  const SyncPlayCommandSocketEvent(this.command);
  final SyncPlayCommand command;
}

class SyncPlayGroupUpdateSocketEvent extends SyncPlaySocketEvent {
  const SyncPlayGroupUpdateSocketEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class SyncPlaySocketStatusEvent extends SyncPlaySocketEvent {
  const SyncPlaySocketStatusEvent(this.connected);
  final bool connected;
}

class SyncPlaySocket {
  SyncPlaySocket(this._api);

  final JellyfinApi _api;
  final _events = StreamController<SyncPlaySocketEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connectFuture;

  Stream<SyncPlaySocketEvent> get events => _events.stream;

  bool get connected => _channel != null;

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
          '[SyncPlay] socket connecting: ${uri.replace(query: '...')}',
        );
      }
      await channel.ready.timeout(const Duration(seconds: 10));
      _channel = channel;
      _events.add(const SyncPlaySocketStatusEvent(true));
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: true,
      );
      if (kDebugMode) debugPrint('[SyncPlay] socket ready');
    } catch (_) {
      _channel = null;
      if (!_events.isClosed) {
        _events.add(const SyncPlaySocketStatusEvent(false));
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
      if (type == 'SyncPlayCommand' && data is Map) {
        _events.add(
          SyncPlayCommandSocketEvent(
            SyncPlayCommand.fromJson(Map<String, dynamic>.from(data)),
          ),
        );
      } else if (type == 'SyncPlayGroupUpdate' && data is Map) {
        final update = Map<String, dynamic>.from(data);
        final updateType =
            update['Type'] as String? ?? update['type'] as String?;
        if (updateType != null) {
          _events.add(SyncPlayGroupUpdateSocketEvent(updateType, update));
        }
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
      _events.add(const SyncPlaySocketStatusEvent(false));
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_events.isClosed) {
      _events.add(const SyncPlaySocketStatusEvent(false));
    }
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
