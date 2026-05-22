import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications.dart';
import '../data/backup_service.dart';
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

  /// Persist [ordered] as the new sequence; positions are renumbered 0..n.
  Future<void> reorder(List<Course> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(order: i),
      ]);
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

  /// Persist [ordered] as the new sequence; positions are renumbered 0..n.
  Future<void> reorder(List<TaskFolder> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i),
      ]);
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
  ///
  /// Recurrence: completing a repeating task spawns its next occurrence
  /// (a fresh task, due one cadence later). Centralised here so every
  /// completion path — dashboard, to-do, planner — gets it for free.
  Future<void> save(TaskItem task) async {
    final prev = _byId(task.id);
    await upsert(task);
    await _syncGrade(task);

    final justCompleted = task.done && (prev == null || !prev.done);
    if (task.recurrence.repeats && justCompleted) {
      final anchor = task.due ?? DateTime.now();
      final next = TaskItem(
        id: newId(),
        title: task.title,
        priority: task.priority,
        due: task.recurrence.next(anchor),
        createdAt: DateTime.now(),
        folderId: task.folderId,
        isAssignment: task.isAssignment,
        courseId: task.courseId,
        categoryId: task.categoryId,
        estimatedMinutes: task.estimatedMinutes,
        recurrence: task.recurrence,
      );
      await upsert(next);
      await _syncGrade(next);
    }
  }

  /// Remove a task. If the task mirrors a gradebook entry, [keepGrade]
  /// decides whether to drop that entry too:
  ///   - false (default) → delete the linked grade as well,
  ///   - true            → leave the gradebook entry untouched as a
  ///                        standalone item.
  ///
  /// The UI is expected to make this choice explicit when a linked grade
  /// exists (see `confirmDeleteTaskWithGrade`). Tasks with no linked
  /// grade ignore [keepGrade].
  Future<void> delete(String id, {bool keepGrade = false}) async {
    final task = _byId(id);
    await remove(id);
    if (task == null) return;
    final g = _linkedGrade(id);
    if (g == null || keepGrade) return;
    await ref.read(gradesProvider.notifier).remove(_gradeId(id));
  }

  /// Write the Gantt's manual ordering for [ordered] back to disk. Each task
  /// is assigned a [TaskItem.ganttOrder] equal to its position in the list,
  /// so subsequent reorders stay stable. Tasks not in [ordered] are left
  /// untouched.
  Future<void> reorderGantt(List<TaskItem> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(ganttOrder: i + 1),
      ]);

  Future<void> _syncGrade(TaskItem t) async {
    final grades = ref.read(gradesProvider.notifier);
    final existing = _linkedGrade(t.id);
    final courseId = _resolveCourseId(t);

    if (t.isAssignment && courseId != null) {
      // Validate the task's category still belongs to the resolved course.
      // If the user switched class on the task and never reopened the
      // picker, the stored id may no longer apply — fall back to whatever
      // the Grades side already has, rather than writing a stale id.
      String? taskCat = t.categoryId;
      if (taskCat != null) {
        final cats = ref.read(gradeCategoriesProvider);
        final ok = cats.any(
            (c) => c.id == taskCat && c.courseId == courseId);
        if (!ok) taskCat = null;
      }
      // The task is the source of truth for placeholder category when it
      // has one set; otherwise we keep whatever the Grades side recorded.
      final mirroredCat = taskCat ?? existing?.categoryId;

      // Create an ungraded placeholder (earned == null → shows "—" and is
      // left out of the average), or mirror title/class/category onto an
      // existing entry without clobbering a score the user may have
      // filled in.
      await grades.upsert(GradeEntry(
        id: _gradeId(t.id),
        courseId: courseId,
        title: t.title,
        earned: existing?.earned,
        total: existing?.total ?? 100,
        weight: existing?.weight ?? 1,
        date: existing?.date ?? t.due ?? DateTime.now(),
        categoryId: mirroredCat,
        // Never clobber the score or extra-credit fields the user filled
        // in on the Grades side.
        extraCredit: existing?.extraCredit ?? false,
        extraCreditIsPoints: existing?.extraCreditIsPoints ?? false,
        extraCreditValue: existing?.extraCreditValue,
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

class DeckGroupNotifier extends CollectionNotifier<DeckGroup> {
  @override
  String get boxName => LocalStore.deckGroups;
  @override
  String idOf(DeckGroup i) => i.id;
  @override
  Map<String, dynamic> encode(DeckGroup i) => i.toJson();
  @override
  DeckGroup decode(Map j) => DeckGroup.fromJson(j);

  /// Persist [ordered] as the new sequence; positions are renumbered 0..n.
  Future<void> reorder(List<DeckGroup> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(order: i),
      ]);
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

class GradeCategoryNotifier extends CollectionNotifier<GradeCategory> {
  @override
  String get boxName => LocalStore.gradeCategories;
  @override
  String idOf(GradeCategory i) => i.id;
  @override
  Map<String, dynamic> encode(GradeCategory i) => i.toJson();
  @override
  GradeCategory decode(Map j) => GradeCategory.fromJson(j);
}

class NoteNotifier extends CollectionNotifier<Note> {
  @override
  String get boxName => LocalStore.notes;
  @override
  String idOf(Note i) => i.id;
  @override
  Map<String, dynamic> encode(Note i) => i.toJson();
  @override
  Note decode(Map j) => Note.fromJson(j);

  /// Persists a new manual order. [ordered] is the full notes list in its
  /// new top-to-bottom sequence; positions are renumbered 0..n.
  Future<void> reorder(List<Note> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i),
      ]);
}

class TimerNotifier extends CollectionNotifier<TimerItem> {
  @override
  String get boxName => LocalStore.timers;
  @override
  String idOf(TimerItem i) => i.id;
  @override
  Map<String, dynamic> encode(TimerItem i) => i.toJson();
  @override
  TimerItem decode(Map j) => TimerItem.fromJson(j);

  TimerItem? _byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Persists a new manual order. [ordered] is the full list in its new
  /// top-to-bottom sequence; positions are renumbered 0..n.
  Future<void> reorder(List<TimerItem> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i),
      ]);

  /// Apply [change] to the timer [id] if it still exists. The lifecycle
  /// transitions ([TimerItem.started] etc.) all route through here so the
  /// board, pop-out window and alarm engine stay in lock-step.
  Future<void> _mutate(String id, TimerItem Function(TimerItem) change) async {
    final t = _byId(id);
    if (t != null) await upsert(change(t));
  }

  Future<void> start(String id) => _mutate(id, (t) => t.started());
  Future<void> pause(String id) => _mutate(id, (t) => t.paused());
  Future<void> resetToFull(String id) =>
      _mutate(id, (t) => t.resetToFull());

  Future<void> toggle(String id) =>
      _mutate(id, (t) => t.isRunning ? t.paused() : t.started());

  Future<void> rename(String id, String name) => _mutate(
      id, (t) => t.copyWith(name: name, updatedAt: DateTime.now()));

  Future<void> recolor(String id, int colorSeed) => _mutate(id,
      (t) => t.copyWith(colorSeed: colorSeed, updatedAt: DateTime.now()));

  /// Re-length a timer. A change resets it to a fresh, stopped full duration
  /// (a running countdown to a now-different total would be meaningless).
  Future<void> setDuration(String id, int seconds) => _mutate(
        id,
        (t) => t
            .copyWith(durationSeconds: seconds, updatedAt: DateTime.now())
            .resetToFull(),
      );
}

