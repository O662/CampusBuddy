import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';

/// Inter-window bridge for popped-out timers — the exact mirror of the notes
/// bridge (`note_window_bridge.dart`), which the docs there explain in full.
///
/// `desktop_multi_window` gives every pop-out its own Flutter engine with
/// **no** Hive and **no** Riverpod. The main window stays the single owner of
/// the data *and* the alarm engine; pop-outs talk to it over the channels
/// here:
///
/// * sub → main: one shared *unidirectional* [WindowMethodChannel]
///   ([kTimerHostChannel]) — many pop-outs invoke, the main window is the
///   sole handler. Carries `load`, `save`, `closed`.
/// * main → sub: each pop-out's own per-window controller channel — the main
///   window pushes `timerUpdated` / `timerDeleted` to a specific pop-out.
///
/// A pop-out only needs *state-change* pushes (start/pause/reset/rename): it
/// runs its own 1-second redraw and derives the countdown from the wall clock
/// (see [TimerItem]). The looping alarm always plays from the main window's
/// [TimerEngine], even when the timer is only visible in its pop-out.

/// businessId tag put in a pop-out window's launch arguments.
const String kTimerBusinessId = 'timer_popout';

/// Shared sub→main channel. Unidirectional: the main window registers the
/// only handler, every pop-out may invoke it.
const String kTimerHostChannel = 'campusbuddy/timers_host';

