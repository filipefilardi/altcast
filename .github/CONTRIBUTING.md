# Contributing to AltCast

Thanks for your interest in contributing to AltCast.

This guide explains how to propose changes, set up your environment, and submit pull requests that are easy to review.

## Code of Conduct

By participating in this project, you agree to follow our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Before You Start

- Check existing issues and pull requests to avoid duplicate work.
- For non-trivial features or refactors, open an issue first so we can align on scope and approach.
- Keep contributions focused: one fix or feature per pull request whenever possible.

## Development Setup

### Prerequisites

- Flutter SDK (stable) with Dart `^3.8.1`
- A running Jellyfin server with a music library for manual testing
- Platform tooling as needed:
  - Xcode for iOS/macOS
  - Android SDK / Android Studio for Android

### Clone and Run

```bash
git clone https://github.com/filipefilardi/altcast.git
cd altcast
flutter pub get
flutter run
```

## Branching

- Branch from `main`.
- Use descriptive branch names, for example:
  - `feat/offline-playlist-filter`
  - `fix/player-seekbar-snap`
  - `chore/dependency-updates`

## Coding Guidelines

- Follow existing architecture and style in `lib/`.
- Use package imports (`package:altcast/...`) rather than relative imports where applicable.
- Keep widgets and controllers small and focused.
- Avoid unrelated formatting-only changes in functional PRs.
- Add comments only when logic is non-obvious.

## Quality Checks

Run these before opening a PR:

```bash
flutter analyze
flutter test
```

If your change touches platform-specific behavior, also run the app on the relevant platform (Android, iOS, and/or macOS) and include the result in the PR description.

## Pull Request Checklist

Include the following in your PR:

- Clear title and summary of what changed
- Why the change is needed
- Screenshots or short recordings for UI changes (if applicable)
- Testing notes (what you ran and what you validated manually)
- Linked issue(s), using `Closes #<issue-number>` when appropriate

## Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/). The prefix matters — it drives both release-note grouping **and** the next version number:

| Prefix | Example | Triggers |
| --- | --- | --- |
| `feat:` | `feat: add artist download button` | **minor** version bump |
| `fix:` / `perf:` | `fix: prevent duplicate tracks in queue` | **patch** version bump |
| `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer | `feat!: drop iOS 13 support` | **major** version bump |
| `chore:` / `docs:` / `refactor:` / `style:` / `test:` / `ci:` / `build:` | `chore: bump flutter_riverpod to latest` | no release |

Use imperative mood ("add", not "adds" or "added"). Keep the subject under 72 characters.

If your PR title (typically used as the merge commit message) follows this format, the release workflow will pick the right version bump automatically. Maintainers can also override via the workflow's manual "Run workflow" button.

## Reporting Bugs

When opening a bug report, include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- Platform/device details
- App version (`Settings -> Version`) if available
- Relevant logs or screenshots

## Feature Requests

Feature requests are welcome. Please describe:

- The problem you are trying to solve
- The proposed solution
- Any alternatives considered

## Release and CI Notes

Every push to `main` runs `.github/workflows/release.yml`. The workflow:

1. **Parses Conventional Commits** since the last release to pick a bump (`feat:` → minor, `fix:`/`perf:` → patch, breaking change → major). If no releasable commits are present, the release is skipped.
2. **Builds** Android (AAB), macOS (unsigned `.app`), and iOS (unsigned `.ipa`) in parallel.
3. **Publishes** a single GitHub Release with all three artifacts.
4. **Deploys** the Android AAB to Google Play's *internal* track as a *draft* — a maintainer manually promotes it to production from the Play Console.

Maintainers can override the auto-detected bump via the workflow's manual "Run workflow" button (`bump: patch | minor | major | skip`).

Contributors do not need to handle release secrets or deployment setup — maintainers manage those credentials.

## Questions

If anything is unclear, open an issue and ask. Small, iterative PRs are encouraged.
