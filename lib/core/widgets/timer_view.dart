import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_palette.dart';
import '../timer_format.dart';
import 'glass.dart';
import 'ui_kit.dart';

/// Shared timer-rendering pieces used by the Timer board card, the popped-out
/// OS window and the in-app fallback page, so a timer looks and behaves the
/// same everywhere. All pieces are storage-agnostic: state changes are handed
/// back via callbacks and the caller decides how to persist (Riverpod on the
/// board, the inter-window bridge on the pop-out).
///
/// None of these widgets tick on their own — the host rebuilds them once per
/// second (the board watches the timer engine; the pop-out window runs its
/// own 1-second `setState`). [TimerItem] derives the remaining time from the
/// wall clock, so a plain rebuild is all that's needed.

/// The circular countdown: progress ring, big digits, and the timer's name
/// plus its state line ("Goes off at 3:45 PM" / "Paused" / "Time's up").
/// Pulses gently while ringing.
class TimerDial extends StatefulWidget {
  const TimerDial({super.key, required this.timer, this.size = 220});

  final TimerItem timer;
  final double size;

  @override
  State<TimerDial> createState() => _TimerDialState();
}

class _TimerDialState extends State<TimerDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(TimerDial old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.timer.isFinished) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.timer;
    final total = t.durationSeconds;
    final remaining = t.remainingSeconds;
    final finished = t.isFinished;
    final accent = finished ? AppPalette.danger : t.color;
    final progress =
        total <= 0 ? 0.0 : (1 - remaining / total).clamp(0.0, 1.0);

    final stateLine = finished
        ? "Time's up"
        : t.isRunning
            ? 'Goes off at ${fmtGoesOff(t.endsAt!)}'
            : t.isPaused
                ? 'Paused · ${fmtDurationLabel(t.durationSeconds)} timer'
                : '${fmtDurationLabel(t.durationSeconds)} timer';

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = finished ? 0.35 + 0.45 * _pulse.value : 0.0;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (finished)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPalette.danger.withValues(alpha: glow * 0.18),
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppPalette.danger.withValues(alpha: glow * 0.5),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.name.trim().isNotEmpty) ...[
                    Text(
                      t.name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    fmtCountdown(remaining),
                    style: TextStyle(
                      fontSize: widget.size * 0.21,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(
                      stateLine,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: finished
                            ? AppPalette.danger
                            : AppPalette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Start/Pause + Reset, replaced by a single "Dismiss" when ringing. Every
/// transition is computed via the [TimerItem] model helpers and handed back
/// through [onChanged]; the caller persists it.
class TimerControls extends StatelessWidget {
  const TimerControls({
    super.key,
    required this.timer,
    required this.onChanged,
  });

  final TimerItem timer;
  final ValueChanged<TimerItem> onChanged;

  @override
  Widget build(BuildContext context) {
    if (timer.isFinished) {
      return SoftButton(
        label: 'Dismiss',
        icon: Icons.notifications_off_rounded,
        filled: true,
        onTap: () => onChanged(timer.resetToFull()),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SoftButton(
          label: timer.isRunning ? 'Pause' : 'Start',
          icon: timer.isRunning
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          filled: true,
          onTap: () => onChanged(
              timer.isRunning ? timer.paused() : timer.started()),
        ),
        const SizedBox(width: 10),
        SoftButton(
          label: 'Start over',
          icon: Icons.refresh_rounded,
          onTap: () => onChanged(timer.resetToFull()),
        ),
      ],
    );
  }
}

/// The full single-timer surface for a pop-out window / the in-app fallback:
/// a header (name editor, pin, close), the dial and the controls. The name
/// controller is seeded once so typing never fights the cursor; an external
/// rename (edited on the board while popped out) is folded back in while the
/// field is unfocused.
class TimerPanel extends StatefulWidget {
  const TimerPanel({
    super.key,
    required this.timer,
    required this.onSave,
    required this.onClose,
    this.pinned,
    this.onTogglePin,
  });

  final TimerItem timer;
  final ValueChanged<TimerItem> onSave;
  final VoidCallback onClose;

  /// Always-on-top state, or null when there's no real OS window to pin
  /// (the non-desktop in-app fallback) — the control is then hidden.
  final bool? pinned;
  final VoidCallback? onTogglePin;

  @override
  State<TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends State<TimerPanel> {
  late final TextEditingController _nameC =
      TextEditingController(text: widget.timer.name);
  final _nameFocus = FocusNode();

  @override
  void didUpdateWidget(TimerPanel old) {
    super.didUpdateWidget(old);
    if (!_nameFocus.hasFocus && _nameC.text != widget.timer.name) {
      _nameC.text = widget.timer.name;
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.timer;
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: t.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameC,
                  focusNode: _nameFocus,
                  onChanged: (v) => widget.onSave(t.copyWith(
                      name: v, updatedAt: DateTime.now())),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Timer name',
                  ),
                ),
              ),
              if (widget.pinned != null && widget.onTogglePin != null)
                Tooltip(
                  message:
                      widget.pinned! ? 'Unpin from top' : 'Keep on top',
                  child: InkWell(
                    onTap: widget.onTogglePin,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        widget.pinned!
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 19,
                        color: widget.pinned!
                            ? AppPalette.accent
                            : AppPalette.textSecondary,
                      ),
                    ),
                  ),
                ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 19, color: AppPalette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(child: TimerDial(timer: t, size: 210)),
          const SizedBox(height: 22),
          TimerControls(timer: t, onChanged: widget.onSave),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Shown in a pop-out (window or fallback page) when its timer has been
/// deleted elsewhere.
class TimerDeletedView extends StatelessWidget {
  const TimerDeletedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_outlined,
              size: 32, color: AppPalette.textFaint),
          const SizedBox(height: 10),
          const Text('This timer was deleted.',
              style: TextStyle(color: AppPalette.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
