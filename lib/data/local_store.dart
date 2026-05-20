import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Thin wrapper over Hive. Every collection is its own box; items are stored
/// as primitive maps keyed by their id. One extra `settings` box holds the
/// single [UserProfile]. No code generation — portable to all platforms.
class LocalStore {
  LocalStore._();

  static const courses = 'courses';
  static const grades = 'grades';
  static const gradeCategories = 'gradeCategories';

  /// Legacy box — assignments were merged into [tasks]. Still opened so the
  /// one-time migration in [_migrateAssignmentsToTasks] can drain it.
  static const assignments = 'assignments';
  static const tasks = 'tasks';
  static const folders = 'folders';
  static const blocks = 'blocks';
  static const events = 'events';
  static const decks = 'decks';
  static const cards = 'cards';
  static const notes = 'notes';
  static const timers = 'timers';
  static const pomodoros = 'pomodoros';
  static const institutions = 'institutions';
  static const semesters = 'semesters';
  static const pastCourses = 'pastCourses';
  static const settings = 'settings';

  static const _boxNames = [
    courses,
    grades,
    gradeCategories,
    assignments,
    tasks,
    folders,
    blocks,
    events,
    decks,
    cards,
    notes,
    timers,
    pomodoros,
    institutions,
    semesters,
    pastCourses,
    settings,
  ];

  static Future<LocalStore> init() async {
    if (kIsWeb) {
      // Web uses IndexedDB; no filesystem path applies.
      await Hive.initFlutter();
    } else {
      // Use the app-support directory (e.g. %APPDATA% on Windows) rather
      // than Documents — the latter is often redirected into OneDrive,
      // whose sync locks the box files and corrupts/blocks Hive writes.
      final dir = await getApplicationSupportDirectory();
      Hive.init('${dir.path}/campus_buddy');
    }
    for (final name in _boxNames) {
      await Hive.openBox<dynamic>(name);
    }
    final store = LocalStore._();
    await store._seedIfFirstRun();
    await store._migrateAssignmentsToTasks();
    await store._migrateStickyNoteToNotes();
    await store._migrateCoursesToInstitution();
    return store;
  }

  Box<dynamic> box(String name) => Hive.box<dynamic>(name);

  UserProfile readProfile() {
    final raw = box(settings).get('profile');
    if (raw is Map) return UserProfile.fromJson(raw);
    return const UserProfile();
  }

  Future<void> writeProfile(UserProfile profile) =>
      box(settings).put('profile', profile.toJson());

  /// Recently used timer durations (seconds), most-recent first, for the
  /// Timer board's one-tap "Recent" suggestions.
  List<int> readTimerRecents() {
    final raw = box(settings).get('timerRecents');
    if (raw is List) {
      return [
        for (final v in raw)
          if (v is num) v.toInt(),
      ];
    }
    return const [];
  }

  Future<void> writeTimerRecents(List<int> seconds) =>
      box(settings).put('timerRecents', seconds);

  /// Populate a friendly starter dataset the first time the app runs so the
  /// dashboard, planner and study pages have something to show.
  Future<void> _seedIfFirstRun() async {
    final s = box(settings);
    if (s.get('seeded') == true) return;

    final now = DateTime.now();
    DateTime day(int addDays) =>
        DateTime(now.year, now.month, now.day).add(Duration(days: addDays));

    final cs = Course(id: newId(), name: 'Algorithms', colorSeed: 0);
    final calc = Course(id: newId(), name: 'Calculus II', colorSeed: 1);
    final hist = Course(id: newId(), name: 'World History', colorSeed: 2);
    for (final c in [cs, calc, hist]) {
      await box(courses).put(c.id, c.toJson());
    }

    final seedGrades = [
      GradeEntry(
          id: newId(),
          courseId: cs.id,
          title: 'Quiz 1',
          earned: 18,
          total: 20,
          weight: 1,
          date: day(-12)),
      GradeEntry(
          id: newId(),
          courseId: cs.id,
          title: 'Project 1',
          earned: 88,
          total: 100,
          weight: 3,
          date: day(-5)),
      GradeEntry(
          id: newId(),
          courseId: calc.id,
          title: 'Midterm',
          earned: 74,
          total: 100,
          weight: 4,
          date: day(-7)),
      GradeEntry(
          id: newId(),
          courseId: hist.id,
          title: 'Essay',
          earned: 92,
          total: 100,
          weight: 2,
          date: day(-3)),
    ];
    for (final g in seedGrades) {
      await box(grades).put(g.id, g.toJson());
    }

    // Folders, two of them linked to a class so assignment tasks filed
    // there route their grade automatically.
    final csFolder =
        TaskFolder(id: newId(), name: 'Algorithms', courseId: cs.id);
    final histFolder =
        TaskFolder(id: newId(), name: 'World History', courseId: hist.id);
    final personalFolder =
        TaskFolder(id: newId(), name: 'Personal', colorSeed: 4);
    for (final f in [csFolder, histFolder, personalFolder]) {
      await box(folders).put(f.id, f.toJson());
    }

    // Assignments are now just tasks with `isAssignment: true`. Seeded ones
    // intentionally skip placeholder grades so the seeded grade trend stays
    // clean; editing one later creates its grade on demand.
    final seedTasks = [
      TaskItem(
          id: newId(),
          title: 'Problem Set 4',
          createdAt: now,
          due: day(2),
          priority: Priority.high,
          folderId: csFolder.id,
          isAssignment: true,
          courseId: cs.id,
          estimatedMinutes: 120),
      TaskItem(
          id: newId(),
          title: 'Reading: Chapter 9',
          createdAt: now,
          due: day(1),
          folderId: histFolder.id,
          isAssignment: true,
          courseId: hist.id,
          estimatedMinutes: 45),
      TaskItem(
          id: newId(),
          title: 'Lab Report',
          createdAt: now,
          due: day(4),
          priority: Priority.high,
          isAssignment: true,
          courseId: calc.id,
          estimatedMinutes: 90),
      TaskItem(
          id: newId(),
          title: 'Email professor about office hours',
          priority: Priority.medium,
          due: day(1),
          folderId: personalFolder.id,
          createdAt: now),
      TaskItem(
          id: newId(),
          title: 'Buy a new notebook',
          priority: Priority.low,
          folderId: personalFolder.id,
          createdAt: now),
    ];
    for (final t in seedTasks) {
      await box(tasks).put(t.id, t.toJson());
    }

    final seedEvents = [
      EventItem(
          id: newId(),
          title: 'Algorithms Lecture',
          start: day(1).add(const Duration(hours: 10)),
          type: EventType.classSession,
          location: 'Hall B'),
      EventItem(
          id: newId(),
          title: 'Calculus Midterm',
          start: day(6).add(const Duration(hours: 9)),
          type: EventType.exam,
          location: 'Room 204'),
      EventItem(
          id: newId(),
          title: 'Study group',
          start: day(2).add(const Duration(hours: 17)),
          type: EventType.personal,
          location: 'Library'),
    ];
    for (final e in seedEvents) {
      await box(events).put(e.id, e.toJson());
    }

    final deck = Deck(
        id: newId(),
        name: 'Algorithms — Big-O',
        description: 'Time complexity basics',
        colorSeed: 0,
        createdAt: now);
    await box(decks).put(deck.id, deck.toJson());
    final seedCards = [
      Flashcard(
          id: newId(),
          deckId: deck.id,
          front: 'Binary search complexity?',
          back: 'O(log n)'),
      Flashcard(
          id: newId(),
          deckId: deck.id,
          front: 'Merge sort complexity?',
          back: 'O(n log n)'),
      Flashcard(
          id: newId(),
          deckId: deck.id,
          front: 'Hash table average lookup?',
          back: 'O(1)'),
    ];
    for (final c in seedCards) {
      await box(cards).put(c.id, c.toJson());
    }

    await s.put('seeded', true);
  }

