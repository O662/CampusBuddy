import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/timer_view.dart';
import '../../data/models.dart';
import 'timer_window_bridge.dart';

/// Entry point for a popped-out timer's own OS window. Runs in its own
/// Flutter engine with **no** Hive/Riverpod — every read/write round-trips to
/// the main window via [TimerHostClient]. A local 1-second ticker redraws the
/// countdown (derived from the wall clock); the looping alarm sound stays in
/// the main window's engine. Sizing + always-on-top use `window_manager`,
/// which resolves *this* engine's native window, so the pin is per-pop-out.
void runTimerWindow(WindowController controller, String timerId) {
  const options = WindowOptions(
    size: Size(340, 430),
    minimumSize: Size(300, 380),
    center: true,
    title: 'Timer · CampusBuddy',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: Color(0xFF15132B),
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(TimerWindowApp(controller: controller, timerId: timerId));
}

class TimerWindowApp extends StatelessWidget {
  const TimerWindowApp({
    super.key,
    required this.controller,
    required this.timerId,
  });

  final WindowController controller;
  final String timerId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: TimerWindowPage(controller: controller, timerId: timerId),
    );
  }
}

class TimerWindowPage extends StatefulWidget {
  const TimerWindowPage({
    super.key,
    required this.controller,
    required this.timerId,
  });

  final WindowController controller;
  final String timerId;

  @override
  State<TimerWindowPage> createState() => _TimerWindowPageState();
}

class _TimerWindowPageState extends State<TimerWindowPage>
    with WindowListener {
  late final TimerHostClient _client =
      TimerHostClient(widget.controller.windowId);

  Timer? _ticker;
  TimerItem? _timer;
  bool _loading = true;
  bool _deleted = false;
  bool _pinned = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    unawaited(widget.controller.setWindowMethodHandler(_onMainCall));
    // Redraw every second so the countdown advances locally; the data only
    // changes when the user (here or on the board) acts on it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _timer != null) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final timer = await _client.load(widget.timerId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (timer == null) {
          _deleted = true;
        } else {
          _timer = timer;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _deleted = true; // main window unreachable — nothing to drive it.
      });
    }
  }

  /// Handles main→sub pushes on this window's dedicated channel.
  Future<dynamic> _onMainCall(MethodCall call) async {
    switch (call.method) {
      case mTimerUpdated:
        final timer =
            TimerItem.fromJson(_asMap(call.arguments) ?? const {});
        if (timer.id == widget.timerId && mounted) {
          setState(() {
            _timer = timer;
            _deleted = false;
            _loading = false;
          });
        }
        return null;
      case mTimerDeleted:
        if (mounted) setState(() => _deleted = true);
        return null;
      case 'window_close':
        await _close();
        return null;
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      final decoded = _tryJson(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  void _onSave(TimerItem next) {
    setState(() => _timer = next); // optimistic — keep controls responsive
    unawaited(_client.save(next));
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() => _pinned = next);
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (_) {}
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      await _client.notifyClosed();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    unawaited(_close());
  }

  @override
  Widget build(BuildContext context) {
    final timer = _timer;
    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_deleted || timer == null)
                    ? TimerDeletedView(onClose: _close)
                    : TimerPanel(
                        timer: timer,
                        onSave: _onSave,
                        onClose: _close,
                        pinned: _pinned,
                        onTogglePin: _togglePin,
                      ),
          ),
        ),
      ),
    );
  }
}
