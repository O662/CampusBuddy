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

/// How often a [TaskItem] repeats. When a repeating task is completed, the
/// next occurrence is spawned automatically (see `TaskNotifier.save`).
enum Recurrence { none, daily, weekly, biweekly, monthly }

extension RecurrenceX on Recurrence {
  String get label => switch (this) {
        Recurrence.none => 'Does not repeat',
        Recurrence.daily => 'Daily',
        Recurrence.weekly => 'Weekly',
        Recurrence.biweekly => 'Every 2 weeks',
        Recurrence.monthly => 'Monthly',
      };

  bool get repeats => this != Recurrence.none;

  /// The next due date after [from] for this cadence (preserves time of
  /// day). Monthly rolls the month over; a short month just clamps via
  /// Dart's DateTime normalization.
  DateTime next(DateTime from) => switch (this) {
        Recurrence.none => from,
        Recurrence.daily => from.add(const Duration(days: 1)),
        Recurrence.weekly => from.add(const Duration(days: 7)),
        Recurrence.biweekly => from.add(const Duration(days: 14)),
        Recurrence.monthly => DateTime(
            from.year, from.month + 1, from.day, from.hour, from.minute),
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

/// Per-class grading scheme.
enum CourseGradingMode { graded, passFail, satisfactory }

extension CourseGradingModeX on CourseGradingMode {
  String get label => switch (this) {
        CourseGradingMode.graded => 'Graded',
        CourseGradingMode.passFail => 'Pass / Fail',
        CourseGradingMode.satisfactory => 'Satisfactory / Unsatisfactory',
      };
}

class Course {
  const Course({
    required this.id,
    required this.name,
    this.colorSeed = 0,
    this.targetGrade = 90,
    this.institutionId,
    this.semesterId,
    this.creditHours = 3,
    this.gradingMode = CourseGradingMode.graded,
    this.passCutoff = 60,
    this.cutoffA = 90,
    this.cutoffB = 80,
    this.cutoffC = 70,
    this.cutoffD = 60,
    this.extraCreditPct = 0,
    this.extraCreditIsPoints = false,
  });

  final String id;
  final String name;
  final int colorSeed;
  final double targetGrade;

  /// The [Institution] this live course belongs to; its grading system
  /// determines how this course's grade is shown. Null only transiently
  /// before the one-time migration assigns one.
  final String? institutionId;

  /// The [Semester] this live course runs in (must belong to
  /// [institutionId]). Null = not pinned to a term yet; the course then
  /// stays out of the live semester point on the GPA chart.
  final String? semesterId;

  /// Credit hours for this course — credit-weights it in the live
  /// semester GPA, mirroring how past classes work.
  final double creditHours;

  /// Per-class grading scheme. [graded] uses the institution's system plus
  /// the letter cutoffs below; the others are simple pass thresholds.
  final CourseGradingMode gradingMode;

  /// % at/above which the class is Pass / Satisfactory.
  final double passCutoff;

  /// Letter-band lower bounds (graded mode). F is below [cutoffD].
  final double cutoffA;
  final double cutoffB;
  final double cutoffC;
  final double cutoffD;

  /// Flat extra-credit / curve value added to the final course %
  /// (0 = none). Interpreted as points or a percentage per
  /// [extraCreditIsPoints]; both add to the final % the same way.
  final double extraCreditPct;

  /// Whether [extraCreditPct] is entered as points (true) or a
  /// percentage (false). Affects the label/suffix only.
  final bool extraCreditIsPoints;

  Color get color => AppPalette.swatchFor(colorSeed);

  /// Letter for a 0–100 [pct] using this course's cutoffs.
  String letterFor(double pct) {
    if (pct >= cutoffA) return 'A';
    if (pct >= cutoffB) return 'B';
    if (pct >= cutoffC) return 'C';
    if (pct >= cutoffD) return 'D';
    return 'F';
  }

  Course copyWith({
    String? name,
    int? colorSeed,
    double? targetGrade,
    String? institutionId,
    String? semesterId,
    bool clearSemester = false,
    double? creditHours,
    CourseGradingMode? gradingMode,
    double? passCutoff,
    double? cutoffA,
    double? cutoffB,
    double? cutoffC,
    double? cutoffD,
    double? extraCreditPct,
    bool? extraCreditIsPoints,
  }) =>
      Course(
        id: id,
        name: name ?? this.name,
        colorSeed: colorSeed ?? this.colorSeed,
        targetGrade: targetGrade ?? this.targetGrade,
        institutionId: institutionId ?? this.institutionId,
        semesterId:
            clearSemester ? null : (semesterId ?? this.semesterId),
        creditHours: creditHours ?? this.creditHours,
        gradingMode: gradingMode ?? this.gradingMode,
        passCutoff: passCutoff ?? this.passCutoff,
        cutoffA: cutoffA ?? this.cutoffA,
        cutoffB: cutoffB ?? this.cutoffB,
        cutoffC: cutoffC ?? this.cutoffC,
        cutoffD: cutoffD ?? this.cutoffD,
        extraCreditPct: extraCreditPct ?? this.extraCreditPct,
        extraCreditIsPoints:
            extraCreditIsPoints ?? this.extraCreditIsPoints,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorSeed': colorSeed,
        'targetGrade': targetGrade,
        'institutionId': institutionId,
        'semesterId': semesterId,
        'creditHours': creditHours,
        'gradingMode': gradingMode.index,
        'passCutoff': passCutoff,
        'cutoffA': cutoffA,
        'cutoffB': cutoffB,
        'cutoffC': cutoffC,
        'cutoffD': cutoffD,
        'extraCreditPct': extraCreditPct,
        'extraCreditIsPoints': extraCreditIsPoints,
      };

  factory Course.fromJson(Map json) => Course(
        id: json['id'] as String,
        name: json['name'] as String,
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
        targetGrade: (json['targetGrade'] as num?)?.toDouble() ?? 90,
        institutionId: json['institutionId'] as String?,
        semesterId: json['semesterId'] as String?,
        creditHours: (json['creditHours'] as num?)?.toDouble() ?? 3,
        gradingMode: _enum(CourseGradingMode.values, json['gradingMode'],
            CourseGradingMode.graded),
        passCutoff: (json['passCutoff'] as num?)?.toDouble() ?? 60,
        cutoffA: (json['cutoffA'] as num?)?.toDouble() ?? 90,
        cutoffB: (json['cutoffB'] as num?)?.toDouble() ?? 80,
        cutoffC: (json['cutoffC'] as num?)?.toDouble() ?? 70,
        cutoffD: (json['cutoffD'] as num?)?.toDouble() ?? 60,
        extraCreditPct: (json['extraCreditPct'] as num?)?.toDouble() ?? 0,
        extraCreditIsPoints:
            json['extraCreditIsPoints'] as bool? ?? false,
      );
}

/// A weighted bucket of grade items in a course (e.g. "Exams" = 40%).
class GradeCategory {
  const GradeCategory({
    required this.id,
    required this.courseId,
    required this.name,
    this.weightPercent = 0,
    this.order = 0,
  });

  final String id;
  final String courseId;
  final String name;
  final double weightPercent;

  /// Manual sort position within its course (drag-to-reorder).
  final int order;

  GradeCategory copyWith({String? name, double? weightPercent, int? order}) =>
      GradeCategory(
        id: id,
        courseId: courseId,
        name: name ?? this.name,
        weightPercent: weightPercent ?? this.weightPercent,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'name': name,
        'weightPercent': weightPercent,
        'order': order,
      };

  factory GradeCategory.fromJson(Map json) => GradeCategory(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        name: json['name'] as String? ?? '',
        weightPercent: (json['weightPercent'] as num?)?.toDouble() ?? 0,
        order: (json['order'] as num?)?.toInt() ?? 0,
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
    this.categoryId,
    this.extraCredit = false,
    this.extraCreditIsPoints = false,
    this.extraCreditValue,
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

  /// Optional [GradeCategory.id] this item is weighted under. Null =
  /// uncategorized.
  final String? categoryId;

  /// Whether this item carries an extra-credit bonus ([extraCreditValue])
  /// on top of its own [earned]/[total] score. An EC item with no base
  /// score (earned == null) is a stand-alone curve that flat-adds to the
  /// course % — see [isBonusOnly].
  final bool extraCredit;

  /// For an [extraCredit] item: whether the bonus is points (true, added
  /// to the earned score) or a percentage (false, added to this item's %).
  final bool extraCreditIsPoints;

  /// The extra-credit bonus amount (points or %, per
  /// [extraCreditIsPoints]). Null/0 = no bonus.
  final double? extraCreditValue;

  bool get isGraded => earned != null;

  /// A stand-alone curve: extra credit with no base score of its own. Its
  /// bonus flat-adds to the final course %, the legacy EC behaviour.
  bool get isBonusOnly => extraCredit && earned == null;

  /// Raw percentage 0..100 from the score alone, or null while not graded.
  double? get percent =>
      earned == null || total <= 0 ? null : (earned! / total) * 100;

  /// The percentage that actually counts toward the course average: the
  /// raw [percent] plus this item's own extra credit. Null when ungraded.
  /// Points add to the earned score; a percentage adds to the item's %.
  double? get effectivePercent {
    final p = percent;
    if (p == null) return null;
    final ec = extraCreditValue ?? 0;
    if (!extraCredit || ec == 0) return p;
    return extraCreditIsPoints ? ((earned! + ec) / total) * 100 : p + ec;
  }

  GradeEntry copyWith({
    String? title,
    double? earned,
    bool clearEarned = false,
    double? total,
    double? weight,
    DateTime? date,
    String? categoryId,
    bool clearCategory = false,
    bool? extraCredit,
    bool? extraCreditIsPoints,
    double? extraCreditValue,
    bool clearExtraCreditValue = false,
  }) =>
      GradeEntry(
        id: id,
        courseId: courseId,
        title: title ?? this.title,
        earned: clearEarned ? null : (earned ?? this.earned),
        total: total ?? this.total,
        weight: weight ?? this.weight,
        date: date ?? this.date,
        categoryId:
            clearCategory ? null : (categoryId ?? this.categoryId),
        extraCredit: extraCredit ?? this.extraCredit,
        extraCreditIsPoints:
            extraCreditIsPoints ?? this.extraCreditIsPoints,
        extraCreditValue: clearExtraCreditValue
            ? null
            : (extraCreditValue ?? this.extraCreditValue),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'earned': earned,
        'total': total,
        'weight': weight,
        'date': date.millisecondsSinceEpoch,
        'categoryId': categoryId,
        'extraCredit': extraCredit,
        'extraCreditIsPoints': extraCreditIsPoints,
        'extraCreditValue': extraCreditValue,
      };

  factory GradeEntry.fromJson(Map json) {
    final extraCredit = json['extraCredit'] as bool? ?? false;
    var earned = (json['earned'] as num?)?.toDouble();
    var ecValue = (json['extraCreditValue'] as num?)?.toDouble();
    // New entries always persist `extraCreditValue`. A pre-existing EC
    // entry without that key is a legacy flat-bonus item: the bonus lived
    // in `earned` (with total 0). Lift it into `extraCreditValue` and drop
    // `earned` so it stays a stand-alone curve under the new model.
    if (extraCredit && !json.containsKey('extraCreditValue')) {
      ecValue = earned;
      earned = null;
    }
    return GradeEntry(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      title: json['title'] as String,
      earned: earned,
      total: (json['total'] as num).toDouble(),
      weight: (json['weight'] as num?)?.toDouble() ?? 1,
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      categoryId: json['categoryId'] as String?,
      extraCredit: extraCredit,
      extraCreditIsPoints: json['extraCreditIsPoints'] as bool? ?? false,
      extraCreditValue: ecValue,
    );
  }
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
    this.recurrence = Recurrence.none,
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

  /// Repeat cadence. [Recurrence.none] = a one-off task.
  final Recurrence recurrence;

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
    Recurrence? recurrence,
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
        recurrence: recurrence ?? this.recurrence,
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
        'recurrence': recurrence.index,
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
        recurrence:
            _enum(Recurrence.values, json['recurrence'], Recurrence.none),
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

// ---------------------------------------------------------------------------
// Academic history — completed classes at (possibly multiple) institutions,
// feeding the per-semester + cumulative GPA chart. Grade points are entered
// directly (no letter mapping), weighted by credit hours. Kept entirely
// separate from the live Course/GradeEntry tracking.
// ---------------------------------------------------------------------------

/// How an institution grades. Set per institution in Profile and inherited
/// by that institution's live courses (and used to display their grade).
enum GradeSystem { percent, points, letter }

extension GradeSystemX on GradeSystem {
  String get label => switch (this) {
        GradeSystem.percent => 'Percentage (out of 100)',
        GradeSystem.points => 'GPA points',
        GradeSystem.letter => 'Letter grades',
      };
}

class Institution {
  const Institution({
    required this.id,
    required this.name,
    this.gradeSystem = GradeSystem.points,
    this.gpaScaleMax = 4.0,
    this.weighted = false,
    this.gpaComplex = false,
    this.usePlusMinus = false,
  });

  final String id;
  final String name;

  /// The grading style for every live course filed under this institution.
  final GradeSystem gradeSystem;

  /// Base top of the GPA scale for [GradeSystem.points] — 4.0, 5.0 or 6.0.
  /// [weighted] raises the effective ceiling by a full point.
  final double gpaScaleMax;

  /// Honors/weighted scale: a 5.0 weighted tops out at 6.0, 6.0 → 7.0…
  final bool weighted;

  /// points: complex = +/- fractional mapping (A 4.0, A− 3.7, B+ 3.3…);
  /// simple = whole steps (A 4.0, B 3.0, C 2.0…).
  final bool gpaComplex;

  /// letter: offer A-, B+ … in addition to whole letters.
  final bool usePlusMinus;

  /// Top of the scale once weighting is applied.
  double get effectiveGpaMax => gpaScaleMax + (weighted ? 1.0 : 0.0);

  Institution copyWith({
    String? name,
    GradeSystem? gradeSystem,
    double? gpaScaleMax,
    bool? weighted,
    bool? gpaComplex,
    bool? usePlusMinus,
  }) =>
      Institution(
        id: id,
        name: name ?? this.name,
        gradeSystem: gradeSystem ?? this.gradeSystem,
        gpaScaleMax: gpaScaleMax ?? this.gpaScaleMax,
        weighted: weighted ?? this.weighted,
        gpaComplex: gpaComplex ?? this.gpaComplex,
        usePlusMinus: usePlusMinus ?? this.usePlusMinus,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gradeSystem': gradeSystem.index,
        'gpaScaleMax': gpaScaleMax,
        'weighted': weighted,
        'gpaComplex': gpaComplex,
        'usePlusMinus': usePlusMinus,
      };

  factory Institution.fromJson(Map json) => Institution(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        gradeSystem:
            _enum(GradeSystem.values, json['gradeSystem'], GradeSystem.points),
        gpaScaleMax: (json['gpaScaleMax'] as num?)?.toDouble() ?? 4.0,
        weighted: json['weighted'] as bool? ?? false,
        // Legacy: the old "allowDecimals" flag ≈ complex/fractional GPA.
        gpaComplex:
            (json['gpaComplex'] ?? json['allowDecimals']) as bool? ?? false,
        usePlusMinus: json['usePlusMinus'] as bool? ?? false,
      );
}

/// Renders a 0–100 percentage in an institution's grading style using
/// standard US % bands (per-class cutoffs are handled in `courseResult`).
extension InstitutionGrading on Institution {
  String _letterFor(double pct) {
    String base;
    if (pct >= 90) {
      base = 'A';
    } else if (pct >= 80) {
      base = 'B';
    } else if (pct >= 70) {
      base = 'C';
    } else if (pct >= 60) {
      base = 'D';
    } else {
      return 'F';
    }
    if (!usePlusMinus || base == 'A' && pct >= 97) return base;
    final ones = pct.floor() % 10; // 0–9 within the letter band
    if (ones >= 7) return base == 'A' ? 'A' : '$base+';
    if (ones < 3) return '$base-';
    return base;
  }

  /// 0–100 % → GPA points: complex uses the +/- fractional table, simple
  /// uses whole steps; both rescaled to [effectiveGpaMax].
  double gpaPointsFor(double pct) {
    final double base;
    if (gpaComplex) {
      if (pct >= 93) {
        base = 4.0;
      } else if (pct >= 90) {
        base = 3.7;
      } else if (pct >= 87) {
        base = 3.3;
      } else if (pct >= 83) {
        base = 3.0;
      } else if (pct >= 80) {
        base = 2.7;
      } else if (pct >= 77) {
        base = 2.3;
      } else if (pct >= 73) {
        base = 2.0;
      } else if (pct >= 70) {
        base = 1.7;
      } else if (pct >= 67) {
        base = 1.3;
      } else if (pct >= 63) {
        base = 1.0;
      } else if (pct >= 60) {
        base = 0.7;
      } else {
        base = 0.0;
      }
    } else {
      if (pct >= 90) {
        base = 4.0;
      } else if (pct >= 80) {
        base = 3.0;
      } else if (pct >= 70) {
        base = 2.0;
      } else if (pct >= 60) {
        base = 1.0;
      } else {
        base = 0.0;
      }
    }
    return double.parse(
        (base * (effectiveGpaMax / 4.0)).toStringAsFixed(2));
  }

  String gpaText(double pct) {
    final g = gpaPointsFor(pct);
    return gpaComplex ? g.toStringAsFixed(2) : g.toStringAsFixed(1);
  }

  /// Display [pct] (0–100, or null = ungraded) in this institution's style.
  String format(double? pct) {
    if (pct == null) return '—';
    switch (gradeSystem) {
      case GradeSystem.percent:
        return '${pct.toStringAsFixed(1)}%';
      case GradeSystem.letter:
        return _letterFor(pct);
      case GradeSystem.points:
        return gpaText(pct);
    }
  }
}

enum AcademicTerm { spring, summer, fall, winter }

extension AcademicTermX on AcademicTerm {
  String get label => switch (this) {
        AcademicTerm.spring => 'Spring',
        AcademicTerm.summer => 'Summer',
        AcademicTerm.fall => 'Fall',
        AcademicTerm.winter => 'Winter',
      };
  String get short => switch (this) {
        AcademicTerm.spring => 'Sp',
        AcademicTerm.summer => 'Su',
        AcademicTerm.fall => 'Fa',
        AcademicTerm.winter => 'Wi',
      };
}

class Semester {
  const Semester({
    required this.id,
    required this.institutionId,
    this.term = AcademicTerm.fall,
    this.year = 2024,
    this.name = '',
  });

  final String id;
  final String institutionId;
  final AcademicTerm term;
  final int year;

  /// Optional custom label; falls back to "Term Year".
  final String name;

  String get label =>
      name.trim().isNotEmpty ? name.trim() : '${term.label} $year';
  String get shortLabel =>
      name.trim().isNotEmpty ? name.trim() : '${term.short}${year % 100}';

  /// Chronological ordering key: year, then term within the year.
  int get sortKey => year * 10 + term.index;

  Semester copyWith({
    String? institutionId,
    AcademicTerm? term,
    int? year,
    String? name,
  }) =>
      Semester(
        id: id,
        institutionId: institutionId ?? this.institutionId,
        term: term ?? this.term,
        year: year ?? this.year,
        name: name ?? this.name,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'institutionId': institutionId,
        'term': term.index,
        'year': year,
        'name': name,
      };

  factory Semester.fromJson(Map json) => Semester(
        id: json['id'] as String,
        institutionId: json['institutionId'] as String? ?? '',
        term: _enum(AcademicTerm.values, json['term'], AcademicTerm.fall),
        year: (json['year'] as num?)?.toInt() ?? 2024,
        name: json['name'] as String? ?? '',
      );
}

class PastCourse {
  const PastCourse({
    required this.id,
    required this.semesterId,
    required this.name,
    this.creditHours = 3,
    this.gradePoints = 4,
  });

  final String id;
  final String semesterId;
  final String name;
  final double creditHours;

  /// Grade points per credit, entered directly (e.g. 3.7). The class's
  /// quality points = [gradePoints] × [creditHours].
  final double gradePoints;

  double get qualityPoints => gradePoints * creditHours;

  PastCourse copyWith({
    String? semesterId,
    String? name,
    double? creditHours,
    double? gradePoints,
  }) =>
      PastCourse(
        id: id,
        semesterId: semesterId ?? this.semesterId,
        name: name ?? this.name,
        creditHours: creditHours ?? this.creditHours,
        gradePoints: gradePoints ?? this.gradePoints,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'semesterId': semesterId,
        'name': name,
        'creditHours': creditHours,
        'gradePoints': gradePoints,
      };

  factory PastCourse.fromJson(Map json) => PastCourse(
        id: json['id'] as String,
        semesterId: json['semesterId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        creditHours: (json['creditHours'] as num?)?.toDouble() ?? 3,
        gradePoints: (json['gradePoints'] as num?)?.toDouble() ?? 4,
      );
}

/// A free-text sticky note on the Notes board. Auto-saved as the user
/// types; [updatedAt] drives most-recent-first ordering.
class Note {
  const Note({
    required this.id,
    this.body = '',
    this.colorSeed = 0,
    required this.updatedAt,
  });

  final String id;
  final String body;
  final int colorSeed;
  final DateTime updatedAt;

  Color get color => AppPalette.swatchFor(colorSeed);

  Note copyWith({String? body, int? colorSeed, DateTime? updatedAt}) => Note(
        id: id,
        body: body ?? this.body,
        colorSeed: colorSeed ?? this.colorSeed,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'colorSeed': colorSeed,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromJson(Map json) => Note(
        id: json['id'] as String,
        body: json['body'] as String? ?? '',
        colorSeed: (json['colorSeed'] as num?)?.toInt() ?? 0,
        updatedAt: json['updatedAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
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
