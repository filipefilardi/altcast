import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ClientMetadata {
  const ClientMetadata({required this.deviceName, required this.appVersion});

  final String deviceName;
  final String appVersion;
}

/// Loads a friendly device name and the app version for the Jellyfin
/// `Authorization` header. Called once at startup, before any auth/bind so
/// every request (including scrobbles) carries the right identifiers.
Future<ClientMetadata> loadClientMetadata() async {
  final deviceName = await _readDeviceName();
  final appVersion = await _readAppVersion();
  return ClientMetadata(deviceName: deviceName, appVersion: appVersion);
}

Future<String> _readDeviceName() async {
  final info = DeviceInfoPlugin();
  try {
    if (kIsWeb) {
      final web = await info.webBrowserInfo;
      return web.browserName.name;
    }
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.name;
    }
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return '${android.manufacturer} ${android.model}'.trim();
    }
    if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      return mac.computerName;
    }
    if (Platform.isWindows) {
      final win = await info.windowsInfo;
      return win.computerName;
    }
    if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      return linux.prettyName;
    }
  } catch (_) {
    // Fall through to default.
  }
  return 'Flutter';
}

Future<String> _readAppVersion() async {
  try {
    final pkg = await PackageInfo.fromPlatform();
    return pkg.version;
  } catch (_) {
    return '0.0.0';
  }
}
