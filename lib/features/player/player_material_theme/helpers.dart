part of '../player_material_theme.dart';

String _formatPlayerTimestamp(Duration value) {
  if (value.isNegative) value = Duration.zero;
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

Future<void> _applyScreenBrightness(ScreenBrightness sb, double v) async {
  final x = v.clamp(0.0, 1.0);
  if (!kIsWeb) {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (await sb.canChangeSystemBrightness) {
          await sb.setSystemScreenBrightness(x);
          return;
        }
      } else {
        await sb.setSystemScreenBrightness(x);
        return;
      }
    } catch (e, st) {
      debugPrint('AltCast brightness (system): $e\n$st');
    }
  }
  try {
    await sb.setApplicationScreenBrightness(x);
  } catch (e, st) {
    debugPrint('AltCast brightness (application): $e\n$st');
  }
}

Future<void> _resetScreenBrightness(ScreenBrightness sb) async {
  try {
    await sb.resetApplicationScreenBrightness();
  } catch (e, st) {
    debugPrint('AltCast brightness reset (application): $e\n$st');
  }
}
