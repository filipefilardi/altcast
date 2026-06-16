import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/data/jellyfin/models/jellyfin_session.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final JellyfinSession session;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.error, this.serverUrl});
  final String? error;
  final String? serverUrl;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _bootstrap();
    return const AuthInitial();
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(authRepositoryProvider);
    final session = await repo.restore();
    state = session == null
        ? const AuthUnauthenticated()
        : AuthAuthenticated(session);
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .login(serverUrl: serverUrl, username: username, password: password);
      state = AuthAuthenticated(session);
    } on JellyfinAuthException catch (e) {
      state = AuthUnauthenticated(error: e.message, serverUrl: serverUrl);
    } on DioException catch (e) {
      state = AuthUnauthenticated(
        error: userFacingDioMessage(e),
        serverUrl: serverUrl,
      );
    } catch (e) {
      state = AuthUnauthenticated(
        error: 'Unexpected error: $e',
        serverUrl: serverUrl,
      );
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthUnauthenticated();
  }

  Future<void> switchUserOnSameServer() async {
    final previous = state;
    final serverUrl = previous is AuthAuthenticated
        ? previous.session.serverUrl
        : null;
    await ref.read(authRepositoryProvider).logout();
    state = AuthUnauthenticated(serverUrl: serverUrl);
  }
}
