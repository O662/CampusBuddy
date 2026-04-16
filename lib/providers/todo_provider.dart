import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_category.dart';
import '../models/todo_task.dart';

class TodoProvider extends ChangeNotifier {
  List<TodoCategory> _categories = [];
  List<TodoTask> _tasks = [];

  static const _catsKey = 'todo_categories';
  static const _tasksKey = 'todo_tasks';

  List<TodoCategory> get categories => List.unmodifiable(_categories);
  List<TodoTask> get allTasks => List.unmodifiable(_tasks);

  List<TodoTask> tasksForCategory(String categoryId) =>
      _tasks.where((t) => t.categoryId == categoryId).toList()
        ..sort((a, b) {
          if (a.isCompleted != b.isCompleted) {
            return a.isCompleted ? 1 : -1;
          }
          final pa = a.priority.index;
          final pb = b.priority.index;
          if (pa != pb) return pb.compareTo(pa); // high first
          if (a.dueDate != null && b.dueDate != null) {
            return a.dueDate!.compareTo(b.dueDate!);
          }
          return a.createdAt.compareTo(b.createdAt);
        });

  List<TodoTask> get tasksDueToday {
    final now = DateTime.now();
    return _tasks
        .where((t) =>
            !t.isCompleted &&
            t.dueDate != null &&
            t.dueDate!.year == now.year &&
            t.dueDate!.month == now.month &&
            t.dueDate!.day == now.day)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  List<TodoTask> get tasksDueSoon {
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 7));
    return _tasks
        .where((t) =>
            !t.isCompleted &&
            t.dueDate != null &&
            t.dueDate!.isAfter(now) &&
            t.dueDate!.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  }

  int pendingCount(String categoryId) =>
      _tasks.where((t) => t.categoryId == categoryId && !t.isCompleted).length;

  int totalCount(String categoryId) =>
      _tasks.where((t) => t.categoryId == categoryId).length;

  TodoCategory? categoryById(String id) =>
      _categories.cast<TodoCategory?>().firstWhere(
            (c) => c?.id == id,
            orElse: () => null,
          );

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final catsData = prefs.getString(_catsKey);
    final tasksData = prefs.getString(_tasksKey);
    if (catsData != null) _categories = TodoCategory.listFromJson(catsData);
    if (tasksData != null) _tasks = TodoTask.listFromJson(tasksData);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_catsKey, TodoCategory.listToJson(_categories));
    await prefs.setString(_tasksKey, TodoTask.listToJson(_tasks));
  }

  // ── Categories ──────────────────────────────────────────────────────────────

  Future<void> addCategory(TodoCategory cat) async {
    _categories.add(cat);
    notifyListeners();
    await _save();
  }

  Future<void> updateCategory(TodoCategory updated) async {
    final idx = _categories.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      _categories[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeCategory(String id) async {
    _categories.removeWhere((c) => c.id == id);
    _tasks.removeWhere((t) => t.categoryId == id);
    notifyListeners();
    await _save();
  }

  // ── Tasks ────────────────────────────────────────────────────────────────────

  Future<void> addTask(TodoTask task) async {
    _tasks.add(task);
    notifyListeners();
    await _save();
  }

  Future<void> updateTask(TodoTask updated) async {
    final idx = _tasks.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      _tasks[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  Future<void> toggleComplete(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      _tasks[idx].isCompleted = !_tasks[idx].isCompleted;
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
    await _save();
  }
}