class PomodoroNotifier extends CollectionNotifier<PomodoroPreset> {
  @override
  String get boxName => LocalStore.pomodoros;
  @override
  String idOf(PomodoroPreset i) => i.id;
  @override
  Map<String, dynamic> encode(PomodoroPreset i) => i.toJson();
  @override
  PomodoroPreset decode(Map j) => PomodoroPreset.fromJson(j);

  /// Persists a new manual order. [ordered] is the full list in its new
  /// top-to-bottom sequence; positions are renumbered 0..n.
  Future<void> reorder(List<PomodoroPreset> ordered) => upsertAll([
        for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i),
      ]);
}

class InstitutionNotifier extends CollectionNotifier<Institution> {
  @override
  String get boxName => LocalStore.institutions;
  @override
  String idOf(Institution i) => i.id;
  @override
  Map<String, dynamic> encode(Institution i) => i.toJson();
  @override
  Institution decode(Map j) => Institution.fromJson(j);
}

class SemesterNotifier extends CollectionNotifier<Semester> {
  @override
  String get boxName => LocalStore.semesters;
  @override
  String idOf(Semester i) => i.id;
  @override
  Map<String, dynamic> encode(Semester i) => i.toJson();
  @override
  Semester decode(Map j) => Semester.fromJson(j);
}

class PastCourseNotifier extends CollectionNotifier<PastCourse> {
  @override
  String get boxName => LocalStore.pastCourses;
  @override
  String idOf(PastCourse i) => i.id;
  @override
  Map<String, dynamic> encode(PastCourse i) => i.toJson();
  @override
  PastCourse decode(Map j) => PastCourse.fromJson(j);
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
final deckGroupsProvider =
    NotifierProvider<DeckGroupNotifier, List<DeckGroup>>(
        DeckGroupNotifier.new);
final cardsProvider =
    NotifierProvider<CardNotifier, List<Flashcard>>(CardNotifier.new);
final notesProvider =
    NotifierProvider<NoteNotifier, List<Note>>(NoteNotifier.new);
final timersProvider =
    NotifierProvider<TimerNotifier, List<TimerItem>>(TimerNotifier.new);
final pomodorosProvider =
    NotifierProvider<PomodoroNotifier, List<PomodoroPreset>>(
        PomodoroNotifier.new);

/// Recently used timer durations (seconds), most-recent first, capped so the
/// board's "Recent" row stays compact. Persisted in the settings box.
class TimerRecentsNotifier extends Notifier<List<int>> {
  static const _max = 5;

