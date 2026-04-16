import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';

class GradesProvider extends ChangeNotifier {
  List<Course> _courses = [];
  static const _key = 'courses';

  List<Course> get courses => List.unmodifiable(_courses);

  double get gpa {
    if (_courses.isEmpty) return 0.0;
    double totalPoints = 0;
    double totalCredits = 0;
    for (final c in _courses) {
      totalPoints += c.gpaPoints * c.credits;
      totalCredits += c.credits;
    }
    return totalCredits == 0 ? 0 : totalPoints / totalCredits;
  }

  double get totalCredits =>
      _courses.fold(0, (sum, c) => sum + c.credits);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      _courses = Course.listFromJson(data);
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, Course.listToJson(_courses));
  }

  Future<void> addCourse(Course course) async {
    _courses.add(course);
    notifyListeners();
    await _save();
  }

  Future<void> updateCourse(Course updated) async {
    final idx = _courses.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      _courses[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeCourse(String id) async {
    _courses.removeWhere((c) => c.id == id);
    notifyListeners();
    await _save();
  }
}
