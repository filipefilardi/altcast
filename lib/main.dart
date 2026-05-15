import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'data/jellyfin/auth_repository.dart';
import 'data/jellyfin/client_metadata.dart';
import 'data/jellyfin/jellyfin_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initializes libmpv (desktop/mobile) and HTML5 video bindings (web).
  // Must run before any [Player] is constructed.
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final metadata = await loadClientMetadata();
  final api = JellyfinApi(
    deviceName: metadata.deviceName,
    appVersion: metadata.appVersion,
  );

  runApp(
    ProviderScope(
      overrides: [jellyfinApiProvider.overrideWithValue(api)],
      child: const AltCastApp(),
    ),
  );
}