  @override
  List<int> build() => ref.read(localStoreProvider).readTimerRecents();

  Future<void> push(int seconds) async {
    if (seconds <= 0) return;
    final next = [seconds, ...state.where((s) => s != seconds)]
        .take(_max)
        .toList();
    await ref.read(localStoreProvider).writeTimerRecents(next);
    state = next;
  }
}

final timerRecentsProvider =
    NotifierProvider<TimerRecentsNotifier, List<int>>(
        TimerRecentsNotifier.new);

/// The two layouts the To-do page supports.
enum TodoViewMode { grid, list }

/// Persists the user's chosen To-do layout to the settings box so it sticks
/// across sessions.
class TodoViewModeNotifier extends Notifier<TodoViewMode> {
  @override
  TodoViewMode build() {
    final raw = ref.read(localStoreProvider).readTodoViewMode();
    return raw == 'list' ? TodoViewMode.list : TodoViewMode.grid;
  }

  Future<void> set(TodoViewMode mode) async {
    if (state == mode) return;
    await ref.read(localStoreProvider).writeTodoViewMode(mode.name);
    state = mode;
  }
}

final todoViewModeProvider =
    NotifierProvider<TodoViewModeNotifier, TodoViewMode>(
        TodoViewModeNotifier.new);

/// The two layouts the Study page supports — mirrors [TodoViewMode] so
/// the UI toggle / persistence stays in lock-step with the To-do page.
enum StudyViewMode { grid, list }

class StudyViewModeNotifier extends Notifier<StudyViewMode> {
  @override
  StudyViewMode build() {
    final raw = ref.read(localStoreProvider).readStudyViewMode();
    return raw == 'list' ? StudyViewMode.list : StudyViewMode.grid;
  }

  Future<void> set(StudyViewMode mode) async {
    if (state == mode) return;
    await ref.read(localStoreProvider).writeStudyViewMode(mode.name);
    state = mode;
  }
}

final studyViewModeProvider =
    NotifierProvider<StudyViewModeNotifier, StudyViewMode>(
        StudyViewModeNotifier.new);

/// Persisted "hide completed tasks" switch. One global flag honored by the
/// To-do board, the Planner's month-view agenda, and the Gantt — flipping
/// it in any one of those places hides finished work everywhere.
class HideCompletedTasksNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(localStoreProvider).readHideCompletedTasks();

  Future<void> set(bool value) async {
    if (state == value) return;
    await ref.read(localStoreProvider).writeHideCompletedTasks(value);
    state = value;
  }

  Future<void> toggle() => set(!state);
}

final hideCompletedTasksProvider =
    NotifierProvider<HideCompletedTasksNotifier, bool>(
        HideCompletedTasksNotifier.new);

/// String keys identifying the three cards in the Grades-page summary
/// strip. Kept as a const list (not an enum) so persistence is simple
/// and adding/removing a card later is just a list edit.
const kGradesWidgetTrend = 'trend';
const kGradesWidgetCalculator = 'calculator';
const kGradesWidgetStability = 'stability';
const kGradesWidgetAll = [
  kGradesWidgetTrend,
  kGradesWidgetCalculator,
  kGradesWidgetStability,
];

/// Persisted order for the Grades summary strip. The notifier always
/// returns a sanitised list — every known key appears exactly once,
/// unknown keys from older sessions are dropped, and any new keys (e.g.
/// after a future widget is added) are appended to the end.
class GradesWidgetOrderNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => _sanitise(
      ref.read(localStoreProvider).readGradesWidgetOrder());

  List<String> _sanitise(List<String> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final k in raw) {
      if (kGradesWidgetAll.contains(k) && seen.add(k)) result.add(k);
    }
    for (final k in kGradesWidgetAll) {
      if (seen.add(k)) result.add(k);
    }
    return result;
  }

  Future<void> reorder(List<String> next) async {
    final clean = _sanitise(next);
    await ref.read(localStoreProvider).writeGradesWidgetOrder(clean);
    state = clean;
  }
}

final gradesWidgetOrderProvider =
    NotifierProvider<GradesWidgetOrderNotifier, List<String>>(
        GradesWidgetOrderNotifier.new);

/// Live snapshot driving per-second redraws of running timers plus the set
/// of timers currently ringing.
typedef TimerEngineState = ({DateTime now, Set<String> alarmingIds});

/// Owns the single 1-second ticker and the alarm sound for *all* timers.
/// Lives in the main window for the whole session (instantiated from
/// `main()`), so timers keep counting and ring even when the Timer page is
/// off-screen or a timer is popped out into its own window.
///
/// Completion that happens *while the app is open* (a timer seen counting
/// then crossing zero) rings the looping chime; a timer found already
/// expired at launch shows "Time's up" silently until dismissed.
class TimerEngine extends Notifier<TimerEngineState> {
  Timer? _ticker;
  AudioPlayer? _player;
  bool _playing = false;

