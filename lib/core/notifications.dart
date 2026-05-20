import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../data/models.dart' show TimerItem;

/// OS-drawer notifications for active timers + the running Pomodoro. Uses
/// `local_notifier` because it handles the Windows-specific Start-menu
/// shortcut + AppUserModelID registration automatically (the missing piece
/// behind "Windows Defender is blocking my notifications" with the more
/// heavyweight `flutter_local_notifications` on unpackaged dev builds).
///
/// Cross-platform note: `local_notifier` is **desktop-only**
/// (Windows / macOS / Linux). On web and mobile the service no-ops; add a
/// platform-conditional path here when mobile becomes a real target.
///
/// Design: notifications are only re-issued when their *contents* would
/// change (a Start, Pause, Reset, Resume or Finish — never per-second). The
/// body shows the wall-clock "goes off at 3:45 PM" so a glance at the
/// drawer tells you when it fires without needing live updates. That also
/// avoids triggering the OS toast sound on every refresh.
class AppNotifications {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  bool _ready = false;

  /// Per-key live notification. We keep handles so we can `destroy()` and
  /// replace on update — `local_notifier` keys its own state by the
  /// `LocalNotification` instance, not its identifier string.
  final Map<String, LocalNotification> _live = {};

  /// Last shown signature per timer id so we can skip a re-show when
  /// nothing the user would see has changed.
  final Map<String, String> _lastActiveSig = {};

  /// Last shown "minute bucket" per timer id — so the body's `X left`
  /// counts down with the timer instead of going stale.
  final Map<String, int> _lastActiveBucket = {};
  int _lastPomoBucket = -1;

  /// One-time init. Safe to call once from `main()`; later calls are no-ops.
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    // local_notifier supports desktop only.
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    try {
      await localNotifier.setup(
        appName: 'CampusBuddy',
        // On Windows, the OS only displays toasts from apps that have a
        // Start menu shortcut tied to an AppUserModelID. requireCreate
        // makes the package register one on first run, so toasts show up
        // in Action Center without the user installing or packaging
        // anything — and Defender stops silencing them.
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
    } catch (_) {
      // If setup throws (rare — usually a sandboxed environment), the
      // service quietly disables and the rest of the app keeps working.
      _ready = false;
    }
  }

  // ---------------------------------------------------------------------
  // Timer notifications — driven by [TimerEngine]
  // ---------------------------------------------------------------------

  String _activeKey(String id) => 'timer-active-$id';
  String _doneKey(String id) => 'timer-done-$id';

  /// True when the visible state for [t] changed since the last push.
  /// Lets the engine cheaply skip re-issuing during a per-second tick.
  bool activeSignatureChanged(TimerItem t) {
    final sig = '${t.name}|${t.endsAt?.millisecondsSinceEpoch ?? 0}';
    if (_lastActiveSig[t.id] == sig) return false;
    _lastActiveSig[t.id] = sig;
    return true;
  }

  /// True when [t]'s visible "X left" should change — i.e. it crossed
  /// into a new minute (or, in the last minute, a new 10-second slice).
  /// Drives the live countdown in the drawer.
  bool activeBucketChanged(TimerItem t) {
    final bucket = _bucketForRemaining(t.remainingSeconds);
    if (_lastActiveBucket[t.id] == bucket) return false;
    _lastActiveBucket[t.id] = bucket;
    return true;
  }

  /// Same "minute bucket" trick for the running Pomodoro session.
  bool pomodoroBucketChanged(int remainingSeconds) {
    final bucket = _bucketForRemaining(remainingSeconds);
    if (_lastPomoBucket == bucket) return false;
    _lastPomoBucket = bucket;
    return true;
  }

  int _bucketForRemaining(int seconds) {
    if (seconds >= 60) return 60 + (seconds ~/ 60); // bucket per minute
    return seconds ~/ 10; // 0..5 in the final minute for finer feedback
  }

  Future<void> showActiveTimer(TimerItem t) async {
    if (!_ready || t.endsAt == null) return;
    final name = t.name.trim().isEmpty ? 'Timer' : t.name.trim();
    await _showOrReplace(
      _activeKey(t.id),
      LocalNotification(
        identifier: _activeKey(t.id),
        title: name,
        body: 'Goes off at ${_fmtClock(t.endsAt!)}'
            ' · ${_humanLeft(t.remainingSeconds)} left',
        silent: true, // ongoing-style entries shouldn't ding
      ),
    );
  }

  Future<void> showTimerFinished(TimerItem t) async {
    if (!_ready) return;
    await _cancel(_activeKey(t.id));
    final name = t.name.trim().isEmpty ? 'Timer' : t.name.trim();
    await _showOrReplace(
      _doneKey(t.id),
      LocalNotification(
        identifier: _doneKey(t.id),
        title: "$name — Time's up",
        body: 'Your ${_humanLeft(t.durationSeconds)} timer just finished.',
        // not silent — the toast sound is the visual companion to the
        // in-app alarm chime.
      ),
    );
  }

  Future<void> cancelActiveTimer(String id) async {
    _lastActiveSig.remove(id);
    _lastActiveBucket.remove(id);
    await _cancel(_activeKey(id));
  }

  Future<void> cancelFinishedTimer(String id) => _cancel(_doneKey(id));

  Future<void> cancelTimer(String id) async {
    await cancelActiveTimer(id);
    await cancelFinishedTimer(id);
  }

  // ---------------------------------------------------------------------
  // Pomodoro session — single slot, driven by the session page
  // ---------------------------------------------------------------------

  static const _pomoKey = 'pomodoro-active';

  Future<void> showPomodoro({
    required String name,
    required String phaseLabel,
    required int remainingSeconds,
    required int round,
    required int totalRounds,
  }) async {
    if (!_ready) return;
    final title = name.trim().isEmpty ? 'Pomodoro' : name.trim();
    final endsAt =
        DateTime.now().add(Duration(seconds: remainingSeconds));
    final body = remainingSeconds > 0
        ? '$phaseLabel · ends at ${_fmtClock(endsAt)}'
            ' · round $round of $totalRounds'
        : phaseLabel;
    await _showOrReplace(
      _pomoKey,
      LocalNotification(
        identifier: _pomoKey,
        title: title,
        body: body,
        silent: true,
      ),
    );
  }

  Future<void> cancelPomodoro() async {
    _lastPomoBucket = -1;
    await _cancel(_pomoKey);
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<void> _showOrReplace(String key, LocalNotification n) async {
    final existing = _live[key];
    if (existing != null) {
      try {
        await existing.destroy();
      } catch (_) {}
    }
    _live[key] = n;
    try {
      await n.show();
    } catch (_) {}
  }

  Future<void> _cancel(String key) async {
    final existing = _live.remove(key);
    if (existing == null) return;
    try {
      await existing.destroy();
    } catch (_) {}
  }

  String _humanLeft(int sec) {
    if (sec <= 0) return '0s';
    if (sec >= 3600) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (sec >= 60) return '${sec ~/ 60}m';
    return '${sec}s';
  }

  String _fmtClock(DateTime t) {
    final h = t.hour;
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }
}
