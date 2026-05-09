import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../auth/auth_controller.dart';
import '../remote/remote_sessions_sheet.dart';
import '../syncplay/syncplay_controller.dart';
import '../syncplay/syncplay_sheet.dart';
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
            _HomeHeader(username: username),
            const SizedBox(height: 18),
            const _LibraryNav(),
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
                onOpen: (item) => openItemDetail(context, item),
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

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({this.username});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = username == null || username!.isEmpty ? 'Home' : username!;
    final syncPlayActive = ref.watch(syncPlayControllerProvider).isActive;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NavIconButton(
              icon: Icons.search_rounded,
              tooltip: 'Search',
              onPressed: () => context.push('/search'),
            ),
            _NavIconButton(
              icon: Icons.groups_rounded,
              tooltip: 'SyncPlay',
              isSelected: syncPlayActive,
              onPressed: () => showSyncPlaySheet(context),
            ),
            _NavIconButton(
              icon: Icons.cast_rounded,
              tooltip: 'Cast',
              onPressed: () => showRemoteSessionsSheet(context),
            ),
            _NavIconButton(
              icon: Icons.download_rounded,
              tooltip: 'Downloads',
              onPressed: () => context.push('/downloads'),
            ),
            _NavIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isSelected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      color: isSelected ? AppColors.primary : AppColors.textPrimary,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: isSelected
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.surfaceElevated,
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _LibraryNav extends StatelessWidget {
  const _LibraryNav();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LibraryNavItem(
            label: 'Movies',
            onTap: () => context.push('/library/movies'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LibraryNavItem(
            label: 'Series',
            onTap: () => context.push('/library/shows'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LibraryNavItem(
            label: 'Collections',
            onTap: () => context.push('/library/collections'),
          ),
        ),
      ],
    );
  }
}

class _LibraryNavItem extends StatelessWidget {
  const _LibraryNavItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
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
          _SkeletonRow(height: skeletonHeight, cardWidth: skeletonCardWidth)
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
          onTap: () => openItemDetail(context, items[i]),
        ),
      ),
    );
  }
}