  final Set<String> _alarming = {};

  /// Ids that were actively counting (running, not yet expired) at the last
  /// evaluation — used to tell a *fresh* finish from a stale one.
  Set<String> _counting = {};

  /// Notification bookkeeping: which timer ids currently own an "active" /
  /// "finished" notification in the OS drawer, so we know what to refresh
  /// vs. cancel on each evaluation.
  final Set<String> _notifiedActive = {};
  final Set<String> _notifiedDone = {};

  @override
  TimerEngineState build() {
    ref.listen(timersProvider, (_, next) => _evaluate(next));
    ref.onDispose(() {
      _ticker?.cancel();
      _player?.dispose();
      // Clear any drawer notifications we own — they'd otherwise be stale
      // through a hot restart or container tear-down.
      final notifs = AppNotifications.instance;
      for (final id in _notifiedActive) {
        unawaited(notifs.cancelActiveTimer(id));
      }
      for (final id in _notifiedDone) {
        unawaited(notifs.cancelFinishedTimer(id));
      }
      _notifiedActive.clear();
      _notifiedDone.clear();
    });
    // First evaluation once the container is up.
    Future.microtask(() => _evaluate(ref.read(timersProvider)));
    return (now: DateTime.now(), alarmingIds: const {});
  }

  void _evaluate(List<TimerItem> timers) {
    final byId = {for (final t in timers) t.id: t};

    // Drop alarms whose timer was dismissed/reset/deleted elsewhere (e.g.
    // from a pop-out window round-tripping a reset back through the bridge).
    _alarming.removeWhere(
        (id) => byId[id] == null || !byId[id]!.isFinished);

    final counting = <String>{};
    for (final t in timers) {
      if (t.isRunning && !t.isFinished) {
        counting.add(t.id);
      } else if (t.isFinished && _counting.contains(t.id)) {
        _alarming.add(t.id); // crossed zero while we were watching
      }
    }
    _counting = counting;

    _syncAudio();
    _syncNotifications(timers);
    _scheduleTicker(counting.isNotEmpty);
    state = (now: DateTime.now(), alarmingIds: Set.unmodifiable(_alarming));
  }

  /// Push the current set of running/finished timers out to the OS drawer.
  /// Quiet, throttled, fault-tolerant — the [AppNotifications] service
  /// no-ops if init failed (e.g. unpackaged Windows builds).
  void _syncNotifications(List<TimerItem> timers) {
    final notifs = AppNotifications.instance;

    // What *should* be in the drawer right now. Per-timer mute drops the
    // timer out of both sets, so muting a running timer is enough to make
    // the cleanup loop below cancel any notification it currently owns.
    final shouldBeActive = <String>{};
    final shouldBeDone = <String>{};
    for (final t in timers) {
      if (!t.notify) continue;
      if (_alarming.contains(t.id)) {
        shouldBeDone.add(t.id);
      } else if (t.isRunning && !t.isFinished) {
        shouldBeActive.add(t.id);
      }
    }

    // Drop notifications for timers that left their state (paused/reset/deleted).
    for (final id in _notifiedActive.toList()) {
      if (!shouldBeActive.contains(id)) {
        unawaited(notifs.cancelActiveTimer(id));
        _notifiedActive.remove(id);
      }
    }
    for (final id in _notifiedDone.toList()) {
      if (!shouldBeDone.contains(id)) {
        unawaited(notifs.cancelFinishedTimer(id));
        _notifiedDone.remove(id);
      }
    }

    // Refresh / show active notifications. Re-push when either:
    //  • state really changed (Start, Resume, Reset, rename) → handled by
    //    [activeSignatureChanged], or
    //  • the visible "X left" should drop a digit (a new minute bucket,
    //    or a 10-second slice in the final minute) → handled by
    //    [activeBucketChanged]. The notification body uses `silent: true`
    //    so these per-minute re-pushes don't make the OS ding each time.
    for (final t in timers) {
      if (!shouldBeActive.contains(t.id)) continue;
      final stateChanged = notifs.activeSignatureChanged(t);
      final bucketChanged = notifs.activeBucketChanged(t);
      if (stateChanged || bucketChanged) {
        unawaited(notifs.showActiveTimer(t));
        _notifiedActive.add(t.id);
      }
    }

    // Fire a one-shot "Time's up" notification for any new finishes.
    for (final t in timers) {
      if (!shouldBeDone.contains(t.id)) continue;
      if (!_notifiedDone.contains(t.id)) {
        unawaited(notifs.showTimerFinished(t));
        _notifiedDone.add(t.id);
      }
    }
  }

  void _tick() {
    _evaluate(ref.read(timersProvider));
  }

