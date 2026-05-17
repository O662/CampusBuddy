import 'package:flutter/material.dart';

import '../core/theme/app_palette.dart';

/// All persisted domain models. Each is a plain immutable class with
/// `toJson`/`fromJson` so it can be stored as a primitive map in Hive —
/// no code generation, works identically on every platform including web.

enum Priority { low, medium, high }

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
      };
  Color get color => switch (this) {
        Priority.low => AppPalette.mint,
        Priority.medium => AppPalette.warning,
        Priority.high => AppPalette.danger,
      };
}

enum EventType { classSession, exam, deadline, personal }

extension EventTypeX on EventType {
  String get label => switch (this) {
        EventType.classSession => 'Class',
        EventType.exam => 'Exam',
        EventType.deadline => 'Deadline',
        EventType.personal => 'Personal',
      };
  IconData get icon => switch (this) {
        EventType.classSession => Icons.school_outlined,
        EventType.exam => Icons.quiz_outlined,
        EventType.deadline => Icons.flag_outlined,
        EventType.personal => Icons.favorite_outline,
      };
}

T _enum<T>(List<T> values, dynamic raw, T fallback) {
  if (raw is int && raw >= 0 && raw < values.length) return values[raw];
  return fallback;
}

class Course {
  const Course({
    required this.id,
    required this.name,
    this.colorSeed = 0,
    this.targetGrade = 90,
  });

  final String id;
  final String name;
  final int colorSeed;
  final double targetGrade;

  Color get color => AppPalette.swatchFor(colorSeed);

  Course copyWith({String? name, int? colorSeed, double? targetGrade}) =>
      Course(
        id: id,
        name: name ?? this.name,
        colorSeed: colorSeed ?? this.colorSeed,
        targetGrade: targetGrade ?? this.targetGrade,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorSeed': colorSeed,
        'targetGrade': targetGrade,
      };

  factory Course.fromJson(Map json) => Course(
        id: json['id'] as String,
        name: json['name'] as String,
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
        targetGrade: (json['targetGrade'] as num?)?.toDouble() ?? 90,
      );
}

/// One graded item inside a course (weighted toward the course grade).
class GradeEntry {
  const GradeEntry({
    required this.id,
    required this.courseId,
    required this.title,
    this.earned,
    required this.total,
    this.weight = 1,
    required this.date,
  });

  final String id;
  final String courseId;
  final String title;

  /// Points earned, or null when the item exists but isn't graded yet
  /// (e.g. an assignment task with no score entered). Ungraded entries
  /// show as "—" and are excluded from any average.
  final double? earned;
  final double total;
  final double weight;
  final DateTime date;

  bool get isGraded => earned != null;

  /// Percentage 0..100, or null while [isGraded] is false.
  double? get percent =>
      earned == null || total <= 0 ? null : (earned! / total) * 100;

  GradeEntry copyWith({
    String? title,
    double? earned,
    bool clearEarned = false,
    double? total,
    double? weight,
    DateTime? date,
  }) =>
      GradeEntry(
        id: id,
        courseId: courseId,
        title: title ?? this.title,
        earned: clearEarned ? null : (earned ?? this.earned),
        total: total ?? this.total,
        weight: weight ?? this.weight,
        date: date ?? this.date,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'earned': earned,
        'total': total,
        'weight': weight,
        'date': date.millisecondsSinceEpoch,
      };

  factory GradeEntry.fromJson(Map json) => GradeEntry(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        title: json['title'] as String,
        earned: (json['earned'] as num?)?.toDouble(),
        total: (json['total'] as num).toDouble(),
        weight: (json['weight'] as num?)?.toDouble() ?? 1,
        date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      );
}

/// A user-created folder that groups [TaskItem]s (e.g. by class or area of
/// life). A folder can optionally be linked to a [Course]; when it is, any
/// assignment task filed under it routes its grade to that course.
class TaskFolder {
  const TaskFolder({
    required this.id,
    required this.name,
    this.courseId,
    this.colorSeed = 0,
  });

  final String id;
  final String name;

  /// Optional [Course.id] this folder maps to. Null = not tied to a class.
  final String? courseId;
  final int colorSeed;

  Color get color => AppPalette.swatchFor(colorSeed);

