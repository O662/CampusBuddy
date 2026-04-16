import 'dart:convert';

enum TaskCategory { assignment, exam, quiz, project, other }

extension TaskCategoryLabel on TaskCategory {
  String get label {
    switch (this) {
      case TaskCategory.assignment:
        return 'Assignment';
      case TaskCategory.exam:
        return 'Exam';
      case TaskCategory.quiz:
        return 'Quiz';
      case TaskCategory.project:
        return 'Project';
      case TaskCategory.other:
        return 'Other';
    }
  }
}

class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final TaskCategory category;
  bool isCompleted;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.category,
    this.isCompleted = false,
  });

  Task copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    TaskCategory? category,
    bool? isCompleted,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      category: category ?? this.category,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dueDate': dueDate.toIso8601String(),
        'category': category.name,
        'isCompleted': isCompleted,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        dueDate: DateTime.parse(json['dueDate'] as String),
        category: TaskCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => TaskCategory.other,
        ),
        isCompleted: json['isCompleted'] as bool,
      );

  static List<Task> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Task> tasks) =>
      jsonEncode(tasks.map((t) => t.toJson()).toList());
}
