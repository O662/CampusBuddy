import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/timer_view.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// In-app single-timer view at `/timer-window/:id`. The **fallback** used on
/// platforms with no OS windows (web, Android). On desktop, "Pop out" instead
/// opens a real, independent, always-on-top window — see
/// `timer_window_bridge.dart` / `timer_window.dart`. The surface itself is
/// the shared [TimerPanel]; here it is wired straight to Riverpod and rebuilt
/// once per second by watching the timer engine.
class TimerPopoutPage extends ConsumerStatefulWidget {
  const TimerPopoutPage({super.key, required this.timerId});

  final String timerId;

  @override
  ConsumerState<TimerPopoutPage> createState() => _TimerPopoutPageState();
}

class _TimerPopoutPageState extends ConsumerState<TimerPopoutPage> {
  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/timer');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watching the engine pulls in the per-second tick that drives the
    // countdown display (the alarm sound itself lives in the engine).
    ref.watch(timerEngineProvider);

    final timers = ref.watch(timersProvider);
    TimerItem? timer;
    for (final t in timers) {
      if (t.id == widget.timerId) {
        timer = t;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: timer == null
                ? TimerDeletedView(onClose: _close)
                : TimerPanel(
                    timer: timer,
                    onSave: (next) =>
                        ref.read(timersProvider.notifier).upsert(next),
                    onClose: _close,
                  ),
          ),
        ),
      ),
    );
  }
}
