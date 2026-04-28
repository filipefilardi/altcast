import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: EmptyState(
          icon: Icons.video_library_outlined,
          title: 'Your library lives here',
          message: 'Coming soon — browse movies and shows by collection.',
        ),
      ),
    );
  }
}