// Method names.
const String _mLoad = 'load'; // sub→main: {windowId, timerId} → JSON|null
const String _mSave = 'save'; // sub→main: timer JSON
const String _mClosed = 'closed'; // sub→main: {windowId}
const String mTimerUpdated = 'timerUpdated'; // main→sub: timer JSON
const String mTimerDeleted = 'timerDeleted'; // main→sub: timerId

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Parsed pop-out launch arguments. Returns null for the main window (which
/// launches with empty arguments) or any non-timer pop-out window.
({String timerId})? parseTimerWindowArguments(String arguments) {
  if (arguments.isEmpty) return null;
  try {
    final m = jsonDecode(arguments) as Map<String, dynamic>;
    if (m['businessId'] != kTimerBusinessId) return null;
    final id = m['timerId'] as String?;
    if (id == null || id.isEmpty) return null;
    return (timerId: id);
  } catch (_) {
    return null;
  }
}

/// Pop a timer out. On desktop this opens (or refocuses) a real
/// always-on-top OS window; everywhere else it falls back to the in-app
/// `/timer-window/:id` editor (no OS windows on web/Android).
void popOutTimer(BuildContext context, String timerId) {
  if (_isDesktop) {
    unawaited(TimerPopoutHost.instance.openOrFocus(timerId));
  } else {
    context.go('/timer-window/$timerId');
  }
}

/// Lives in the **main** window. Owns the channel handler + the
/// timer→window registry, and pushes timer changes out to open pop-outs.
class TimerPopoutHost {
  TimerPopoutHost._();
  static final TimerPopoutHost instance = TimerPopoutHost._();

  static const _channel = WindowMethodChannel(kTimerHostChannel,
      mode: ChannelMode.unidirectional);

  ProviderContainer? _container;
  ProviderSubscription<List<TimerItem>>? _sub;
  StreamSubscription<void>? _windowsSub;
  bool _attached = false;

  // timerId ↔ windowId, kept in lock-step.
  final Map<String, String> _windowByTimer = {};
  final Map<String, String> _timerByWindow = {};

  /// Wire the host to the app's [ProviderContainer]. Call once from the main
  /// window's `main()` (desktop only) before `runApp`.
  void attach(ProviderContainer container) {
    if (!_isDesktop || _attached) return;
    _attached = true;
    _container = container;

    _channel.setMethodCallHandler(_onSubCall);

    _sub = container.listen<List<TimerItem>>(
      timersProvider,
      (_, timers) => _broadcast(timers),
      fireImmediately: false,
    );

    _windowsSub = onWindowsChanged.listen((_) => _pruneClosedWindows());
  }

  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    _sub?.close();
    await _windowsSub?.cancel();
    await _channel.setMethodCallHandler(null);
    _sub = null;
    _windowsSub = null;
    _container = null;
    _windowByTimer.clear();
    _timerByWindow.clear();
  }

  Future<dynamic> _onSubCall(MethodCall call) async {
    final container = _container;
    if (container == null) return null;
    switch (call.method) {
      case _mLoad:
        final args = _decodeArgs(call.arguments);
        final windowId = args['windowId'] as String?;
        final timerId = args['timerId'] as String?;
        if (windowId != null && timerId != null) {
          _register(timerId, windowId);
        }
        final timer = _find(timerId);
        return timer == null ? null : jsonEncode(timer.toJson());
      case _mSave:
        final map = _decodeArgs(call.arguments);
        final timer = TimerItem.fromJson(map);
        await container.read(timersProvider.notifier).upsert(timer);
        return null;
      case _mClosed:
        final args = _decodeArgs(call.arguments);
        _unregister(args['windowId'] as String?);
        return null;
    }
    return null;
  }

  Map<String, dynamic> _decodeArgs(dynamic raw) {
    if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  TimerItem? _find(String? id) {
    if (id == null) return null;
    for (final t in _container!.read(timersProvider)) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _register(String timerId, String windowId) {
    final prevWindow = _windowByTimer.remove(timerId);
    if (prevWindow != null) _timerByWindow.remove(prevWindow);
    final prevTimer = _timerByWindow.remove(windowId);
    if (prevTimer != null) _windowByTimer.remove(prevTimer);
    _windowByTimer[timerId] = windowId;
    _timerByWindow[windowId] = timerId;
  }

  void _unregister(String? windowId) {
    if (windowId == null) return;
    final timerId = _timerByWindow.remove(windowId);
    if (timerId != null) _windowByTimer.remove(timerId);
  }

  void _broadcast(List<TimerItem> timers) {
    if (_timerByWindow.isEmpty) return;
    final byId = {for (final t in timers) t.id: t};
    for (final entry in _timerByWindow.entries.toList()) {
      final windowId = entry.key;
      final timerId = entry.value;
      final timer = byId[timerId];
      final target = WindowController.fromWindowId(windowId);
      if (timer == null) {
        unawaited(_safePush(target, mTimerDeleted, timerId));
      } else {
        unawaited(_safePush(
            target, mTimerUpdated, jsonEncode(timer.toJson())));
      }
    }
  }

  Future<void> _safePush(
      WindowController target, String method, dynamic args) async {
    try {
      await target.invokeMethod(method, args);
    } catch (_) {
      // Window went away mid-push; the backstop prune will clean up.
    }
  }

  Future<void> _pruneClosedWindows() async {
    try {
      final live = (await WindowController.getAll())
          .map((c) => c.windowId)
          .toSet();
      final gone =
          _timerByWindow.keys.where((id) => !live.contains(id)).toList();
      for (final id in gone) {
        _unregister(id);
      }
    } catch (_) {}
  }

  /// Open a pop-out OS window for [timerId], or focus the existing one if
  /// that timer is already popped out (one window per timer).
  Future<void> openOrFocus(String timerId) async {
    if (!_isDesktop) return;
    final existing = _windowByTimer[timerId];
    if (existing != null) {
      try {
        await WindowController.fromWindowId(existing).show();
        return;
      } catch (_) {
        _unregister(existing);
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode(
            {'businessId': kTimerBusinessId, 'timerId': timerId}),
      ),
    );
    _register(timerId, controller.windowId);
  }
}

/// Client side helper used by the pop-out window to reach the main window.
class TimerHostClient {
  const TimerHostClient(this.windowId);

  /// This pop-out's own window id (`WindowController.fromCurrentEngine`).
  final String windowId;

  static const _channel = WindowMethodChannel(kTimerHostChannel,
      mode: ChannelMode.unidirectional);

  /// Fetch the timer's current state from the main window (null = deleted).
  Future<TimerItem?> load(String timerId) async {
    final raw = await _channel.invokeMethod<String>(
        _mLoad, jsonEncode({'windowId': windowId, 'timerId': timerId}));
    if (raw == null) return null;
    return TimerItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Persist a change through the main window's Hive/Riverpod (and so the
  /// alarm engine, which re-evaluates on every timers change).
  Future<void> save(TimerItem timer) =>
      _channel.invokeMethod(_mSave, jsonEncode(timer.toJson()));

  /// Tell the main window this pop-out is closing so it stops pushing.
  Future<void> notifyClosed() =>
      _channel.invokeMethod(_mClosed, jsonEncode({'windowId': windowId}));
}
