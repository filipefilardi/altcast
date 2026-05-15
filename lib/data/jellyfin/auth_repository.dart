import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/local/secure_storage.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

const _sessionKey = 'jellyfin_session_v1';

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
    return session;
  }

  Future<void> logout() async {
    await api.logout();
    await storage.delete(_sessionKey);
  }
}
