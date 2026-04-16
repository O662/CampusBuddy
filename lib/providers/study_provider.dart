import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StudyMode { work, shortBreak, longBreak }

class StudyProvider extends ChangeNotifier {
  static const _totalSessionsKey = 'total_sessions';
  static const _totalMinutesKey = 'total_minutes';

  int _workMinutes = 25;
  int _shortBreakMinutes = 5;
  int _longBreakMinutes = 15;
  int _sessionsBeforeLongBreak = 4;

  StudyMode _mode = StudyMode.work;
  int _secondsRemaining = 25 * 60;
  bool _isRunning = false;
  int _completedSessions = 0;
  Timer? _timer;

  int _totalSessions = 0;
  int _totalMinutesStudied = 0;

  int get workMinutes => _workMinutes;
  int get shortBreakMinutes => _shortBreakMinutes;
  int get longBreakMinutes => _longBreakMinutes;
  int get sessionsBeforeLongBreak => _sessionsBeforeLongBreak;

  StudyMode get mode => _mode;
  int get secondsRemaining => _secondsRemaining;
  bool get isRunning => _isRunning;
  int get completedSessions => _completedSessions;
  int get totalSessions => _totalSessions;
  int get totalMinutesStudied => _totalMinutesStudied;

  String get timeDisplay {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get progress {
    final total = _totalSecondsForMode(_mode);
    return 1.0 - (_secondsRemaining / total);
  }

  int _totalSecondsForMode(StudyMode m) {
    switch (m) {
      case StudyMode.work:
        return _workMinutes * 60;
      case StudyMode.shortBreak:
        return _shortBreakMinutes * 60;
      case StudyMode.longBreak:
        return _longBreakMinutes * 60;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _totalSessions = prefs.getInt(_totalSessionsKey) ?? 0;
    _totalMinutesStudied = prefs.getInt(_totalMinutesKey) ?? 0;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalSessionsKey, _totalSessions);
    await prefs.setInt(_totalMinutesKey, _totalMinutesStudied);
  }

  void startPause() {
    if (_isRunning) {
      _timer?.cancel();
      _isRunning = false;
    } else {
      _isRunning = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    notifyListeners();
  }

  void _tick() {
    if (_secondsRemaining > 0) {
      _secondsRemaining--;
      notifyListeners();
    } else {
      _timer?.cancel();
      _isRunning = false;
      _onSessionComplete();
    }
  }

  void _onSessionComplete() {
    if (_mode == StudyMode.work) {
      _completedSessions++;
      _totalSessions++;
      _totalMinutesStudied += _workMinutes;
      _save();

      if (_completedSessions % _sessionsBeforeLongBreak == 0) {
        _switchMode(StudyMode.longBreak);
      } else {
        _switchMode(StudyMode.shortBreak);
      }
    } else {
      _switchMode(StudyMode.work);
    }
    notifyListeners();
  }

  void _switchMode(StudyMode newMode) {
    _mode = newMode;
    _secondsRemaining = _totalSecondsForMode(newMode);
    _isRunning = false;
  }

  void setMode(StudyMode newMode) {
    _timer?.cancel();
    _switchMode(newMode);
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _isRunning = false;
    _secondsRemaining = _totalSecondsForMode(_mode);
    notifyListeners();
  }

  void updateSettings({
    int? workMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? sessionsBeforeLongBreak,
  }) {
    _timer?.cancel();
    _isRunning = false;
    if (workMinutes != null) _workMinutes = workMinutes;
    if (shortBreakMinutes != null) _shortBreakMinutes = shortBreakMinutes;
    if (longBreakMinutes != null) _longBreakMinutes = longBreakMinutes;
    if (sessionsBeforeLongBreak != null) {
      _sessionsBeforeLongBreak = sessionsBeforeLongBreak;
    }
    _secondsRemaining = _totalSecondsForMode(_mode);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
