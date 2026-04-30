# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get        # Install dependencies
flutter run            # Run on connected device/simulator
flutter analyze        # Lint
flutter test           # Run tests
```

## Architecture

AltCast is a Flutter movie & TV-show player that streams from a **Jellyfin** server. It is the sister app to AltSound and shares the same brand identity, design tokens, and overall architecture, but targets video items (Movie, Series, Season, Episode) instead of audio.

### Entry point & bootstrapping

`main.dart` configures system UI overlays and runs the app inside a `ProviderScope`. `app.dart` reads `routerProvider` and applies `AppTheme.dark()`; while auth is in `AuthInitial` state it shows a splash, then defers to the router.

### Data layer (`lib/data/`)

- **`jellyfin/`** — All Jellyfin API calls. `JellyfinApi` is the raw Dio client (session token in header, `Client="AltCast"`); `JellyfinRepository` is the business-logic layer (Continue Watching, Recently added Movies/Shows, image URL builders). `AuthRepository` handles login and persists the session via `flutter_secure_storage` under key `jellyfin_session_v1`.
- **`local/secure_storage.dart`** — Thin wrapper around `flutter_secure_storage`; used for the Jellyfin session today and other prefs as features land.

### State management (Riverpod)

| Pattern | Used for |
|---|---|
| `Provider` | Singletons — `jellyfinRepositoryProvider`, `authRepositoryProvider`, `routerProvider` |
| `NotifierProvider` | Mutable state — `authControllerProvider` |
| `FutureProvider.autoDispose` | Per-screen async data — `continueWatchingProvider`, `recentMoviesProvider`, `recentShowsProvider` |

### Routing (`lib/app/router.dart`)

GoRouter with an auth redirect guard (`authControllerProvider`). The bottom nav (Home / Search / Library) uses `StatefulShellRoute.indexedStack`. Detail and player routes will land in follow-up sessions.

### UI conventions

- Theme is defined in `AppTheme.dark()` (`lib/core/theme/`). Always use `AppColors` constants — never hardcode colours. Notable tokens: `AppColors.onAccent` (foreground on the accent gradient), `AppColors.like` (favorite/heart red — distinct from `AppColors.error`).
- Typography uses Manrope (body) and Space Grotesk (display/headlines) via `google_fonts`.
- Bottom sheets use `showDragHandle: true`; the theme sets `surfaceElevated` background and 24 px top radius automatically.
- Section headers in lists use `Theme.of(context).textTheme.labelLarge` (11 px, 700 weight, 1.4 letter-spacing, uppercased).
- Skeleton loading uses `Skeleton.group` / `Skeleton.line` from `lib/core/widgets/skeleton.dart`.
- Empty / error states use `EmptyState` and `ErrorStateView` from `lib/core/widgets/`.
- Spacing: **16 px** is the default horizontal padding for cards, list tiles, and inner layouts. **20 px** is used for top-level/tab-root horizontal padding (home, settings, sheet content). **32 px** is reserved for empty-state padding (`EdgeInsets.all(32)`). Avoid mixing 24 px horizontal — it's reserved for section vertical breaks.
- Back buttons use `BackButton(onPressed: () => context.pop())` — never a raw `IconButton(Icons.arrow_back)`.
- Artwork that may be local (downloaded) or remote uses `LocalOrNetworkImage` from `lib/core/widgets/`.
- Detail screens (movie / series / season) should wrap their scrollable in a `RefreshIndicator` whose `onRefresh` calls `ref.refresh(provider(id).future)`.

### Posters vs backdrops

- Movies & shows: 2:3 portrait Primary image — use `JellyfinRepository.posterUrl(...)` and the `PosterCard` widget.
- Episodes & resume cards: 16:9 — use `backdropUrl(...)` and the `ResumeCard` widget. Backdrops fall back to the Primary image when no Backdrop tag is present (episodes typically only have a Primary still).
