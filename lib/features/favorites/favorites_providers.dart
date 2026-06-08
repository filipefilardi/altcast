import 'package:flutter_riverpod/flutter_riverpod.dart';

class FavoritesRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final favoritesRevisionProvider =
    NotifierProvider<FavoritesRevisionNotifier, int>(
      FavoritesRevisionNotifier.new,
    );
