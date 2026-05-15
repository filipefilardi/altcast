import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altcast/data/jellyfin/jellyfin_repository.dart';
import 'package:altcast/data/jellyfin/models/browse_item.dart';
import 'package:altcast/data/jellyfin/models/person_details.dart';

final personProvider = FutureProvider.autoDispose.family<PersonDetails, String>(
  (ref, id) {
    return ref.watch(jellyfinRepositoryProvider).getPerson(id);
  },
);

final personItemsProvider = FutureProvider.autoDispose
    .family<List<BrowseItem>, String>((ref, id) {
      return ref.watch(jellyfinRepositoryProvider).getItemsByPerson(id);
    });
