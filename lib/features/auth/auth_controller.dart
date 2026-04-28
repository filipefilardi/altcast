import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/auth_repository.dart';
import '../../data/jellyfin/jellyfin_api.dart';
import '../../data/jellyfin/models/jellyfin_session.dart';

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
  const AuthUnauthenticated({this.error});
  final String? error;
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

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
      final session = await ref.read(authRepositoryProvider).login(
            serverUrl: serverUrl,
            username: username,
            password: password,
          );
      state = AuthAuthenticated(session);
    } on JellyfinAuthException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    } on DioException catch (e) {
      state = AuthUnauthenticated(error: _dioMessage(e));
    } catch (e) {
      state = AuthUnauthenticated(error: 'Unexpected error: $e');
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthUnauthenticated();
  }

  String _dioMessage(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Invalid username or password.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Could not reach server. Check the URL and your network.';
    }
    return e.message ?? 'Network error.';
  }
}
