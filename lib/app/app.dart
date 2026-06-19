import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/theme/app_theme.dart';
import 'package:altcast/data/local/notification_preferences.dart';
import 'package:altcast/data/notifications/library_notification_scheduler.dart';
import 'package:altcast/features/auth/auth_controller.dart';
import 'package:altcast/app/router.dart';

class AltCastApp extends ConsumerWidget {
  const AltCastApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authControllerProvider);
    final notificationPreferences = ref.watch(notificationPreferencesProvider);
    if (notificationPreferences.isRestored) {
      unawaited(
        LibraryNotificationScheduler.configure(notificationPreferences),
      );
    }

    return MaterialApp.router(
      title: 'AltCast',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
      builder: (context, child) {
        if (auth is AuthInitial) {
          return const _SplashScreen();
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => flushPendingNotificationRoute(),
        );
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final displayTitle = Theme.of(
      context,
    ).textTheme.displayMedium!.copyWith(color: Colors.white);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.loginBackdrop),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) =>
                    AppGradients.accent.createShader(bounds),
                child: Text('AltCast', style: displayTitle),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
