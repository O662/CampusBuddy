import 'dart:convert';

class PlannedTask {
  final String id;
  final String taskId;
  final DateTime date;
  final int? startMinutes; // null = all-day planned
  final int durationMinutes;

  PlannedTask({
    required this.id,
    required this.taskId,
    required this.date,
    this.startMinutes,
    this.durationMinutes = 60,
  });

  PlannedTask copyWith({
    String? id,
    String? taskId,
    DateTime? date,
    int? startMinutes,
    bool clearStartMinutes = false,
    int? durationMinutes,
  }) {
    return PlannedTask(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      date: date ?? this.date,
      startMinutes:
          clearStartMinutes ? null : (startMinutes ?? this.startMinutes),
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'date': date.toIso8601String(),
        'startMinutes': startMinutes,
        'durationMinutes': durationMinutes,
      };

  factory PlannedTask.fromJson(Map<String, dynamic> json) => PlannedTask(
        id: json['id'] as String,
        taskId: json['taskId'] as String,
        date: DateTime.parse(json['date'] as String),
        startMinutes: json['startMinutes'] as int?,
        durationMinutes: json['durationMinutes'] as int? ?? 60,
      );

  static List<PlannedTask> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => PlannedTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<PlannedTask> items) =>
      jsonEncode(items.map((p) => p.toJson()).toList());
}
