import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:altcast/core/widgets/edge_light_background.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return EdgeLightBackground(
      child: Scaffold(body: SafeArea(bottom: false, child: navigationShell)),
    );
  }
}
