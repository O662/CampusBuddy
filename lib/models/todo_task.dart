import 'dart:convert';

enum TaskPriority { low, medium, high }

extension TaskPriorityLabel on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }
}

class TodoTask {
  final String id;
  final String categoryId;
  final String title;
  final String description;
  final DateTime? dueDate;
  final TaskPriority priority;
  bool isCompleted;
  final DateTime createdAt;

  TodoTask({
    required this.id,
    required this.categoryId,
    required this.title,
    this.description = '',
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.isCompleted = false,
    required this.createdAt,
  });

  TodoTask copyWith({
    String? id,
    String? categoryId,
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskPriority? priority,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return TodoTask(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'title': title,
        'description': description,
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority.name,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TodoTask.fromJson(Map<String, dynamic> json) => TodoTask(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        dueDate: json['dueDate'] != null
            ? DateTime.parse(json['dueDate'] as String)
            : null,
        priority: TaskPriority.values.firstWhere(
          (e) => e.name == json['priority'],
          orElse: () => TaskPriority.medium,
        ),
        isCompleted: json['isCompleted'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  static List<TodoTask> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => TodoTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<TodoTask> tasks) =>
      jsonEncode(tasks.map((t) => t.toJson()).toList());
}
