import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../auth/auth_controller.dart';
import 'home_providers.dart';
import 'widgets/continue_watching_hero.dart';
import 'widgets/poster_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final username = auth is AuthAuthenticated ? auth.session.username : null;

    final resumeAsync = ref.watch(continueWatchingProvider);
    final moviesAsync = ref.watch(recentMoviesProvider);
    final showsAsync = ref.watch(recentShowsProvider);

    final everythingFailed =
        resumeAsync.hasError && moviesAsync.hasError && showsAsync.hasError;
    final everythingEmpty =
        resumeAsync.value?.isEmpty == true &&
        moviesAsync.value?.isEmpty == true &&
        showsAsync.value?.isEmpty == true;

    Future<void> refresh() async {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(recentMoviesProvider);
      ref.invalidate(recentShowsProvider);
      final errors = <Object?>[];
      await Future.wait([
        ref.read(continueWatchingProvider.future).catchError((e, _) {
          errors.add(e);
          return <BrowseItem>[];
        }),
        ref.read(recentMoviesProvider.future).catchError((e, _) {
          errors.add(e);
          return <BrowseItem>[];
        }),
        ref.read(recentShowsProvider.future).catchError((e, _) {
          errors.add(e);
          return <BrowseItem>[];
        }),
      ]);
      if (context.mounted && errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errors.length == 3
                  ? "Couldn't refresh home. Check your connection."
                  : "Some sections didn't refresh. Pull to try again.",
            ),
          ),
        );
      }
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _Greeting(
              username: username,
              greetingPhrase: _timeBasedGreeting(),
            ),
            const SizedBox(height: 24),
            if (everythingFailed)
              ErrorStateView(
                title: "Couldn't load library",
                message: 'Pull to retry, or check your server connection.',
                onRetry: refresh,
              )
            else if (everythingEmpty)
              EmptyState(
                icon: Icons.movie_filter_outlined,
                title: 'Nothing here yet',
                message: 'Add some movies or shows to your Jellyfin server.',
                action: TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              )
            else ...[
              ContinueWatchingShelf(
                itemsAsync: resumeAsync,
                onRetry: () => ref.invalidate(continueWatchingProvider),
                onOpen: (item) => _openDetail(context, item),
              ),
              _Section<List<BrowseItem>>(
                title: 'Recently added movies',
                state: moviesAsync,
                onRetry: () => ref.invalidate(recentMoviesProvider),
                builder: (items) => _PosterRow(items: items),
                hideWhenEmpty: true,
                skeletonHeight: 248,
                onSeeAll: () => context.push('/library/movies'),
              ),
              _Section<List<BrowseItem>>(
                title: 'Recently added shows',
                state: showsAsync,
                onRetry: () => ref.invalidate(recentShowsProvider),
                builder: (items) => _PosterRow(items: items),
                hideWhenEmpty: true,
                skeletonHeight: 248,
                onSeeAll: () => context.push('/library/shows'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Local-time greeting for the home header (5–12 morning, 12–17 afternoon, else evening).
String _timeBasedGreeting() {
  final h = DateTime.now().hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  return 'Good evening';
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.username, required this.greetingPhrase});

  final String? username;
  final String greetingPhrase;

  @override
  Widget build(BuildContext context) {
    final displayTitle = Theme.of(context).textTheme.displayMedium!.copyWith(
      // ShaderMask + BlendMode.srcIn: fill must be a solid light color so the
      // accent gradient reads correctly (matches previous white treatment).
      color: AppColors.textPrimary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) =>
                    AppGradients.accent.createShader(bounds),
                child: Text('AltCast', style: displayTitle),
              ),
              const SizedBox(height: 8),
              Text(
                username == null || username!.isEmpty
                    ? greetingPhrase
                    : '$greetingPhrase, $username',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceElevated,
            foregroundColor: AppColors.textPrimary,
          ),
          tooltip: 'Settings',
        ),
      ],
    );
  }
}

class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.state,
    required this.onRetry,
    required this.builder,
    required this.skeletonHeight,
    this.hideWhenEmpty = false,
    this.skeletonCardWidth = 132,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<T> state;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;
  final double skeletonHeight;
  final double skeletonCardWidth;
  final bool hideWhenEmpty;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final isEmpty = state.value is List && (state.value as List).isEmpty;
    if (state.hasValue && hideWhenEmpty && isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        if (state.isLoading)
          _SkeletonRow(
            height: skeletonHeight,
            cardWidth: skeletonCardWidth,
          )
        else if (state.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ErrorStateView(
              title: "Couldn't load $title",
              onRetry: onRetry,
            ),
          )
        else if (state.hasValue)
          builder(state.requireValue),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.height, required this.cardWidth});
  final double height;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Skeleton.group(
        child: ListView.separated(
          primary: false,
          scrollDirection: Axis.horizontal,
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) =>
              Skeleton.box(width: cardWidth, height: height - 8),
        ),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.items});
  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => PosterCard(
          item: items[i],
          onTap: () => _openDetail(context, items[i]),
        ),
      ),
    );
  }
}

/// Routes a Home tap to the right detail screen based on item kind.
/// Episodes & seasons land on their parent series — there's no per-episode
/// screen yet (planned for the player phase).
void _openDetail(BuildContext context, BrowseItem item) {
  switch (item.kind) {
    case MediaKind.movie:
      context.push('/movie/${item.id}');
    case MediaKind.series:
      context.push('/series/${item.id}');
    case MediaKind.season:
      context.push('/season/${item.id}');
    case MediaKind.episode:
      context.push('/episode/${item.id}');
    case MediaKind.person:
      context.push('/person/${item.id}');
  }
}
