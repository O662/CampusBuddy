import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../state/app_state.dart';

class TimerPage extends ConsumerStatefulWidget {
  const TimerPage({super.key});

  @override
  ConsumerState<TimerPage> createState() => _TimerPageState();
}

enum _Mode { focus, breakTime }

class _TimerPageState extends ConsumerState<TimerPage> {
  Timer? _ticker;
  _Mode _mode = _Mode.focus;
  late int _remaining; // seconds
  bool _running = false;
  int _completedFocus = 0;

  @override
  void initState() {
    super.initState();
    _remaining = _durationFor(_mode);
  }

  int _durationFor(_Mode m) {
    final p = ref.read(profileProvider);
    return (m == _Mode.focus ? p.focusLengthMinutes : p.breakLengthMinutes) *
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
        _ticker?.cancel();
        setState(() {
          _running = false;
          if (_mode == _Mode.focus) _completedFocus++;
          _mode = _mode == _Mode.focus ? _Mode.breakTime : _Mode.focus;
          _remaining = _durationFor(_mode);
        });
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remaining = _durationFor(_mode);
    });
  }

  void _switchMode(_Mode m) {
    _ticker?.cancel();
    setState(() {
      _mode = m;
      _running = false;
      _remaining = _durationFor(m);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _durationFor(_mode);
    final progress = 1 - (_remaining / total);
    final mm = (_remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (_remaining % 60).toString().padLeft(2, '0');
    final accent =
        _mode == _Mode.focus ? AppPalette.periwinkle : AppPalette.mint;

    return PageBody(
      title: 'Timer',
      subtitle: 'Pomodoro-style focus sessions · $_completedFocus completed',
      scrollable: false,
      child: Expanded(
        child: Center(
          child: GlassContainer(
            width: 420,
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _modeChip('Focus', _Mode.focus, accent),
                    const SizedBox(width: 10),
                    _modeChip('Break', _Mode.breakTime, accent),
                  ],
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 10,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          valueColor:
                              AlwaysStoppedAnimation(accent),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$mm:$ss',
                              style: const TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              _mode == _Mode.focus
                                  ? 'Stay focused'
                                  : 'Relax a little',
                              style: const TextStyle(
                                  color: AppPalette.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
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
                    const SizedBox(width: 12),
                    SoftButton(
                      label: 'Reset',
                      icon: Icons.refresh_rounded,
                      onTap: _reset,
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

  Widget _modeChip(String label, _Mode m, Color accent) {
    final selected = _mode == m;
    return GestureDetector(
      onTap: () => _switchMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF15132B)
                    : AppPalette.textSecondary)),
      ),
    );
  }
}
