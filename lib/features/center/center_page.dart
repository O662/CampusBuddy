import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/animated_gradient_background.dart';

/// A full-screen, immersive breathing meditation. Selecting "Center" lands
/// straight here (outside the app shell — no rail or top bar) and the guided
/// cycle begins on its own. Tap anywhere once to pause/resume, double-tap to
/// end, or tap the gentle "Feeling better?" button to finish.
///
/// One calming 16-second loop: in (4s) · hold (4s) · out (6s) · rest (2s).
class CenterPage extends StatefulWidget {
  const CenterPage({super.key});

  @override
  State<CenterPage> createState() => _CenterPageState();
}

/// A breathing phase: its spoken cue and how the orb should be sized.
class _Phase {
  const _Phase(this.label, this.seconds, this.fromScale, this.toScale);
  final String label;
  final int seconds;
  final double fromScale;
  final double toScale;
}

const _phases = <_Phase>[
  _Phase('Breathe in', 4, 0.55, 1.0),
  _Phase('Hold', 4, 1.0, 1.0),
  _Phase('Breathe out', 6, 1.0, 0.55),
  _Phase('Rest', 2, 0.55, 0.55),
];

final int _cycleSeconds =
    _phases.fold(0, (sum, p) => sum + p.seconds); // 16

class _CenterPageState extends State<CenterPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _cycles = 0;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: _cycleSeconds),
    )
      ..addListener(() {
        // Detect the loop wrapping back to the start to count a full cycle.
        if (_controller.value < _lastValue - 0.5) {
          _cycles++;
          // Reveal the finish button once the first whole breath completes.
          if (_cycles == 1) setState(() {});
        }
        _lastValue = _controller.value;
      })
      ..repeat(); // begins immediately
  }

  bool get _running => _controller.isAnimating;

  void _toggleRunning() {
    setState(() {
      if (_running) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    });
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  /// Current phase, the eased orb scale, and seconds left in the phase, for
  /// a given controller value (0..1).
  ({_Phase phase, double scale, int secondsLeft}) _frame(double v) {
    final elapsed = v * _cycleSeconds;
    var start = 0.0;
    for (final p in _phases) {
      final end = start + p.seconds;
      if (elapsed < end || p == _phases.last) {
        final local = ((elapsed - start) / p.seconds).clamp(0.0, 1.0);
        final eased = Curves.easeInOut.transform(local);
        return (
          phase: p,
          scale: p.fromScale + (p.toScale - p.fromScale) * eased,
          secondsLeft: (p.seconds - (elapsed - start)).ceil().clamp(1, p.seconds),
        );
      }
      start = end;
    }
    throw StateError('unreachable');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          // Tapping anywhere once pauses/resumes; a double-tap ends.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleRunning,
            onDoubleTap: _close,
            child: Stack(
              children: [
                Center(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final f = _frame(_controller.value);
                      final paused = !_running;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Center',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Follow the orb. Let everything else wait.',
                            style: TextStyle(
                                color: AppPalette.textSecondary,
                                fontSize: 13),
                          ),
                          const SizedBox(height: 48),
                          SizedBox(
                            width: 320,
                            height: 320,
                            child: Center(
                              child: _Orb(
                                scale: f.scale,
                                label: paused ? 'Paused' : f.phase.label,
                                secondsLeft:
                                    paused ? null : f.secondsLeft,
                              ),
                            ),
                          ),
                          const SizedBox(height: 48),
                          Text(
                            '$_cycles ${_cycles == 1 ? 'breath' : 'breaths'} · '
                            'tap to ${paused ? 'resume' : 'pause'} · '
                            'double-tap to end',
                            style: const TextStyle(
                                color: AppPalette.textFaint,
                                fontSize: 12.5),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    // Hidden until one full breath has completed, then it
                    // gently rises and fades into view.
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOut,
                      offset: _cycles >= 1
                          ? Offset.zero
                          : const Offset(0, 0.5),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 700),
                        opacity: _cycles >= 1 ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: _cycles < 1,
                          child: _FinishButton(onTap: _close),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The breathing orb: a soft glowing circle that scales with the breath.
class _Orb extends StatelessWidget {
  const _Orb({
    required this.scale,
    required this.label,
    required this.secondsLeft,
  });

  final double scale;
  final String label;
  final int? secondsLeft;

  @override
  Widget build(BuildContext context) {
    final size = 320.0 * scale;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          AppPalette.periwinkle.withValues(alpha: 0.60),
          AppPalette.mint.withValues(alpha: 0.16),
        ]),
        boxShadow: [
          BoxShadow(
            color: AppPalette.periwinkle.withValues(alpha: 0.45),
            blurRadius: 70,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (secondsLeft != null) ...[
              const SizedBox(height: 4),
              Text(
                '$secondsLeft',
                style: const TextStyle(
                    fontSize: 15,
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The large, calm "Feeling better?" button that ends the session.
class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF15132B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: AppPalette.accent,
            boxShadow: [
              BoxShadow(
                color: AppPalette.accent.withValues(alpha: 0.4),
                blurRadius: 34,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 24, color: ink),
              SizedBox(width: 12),
              Text(
                'Feeling better?',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}