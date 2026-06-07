/// Maps an ISO 639-1/2/3 language code to a human-readable English name.
///
/// Returns null for empty input, the literal `"und"`/`"unknown"` (Jellyfin's
/// "undetermined" sentinel), or codes we don't recognize — letting callers
/// decide whether to fall back to the raw code or omit the field entirely.
///
/// Intentionally not exhaustive: covers the ~50 most common codes seen on
/// Jellyfin libraries. Extend if a user reports a gap.
String? languageDisplay(String? raw) {
  final code = canonicalLanguageKey(raw);
  if (code == null) return null;
  return _iso[code];
}

String? canonicalLanguageKey(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
  final displayMatch = _canonicalByDisplayLower[normalized];
  if (displayMatch != null) return displayMatch;
  final code = normalized.split('-').first;
  if (code.isEmpty || code == 'und' || code == 'unknown') return null;
  final display = _iso[code];
  if (display == null) return code;
  // Collapse aliases (e.g. `en`/`eng`) onto the first key sharing the display
  // name, so two codes for the same language compare equal.
  return _canonicalByDisplay[display] ?? code;
}

bool languageCodesMatch(String? a, String? b) {
  final left = canonicalLanguageKey(a);
  final right = canonicalLanguageKey(b);
  return left != null && right != null && left == right;
}

const _iso = <String, String>{
  // Most common, by world population / streaming usage.
  'en': 'English', 'eng': 'English',
  'es': 'Spanish', 'spa': 'Spanish',
  'pt': 'Portuguese', 'por': 'Portuguese',
  'fr': 'French', 'fra': 'French', 'fre': 'French',
  'de': 'German', 'deu': 'German', 'ger': 'German',
  'it': 'Italian', 'ita': 'Italian',
  'ja': 'Japanese', 'jpn': 'Japanese',
  'zh': 'Chinese', 'zho': 'Chinese', 'chi': 'Chinese',
  'ko': 'Korean', 'kor': 'Korean',
  'ru': 'Russian', 'rus': 'Russian',
  'ar': 'Arabic', 'ara': 'Arabic',
  'hi': 'Hindi', 'hin': 'Hindi',
  'bn': 'Bengali', 'ben': 'Bengali',
  'tr': 'Turkish', 'tur': 'Turkish',
  'pl': 'Polish', 'pol': 'Polish',
  'nl': 'Dutch', 'nld': 'Dutch', 'dut': 'Dutch',
  'sv': 'Swedish', 'swe': 'Swedish',
  'no': 'Norwegian', 'nor': 'Norwegian',
  'da': 'Danish', 'dan': 'Danish',
  'fi': 'Finnish', 'fin': 'Finnish',
  'is': 'Icelandic', 'isl': 'Icelandic', 'ice': 'Icelandic',
  'cs': 'Czech', 'ces': 'Czech', 'cze': 'Czech',
  'sk': 'Slovak', 'slk': 'Slovak', 'slo': 'Slovak',
  'hu': 'Hungarian', 'hun': 'Hungarian',
  'ro': 'Romanian', 'ron': 'Romanian', 'rum': 'Romanian',
  'el': 'Greek', 'ell': 'Greek', 'gre': 'Greek',
  'bg': 'Bulgarian', 'bul': 'Bulgarian',
  'sr': 'Serbian', 'srp': 'Serbian',
  'hr': 'Croatian', 'hrv': 'Croatian',
  'uk': 'Ukrainian', 'ukr': 'Ukrainian',
  'he': 'Hebrew', 'heb': 'Hebrew',
  'fa': 'Persian', 'fas': 'Persian', 'per': 'Persian',
  'th': 'Thai', 'tha': 'Thai',
  'vi': 'Vietnamese', 'vie': 'Vietnamese',
  'id': 'Indonesian', 'ind': 'Indonesian',
  'ms': 'Malay', 'msa': 'Malay', 'may': 'Malay',
  'ta': 'Tamil', 'tam': 'Tamil',
  'te': 'Telugu', 'tel': 'Telugu',
  'mr': 'Marathi', 'mar': 'Marathi',
  'gu': 'Gujarati', 'guj': 'Gujarati',
  'ur': 'Urdu', 'urd': 'Urdu',
  'la': 'Latin', 'lat': 'Latin',
  'ca': 'Catalan', 'cat': 'Catalan',
  'gl': 'Galician', 'glg': 'Galician',
  'eu': 'Basque', 'eus': 'Basque', 'baq': 'Basque',
};

/// Display name → first `_iso` key that produces it. Lets [canonicalLanguageKey]
/// resolve aliases without rescanning `_iso` on every call.
final Map<String, String> _canonicalByDisplay = () {
  final map = <String, String>{};
  for (final entry in _iso.entries) {
    map.putIfAbsent(entry.value, () => entry.key);
  }
  return map;
}();

final Map<String, String> _canonicalByDisplayLower = {
  for (final entry in _canonicalByDisplay.entries)
    entry.key.toLowerCase(): entry.value,
};
