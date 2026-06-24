import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/core/platform/android_background_settings.dart';
import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/theme/app_gradients.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';
import 'package:altcast/data/local/notification_preferences.dart';
import 'package:altcast/data/local/onboarding_preferences.dart';
import 'package:altcast/data/notifications/app_notifications.dart';
import 'package:altcast/data/notifications/library_notification_scheduler.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next(int pageCount) async {
    if (_page == pageCount - 1) {
      await ref.read(onboardingPreferencesProvider.notifier).complete();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() async {
    await ref.read(onboardingPreferencesProvider.notifier).skip();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _IntroPage(),
      const _NotificationSetupPage(),
      if (AndroidBackgroundSettings.isSupported) const _AndroidBackgroundPage(),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.loginBackdrop),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) =>
                          AppGradients.accent.createShader(bounds),
                      child: Text(
                        'AltCast',
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: _skip, child: const Text('Skip')),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: pages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _GlassSurface(
                      borderRadius: 24,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: _page == 0
                                  ? null
                                  : () => _controller.previousPage(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                    ),
                              child: const Text('Back'),
                            ),
                            Expanded(
                              child: _PageDots(
                                count: pages.length,
                                activeIndex: _page,
                              ),
                            ),
                            FilledButton(
                              onPressed: () => _next(pages.length),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onAccent,
                                minimumSize: const Size(120, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _page == pages.length - 1 ? 'Finish' : 'Next',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    return _OnboardingPage(
      title: 'Your Jellyfin library, anywhere',
      body:
          'AltCast streams your movies and shows, saves downloads for offline playback, and keeps your media sync’d in the background.',
      children: const [
        _FeatureRow(
          title: 'Stream from your server',
          subtitle: 'Access your entire Jellyfin library seamlessly on the go.',
        ),
        _FeatureRow(
          title: 'Take videos offline',
          subtitle:
              'Download episodes and movies for flights, commutes, or patchy networks.',
        ),
        _FeatureRow(
          title: 'Stay up to date',
          subtitle:
              'Get optional notifications for completed downloads and fresh media.',
        ),
        _FeatureRow(
          title: 'Private and personal',
          subtitle:
              'Your playback history, settings, and downloaded files stay securely on this device.',
        ),
      ],
    );
  }
}

class _NotificationSetupPage extends ConsumerWidget {
  const _NotificationSetupPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return _OnboardingPage(
      title: 'Stay in the loop',
      body:
          'Get notified when your favorite titles finish downloading or when new episodes drop.',
      children: [
        _SetupPanel(
          title: prefs.notificationsEnabled
              ? 'You\'re all set!'
              : 'Enable notifications',
          subtitle: prefs.notificationsEnabled
              ? 'AltCast will keep you updated on this device.'
              : 'Tap below to allow AltCast to send you download updates and library alerts.',
          actionLabel: prefs.notificationsEnabled
              ? 'Enabled'
              : 'Turn on Notifications',
          actionEnabled: !prefs.notificationsEnabled,
          onAction: () => _enableNotifications(context, ref),
        ),
      ],
    );
  }

  Future<void> _enableNotifications(BuildContext context, WidgetRef ref) async {
    final allowed = await AppNotifications.requestPermissions();
    if (!context.mounted) return;
    if (!allowed) {
      showAppSnackBar(context, "Notifications weren't enabled.");
      return;
    }

    await ref
        .read(notificationPreferencesProvider.notifier)
        .setNotificationsEnabled(true);
    await LibraryNotificationScheduler.configure(
      ref.read(notificationPreferencesProvider),
    );
  }
}

class _AndroidBackgroundPage extends StatefulWidget {
  const _AndroidBackgroundPage();

  @override
  State<_AndroidBackgroundPage> createState() => _AndroidBackgroundPageState();
}

class _AndroidBackgroundPageState extends State<_AndroidBackgroundPage>
    with WidgetsBindingObserver {
  bool? _isUnrestricted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBatteryState();
    }
  }

  Future<void> _refreshBatteryState() async {
    final unrestricted =
        await AndroidBackgroundSettings.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() => _isUnrestricted = unrestricted);
  }

  @override
  Widget build(BuildContext context) {
    final unrestricted = _isUnrestricted == true;
    return _OnboardingPage(
      title: 'Get fresh content instantly',
      body:
          'Android\'s battery saver can delay background updates, meaning new movie or episode alerts won\'t show up until you manually open the app.',
      children: [
        _SetupPanel(
          title: unrestricted
              ? 'Background updates enabled'
              : 'Fix battery delays',
          subtitle: unrestricted
              ? 'AltCast can now reliably check for new content in the background.'
              : 'To get updates on time, change AltCast to "Unrestricted" in your device\'s battery settings.',
          actionLabel: unrestricted ? 'Enabled' : 'Open Settings',
          actionEnabled: !unrestricted,
          onAction: () => _openBatterySettings(context),
        ),
      ],
    );
  }

  Future<void> _openBatterySettings(BuildContext context) async {
    final opened = await AndroidBackgroundSettings.openBatterySettings();
    if (!context.mounted || opened) return;
    showAppSnackBar(context, "Couldn't open Android settings.");
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.children,
  });

  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 152,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 58,
                      child: Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 82,
                      child: Center(
                        child: Text(
                          body,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.42,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ..._withSpacing(children),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _withSpacing(List<Widget> widgets) {
    return [
      for (var i = 0; i < widgets.length; i++) ...[
        widgets[i],
        if (i < widgets.length - 1) const SizedBox(height: 12),
      ],
    ];
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SetupCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 74),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.actionEnabled = true,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final bool actionEnabled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 22,
      opacity: 0.22,
      borderOpacity: 0.14,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 172),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.38,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: actionEnabled ? onAction : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.success.withValues(
                    alpha: 0.22,
                  ),
                  disabledForegroundColor: AppColors.success,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      opacity: 0.18,
      borderOpacity: 0.11,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.borderRadius = 18,
    this.opacity = 0.2,
    this.borderOpacity = 0.12,
  });

  final Widget child;
  final double borderRadius;
  final double opacity;
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 26,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surfaceHighlight,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
