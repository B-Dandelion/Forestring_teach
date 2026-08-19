class AcademyBranch {
  const AcademyBranch({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory AcademyBranch.fromJson(
    Map<String, dynamic> json,
  ) {
    return AcademyBranch(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
    );
  }
}
