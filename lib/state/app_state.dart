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

class AssignmentNotifier extends CollectionNotifier<Assignment> {
  @override
  String get boxName => LocalStore.assignments;
  @override
  String idOf(Assignment i) => i.id;
  @override
  Map<String, dynamic> encode(Assignment i) => i.toJson();
  @override
  Assignment decode(Map j) => Assignment.fromJson(j);
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
final assignmentsProvider =
    NotifierProvider<AssignmentNotifier, List<Assignment>>(
        AssignmentNotifier.new);
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

/// Open assignments sorted by due date (soonest first).
final upcomingAssignmentsProvider = Provider<List<Assignment>>((ref) {
  final list = ref
      .watch(assignmentsProvider)
      .where((a) => !a.isDone)
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return list;
});

/// Weighted course percentage, or null when the course has no grades yet.
double? courseGrade(List<GradeEntry> grades, String courseId) {
  final items = grades.where((g) => g.courseId == courseId).toList();
  if (items.isEmpty) return null;
  var weighted = 0.0;
  var weightSum = 0.0;
  for (final g in items) {
    weighted += g.percent * g.weight;
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
