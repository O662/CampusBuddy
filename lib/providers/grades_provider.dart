import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';
import '../models/institution.dart';
import '../models/semester.dart';

class GradesProvider extends ChangeNotifier {
  List<Course> _courses = [];
  List<Institution> _institutions = [];
  List<Semester> _semesters = [];

  static const _coursesKey = 'courses';
  static const _institutionsKey = 'institutions';
  static const _semestersKey = 'semesters';

  List<Course> get courses => List.unmodifiable(_courses);
  List<Institution> get institutions => List.unmodifiable(_institutions);
  List<Semester> get semesters => List.unmodifiable(_semesters);

  // ── GPA calculations ────────────────────────────────────────────────────────

  /// Cumulative GPA across all courses where includeInGpa is true (4.0 scale).
  double get gpa {
    final included = _courses.where((c) => c.includeInGpa).toList();
    if (included.isEmpty) return 0.0;
    double totalPoints = 0;
    double totalCredits = 0;
    for (final c in included) {
      totalPoints += c.gpaPoints * c.credits;
      totalCredits += c.credits;
    }
    return totalCredits == 0 ? 0 : totalPoints / totalCredits;
  }

  /// Total credit hours for GPA-counted courses.
  double get totalCredits =>
      _courses.where((c) => c.includeInGpa).fold(0.0, (s, c) => s + c.credits);

  /// GPA for a specific institution, scaled to that institution's gpaScale.
  double gpaForInstitution(String institutionId) {
    final inst = _institutions.where((i) => i.id == institutionId).firstOrNull;
    final scale = inst?.gpaScale ?? 4.0;
    final courses =
        _courses.where((c) => c.institutionId == institutionId).toList();
    if (courses.isEmpty) return 0.0;
    double totalPoints = 0;
    double totalCredits = 0;
    for (final c in courses) {
      totalPoints += c.gpaPointsForScale(scale) * c.credits;
      totalCredits += c.credits;
    }
    return totalCredits == 0 ? 0 : totalPoints / totalCredits;
  }

  /// GPA for a specific semester (4.0 scale).
  double gpaForSemester(String semesterId) {
    final courses =
        _courses.where((c) => c.semesterId == semesterId).toList();
    if (courses.isEmpty) return 0.0;
    double totalPoints = 0;
    double totalCredits = 0;
    for (final c in courses) {
      totalPoints += c.gpaPoints * c.credits;
      totalCredits += c.credits;
    }
    return totalCredits == 0 ? 0 : totalPoints / totalCredits;
  }

  /// Courses that belong to a given institution but have no semesterId assigned.
  List<Course> unsortedCoursesForInstitution(String institutionId) =>
      _courses
          .where((c) =>
              c.institutionId == institutionId && c.semesterId == null)
          .toList();

  /// Courses with no institution assigned.
  List<Course> get uncategorizedCourses =>
      _courses.where((c) => c.institutionId == null).toList();

  /// Semesters that belong to a given institution, sorted by sortOrder.
  List<Semester> semestersForInstitution(String institutionId) =>
      _semesters
          .where((s) => s.institutionId == institutionId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Courses that belong to a given semester.
  List<Course> coursesForSemester(String semesterId) =>
      _courses.where((c) => c.semesterId == semesterId).toList();

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final coursesData = prefs.getString(_coursesKey);
    if (coursesData != null) _courses = Course.listFromJson(coursesData);

    final institutionsData = prefs.getString(_institutionsKey);
    if (institutionsData != null) {
      _institutions = Institution.listFromJson(institutionsData);
    }

    final semestersData = prefs.getString(_semestersKey);
    if (semestersData != null) {
      _semesters = Semester.listFromJson(semestersData);
    }

    notifyListeners();
  }

  Future<void> _saveCourses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_coursesKey, Course.listToJson(_courses));
  }

  Future<void> _saveInstitutions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _institutionsKey, Institution.listToJson(_institutions));
  }

  Future<void> _saveSemesters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_semestersKey, Semester.listToJson(_semesters));
  }

  // ── Course CRUD ──────────────────────────────────────────────────────────────

  Future<void> addCourse(Course course) async {
    _courses.add(course);
    notifyListeners();
    await _saveCourses();
  }

  Future<void> updateCourse(Course updated) async {
    final idx = _courses.indexWhere((c) => c.id == updated.id);
    if (idx != -1) {
      _courses[idx] = updated;
      notifyListeners();
      await _saveCourses();
    }
  }

  Future<void> removeCourse(String id) async {
    _courses.removeWhere((c) => c.id == id);
    notifyListeners();
    await _saveCourses();
  }

  // ── Institution CRUD ─────────────────────────────────────────────────────────

  Future<void> addInstitution(Institution institution) async {
    _institutions.add(institution);
    notifyListeners();
    await _saveInstitutions();
  }

  Future<void> updateInstitution(Institution updated) async {
    final idx = _institutions.indexWhere((i) => i.id == updated.id);
    if (idx != -1) {
      _institutions[idx] = updated;
      notifyListeners();
      await _saveInstitutions();
    }
  }

  /// Removes an institution and clears institutionId on associated courses.
  Future<void> removeInstitution(String id) async {
    _institutions.removeWhere((i) => i.id == id);
    _courses = _courses
        .map((c) => c.institutionId == id ? c.copyWith(institutionId: null, semesterId: null) : c)
        .toList();
    _semesters.removeWhere((s) => s.institutionId == id);
    notifyListeners();
    await Future.wait([_saveInstitutions(), _saveCourses(), _saveSemesters()]);
  }

  // ── Semester CRUD ────────────────────────────────────────────────────────────

  Future<void> addSemester(Semester semester) async {
    _semesters.add(semester);
    notifyListeners();
    await _saveSemesters();
  }

  Future<void> updateSemester(Semester updated) async {
    final idx = _semesters.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _semesters[idx] = updated;
      notifyListeners();
      await _saveSemesters();
    }
  }

  /// Removes a semester and clears semesterId on associated courses.
  Future<void> removeSemester(String id) async {
    _semesters.removeWhere((s) => s.id == id);
    _courses = _courses
        .map((c) => c.semesterId == id ? c.copyWith(semesterId: null) : c)
        .toList();
    notifyListeners();
    await Future.wait([_saveSemesters(), _saveCourses()]);
  }
}