  TaskFolder copyWith({
    String? name,
    String? courseId,
    bool clearCourse = false,
    int? colorSeed,
  }) =>
      TaskFolder(
        id: id,
        name: name ?? this.name,
        courseId: clearCourse ? null : (courseId ?? this.courseId),
        colorSeed: colorSeed ?? this.colorSeed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'courseId': courseId,
        'colorSeed': colorSeed,
      };

  factory TaskFolder.fromJson(Map json) => TaskFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        courseId: json['courseId'] as String?,
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
      );
}

/// The single unit of "things to do". A plain task by default; flip
/// [isAssignment] to mark it as coursework, which (when a class can be
/// resolved from [courseId] or the folder's link) keeps a placeholder grade
/// in sync under that course.
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.done = false,
    this.priority = Priority.medium,
    this.due,
    required this.createdAt,
    this.folderId,
    this.isAssignment = false,
    this.courseId,
    this.estimatedMinutes = 60,
  });

  final String id;
  final String title;
  final bool done;
  final Priority priority;
  final DateTime? due;
  final DateTime createdAt;

  /// Optional [TaskFolder.id] this task is filed under. Null = unfiled.
  final String? folderId;

  /// When true this task represents graded coursework.
  final bool isAssignment;

  /// Explicit [Course.id] for the grade link. Falls back to the folder's
  /// linked course when null (resolved in state, not here).
  final String? courseId;

  /// Rough effort estimate — drives the default block length on the planner.
  final int estimatedMinutes;

  TaskItem copyWith({
    String? title,
    bool? done,
    Priority? priority,
    DateTime? due,
    bool clearDue = false,
    String? folderId,
    bool clearFolder = false,
    bool? isAssignment,
    String? courseId,
    bool clearCourse = false,
    int? estimatedMinutes,
  }) =>
      TaskItem(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        priority: priority ?? this.priority,
        due: clearDue ? null : (due ?? this.due),
        createdAt: createdAt,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        isAssignment: isAssignment ?? this.isAssignment,
        courseId: clearCourse ? null : (courseId ?? this.courseId),
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'priority': priority.index,
        'due': due?.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'folderId': folderId,
        'isAssignment': isAssignment,
        'courseId': courseId,
        'estimatedMinutes': estimatedMinutes,
      };

  factory TaskItem.fromJson(Map json) => TaskItem(
        id: json['id'] as String,
        title: json['title'] as String,
        done: json['done'] as bool? ?? false,
        priority: _enum(Priority.values, json['priority'], Priority.medium),
        due: json['due'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['due'] as int),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        folderId: json['folderId'] as String?,
        isAssignment: json['isAssignment'] as bool? ?? false,
        courseId: json['courseId'] as String?,
        estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 60,
      );
}

/// A scheduled block of time on the planner. Created by dragging a to-do
/// onto a day, then resized/moved along the day.
class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.title,
    this.taskId,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    this.colorSeed = 0,
  });

  final String id;
  final String title;

  /// The [TaskItem.id] this block was scheduled from, if any.
  final String? taskId;

  /// Midnight of the day this block lives on.
  final DateTime day;

  /// Minutes from midnight.
  final int startMinute;
  final int endMinute;
  final int colorSeed;

  int get durationMinutes => endMinute - startMinute;
  Color get color => AppPalette.swatchFor(colorSeed);

  TimeBlock copyWith({
    String? title,
    DateTime? day,
    int? startMinute,
    int? endMinute,
  }) =>
      TimeBlock(
        id: id,
        title: title ?? this.title,
        taskId: taskId,
        day: day ?? this.day,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        colorSeed: colorSeed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'taskId': taskId,
        'day': day.millisecondsSinceEpoch,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'colorSeed': colorSeed,
      };

  factory TimeBlock.fromJson(Map json) => TimeBlock(
        id: json['id'] as String,
        title: json['title'] as String,
        // Read the legacy `assignmentId` key for blocks created before
        // assignments were merged into to-dos.
        taskId: (json['taskId'] ?? json['assignmentId']) as String?,
        day: DateTime.fromMillisecondsSinceEpoch(json['day'] as int),
        startMinute: (json['startMinute'] as num).toInt(),
        endMinute: (json['endMinute'] as num).toInt(),
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
      );
}

class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.start,
    this.type = EventType.personal,
    this.location = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final EventType type;
  final String location;

  EventItem copyWith({
    String? title,
    DateTime? start,
    EventType? type,
    String? location,
  }) =>
      EventItem(
        id: id,
        title: title ?? this.title,
        start: start ?? this.start,
        type: type ?? this.type,
        location: location ?? this.location,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'type': type.index,
        'location': location,
      };

  factory EventItem.fromJson(Map json) => EventItem(
        id: json['id'] as String,
        title: json['title'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(json['start'] as int),
        type: _enum(EventType.values, json['type'], EventType.personal),
        location: json['location'] as String? ?? '',
      );
}