  /// One-time, idempotent: fold any rows left in the legacy `assignments`
  /// box into the unified `tasks` box as assignment tasks, then drain it.
  ///
  /// Migrated tasks are flagged `isAssignment` and keep their course link,
  /// but no placeholder grades are created here — that would spam Grades
  /// with zeros for every old assignment. Editing one later creates its
  /// grade on demand via [TaskNotifier].
  Future<void> _migrateAssignmentsToTasks() async {
    final s = box(settings);
    if (s.get('assignmentsMerged') == true) return;

    final legacy = box(assignments);
    final tasksBox = box(tasks);
    for (final raw in legacy.values.whereType<Map>().toList()) {
      final dueMs = raw['dueDate'] as int?;
      // Old status enum: 0=todo, 1=inProgress, 2=done.
      final done = (raw['status'] as num?)?.toInt() == 2;
      final task = TaskItem(
        id: (raw['id'] as String?) ?? newId(),
        title: (raw['title'] as String?) ?? 'Untitled',
        done: done,
        priority: Priority.medium,
        due: dueMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(dueMs),
        createdAt: DateTime.now(),
        isAssignment: true,
        courseId: raw['courseId'] as String?,
        estimatedMinutes: (raw['estimatedMinutes'] as num?)?.toInt() ?? 60,
      );
      await tasksBox.put(task.id, task.toJson());
    }
    await legacy.clear();
    await s.put('assignmentsMerged', true);
  }

  /// One-time, idempotent: lift the legacy single sticky-note string (kept
  /// under `settings/stickyNote`) into the multi-note `notes` box, then drop
  /// the old key so the Notes board is the sole owner from then on.
  Future<void> _migrateStickyNoteToNotes() async {
    final s = box(settings);
    if (s.get('stickyNoteMigrated') == true) return;

    final legacy = (s.get('stickyNote') as String?)?.trim() ?? '';
    if (legacy.isNotEmpty) {
      final note = Note(id: newId(), body: legacy, updatedAt: DateTime.now());
      await box(notes).put(note.id, note.toJson());
    }
    await s.delete('stickyNote');
    await s.put('stickyNoteMigrated', true);
  }

  /// One-time, idempotent: every live course must belong to an institution
  /// (its grading system drives how the grade is shown). Ensures at least
  /// one institution exists, then files any institution-less course under
  /// the first one. The user can re-assign via the course editor.
  Future<void> _migrateCoursesToInstitution() async {
    final s = box(settings);
    if (s.get('coursesInstitutionAssigned') == true) return;

    final coursesBox = box(courses);
    final needsAssign = coursesBox.values
        .whereType<Map>()
        .where((m) => (m['institutionId'] as String?) == null)
        .toList();
    if (needsAssign.isEmpty) {
      await s.put('coursesInstitutionAssigned', true);
      return;
    }

    final instBox = box(institutions);
    String defaultId;
    final existing = instBox.values.whereType<Map>().toList();
    if (existing.isEmpty) {
      final school = readProfile().school.trim();
      final inst = Institution(
          id: newId(), name: school.isEmpty ? 'My University' : school);
      await instBox.put(inst.id, inst.toJson());
      defaultId = inst.id;
    } else {
      defaultId = existing.first['id'] as String;
    }

    for (final raw in needsAssign) {
      final course = Course.fromJson(raw).copyWith(institutionId: defaultId);
      await coursesBox.put(course.id, course.toJson());
    }
    await s.put('coursesInstitutionAssigned', true);
  }
}