  /// Keep a 1-second heartbeat only while something is actually counting or
  /// ringing; otherwise idle so nothing rebuilds needlessly.
  void _scheduleTicker(bool counting) {
    final needed = counting || _alarming.isNotEmpty;
    if (needed && _ticker == null) {
      _ticker =
          Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!needed && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  Future<void> _syncAudio() async {
    if (_alarming.isNotEmpty && !_playing) {
      _playing = true;
      try {
        final p = _player ??= AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        await p.play(AssetSource('sounds/alarm.wav'));
      } catch (_) {
        _playing = false; // audio unavailable — visual alarm still shows
      }
    } else if (_alarming.isEmpty && _playing) {
      _playing = false;
      try {
        await _player?.stop();
      } catch (_) {}
    }
  }

  /// Silence [id]'s alarm and reset it to a fresh full duration.
  void dismiss(String id) {
    _alarming.remove(id);
    unawaited(ref.read(timersProvider.notifier).resetToFull(id));
    _syncAudio();
    _scheduleTicker(_counting.isNotEmpty);
    state = (now: DateTime.now(), alarmingIds: Set.unmodifiable(_alarming));
  }
}

final timerEngineProvider =
    NotifierProvider<TimerEngine, TimerEngineState>(TimerEngine.new);
final gradeCategoriesProvider =
    NotifierProvider<GradeCategoryNotifier, List<GradeCategory>>(
        GradeCategoryNotifier.new);
final institutionsProvider =
    NotifierProvider<InstitutionNotifier, List<Institution>>(
        InstitutionNotifier.new);
final semestersProvider =
    NotifierProvider<SemesterNotifier, List<Semester>>(
        SemesterNotifier.new);
final pastCoursesProvider =
    NotifierProvider<PastCourseNotifier, List<PastCourse>>(
        PastCourseNotifier.new);

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

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.read(localStoreProvider)),
);

