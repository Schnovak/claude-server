enum ProjectType {
  flutter,
  web,
  node,
  python,
  other;

  static ProjectType fromString(String value) {
    return ProjectType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ProjectType.other,
    );
  }
}

class Project {
  final String id;
  final String ownerId;
  final String name;
  final ProjectType type;
  final String rootPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.rootPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      ownerId: json['owner_id'],
      name: json['name'],
      type: ProjectType.fromString(json['type']),
      rootPath: json['root_path'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'name': name,
      'type': type.name,
    };
  }
}
