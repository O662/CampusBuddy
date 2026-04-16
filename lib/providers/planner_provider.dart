import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';

class PlannerProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  DateTime _selectedDay = DateTime.now();
  static const _key = 'tasks';

  List<Task> get allTasks => List.unmodifiable(_tasks);

  DateTime get selectedDay => _selectedDay;

  List<Task> get tasksForSelectedDay => _tasks
      .where((t) => _isSameDay(t.dueDate, _selectedDay))
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  List<Task> tasksForDay(DateTime day) =>
      _tasks.where((t) => _isSameDay(t.dueDate, day)).toList();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void selectDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      _tasks = Task.listFromJson(data);
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, Task.listToJson(_tasks));
  }

  Future<void> addTask(Task task) async {
    _tasks.add(task);
    notifyListeners();
    await _save();
  }

  Future<void> updateTask(Task updated) async {
    final idx = _tasks.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      _tasks[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  Future<void> toggleComplete(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _tasks[idx].isCompleted = !_tasks[idx].isCompleted;
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
    await _save();
  }
}
