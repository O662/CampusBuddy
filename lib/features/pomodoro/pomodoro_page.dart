import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../state/app_state.dart';

enum _Phase { work, shortBreak, longBreak }

extension _PhaseX on _Phase {
  String get label => switch (this) {
        _Phase.work => 'Focus',
        _Phase.shortBreak => 'Short break',
        _Phase.longBreak => 'Long break',
      };
  Color get color => switch (this) {
        _Phase.work => AppPalette.periwinkle,
        _Phase.shortBreak => AppPalette.mint,
        _Phase.longBreak => AppPalette.lavender,
      };
}

/// A full Pomodoro cycle: focus → short break, with a long break every
/// [_roundsBeforeLong] focus sessions. Durations come from Profile.
class PomodoroPage extends ConsumerStatefulWidget {
  const PomodoroPage({super.key});

  @override
  ConsumerState<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends ConsumerState<PomodoroPage> {
  static const _roundsBeforeLong = 4;
  static const _longBreakMinutes = 15;

  final _intentC = TextEditingController();
  Timer? _ticker;
  _Phase _phase = _Phase.work;
  late int _remaining = _durationFor(_phase);
  bool _running = false;
  int _completed = 0; // finished focus sessions

  int _durationFor(_Phase p) {
    final profile = ref.read(profileProvider);
    return switch (p) {
          _Phase.work => profile.focusLengthMinutes,
          _Phase.shortBreak => profile.breakLengthMinutes,
          _Phase.longBreak => _longBreakMinutes,
        } *
        60;
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

  void _advance() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      if (_phase == _Phase.work) {
        _completed++;
        _phase = _completed % _roundsBeforeLong == 0
            ? _Phase.longBreak
            : _Phase.shortBreak;
      } else {
        _phase = _Phase.work;
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

  void _skip() => _advance();

  @override
  void dispose() {
    _ticker?.cancel();
    _intentC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _durationFor(_phase);
    final progress = total == 0 ? 0.0 : 1 - (_remaining / total);
    final mm = (_remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (_remaining % 60).toString().padLeft(2, '0');
    final accent = _phase.color;
    final untilLong = _roundsBeforeLong - (_completed % _roundsBeforeLong);

    return PageBody(
      title: 'Pomodoro',
      subtitle:
          '$_completed focus sessions done · long break in $untilLong',
      scrollable: false,
      child: Expanded(
        child: Center(
          child: GlassContainer(
            width: 460,
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final p in _Phase.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _phaseChip(p, accent),
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
                          Text(_phase.label,
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
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
                const SizedBox(height: 22),
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
                    const SizedBox(width: 10),
                    SoftButton(
                      label: 'Skip',
                      icon: Icons.skip_next_rounded,
                      onTap: _skip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phaseChip(_Phase p, Color accent) {
    final selected = _phase == p;
    return GestureDetector(
      onTap: () {
        _ticker?.cancel();
        setState(() {
          _phase = p;
          _running = false;
          _remaining = _durationFor(p);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        child: Text(p.label,
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
