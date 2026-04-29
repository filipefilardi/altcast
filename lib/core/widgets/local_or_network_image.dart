import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders an image from either a local `file://` URI / path or a remote
/// http(s) URL, dispatching to the right loader. Falls back to [errorBuilder]
/// (or a transparent box) when [source] is null/empty or fails to load.
///
/// Use this when an artwork URL may be either a local downloaded asset (set
/// via `Uri.file(...)` in the player layer) or a remote Jellyfin URL.
class LocalOrNetworkImage extends StatelessWidget {
  const LocalOrNetworkImage({
    required this.source,
    this.fit = BoxFit.cover,
    this.placeholderBuilder,
    this.errorBuilder,
    super.key,
  });

  /// Either a `file://...` URI, a bare absolute file path, or an `http(s)://`
  /// URL. `null` or empty is treated as missing.
  final String? source;
  final BoxFit fit;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  Widget _fallback(BuildContext context) =>
      errorBuilder?.call(context) ?? const SizedBox.expand();

  @override
  Widget build(BuildContext context) {
    final src = source;
    if (src == null || src.isEmpty) return _fallback(context);

    if (src.startsWith('file://') || src.startsWith('/')) {
      try {
        final path = src.startsWith('file://')
            ? Uri.parse(src).toFilePath()
            : src;
        return Image.file(
          File(path),
          fit: fit,
          errorBuilder: (ctx, _, _) => _fallback(ctx),
        );
      } catch (_) {
        return _fallback(context);
      }
    }

    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      placeholder: placeholderBuilder == null
          ? null
          : (ctx, _) => placeholderBuilder!(ctx),
      errorWidget: (ctx, _, _) => _fallback(ctx),
    );
  }
}
