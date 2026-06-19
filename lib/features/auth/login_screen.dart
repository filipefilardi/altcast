import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/utils/dio_error_message.dart';
import 'package:altcast/core/widgets/glass_popover.dart';
import 'package:altcast/data/jellyfin/auth_repository.dart';
import 'package:altcast/data/jellyfin/jellyfin_api.dart';
import 'package:altcast/features/auth/auth_controller.dart';

enum _LoginStep { server, user }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialServerUrl});

  final String? initialServerUrl;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  _LoginStep _step = _LoginStep.server;
  late Future<List<SavedJellyfinServer>> _savedServersFuture;
  JellyfinPublicServerInfo? _serverInfo;
  String? _serverError;
  bool _checkingServer = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _savedServersFuture = _loadSavedServers();
    _serverCtrl.addListener(_onServerUrlChanged);
    final initialServerUrl = widget.initialServerUrl;
    if (initialServerUrl != null && initialServerUrl.isNotEmpty) {
      _serverCtrl.text = initialServerUrl;
      _serverInfo = JellyfinPublicServerInfo(serverUrl: initialServerUrl);
      _step = _LoginStep.user;
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialServerUrl;
    if (next != oldWidget.initialServerUrl && next != null && next.isNotEmpty) {
      _serverCtrl.text = next;
      _serverInfo = JellyfinPublicServerInfo(serverUrl: next);
      _serverError = null;
      _step = _LoginStep.user;
    }
  }

  @override
  void dispose() {
    _serverCtrl.removeListener(_onServerUrlChanged);
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _onServerUrlChanged() {
    if (!mounted || _step != _LoginStep.server || _checkingServer) return;
    setState(() {});
  }

  void _submit() {
    if (_step == _LoginStep.server) {
      _continueWithServer();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .login(
          serverUrl: _serverInfo?.serverUrl ?? _serverCtrl.text.trim(),
          username: _userCtrl.text.trim(),
          password: _passCtrl.text,
        );
  }

  Future<void> _continueWithServer() async {
    if (_serverCtrl.text.trim().isEmpty) return;
    setState(() {
      _checkingServer = true;
      _serverError = null;
    });
    try {
      final info = await ref
          .read(authRepositoryProvider)
          .publicServerInfo(_serverCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _serverInfo = info;
        _serverCtrl.text = info.serverUrl;
        _savedServersFuture = _loadSavedServers();
        _step = _LoginStep.user;
      });
    } on JellyfinAuthException catch (e) {
      if (!mounted) return;
      setState(() => _serverError = e.message);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _serverError = userFacingDioMessage(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _checkingServer = false);
    }
  }

  void _changeServer() {
    setState(() {
      _step = _LoginStep.server;
      _serverInfo = null;
      _serverError = null;
      _serverCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
    });
  }

  Future<List<SavedJellyfinServer>> _loadSavedServers() async {
    final servers = await ref.read(authRepositoryProvider).savedServers();
    final current = _serverInfo;
    if (mounted &&
        current != null &&
        (current.serverName == null || current.serverName!.isEmpty)) {
      for (final server in servers) {
        if (server.serverUrl == current.serverUrl) {
          setState(() => _serverInfo = server.toPublicInfo());
          break;
        }
      }
    }
    return servers;
  }

  void _selectSavedServer(SavedJellyfinServer server) {
    setState(() {
      _serverCtrl.text = server.serverUrl;
      _serverInfo = server.toPublicInfo();
      _serverError = null;
      _userCtrl.text = server.lastUsername ?? '';
      _passCtrl.clear();
      _step = _LoginStep.user;
    });
  }

  Future<void> _forgetSavedServer(SavedJellyfinServer server) async {
    await ref.read(authRepositoryProvider).forgetServer(server.serverUrl);
    if (!mounted) return;
    final nextSavedServers = _loadSavedServers();
    setState(() {
      _savedServersFuture = nextSavedServers;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final loading = state is AuthLoading;
    final errorMessage = _step == _LoginStep.server
        ? _serverError
        : state is AuthUnauthenticated
        ? state.error
        : null;
    final busy = loading || _checkingServer;
    final canSubmit =
        !busy &&
        (_step == _LoginStep.user || _serverCtrl.text.trim().isNotEmpty);

    return Scaffold(
      body: _LoginBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _GlassLoginPanel(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LoginBrand(
                          subtitle: _step == _LoginStep.server
                              ? 'Choose your Jellyfin server'
                              : 'Sign in to your account',
                        ),
                        const SizedBox(height: 26),
                        _LoginStepIndicator(
                          step: _step,
                          onServerTap: _step == _LoginStep.user
                              ? _changeServer
                              : null,
                        ),
                        const SizedBox(height: 28),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _step == _LoginStep.server
                                ? FutureBuilder<List<SavedJellyfinServer>>(
                                    key: const ValueKey('server-step'),
                                    future: _savedServersFuture,
                                    builder: (context, snapshot) {
                                      return _ServerStep(
                                        controller: _serverCtrl,
                                        savedServers: snapshot.data ?? const [],
                                        loadingSavedServers:
                                            snapshot.connectionState ==
                                            ConnectionState.waiting,
                                        onSelectSavedServer: _selectSavedServer,
                                        onForgetSavedServer: _forgetSavedServer,
                                        onSubmitted: _submit,
                                      );
                                    },
                                  )
                                : _UserStep(
                                    key: const ValueKey('user-step'),
                                    serverInfo: _serverInfo,
                                    usernameController: _userCtrl,
                                    passwordController: _passCtrl,
                                    obscurePassword: _obscure,
                                    onTogglePassword: () =>
                                        setState(() => _obscure = !_obscure),
                                    onSubmitted: _submit,
                                  ),
                          ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _LoginErrorBanner(message: errorMessage),
                        ],
                        const SizedBox(height: 28),
                        _PrimaryLoginButton(
                          busy: busy,
                          label: _step == _LoginStep.server
                              ? 'Continue'
                              : 'Sign in',
                          onPressed: canSubmit ? _submit : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071018), AppColors.background, Color(0xFF0E1118)],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.72, -0.84),
                radius: 1.25,
                colors: [
                  AppColors.primary.withValues(alpha: 0.24),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.68],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  AppColors.primaryDark.withValues(alpha: 0.12),
                  Colors.transparent,
                  AppColors.surfaceHighlight.withValues(alpha: 0.18),
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlassLoginPanel extends StatelessWidget {
  const _GlassLoginPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.34),
                blurRadius: 36,
                offset: const Offset(0, 24),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => AppGradients.accent.createShader(bounds),
          child: Text(
            'AltCast',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LoginStepIndicator extends StatelessWidget {
  const _LoginStepIndicator({required this.step, this.onServerTap});

  final _LoginStep step;
  final VoidCallback? onServerTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: _LoginStepPill(
                    icon: PiconsRegular.hardDrives,
                    label: 'Server',
                    active: step == _LoginStep.server,
                    onTap: onServerTap,
                  ),
                ),
                Expanded(
                  child: _LoginStepPill(
                    icon: PiconsRegular.user,
                    label: 'Account',
                    active: step == _LoginStep.user,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginStepPill extends StatelessWidget {
  const _LoginStepPill({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.onAccent : AppColors.textSecondary;
    return Material(
      color: active ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryLoginButton extends StatelessWidget {
  const _PrimaryLoginButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : AppGradients.accent,
        color: onPressed == null
            ? AppColors.surfaceHighlight.withValues(alpha: 0.4)
            : null,
        borderRadius: BorderRadius.circular(18),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 54,
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.onAccent,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.onAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerStep extends StatelessWidget {
  const _ServerStep({
    required this.controller,
    required this.savedServers,
    required this.loadingSavedServers,
    required this.onSelectSavedServer,
    required this.onForgetSavedServer,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final List<SavedJellyfinServer> savedServers;
  final bool loadingSavedServers;
  final ValueChanged<SavedJellyfinServer> onSelectSavedServer;
  final ValueChanged<SavedJellyfinServer> onForgetSavedServer;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loadingSavedServers)
          const _SavedServersSkeleton()
        else if (savedServers.isNotEmpty) ...[
          const _SectionHeader(label: 'Saved servers'),
          const SizedBox(height: 12),
          for (final server in savedServers) ...[
            _SavedServerTile(
              server: server,
              onTap: () => onSelectSavedServer(server),
              onForget: () => onForgetSavedServer(server),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 18),
        ],
        _SectionHeader(
          label: savedServers.isEmpty ? 'Server URL' : 'Use another server',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: const InputDecoration(
            hintText: 'https://jellyfin.example.com',
            prefixIcon: Icon(PiconsRegular.hardDrives),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SavedServerTile extends StatelessWidget {
  const _SavedServerTile({
    required this.server,
    required this.onTap,
    required this.onForget,
  });

  final SavedJellyfinServer server;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return _ServerTile(
      title: _serverTitle(server.serverName),
      subtitle: server.serverUrl,
      onTap: onTap,
      onDelete: onForget,
    );
  }
}

String _serverTitle(String? serverName) {
  final name = serverName?.trim();
  return name == null || name.isEmpty ? 'Jellyfin server' : name;
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.title,
    this.subtitle,
    this.readOnly = false,
    this.onTap,
    this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool readOnly;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Material(
          color: readOnly
              ? AppColors.primary.withValues(alpha: 0.075)
              : Colors.white.withValues(alpha: 0.045),
          child: InkWell(
            onTap: readOnly ? null : onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: readOnly
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.075),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 13, readOnly ? 16 : 8, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (readOnly) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'Server options',
                        onPressed: () => _showServerOptions(context),
                        icon: const Icon(PiconsRegular.dotsThree, size: 20),
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showServerOptions(BuildContext context) {
    return showGlassPopover<void>(
      context: context,
      width: 240,
      builder: (_) => SafeArea(
        child: GlassPopoverItem(
          icon: PiconsRegular.trash,
          label: 'Delete Server',
          destructive: true,
          onTap: onDelete!,
        ),
      ),
    );
  }
}

class _SavedServersSkeleton extends StatelessWidget {
  const _SavedServersSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceElevated.withValues(alpha: 0.32),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _UserStep extends StatelessWidget {
  const _UserStep({
    super.key,
    required this.serverInfo,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmitted,
  });

  final JellyfinPublicServerInfo? serverInfo;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ServerTile(
          title: _serverTitle(serverInfo?.serverName),
          subtitle: serverInfo?.serverUrl,
          readOnly: true,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: usernameController,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(PiconsRegular.user),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(PiconsRegular.lock),
            suffixIcon: IconButton(
              icon: Icon(
                PiconsRegular.eye,
                color: obscurePassword
                    ? AppColors.textSecondary
                    : AppColors.primary,
              ),
              onPressed: onTogglePassword,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            PiconsRegular.warningCircle,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
