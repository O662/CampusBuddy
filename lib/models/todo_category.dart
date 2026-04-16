import 'dart:convert';
import 'package:flutter/material.dart';

class TodoCategory {
  final String id;
  final String name;
  final int colorValue;
  final String iconKey;

  TodoCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
  });

  Color get color => Color(colorValue);

  static const Map<String, IconData> icons = {
    'school': Icons.school,
    'calculate': Icons.calculate,
    'science': Icons.science,
    'history': Icons.history_edu,
    'language': Icons.language,
    'code': Icons.code,
    'sports': Icons.sports,
    'music': Icons.music_note,
    'art': Icons.brush,
    'business': Icons.business_center,
    'book': Icons.book,
    'biotech': Icons.biotech,
    'psychology': Icons.psychology,
    'computer': Icons.computer,
  };

  static const List<int> palette = [
    0xFFEF5350,
    0xFFEC407A,
    0xFFAB47BC,
    0xFF7E57C2,
    0xFF5C6BC0,
    0xFF42A5F5,
    0xFF26C6DA,
    0xFF26A69A,
    0xFF66BB6A,
    0xFFFFCA28,
    0xFFFFA726,
    0xFF8D6E63,
  ];

  IconData get icon => icons[iconKey] ?? Icons.folder;

  TodoCategory copyWith({
    String? id,
    String? name,
    int? colorValue,
    String? iconKey,
  }) {
    return TodoCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
      };

  factory TodoCategory.fromJson(Map<String, dynamic> json) => TodoCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int,
        iconKey: json['iconKey'] as String,
      );

  static List<TodoCategory> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => TodoCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<TodoCategory> cats) =>
      jsonEncode(cats.map((c) => c.toJson()).toList());
}
