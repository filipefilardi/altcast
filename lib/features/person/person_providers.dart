import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/browse_item.dart';
import '../../data/jellyfin/models/person_details.dart';

final personProvider = FutureProvider.autoDispose.family<PersonDetails, String>(
  (ref, id) {
    return ref.watch(jellyfinRepositoryProvider).getPerson(id);
  },
);

final personItemsProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getItemsByPerson(id);
    });
