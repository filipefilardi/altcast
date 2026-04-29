/// Reads Jellyfin/TMDB-style original language hints from an item payload.
///
/// Prefer explicit `OriginalLanguage` when the server sends it; otherwise
/// match TMDB tag augmentation (`lang-xx`) used by some Jellyfin versions.
String? parseOriginalLanguageFromItemJson(Map<String, dynamic> json) {
  final direct = json['OriginalLanguage'] as String?;
  if (direct != null && direct.trim().isNotEmpty) {
    return direct.trim();
  }
  final tags = json['Tags'];
  if (tags is List) {
    for (final t in tags) {
      final s = t.toString().trim().toLowerCase();
      if (s.startsWith('lang-') && s.length > 5) {
        return s.substring(5).trim();
      }
    }
  }
  return null;
}
