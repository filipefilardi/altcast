import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

const _sessionKey = 'jellyfin_session_v1';
const _savedServersKey = 'jellyfin_saved_servers_v1';
const _maxSavedServers = 8;

final jellyfinApiProvider = Provider<JellyfinApi>((ref) => JellyfinApi());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(jellyfinApiProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

class AuthRepository {
  AuthRepository({required this.api, required this.storage});

  final JellyfinApi api;
  final SecureStorage storage;

  Future<JellyfinSession?> restore() async {
    final raw = await storage.read(_sessionKey);
    if (raw == null) return null;
    try {
      final session = JellyfinSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      api.bind(session);
      return session;
    } catch (_) {
      await storage.delete(_sessionKey);
      return null;
    }
  }

  Future<JellyfinPublicServerInfo> publicServerInfo(String serverUrl) {
    return api.publicServerInfo(serverUrl).then((info) async {
      await saveServer(info);
      return info;
    });
  }

  Future<List<SavedJellyfinServer>> savedServers() async {
    final raw = await storage.read(_savedServersKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final servers =
          decoded
              .whereType<Map<String, dynamic>>()
              .map(SavedJellyfinServer.fromJson)
              .where((server) => server.serverUrl.isNotEmpty)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return servers;
    } catch (_) {
      await storage.delete(_savedServersKey);
      return const [];
    }
  }

  Future<SavedJellyfinServer> saveServer(
    JellyfinPublicServerInfo info, {
    String? lastUsername,
  }) async {
    return _upsertSavedServer(
      serverUrl: info.serverUrl,
      serverName: info.serverName,
      version: info.version,
      lastUsername: lastUsername,
    );
  }

  Future<void> forgetServer(String serverUrl) async {
    final servers = await savedServers();
    final next = servers
        .where((server) => server.serverUrl != serverUrl)
        .toList();
    await _writeSavedServers(next);
  }

  Future<JellyfinSession> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final session = await api.authenticate(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    await storage.write(_sessionKey, jsonEncode(session.toJson()));
    await _upsertSavedServer(
      serverUrl: session.serverUrl,
      lastUsername: session.username,
    );
    return session;
  }

  Future<void> logout() async {
    await api.logout();
    await storage.delete(_sessionKey);
  }

  Future<SavedJellyfinServer> _upsertSavedServer({
    required String serverUrl,
    String? serverName,
    String? version,
    String? lastUsername,
  }) async {
    final servers = await savedServers();
    final existing = servers.where((server) => server.serverUrl == serverUrl);
    final previous = existing.isEmpty ? null : existing.first;
    final saved = SavedJellyfinServer(
      serverUrl: serverUrl,
      serverName: serverName ?? previous?.serverName,
      version: version ?? previous?.version,
      lastUsername: lastUsername ?? previous?.lastUsername,
      updatedAt: DateTime.now().toUtc(),
    );
    final next = [
      saved,
      for (final server in servers)
        if (server.serverUrl != serverUrl) server,
    ].take(_maxSavedServers).toList();
    await _writeSavedServers(next);
    return saved;
  }

  Future<void> _writeSavedServers(List<SavedJellyfinServer> servers) async {
    await storage.write(
      _savedServersKey,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
  }
}

class SavedJellyfinServer {
  const SavedJellyfinServer({
    required this.serverUrl,
    required this.updatedAt,
    this.serverName,
    this.version,
    this.lastUsername,
  });

  final String serverUrl;
  final String? serverName;
  final String? version;
  final String? lastUsername;
  final DateTime updatedAt;

  JellyfinPublicServerInfo toPublicInfo() {
    return JellyfinPublicServerInfo(
      serverUrl: serverUrl,
      serverName: serverName,
      version: version,
    );
  }

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    if (serverName != null) 'serverName': serverName,
    if (version != null) 'version': version,
    if (lastUsername != null) 'lastUsername': lastUsername,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SavedJellyfinServer.fromJson(Map<String, dynamic> json) {
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    return SavedJellyfinServer(
      serverUrl: json['serverUrl'] as String? ?? '',
      serverName: json['serverName'] as String?,
      version: json['version'] as String?,
      lastUsername: json['lastUsername'] as String?,
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
