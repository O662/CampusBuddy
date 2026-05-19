import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../state/app_state.dart';

/// The two timer styles, merged onto one page and switched with the toggle
/// at the top. [simple] is a plain Focus/Break countdown; [pomodoro] adds
/// the work → short → long-break cycle, an optional intent, and Skip.
enum _Kind { simple, pomodoro }

/// Phases shared by both modes. Simple mode only ever uses [focus] and
/// [shortBreak] (shown as "Break").
enum _Phase { focus, shortBreak, longBreak }

extension _PhaseX on _Phase {
  Color get color => switch (this) {
        _Phase.focus => AppPalette.periwinkle,
        _Phase.shortBreak => AppPalette.mint,
        _Phase.longBreak => AppPalette.lavender,
      };
}

class TimerPage extends ConsumerStatefulWidget {
  const TimerPage({super.key});

  @override
  ConsumerState<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends ConsumerState<TimerPage> {
  static const _roundsBeforeLong = 4;
  static const _longBreakMinutes = 15;

  final _intentC = TextEditingController();
  Timer? _ticker;

  _Kind _kind = _Kind.pomodoro;
  _Phase _phase = _Phase.focus;
  late int _remaining = _durationFor(_phase);
  bool _running = false;
  int _completed = 0; // finished focus sessions in the current mode

  int _durationFor(_Phase p) {
    final profile = ref.read(profileProvider);
    return switch (p) {
          _Phase.focus => profile.focusLengthMinutes,
          _Phase.shortBreak => profile.breakLengthMinutes,
          _Phase.longBreak => _longBreakMinutes,
        } *
        60;
  }

  /// Phases available to the current mode (simple has no long break).
  List<_Phase> get _phases => _kind == _Kind.simple
      ? const [_Phase.focus, _Phase.shortBreak]
      : _Phase.values;

  String _phaseLabel(_Phase p) => switch (p) {
        _Phase.focus => 'Focus',
        _Phase.shortBreak => _kind == _Kind.simple ? 'Break' : 'Short break',
        _Phase.longBreak => 'Long break',
      };

  void _switchKind(_Kind k) {
    if (k == _kind) return;
    _ticker?.cancel();
    setState(() {
      _kind = k;
      _phase = _Phase.focus;
      _running = false;
      _completed = 0;
      _remaining = _durationFor(_phase);
    });
  }

  void _toggle() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _advance();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  /// Move to the next phase. Both modes return to focus after a break; the
  /// difference is which break follows a focus session.
  void _advance() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      if (_phase == _Phase.focus) {
        _completed++;
        if (_kind == _Kind.pomodoro &&
            _completed % _roundsBeforeLong == 0) {
          _phase = _Phase.longBreak;
        } else {
          _phase = _Phase.shortBreak;
        }
      } else {
        _phase = _Phase.focus;
      }
      _remaining = _durationFor(_phase);
    });
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remaining = _durationFor(_phase);
    });
  }

  void _selectPhase(_Phase p) {
    _ticker?.cancel();
    setState(() {
      _phase = p;
      _running = false;
      _remaining = _durationFor(p);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _intentC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPomodoro = _kind == _Kind.pomodoro;
    final total = _durationFor(_phase);
    final progress = total == 0 ? 0.0 : 1 - (_remaining / total);
    final mm = (_remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (_remaining % 60).toString().padLeft(2, '0');
    final accent = _phase.color;
    final untilLong = _roundsBeforeLong - (_completed % _roundsBeforeLong);

    return PageBody(
      title: 'Timer',
      subtitle: isPomodoro
          ? '$_completed focus sessions done · long break in $untilLong'
          : 'Simple focus timer · $_completed sessions completed',
      scrollable: false,
      child: Expanded(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: GlassContainer(
                  width: 460,
                  padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _kindToggle(),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final p in _phases)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _phaseChip(p),
                      ),
                  ],
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: 230,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 230,
                        height: 230,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 11,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$mm:$ss',
                              style: const TextStyle(
                                  fontSize: 54,
                                  fontWeight: FontWeight.w800)),
                          Text(_phaseLabel(_phase),
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isPomodoro) ...[
                  const SizedBox(height: 26),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _intentC,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                          hintText: 'Focusing on… (optional)'),
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SoftButton(
                      label: _running ? 'Pause' : 'Start',
                      icon: _running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      filled: true,
                      onTap: _toggle,
                    ),
                    const SizedBox(width: 10),
                    SoftButton(
                      label: 'Reset',
                      icon: Icons.refresh_rounded,
                      onTap: _reset,
                    ),
                    if (isPomodoro) ...[
                      const SizedBox(width: 10),
                      SoftButton(
                        label: 'Skip',
                        icon: Icons.skip_next_rounded,
                        onTap: _advance,
                      ),
                    ],
                  ],
                ),
              ],
            ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindToggle() {
    Widget seg(String label, _Kind k) {
      final selected = _kind == k;
      return GestureDetector(
        onTap: () => _switchKind(k),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF15132B)
                      : AppPalette.textSecondary)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Simple', _Kind.simple),
          seg('Pomodoro', _Kind.pomodoro),
        ],
      ),
    );
  }

  Widget _phaseChip(_Phase p) {
    final selected = _phase == p;
    return GestureDetector(
      onTap: () => _selectPhase(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.color : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        child: Text(_phaseLabel(p),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF15132B)
                    : AppPalette.textSecondary)),
      ),
    );
  }
}
