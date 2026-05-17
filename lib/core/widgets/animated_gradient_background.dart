import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A slow, calming animated gradient. It continuously drifts the gradient
/// angle while cross-fading between the color frames in
/// [AppPalette.backgroundFrames], and floats a couple of soft blurred
/// "aurora" blobs for extra depth. Cheap enough to run on every platform.
class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One very slow loop — the whole point is "subtle".
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value; // 0..1
        return DecoratedBox(
          decoration: BoxDecoration(gradient: _gradient(t)),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _AuroraPainter(t))),
              if (child != null) Positioned.fill(child: child),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }

  LinearGradient _gradient(double t) {
    final frames = AppPalette.backgroundFrames;
    final scaled = t * frames.length;
    final i = scaled.floor() % frames.length;
    final next = (i + 1) % frames.length;
    final localT = scaled - scaled.floorToDouble();

    final a = frames[i];
    final b = frames[next];
    final colors = <Color>[
      for (var c = 0; c < a.length; c++) Color.lerp(a[c], b[c], localT)!,
    ];

    // Drift the gradient direction around a gentle circular path.
    final angle = t * 2 * math.pi;
    final begin = Alignment(math.cos(angle) * 0.9, math.sin(angle) * 0.9);
    return LinearGradient(
      begin: begin,
      end: -begin,
      colors: colors,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * 2 * math.pi;

    void blob(Color color, Offset center, double radius) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
      canvas.drawCircle(center, radius, paint);
    }

    blob(
      AppPalette.lavender,
      Offset(
        size.width * (0.25 + 0.12 * math.cos(angle)),
        size.height * (0.30 + 0.10 * math.sin(angle)),
      ),
      size.shortestSide * 0.55,
    );
    blob(
      AppPalette.mint,
      Offset(
        size.width * (0.78 + 0.10 * math.sin(angle * 0.8)),
        size.height * (0.72 + 0.12 * math.cos(angle * 0.8)),
      ),
      size.shortestSide * 0.50,
    );
    blob(
      AppPalette.periwinkle,
      Offset(
        size.width * (0.60 + 0.10 * math.cos(angle * 1.2 + 1.5)),
        size.height * (0.20 + 0.08 * math.sin(angle * 1.2 + 1.5)),
      ),
      size.shortestSide * 0.42,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.t != t;
}
