import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/planned_task.dart';

class TaskPlannerProvider extends ChangeNotifier {
  List<PlannedTask> _planned = [];
  static const _key = 'task_planner_v1';

  List<PlannedTask> get all => List.unmodifiable(_planned);

  List<PlannedTask> forDate(DateTime date) =>
      _planned.where((p) => _sameDay(p.date, date)).toList();

  bool isPlanned(String taskId) => _planned.any((p) => p.taskId == taskId);

  PlannedTask? byTaskId(String taskId) {
    for (final p in _planned) {
      if (p.taskId == taskId) return p;
    }
    return null;
  }

  Future<void> plan(
    String taskId,
    DateTime date, {
    int? startMinutes,
    int durationMinutes = 60,
  }) async {
    _planned.removeWhere((p) => p.taskId == taskId);
    _planned.add(PlannedTask(
      id: '${DateTime.now().millisecondsSinceEpoch}_$taskId',
      taskId: taskId,
      date: DateTime(date.year, date.month, date.day),
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
    ));
    notifyListeners();
    await _save();
  }

  Future<void> unplan(String taskId) async {
    _planned.removeWhere((p) => p.taskId == taskId);
    notifyListeners();
    await _save();
  }

  Future<void> updatePlanned(PlannedTask updated) async {
    final idx = _planned.indexWhere((p) => p.id == updated.id);
    if (idx != -1) {
      _planned[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      try {
        _planned = PlannedTask.listFromJson(data);
      } catch (_) {
        _planned = [];
      }
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, PlannedTask.listToJson(_planned));
  }
}
