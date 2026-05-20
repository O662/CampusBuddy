import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/models.dart' show TimerItem;

/// Wraps `flutter_local_notifications` so the rest of the app stays
/// platform-agnostic. Falls back to a quiet no-op on web (no native drawer)
/// or when init fails (e.g. an unpackaged Windows build where the OS
/// rejects the toast registration) — the app still works, the drawer just
/// stays empty.
///
/// Two notification flavours per timer:
///
/// * **Active** — low-priority, ongoing, silent. One per running countdown
///   timer and one for the active Pomodoro session. Refreshed once per
///   minute as the countdown drops; the body shows "X left · goes off at
///   3:45 PM" so a glance at the drawer is enough.
/// * **Finished** — high-priority, one-shot, with the system alert sound.
///   Fired when a timer actually fires. Cleared when the user dismisses
///   the alarm in-app.
class AppNotifications {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Reserved id space for the single Pomodoro slot. Picked far away from
  // anywhere a timer-id hash would land.
  static const int _pomodoroId = 0x70000001;

  // Throttle state — only re-issue a notification when the "minute bucket"
  // it would show changes, so the drawer doesn't churn every second.
  final Map<String, int> _lastTimerBucket = {};
  int _lastPomoBucket = -1;

  /// One-time init. Safe to call once from `main()`; later calls are no-ops.
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      const init = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open CampusBuddy',
        ),
        windows: WindowsInitializationSettings(
          appName: 'CampusBuddy',
          appUserModelId: 'com.campusbuddy.app',
          // Stable random GUID — must not change between releases, or the
          // OS will treat this as a different sender and lose pinned toasts.
          guid: '7beb1f88-3d5b-4f6f-a8c0-9c4e2a5d8b1f',
        ),
      );
      await _plugin.initialize(init);

      // Android 13+ surfaces a runtime permission gate for notifications.
      if (!kIsWeb && Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _ready = true;
    } catch (_) {
      // Init failure → silently disable. Common on unpackaged Windows
      // builds where the app isn't registered with the OS yet.
      _ready = false;
    }
  }

  // ---------------------------------------------------------------------
  // Timer notifications — driven by [TimerEngine]
  // ---------------------------------------------------------------------

  /// Hash a UUID-ish string into a stable positive int notification id.
  int _idForTimer(String uuid) => uuid.hashCode & 0x3FFFFFFF;
  int _idForTimerDone(String uuid) => (_idForTimer(uuid) ^ 0x10000000) | 0x40000000;

  /// True when an active-timer notification for [id] should be re-issued
  /// because its visible "minute left" bucket changed since last update.
  bool shouldRefreshActiveTimer(String id, int remainingSeconds) {
    final bucket = _bucketForRemaining(remainingSeconds);
    if (_lastTimerBucket[id] == bucket) return false;
    _lastTimerBucket[id] = bucket;
    return true;
  }

  Future<void> showActiveTimer(TimerItem t) async {
    if (!_ready || t.endsAt == null) return;
    final name = t.name.trim().isEmpty ? 'Timer' : t.name.trim();
    final body = '${_humanLeft(t.remainingSeconds)} left'
        ' · goes off at ${_fmtClock(t.endsAt!)}';
    try {
      await _plugin.show(_idForTimer(t.id), name, body, _activeDetails(name));
    } catch (_) {}
  }

  Future<void> showTimerFinished(TimerItem t) async {
    if (!_ready) return;
    final name = t.name.trim().isEmpty ? 'Timer' : t.name.trim();
    try {
      await _plugin.cancel(_idForTimer(t.id));
      await _plugin.show(
        _idForTimerDone(t.id),
        "$name — Time's up",
        'Your ${_humanLeft(t.durationSeconds)} timer just finished.',
        _doneDetails(name),
      );
    } catch (_) {}
  }

  Future<void> cancelActiveTimer(String id) async {
    if (!_ready) return;
    _lastTimerBucket.remove(id);
    try {
      await _plugin.cancel(_idForTimer(id));
    } catch (_) {}
  }

  Future<void> cancelFinishedTimer(String id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_idForTimerDone(id));
    } catch (_) {}
  }

  /// Tear-down used when a timer is deleted outright.
  Future<void> cancelTimer(String id) async {
    await cancelActiveTimer(id);
    await cancelFinishedTimer(id);
  }

  // ---------------------------------------------------------------------
  // Pomodoro session — single slot, driven by the session page
  // ---------------------------------------------------------------------

  /// Throttle: true at the start of each new minute bucket of the session
  /// countdown. The session page already ticks every second; this lets it
  /// piggy-back a notification refresh on those ticks cheaply.
  bool shouldRefreshPomodoro(int remainingSeconds) {
    final bucket = _bucketForRemaining(remainingSeconds);
    if (_lastPomoBucket == bucket) return false;
    _lastPomoBucket = bucket;
    return true;
  }

  Future<void> showPomodoro({
    required String name,
    required String phaseLabel,
    required int remainingSeconds,
    required int round,
    required int totalRounds,
  }) async {
    if (!_ready) return;
    final title = name.trim().isEmpty ? 'Pomodoro' : name.trim();
    final body = remainingSeconds > 0
        ? '$phaseLabel · ${_humanLeft(remainingSeconds)} left'
            ' · round $round of $totalRounds'
        : phaseLabel;
    try {
      await _plugin.show(_pomodoroId, title, body, _pomodoroDetails(title));
    } catch (_) {}
  }

  Future<void> cancelPomodoro() async {
    if (!_ready) return;
    _lastPomoBucket = -1;
    try {
      await _plugin.cancel(_pomodoroId);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// "Minute bucket" used for throttling so the drawer only refreshes when
  /// the visible "X left" digit would change. Below a minute, every 10s gets
  /// its own bucket so the last stretch shows real progress.
  int _bucketForRemaining(int seconds) {
    if (seconds >= 60) return 60 + (seconds ~/ 60); // bucket per minute
    return seconds ~/ 10; // 0..5 for the final minute
  }

  String _humanLeft(int sec) {
    if (sec <= 0) return '0s';
    if (sec >= 3600) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (sec >= 60) {
      final m = sec ~/ 60;
      return '${m}m';
    }
    return '${sec}s';
  }

  String _fmtClock(DateTime t) {
    final h = t.hour;
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  NotificationDetails _activeDetails(String tickerText) => NotificationDetails(
        android: AndroidNotificationDetails(
          'cb_timer_active',
          'Active timers',
          channelDescription: 'Ongoing countdown timers from CampusBuddy',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          silent: true,
          ticker: tickerText,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
        macOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
        linux: const LinuxNotificationDetails(),
        windows: const WindowsNotificationDetails(),
      );

  NotificationDetails _doneDetails(String tickerText) => NotificationDetails(
        android: AndroidNotificationDetails(
          'cb_timer_done',
          'Finished timers',
          channelDescription:
              'Notifications when a CampusBuddy countdown finishes',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          ticker: tickerText,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
        macOS: const DarwinNotificationDetails(presentSound: true),
        linux: const LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.critical,
        ),
        windows: const WindowsNotificationDetails(),
      );

  NotificationDetails _pomodoroDetails(String tickerText) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          'cb_pomodoro_active',
          'Active Pomodoro',
          channelDescription: 'The Pomodoro session currently in progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          silent: true,
          ticker: tickerText,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
        macOS: const DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
        linux: const LinuxNotificationDetails(),
        windows: const WindowsNotificationDetails(),
      );
}
