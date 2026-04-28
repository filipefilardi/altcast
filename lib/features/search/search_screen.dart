import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: EmptyState(
          icon: Icons.search,
          title: 'Search coming soon',
          message: 'Movie and show search lands in the next pass.',
        ),
      ),
    );
  }
}
