import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/models/browse_item.dart';

/// Pushes the right detail route for a [BrowseItem] based on its
/// [MediaKind]. Centralised so every list/grid in the app routes the same
/// way (Home, Search, Library, Person, Continue Watching, etc).
void openItemDetail(BuildContext context, BrowseItem item) {
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
    case MediaKind.collection:
      context.push(
        Uri(
          path: '/collection/${item.id}',
          queryParameters: {'title': item.name},
        ).toString(),
      );
  }
}