/// Rebuilds exactly the collections an import touched. The merge writes
/// straight to Hive, so the affected notifiers must be invalidated for any
/// open page to reflect the restored data.
void refreshAfterImport(WidgetRef ref, Iterable<BackupCategory> cats) {
  for (final c in cats) {
    switch (c) {
      case BackupCategory.profile:
        ref.invalidate(profileProvider);
        // UI preferences ride along inside the profile section now, so
        // every notifier that pulls from `LocalStore.readBackupPrefs()`
        // needs to be rebuilt to pick up the restored value.
        ref.invalidate(hideCompletedTasksProvider);
        ref.invalidate(todoViewModeProvider);
        ref.invalidate(studyViewModeProvider);
        ref.invalidate(gradesWidgetOrderProvider);
        ref.invalidate(timerRecentsProvider);
      case BackupCategory.coursesGrades:
        ref.invalidate(coursesProvider);
        ref.invalidate(gradesProvider);
        ref.invalidate(gradeCategoriesProvider);
      case BackupCategory.academicHistory:
        ref.invalidate(institutionsProvider);
        ref.invalidate(semestersProvider);
        ref.invalidate(pastCoursesProvider);
      case BackupCategory.todos:
        ref.invalidate(tasksProvider);
        ref.invalidate(foldersProvider);
      case BackupCategory.planner:
        ref.invalidate(blocksProvider);
        ref.invalidate(eventsProvider);
      case BackupCategory.flashcards:
        ref.invalidate(decksProvider);
        ref.invalidate(cardsProvider);
      case BackupCategory.notes:
        ref.invalidate(notesProvider);
      case BackupCategory.timers:
        ref.invalidate(timersProvider);
      case BackupCategory.pomodoros:
        ref.invalidate(pomodorosProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Derived / computed providers
// ---------------------------------------------------------------------------

final coursesByIdProvider = Provider<Map<String, Course>>((ref) {
  return {for (final c in ref.watch(coursesProvider)) c.id: c};
});

final institutionsByIdProvider = Provider<Map<String, Institution>>((ref) {
  return {for (final i in ref.watch(institutionsProvider)) i.id: i};
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
/// are skipped entirely so they don't drag the average down. The
/// per-item weight depends on the course's [GradingStyle] — explicit
/// weights in percent mode, point totals in points mode (via
/// [Course.weightOf]).
double? courseGrade(List<GradeEntry> grades, Course course) {
  final items = grades
      .where((g) => g.courseId == course.id && g.isGraded)
      .toList();
  if (items.isEmpty) return null;
  var weighted = 0.0;
  var weightSum = 0.0;
  for (final g in items) {
    final w = course.weightOf(g);
    weighted += g.effectivePercent! * w;
    weightSum += w;
  }
  return weightSum == 0 ? null : weighted / weightSum;
}

/// Phase-2 course %: weighted categories + extra credit. Falls back to a
/// flat weighted average when the course has no categories. Categories
/// (and the uncategorized bucket) with no graded items are excluded and
/// the rest renormalised — same "ignore ungraded" rule used elsewhere.
double? courseWeightedPercent(
  Course course,
  List<GradeCategory> categories,
  List<GradeEntry> allEntries,
) {
  final courseEntries =
      allEntries.where((g) => g.courseId == course.id).toList();
  final graded = courseEntries.where((g) => g.isGraded).toList();

  // Course-level curve + stand-alone bonus-only EC items flat-add to the
  // final %. A graded item's *own* extra credit is already baked into its
  // effectivePercent and rides the weighted average like a normal score.
  var bonus = course.extraCreditPct;
  for (final g in courseEntries) {
    if (g.isBonusOnly) bonus += g.extraCreditValue ?? 0;
  }
  final normal = graded;

  double? avgOf(Iterable<GradeEntry> items) {
    var w = 0.0, wp = 0.0;
    for (final g in items) {
      // Points-mode courses weight by total; percent-mode by the
      // explicit weight field. Centralised on Course.weightOf so we
      // can't drift out of sync with the rest of the calculator.
      final iw = course.weightOf(g);
      wp += g.effectivePercent! * iw;
      w += iw;
    }
    return w == 0 ? null : wp / w;
  }

  final cats =
      categories.where((c) => c.courseId == course.id).toList();
  double? base;
  if (cats.isEmpty) {
    base = avgOf(normal);
  } else {
    final buckets = <(double, double)>[]; // (weight, pct)
    var catWeightSum = 0.0;
    for (final c in cats) {
      catWeightSum += c.weightPercent;
      final a = avgOf(normal.where((g) => g.categoryId == c.id));
      if (a != null && c.weightPercent > 0) buckets.add((c.weightPercent, a));
    }
    final leftover = 100 - catWeightSum;
    final uncategorized = avgOf(normal.where((g) => g.categoryId == null));
    if (uncategorized != null && leftover > 0) {
      buckets.add((leftover, uncategorized));
    }
    if (buckets.isEmpty) {
      base = avgOf(normal); // weights unset — don't silently drop grades
    } else {
      var w = 0.0, wp = 0.0;
      for (final b in buckets) {
        w += b.$1;
        wp += b.$1 * b.$2;
      }
      base = w == 0 ? null : wp / w;
    }
  }

  if (base == null) return bonus > 0 ? bonus : null;
  final total = base + bonus;
  return total < 0 ? 0 : total;
}

/// What the grade-stability tracker reports for a single course.
///
/// - `current` — the same number `courseWeightedPercent` would return
///   (null when there's nothing to base it on).
/// - `best` / `worst` — bounds the course grade could still settle at,
///   assuming every remaining assignment scores 100% / 0% respectively.
///   Both fold in [Course.extraCreditPct] and any bonus-only EC items
///   the same way `courseWeightedPercent` does, so the current grade
///   always lies within `[worst, best]`.
/// - `swing` — `best - worst`, the maximum total movement still on the
///   table. The most actionable single number for the user.
/// - `partial` — true when one or more weighted categories (or the
///   uncategorized leftover) has no `assignmentCount` set AND has at
///   least one assignment still unaccounted for. In that case the
///   bounds reflect a best-effort estimate (no-count buckets stay at
///   their current pace); the actual swing could be wider.
/// - `hasAnyCount` — at least one category has an `assignmentCount`
///   set. The grades-page card uses this to gate the prompt that
///   tells the user "add counts to see stability".
typedef CourseStability = ({
  double? current,
  double? best,
  double? worst,
  double? swing,
  bool partial,
  bool hasAnyCount,
});

/// Bound the course's final grade based on what's still pending.
///
/// For each weighted category with an `assignmentCount` we treat the
/// graded share as locked in at its current average and the remaining
/// share as a floor-or-ceiling unknown (0% / 100%). Categories without
/// a count — and the uncategorized leftover — are assumed to continue
/// at their current pace (so they contribute zero swing); this is a
/// **lower bound** on the true swing, surfaced via `partial`. Bonuses
/// flat-add to both ends the same way they do in [courseWeightedPercent].
CourseStability courseStability(
  Course course,
  List<GradeCategory> categories,
  List<GradeEntry> allEntries,
) {
  final courseEntries =
      allEntries.where((g) => g.courseId == course.id).toList();
  final graded = courseEntries.where((g) => g.isGraded).toList();

  // Flat bonus added to both best and worst — same rule as the
  // current-grade calculation.
  var bonus = course.extraCreditPct;
  for (final g in courseEntries) {
    if (g.isBonusOnly) bonus += g.extraCreditValue ?? 0;
  }

  final cats =
      categories.where((c) => c.courseId == course.id).toList();
  final current = courseWeightedPercent(course, categories, allEntries);

  if (cats.isEmpty) {
    // No categories at all → no way to know what's pending; treat
    // everything as "current pace" so there's no swing to report.
    return (
      current: current,
      best: current,
      worst: current,
      swing: current == null ? null : 0,
      partial: false,
      hasAnyCount: false,
    );
  }

  double? avgOf(Iterable<GradeEntry> items) {
    var w = 0.0, wp = 0.0;
    for (final g in items) {
      final iw = course.weightOf(g);
      wp += g.effectivePercent! * iw;
      w += iw;
    }
    return w == 0 ? null : wp / w;
  }

  var best = 0.0;
  var worst = 0.0;
  var partial = false;
  var hasAnyCount = false;
  var weightAccounted = 0.0;

  for (final c in cats) {
    if (c.weightPercent <= 0) continue;
    weightAccounted += c.weightPercent;
    final catEntries =
        graded.where((g) => g.categoryId == c.id).toList();
    final nDone = catEntries.length;
    final catAvg = avgOf(catEntries); // null if nothing graded yet

    final N = c.assignmentCount;
    if (N != null && N > 0) {
      hasAnyCount = true;
      final pending = (N - nDone).clamp(0, N);
      if (pending == 0) {
        // Category fully done — locked in.
        final avg = catAvg ?? 0;
        best += avg * c.weightPercent / 100;
        worst += avg * c.weightPercent / 100;
      } else {
        // Locked share keeps the current category average; pending
        // share floats between 0 and 100.
        final lockedWeight = (nDone / N) * c.weightPercent;
        final remainingWeight = (pending / N) * c.weightPercent;
        final lockedAvg = catAvg ?? 0; // 0 only when nDone == 0
        final lockedContribution = lockedAvg * lockedWeight / 100;
        best += lockedContribution + remainingWeight; // remaining @ 100
        worst += lockedContribution; // remaining @ 0
      }
    } else {
      // No total specified. Honest bounds would be 0..weight, but a
      // category with established pace usually keeps it — using the
      // current avg keeps swing meaningful while we flag the gap via
      // `partial`. A truly empty bucket (no avg) defaults to 0 for
      // worst and the full weight for best so the user still sees
      // upside.
      if (catAvg != null) {
        best += catAvg * c.weightPercent / 100;
        worst += catAvg * c.weightPercent / 100;
        if (nDone > 0) partial = true;
      } else {
        best += c.weightPercent;
        worst += 0;
      }
    }
  }

  // Uncategorized leftover — same treatment as a no-count category.
  final leftover = (100 - weightAccounted).clamp(0, 100);
  if (leftover > 0) {
    final uncatAvg = avgOf(graded.where((g) => g.categoryId == null));
    if (uncatAvg != null) {
      best += uncatAvg * leftover / 100;
      worst += uncatAvg * leftover / 100;
      partial = true;
    } else {
      best += leftover;
      worst += 0;
    }
  }

  best = (best + bonus).clamp(0, double.infinity);
  worst = (worst + bonus).clamp(0, double.infinity);

  return (
    current: current,
    best: best,
    worst: worst,
    swing: best - worst,
    partial: partial,
    hasAnyCount: hasAnyCount,
  );
}

/// Total earned points across a course's graded items — what
/// `cutoffsArePoints` mode compares against. Includes item-level extra
/// credit when it's expressed in points (per [GradeEntry.effectivePercent]'s
/// rule) and the course-level [Course.extraCreditPct] when it's points;
/// percentage-style EC has no point analog and is ignored.
double courseEarnedPoints(Course course, List<GradeEntry> allEntries) {
  var pts = 0.0;
  for (final g in allEntries) {
    if (g.courseId != course.id) continue;
    if (g.isBonusOnly) {
      if (g.extraCreditIsPoints) pts += g.extraCreditValue ?? 0;
      continue;
    }
    if (!g.isGraded) continue;
    pts += g.earned!;
    if (g.extraCredit && g.extraCreditIsPoints) {
      pts += g.extraCreditValue ?? 0;
    }
  }
  if (course.extraCreditIsPoints) pts += course.extraCreditPct;
  return pts;
}

/// The course's final grade rendered per its grading mode + its
/// institution's system (graded mode uses the course's own cutoffs).
/// Pass [earnedPoints] when the course has [Course.cutoffsArePoints] set
/// so the letter/pass decision compares against raw points; without it
/// the function falls back to the percent path.
String courseResult(Course course, Institution? inst, double? pct,
    {double? earnedPoints}) {
  if (pct == null) return '—';
  final byPoints = course.cutoffsArePoints && earnedPoints != null;
  bool pass() => byPoints
      ? earnedPoints >= course.passCutoff
      : pct >= course.passCutoff;
  String letter() => byPoints
      ? course.letterForPoints(earnedPoints)
      : course.letterFor(pct);
  switch (course.gradingMode) {
    case CourseGradingMode.passFail:
      return pass() ? 'Pass' : 'Fail';
    case CourseGradingMode.satisfactory:
      return pass() ? 'Satisfactory' : 'Unsatisfactory';
    case CourseGradingMode.graded:
      final system = inst?.gradeSystem ?? GradeSystem.percent;
      switch (system) {
        case GradeSystem.percent:
          return '${pct.toStringAsFixed(1)}%';
        case GradeSystem.letter:
          return letter();
        case GradeSystem.points:
          // Complex uses the institution's standard fractional table;
          // simple maps the course's own letter cutoffs to whole points.
          if (inst!.gpaComplex) return inst.gpaText(pct);
          final base = switch (letter()) {
            'A' => 4.0,
            'B' => 3.0,
            'C' => 2.0,
            'D' => 1.0,
            _ => 0.0,
          };
          return (base * (inst.effectiveGpaMax / 4.0))
              .toStringAsFixed(1);
      }
  }
}

/// Overall GPA-ish average across all courses that have grades (0..100).
final overallGradeProvider = Provider<double?>((ref) {
  final grades = ref.watch(gradesProvider);
  final courses = ref.watch(coursesProvider);
  final perCourse = <double>[];
  for (final c in courses) {
    final g = courseGrade(grades, c);
    if (g != null) perCourse.add(g);
  }
  if (perCourse.isEmpty) return null;
  return perCourse.reduce((a, b) => a + b) / perCourse.length;
});

final dueCardCountProvider = Provider<int>((ref) {
  return ref.watch(cardsProvider).where((c) => c.isDue).length;
});

// ---------------------------------------------------------------------------
// Academic history — credit-weighted GPA. GPA = Σ(gradePoints×credits) /
// Σ credits. Null when there are no credits to average.
// ---------------------------------------------------------------------------

double? semesterGpa(Iterable<PastCourse> classes) {
  var quality = 0.0;
  var credits = 0.0;
  for (final p in classes) {
    quality += p.qualityPoints;
    credits += p.creditHours;
  }
  return credits <= 0 ? null : quality / credits;
}

/// One point on the GPA chart: a semester (that has classes), its GPA, and
/// the cumulative GPA across every semester up to and including it.
typedef GpaPoint = ({Semester semester, double gpa, double cumulative});

/// Semesters of [institutionId] that have classes, chronological, each with
/// its own GPA and the cumulative GPA *within that institution*. Drives the
/// per-institution grades chart.
final gpaSeriesProvider =
    Provider.family<List<GpaPoint>, String>((ref, institutionId) {
  final semesters = [
    for (final s in ref.watch(semestersProvider))
      if (s.institutionId == institutionId) s,
  ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  final byId = <String, List<PastCourse>>{};
  for (final p in ref.watch(pastCoursesProvider)) {
    byId.putIfAbsent(p.semesterId, () => <PastCourse>[]).add(p);
  }

  // Live courses pinned to a semester here: their current weighted % is
  // converted to GPA points (institution's scale) and credit-weighted, so
  // the active term shows up on the chart and recomputes live.
  final inst = ref.watch(institutionsByIdProvider)[institutionId];
  final cats = ref.watch(gradeCategoriesProvider);
  final grades = ref.watch(gradesProvider);
  final liveById = <String, List<Course>>{};
  for (final c in ref.watch(coursesProvider)) {
    if (c.institutionId == institutionId && c.semesterId != null) {
      liveById.putIfAbsent(c.semesterId!, () => <Course>[]).add(c);
    }
  }

  final out = <GpaPoint>[];
  var cumQuality = 0.0;
  var cumCredits = 0.0;
  for (final s in semesters) {
    var quality = 0.0;
    var credits = 0.0;
    for (final p in (byId[s.id] ?? const <PastCourse>[])) {
      quality += p.qualityPoints;
      credits += p.creditHours;
    }
    for (final c in (liveById[s.id] ?? const <Course>[])) {
      final pct = courseWeightedPercent(c, cats, grades);
      if (pct == null || inst == null) continue;
      quality += inst.gpaPointsFor(pct) * c.creditHours;
      credits += c.creditHours;
    }
    if (credits <= 0) continue;
    cumQuality += quality;
    cumCredits += credits;
    out.add((
      semester: s,
      gpa: quality / credits,
      cumulative: cumQuality / cumCredits,
    ));
  }
  return out;
});

/// Institutions that have at least one recorded past class, ordered by
/// their most-recent semester first — so the grades chart can default to
/// the institution of the latest semester.
final institutionsWithHistoryProvider = Provider<List<Institution>>((ref) {
  final semById = {for (final s in ref.watch(semestersProvider)) s.id: s};
  final latestKey = <String, int>{}; // institutionId → max semester sortKey

  void mark(String? semesterId) {
    final s = semesterId == null ? null : semById[semesterId];
    if (s == null) return;
    final cur = latestKey[s.institutionId];
    if (cur == null || s.sortKey > cur) {
      latestKey[s.institutionId] = s.sortKey;
    }
  }

  // Either a recorded past class OR a live course pinned to a semester
  // makes an institution chartable.
  for (final p in ref.watch(pastCoursesProvider)) {
    mark(p.semesterId);
  }
  for (final c in ref.watch(coursesProvider)) {
    mark(c.semesterId);
  }
  if (latestKey.isEmpty) return const [];
  return [
    for (final i in ref.watch(institutionsProvider))
      if (latestKey.containsKey(i.id)) i,
  ]..sort((a, b) =>
      (latestKey[b.id] ?? 0).compareTo(latestKey[a.id] ?? 0));
});
