import 'dart:convert';

class Institution {
  final String id;
  final String name;
  final double gpaScale; // 4.0 or 5.0

  const Institution({
    required this.id,
    required this.name,
    this.gpaScale = 4.0,
  });

  Institution copyWith({String? id, String? name, double? gpaScale}) =>
      Institution(
        id: id ?? this.id,
        name: name ?? this.name,
        gpaScale: gpaScale ?? this.gpaScale,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gpaScale': gpaScale,
      };

  factory Institution.fromJson(Map<String, dynamic> json) => Institution(
        id: json['id'] as String,
        name: json['name'] as String,
        gpaScale: (json['gpaScale'] as num?)?.toDouble() ?? 4.0,
      );

  static List<Institution> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => Institution.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<Institution> items) =>
      jsonEncode(items.map((i) => i.toJson()).toList());
}
