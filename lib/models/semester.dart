import 'dart:convert';

class Semester {
  final String id;
  final String name; // e.g. "Fall 2024", "Spring 2025"
  final String institutionId;
  final int sortOrder;

  const Semester({
    required this.id,
    required this.name,
    required this.institutionId,
    this.sortOrder = 0,
  });

  Semester copyWith({
    String? id,
    String? name,
    String? institutionId,
    int? sortOrder,
  }) =>
      Semester(
        id: id ?? this.id,
        name: name ?? this.name,
        institutionId: institutionId ?? this.institutionId,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'institutionId': institutionId,
        'sortOrder': sortOrder,
      };

  factory Semester.fromJson(Map<String, dynamic> json) => Semester(
        id: json['id'] as String,
        name: json['name'] as String,
        institutionId: json['institutionId'] as String,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  static List<Semester> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => Semester.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<Semester> items) =>
      jsonEncode(items.map((s) => s.toJson()).toList());
}
