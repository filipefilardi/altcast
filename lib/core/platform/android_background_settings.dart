import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBackgroundSettings {
  AndroidBackgroundSettings._();

  static const _channel = MethodChannel(
    'com.silent_summit.altcast/android_background_settings',
  );

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openBatterySettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
