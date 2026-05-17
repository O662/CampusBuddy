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
  static const assignments = 'assignments';
  static const tasks = 'tasks';
  static const blocks = 'blocks';
  static const events = 'events';
  static const decks = 'decks';
  static const cards = 'cards';
  static const settings = 'settings';

  static const _boxNames = [
    courses,
    grades,
    assignments,
    tasks,
    blocks,
    events,
    decks,
    cards,
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

    final seedAssignments = [
      Assignment(
          id: newId(),
          title: 'Problem Set 4',
          courseId: cs.id,
          dueDate: day(2),
          estimatedMinutes: 120),
      Assignment(
          id: newId(),
          title: 'Reading: Chapter 9',
          courseId: hist.id,
          dueDate: day(1),
          estimatedMinutes: 45),
      Assignment(
          id: newId(),
          title: 'Lab Report',
          courseId: calc.id,
          dueDate: day(4),
          estimatedMinutes: 90),
    ];
    for (final a in seedAssignments) {
      await box(assignments).put(a.id, a.toJson());
    }

    final seedTasks = [
      TaskItem(
          id: newId(),
          title: 'Email professor about office hours',
          priority: Priority.medium,
          due: day(1),
          createdAt: now),
      TaskItem(
          id: newId(),
          title: 'Buy a new notebook',
          priority: Priority.low,
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
}
