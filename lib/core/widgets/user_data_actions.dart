import 'package:flutter/material.dart';
import 'package:picons/picons.dart';

import 'package:altcast/core/theme/app_colors.dart';
import 'package:altcast/core/widgets/app_snackbar.dart';

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
    required this.initialFavorite,
    required this.onSetFavorite,
  });

  final bool initialPlayed;
  final Future<void> Function(bool played) onSetPlayed;
  final bool initialFavorite;
  final Future<void> Function(bool favorite) onSetFavorite;

  @override
  State<UserDataActions> createState() => _UserDataActionsState();
}

class _UserDataActionsState extends State<UserDataActions> {
  late bool _played = widget.initialPlayed;
  late bool _favorite = widget.initialFavorite;
  bool _playedBusy = false;
  bool _favoriteBusy = false;

  @override
  void didUpdateWidget(covariant UserDataActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt incoming server state when not actively mid-toggle, so a parent
    // refresh doesn't fight our optimistic value.
    if (!_playedBusy && oldWidget.initialPlayed != widget.initialPlayed) {
      _played = widget.initialPlayed;
    }
    if (!_favoriteBusy && oldWidget.initialFavorite != widget.initialFavorite) {
      _favorite = widget.initialFavorite;
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

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final next = !_favorite;
    setState(() {
      _favorite = next;
      _favoriteBusy = true;
    });
    try {
      await widget.onSetFavorite(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorite = !next);
      _showError(
        next ? "Couldn't add to favorites" : "Couldn't remove from favorites",
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  void _showError(String message) {
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 22,
          tooltip: _favorite ? 'Remove from favorites' : 'Add to favorites',
          onPressed: _toggleFavorite,
          icon: Icon(
            _favorite ? PiconsFill.heart : PiconsRegular.heart,
            color: _favorite ? AppColors.like : AppColors.textSecondary,
          ),
        ),
        IconButton(
          iconSize: 22,
          tooltip: _played ? 'Mark as unwatched' : 'Mark as watched',
          onPressed: _togglePlayed,
          icon: Icon(
            PiconsRegular.checkCircle,
            color: _played ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
