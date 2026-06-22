class PersonCredit {
  const PersonCredit({
    required this.name,
    this.id,
    this.type,
    this.role,
    this.primaryImageTag,
  });

  final String name;
  final String? id;
  final String? type;
  final String? role;
  final String? primaryImageTag;

  String get subtitle {
    if (role != null && role!.trim().isNotEmpty) return role!.trim();
    if (type != null && type!.trim().isNotEmpty) return type!.trim();
    return '';
  }

  factory PersonCredit.fromJson(Map<String, dynamic> json) {
    return PersonCredit(
      name: (json['Name'] as String?)?.trim() ?? '',
      id: (json['Id'] as String?)?.trim(),
      type: (json['Type'] as String?)?.trim(),
      role: (json['Role'] as String?)?.trim(),
      primaryImageTag: (json['PrimaryImageTag'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'Name': name,
    if (id != null) 'Id': id,
    if (type != null) 'Type': type,
    if (role != null) 'Role': role,
    if (primaryImageTag != null) 'PrimaryImageTag': primaryImageTag,
  };
}
