import 'package:flutter/material.dart';

import 'package:altcast/core/theme/app_colors.dart';

/// Watched toggle used on the movie / series detail screens.
///
/// Owns optimistic local state: a tap flips the icon immediately and only
/// reverts (with a snackbar) if the underlying call fails. Callers wire the
/// API side via [onSetPlayed].
class UserDataActions extends StatefulWidget {
  const UserDataActions({
    super.key,
    required this.initialPlayed,
    required this.onSetPlayed,
  });

  final bool initialPlayed;
  final Future<void> Function(bool played) onSetPlayed;

  @override
  State<UserDataActions> createState() => _UserDataActionsState();
}

class _UserDataActionsState extends State<UserDataActions> {
  late bool _played = widget.initialPlayed;
  bool _playedBusy = false;

  @override
  void didUpdateWidget(covariant UserDataActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt incoming server state when not actively mid-toggle, so a parent
    // refresh doesn't fight our optimistic value.
    if (!_playedBusy && oldWidget.initialPlayed != widget.initialPlayed) {
      _played = widget.initialPlayed;
    }
  }

  Future<void> _togglePlayed() async {
    if (_playedBusy) return;
    final next = !_played;
    setState(() {
      _played = next;
      _playedBusy = true;
    });
    try {
      await widget.onSetPlayed(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _played = !next);
      _showError(
        next ? "Couldn't mark as watched" : "Couldn't mark as unwatched",
      );
    } finally {
      if (mounted) setState(() => _playedBusy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 22,
          tooltip: _played ? 'Mark as unwatched' : 'Mark as watched',
          onPressed: _togglePlayed,
          icon: Icon(
            _played ? Icons.check_circle : Icons.check_circle_outline,
            color: _played ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