class Deck {
  const Deck({
    required this.id,
    required this.name,
    this.description = '',
    this.colorSeed = 0,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final int colorSeed;
  final DateTime createdAt;

  Color get color => AppPalette.swatchFor(colorSeed);

  Deck copyWith({String? name, String? description, int? colorSeed}) => Deck(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        colorSeed: colorSeed ?? this.colorSeed,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'colorSeed': colorSeed,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Deck.fromJson(Map json) => Deck(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      );
}

/// A flashcard with Leitner spaced-repetition state (box 1..5).
class Flashcard {
  const Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.box = 1,
    DateTime? nextDue,
    this.lastReviewed,
  }) : _nextDue = nextDue;

  final String id;
  final String deckId;
  final String front;
  final String back;
  final int box;
  final DateTime? _nextDue;
  final DateTime? lastReviewed;

  DateTime get nextDue =>
      _nextDue ?? DateTime.fromMillisecondsSinceEpoch(0);
  bool get isDue => !nextDue.isAfter(DateTime.now());

  /// Leitner intervals in days per box.
  static const _intervals = [0, 1, 3, 7, 16, 35];

  Flashcard reviewed({required bool correct}) {
    final newBox = correct ? (box + 1).clamp(1, 5) : 1;
    final now = DateTime.now();
    return Flashcard(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      box: newBox,
      lastReviewed: now,
      nextDue: now.add(Duration(days: _intervals[newBox])),
    );
  }

  Flashcard copyWith({String? front, String? back}) => Flashcard(
        id: id,
        deckId: deckId,
        front: front ?? this.front,
        back: back ?? this.back,
        box: box,
        nextDue: _nextDue,
        lastReviewed: lastReviewed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deckId': deckId,
        'front': front,
        'back': back,
        'box': box,
        'nextDue': _nextDue?.millisecondsSinceEpoch,
        'lastReviewed': lastReviewed?.millisecondsSinceEpoch,
      };

  factory Flashcard.fromJson(Map json) => Flashcard(
        id: json['id'] as String,
        deckId: json['deckId'] as String,
        front: json['front'] as String,
        back: json['back'] as String,
        box: (json['box'] as num?)?.toInt() ?? 1,
        nextDue: json['nextDue'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['nextDue'] as int),
        lastReviewed: json['lastReviewed'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['lastReviewed'] as int),
      );
}

/// A single user profile + preferences (one row, stored under a fixed key).
class UserProfile {
  const UserProfile({
    this.name = 'Student',
    this.school = '',
    this.major = '',
    this.dailyGoalMinutes = 120,
    this.focusLengthMinutes = 25,
    this.breakLengthMinutes = 5,
  });

  final String name;
  final String school;
  final String major;
  final int dailyGoalMinutes;
  final int focusLengthMinutes;
  final int breakLengthMinutes;

  UserProfile copyWith({
    String? name,
    String? school,
    String? major,
    int? dailyGoalMinutes,
    int? focusLengthMinutes,
    int? breakLengthMinutes,
  }) =>
      UserProfile(
        name: name ?? this.name,
        school: school ?? this.school,
        major: major ?? this.major,
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        focusLengthMinutes: focusLengthMinutes ?? this.focusLengthMinutes,
        breakLengthMinutes: breakLengthMinutes ?? this.breakLengthMinutes,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'school': school,
        'major': major,
        'dailyGoalMinutes': dailyGoalMinutes,
        'focusLengthMinutes': focusLengthMinutes,
        'breakLengthMinutes': breakLengthMinutes,
      };

  factory UserProfile.fromJson(Map json) => UserProfile(
        name: json['name'] as String? ?? 'Student',
        school: json['school'] as String? ?? '',
        major: json['major'] as String? ?? '',
        dailyGoalMinutes: (json['dailyGoalMinutes'] as num?)?.toInt() ?? 120,
        focusLengthMinutes:
            (json['focusLengthMinutes'] as num?)?.toInt() ?? 25,
        breakLengthMinutes:
            (json['breakLengthMinutes'] as num?)?.toInt() ?? 5,
      );
}
