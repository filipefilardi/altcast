import 'package:flutter/material.dart';

TextStyle playbackSubtitleTextStyle(double fontSize) {
  return TextStyle(
    fontSize: fontSize,
    color: Colors.white,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0,
    shadows: const [
      Shadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0xCC000000)),
      Shadow(offset: Offset(0, 0), blurRadius: 3, color: Color(0x99000000)),
    ],
  );
}
