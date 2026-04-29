class PersonDetails {
  const PersonDetails({
    required this.id,
    required this.name,
    this.overview,
    this.imageTag,
    this.birthDate,
    this.deathDate,
    this.placeOfBirth,
  });

  final String id;
  final String name;
  final String? overview;
  final String? imageTag;
  final DateTime? birthDate;
  final DateTime? deathDate;
  final String? placeOfBirth;

  factory PersonDetails.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
    return PersonDetails(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Unknown',
      overview: json['Overview'] as String?,
      imageTag: (tags is Map && tags['Primary'] is String)
          ? tags['Primary'] as String
          : null,
      birthDate: DateTime.tryParse((json['BirthDate'] as String?) ?? ''),
      deathDate: DateTime.tryParse((json['DeathDate'] as String?) ?? ''),
      placeOfBirth: (json['PlaceOfBirth'] as String?)?.trim(),
    );
  }
}
