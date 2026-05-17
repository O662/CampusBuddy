import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/models.dart';

/// Bound to the initialized [LocalStore] in `main()` via an override.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

/// Generic CRUD notifier backed by one Hive box. Concrete collections only
/// supply the box name and (de)serialization.
abstract class CollectionNotifier<T> extends Notifier<List<T>> {
  String get boxName;
  String idOf(T item);
  Map<String, dynamic> encode(T item);
  T decode(Map<dynamic, dynamic> json);

  LocalStore get _store => ref.read(localStoreProvider);

  @override
  List<T> build() => _read();

  List<T> _read() => _store
      .box(boxName)
      .values
      .whereType<Map>()
      .map((e) => decode(e))
      .toList();

  Future<void> upsert(T item) async {
    await _store.box(boxName).put(idOf(item), encode(item));
    state = _read();
  }

  Future<void> upsertAll(Iterable<T> items) async {
    final box = _store.box(boxName);
    for (final item in items) {
      await box.put(idOf(item), encode(item));
    }
    state = _read();
  }

  Future<void> remove(String id) async {
    await _store.box(boxName).delete(id);
    state = _read();
  }
}

class CourseNotifier extends CollectionNotifier<Course> {
  @override
  String get boxName => LocalStore.courses;
  @override
  String idOf(Course i) => i.id;
  @override
  Map<String, dynamic> encode(Course i) => i.toJson();
  @override
  Course decode(Map j) => Course.fromJson(j);
}

class GradeNotifier extends CollectionNotifier<GradeEntry> {
  @override
  String get boxName => LocalStore.grades;
  @override
  String idOf(GradeEntry i) => i.id;
  @override
  Map<String, dynamic> encode(GradeEntry i) => i.toJson();
  @override
  GradeEntry decode(Map j) => GradeEntry.fromJson(j);
}

class FolderNotifier extends CollectionNotifier<TaskFolder> {
  @override
  String get boxName => LocalStore.folders;
  @override
  String idOf(TaskFolder i) => i.id;
  @override
  Map<String, dynamic> encode(TaskFolder i) => i.toJson();
  @override
  TaskFolder decode(Map j) => TaskFolder.fromJson(j);
}

class TaskNotifier extends CollectionNotifier<TaskItem> {
  @override
  String get boxName => LocalStore.tasks;
  @override
  String idOf(TaskItem i) => i.id;
  @override
  Map<String, dynamic> encode(TaskItem i) => i.toJson();
  @override
  TaskItem decode(Map j) => TaskItem.fromJson(j);

  /// Stable id for the grade entry mirrored from an assignment task.
  String _gradeId(String taskId) => 'task-$taskId';

  TaskItem? _byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  GradeEntry? _linkedGrade(String taskId) {
    final id = _gradeId(taskId);
    for (final g in ref.read(gradesProvider)) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Course for an assignment task: an explicit [TaskItem.courseId] wins,
  /// otherwise the linked course of its folder, otherwise none.
  String? _resolveCourseId(TaskItem t) {
    if (t.courseId != null) return t.courseId;
    if (t.folderId == null) return null;
    for (final f in ref.read(foldersProvider)) {
      if (f.id == t.folderId) return f.courseId;
    }
    return null;
  }

  /// Persist a task and keep its placeholder grade in sync. Use this from
  /// the UI instead of [upsert] so the assignment↔grade link is maintained.
  Future<void> save(TaskItem task) async {
    await upsert(task);
    await _syncGrade(task);
  }

  /// Remove a task; drop its placeholder grade only when still ungraded
  /// (a real recorded score is kept as standalone academic history).
  Future<void> delete(String id) async {
    final task = _byId(id);
    await remove(id);
    if (task == null) return;
    final g = _linkedGrade(id);
    if (g != null && !g.isGraded) {
      await ref.read(gradesProvider.notifier).remove(_gradeId(id));
    }
  }

  Future<void> _syncGrade(TaskItem t) async {
    final grades = ref.read(gradesProvider.notifier);
    final existing = _linkedGrade(t.id);
    final courseId = _resolveCourseId(t);

    if (t.isAssignment && courseId != null) {
      // Create an ungraded placeholder (earned == null → shows "—" and is
      // left out of the average), or mirror title/class onto an existing
      // entry without clobbering a score the user may have filled in.
      await grades.upsert(GradeEntry(
        id: _gradeId(t.id),
        courseId: courseId,
        title: t.title,
        earned: existing?.earned,
        total: existing?.total ?? 100,
        weight: existing?.weight ?? 1,
        date: existing?.date ?? t.due ?? DateTime.now(),
      ));
    } else if (existing != null) {
      // No longer an assignment, or no class can be resolved.
      await grades.remove(_gradeId(t.id));
    }
  }
}

class BlockNotifier extends CollectionNotifier<TimeBlock> {
  @override
  String get boxName => LocalStore.blocks;
  @override
  String idOf(TimeBlock i) => i.id;
  @override
  Map<String, dynamic> encode(TimeBlock i) => i.toJson();
  @override
  TimeBlock decode(Map j) => TimeBlock.fromJson(j);
}

class EventNotifier extends CollectionNotifier<EventItem> {
  @override
  String get boxName => LocalStore.events;
  @override
  String idOf(EventItem i) => i.id;
  @override
  Map<String, dynamic> encode(EventItem i) => i.toJson();
  @override
  EventItem decode(Map j) => EventItem.fromJson(j);
}

class DeckNotifier extends CollectionNotifier<Deck> {
  @override
  String get boxName => LocalStore.decks;
  @override
  String idOf(Deck i) => i.id;
  @override
  Map<String, dynamic> encode(Deck i) => i.toJson();
  @override
  Deck decode(Map j) => Deck.fromJson(j);
}

class CardNotifier extends CollectionNotifier<Flashcard> {
  @override
  String get boxName => LocalStore.cards;
  @override
  String idOf(Flashcard i) => i.id;
  @override
  Map<String, dynamic> encode(Flashcard i) => i.toJson();
  @override
  Flashcard decode(Map j) => Flashcard.fromJson(j);
}

final coursesProvider =
    NotifierProvider<CourseNotifier, List<Course>>(CourseNotifier.new);
final gradesProvider =
    NotifierProvider<GradeNotifier, List<GradeEntry>>(GradeNotifier.new);
final foldersProvider =
    NotifierProvider<FolderNotifier, List<TaskFolder>>(FolderNotifier.new);
final tasksProvider =
    NotifierProvider<TaskNotifier, List<TaskItem>>(TaskNotifier.new);
final blocksProvider =
    NotifierProvider<BlockNotifier, List<TimeBlock>>(BlockNotifier.new);
final eventsProvider =
    NotifierProvider<EventNotifier, List<EventItem>>(EventNotifier.new);
final decksProvider =
    NotifierProvider<DeckNotifier, List<Deck>>(DeckNotifier.new);
final cardsProvider =
    NotifierProvider<CardNotifier, List<Flashcard>>(CardNotifier.new);

class ProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() => ref.read(localStoreProvider).readProfile();

  Future<void> save(UserProfile profile) async {
    await ref.read(localStoreProvider).writeProfile(profile);
    state = profile;
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

// ---------------------------------------------------------------------------
// Derived / computed providers
// ---------------------------------------------------------------------------

final coursesByIdProvider = Provider<Map<String, Course>>((ref) {
  return {for (final c in ref.watch(coursesProvider)) c.id: c};
});

/// Open, due-dated tasks sorted soonest-first — the schedulable backlog
/// shown on the planner and dashboard. Assignment tasks float ahead of
/// plain ones on the same day.
final upcomingTasksProvider = Provider<List<TaskItem>>((ref) {
  final list = ref
      .watch(tasksProvider)
      .where((t) => !t.done && t.due != null)
      .toList()
    ..sort((a, b) {
      final byDue = a.due!.compareTo(b.due!);
      if (byDue != 0) return byDue;
      if (a.isAssignment != b.isAssignment) return a.isAssignment ? -1 : 1;
      return b.priority.index.compareTo(a.priority.index);
    });
  return list;
});

/// The schedulable backlog minus anything already placed on the planner
/// (a task with a [TimeBlock] referencing it). Drives the planner's
/// "To-do to schedule" list so a task vanishes once it's blocked out and
/// returns if that block is removed.
final unscheduledTasksProvider = Provider<List<TaskItem>>((ref) {
  final scheduled = <String>{
    for (final b in ref.watch(blocksProvider))
      if (b.taskId != null) b.taskId!,
  };
  return ref
      .watch(upcomingTasksProvider)
      .where((t) => !scheduled.contains(t.id))
      .toList();
});

/// Folders paired with their resolved [Course] link (null when unlinked).
final foldersWithCourseProvider =
    Provider<List<(TaskFolder, Course?)>>((ref) {
  final byId = ref.watch(coursesByIdProvider);
  return [
    for (final f in ref.watch(foldersProvider))
      (f, f.courseId == null ? null : byId[f.courseId]),
  ];
});

/// Weighted course percentage, or null when the course has no *graded*
/// items yet. Ungraded placeholders (e.g. assignments awaiting a score)
/// are skipped entirely so they don't drag the average down.
double? courseGrade(List<GradeEntry> grades, String courseId) {
  final items = grades
      .where((g) => g.courseId == courseId && g.isGraded)
      .toList();
  if (items.isEmpty) return null;
  var weighted = 0.0;
  var weightSum = 0.0;
  for (final g in items) {
    weighted += g.percent! * g.weight;
    weightSum += g.weight;
  }
  return weightSum == 0 ? null : weighted / weightSum;
}

/// Overall GPA-ish average across all courses that have grades (0..100).
final overallGradeProvider = Provider<double?>((ref) {
  final grades = ref.watch(gradesProvider);
  final courses = ref.watch(coursesProvider);
  final perCourse = <double>[];
  for (final c in courses) {
    final g = courseGrade(grades, c.id);
    if (g != null) perCourse.add(g);
  }
  if (perCourse.isEmpty) return null;
  return perCourse.reduce((a, b) => a + b) / perCourse.length;
});

final dueCardCountProvider = Provider<int>((ref) {
  return ref.watch(cardsProvider).where((c) => c.isDue).length;
});
