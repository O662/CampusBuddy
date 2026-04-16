import 'package:flutter/material.dart';

void showFocusOverlay(BuildContext context) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _FocusOverlayWidget(onDismiss: () => entry.remove()),
  );
  // rootOverlay: true ensures we sit above every navigator and scaffold
  Overlay.of(context, rootOverlay: true).insert(entry);
}

class _FocusOverlayWidget extends StatefulWidget {
  final VoidCallback onDismiss;
  const _FocusOverlayWidget({required this.onDismiss});

  @override
  State<_FocusOverlayWidget> createState() => _FocusOverlayWidgetState();
}

class _FocusOverlayWidgetState extends State<_FocusOverlayWidget>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _breathCtrl;
  late final AnimationController _textCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  bool _breathingIn = true;

  static const _inDuration = Duration(seconds: 4);
  static const _outDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _breathCtrl = AnimationController(vsync: this, duration: _inDuration);
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500), value: 1.0);

    _scaleAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
    );

    _breathCtrl.addStatusListener(_onBreathStatus);
    _fadeCtrl.forward();
    _breathCtrl.forward();
  }

  void _onBreathStatus(AnimationStatus status) async {
    if (status == AnimationStatus.completed) {
      await _textCtrl.reverse();
      if (!mounted) return;
      setState(() => _breathingIn = false);
      await _textCtrl.forward();
      if (!mounted) return;
      _breathCtrl.duration = _outDuration;
      _breathCtrl.reverse();
    } else if (status == AnimationStatus.dismissed) {
      await _textCtrl.reverse();
      if (!mounted) return;
      setState(() => _breathingIn = true);
      await _textCtrl.forward();
      if (!mounted) return;
      _breathCtrl.duration = _inDuration;
      _breathCtrl.forward();
    }
  }

  Future<void> _dismiss() async {
    await _fadeCtrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _breathCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: GestureDetector(
        onTap: _dismiss,
        behavior: HitTestBehavior.opaque,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A1628),
                  Color(0xFF0D2137),
                  Color(0xFF0A1628),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Breathing rings
                  AnimatedBuilder(
                    animation: Listenable.merge([_scaleAnim, _glowAnim]),
                    builder: (_, child) {
                      final s = _scaleAnim.value;
                      final g = _glowAnim.value;
                      return SizedBox(
                        width: 280,
                        height: 280,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow ring
                            Transform.scale(
                              scale: s,
                              child: Container(
                                width: 280,
                                height: 280,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.lightBlueAccent
                                        .withValues(alpha: 0.08 * g),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            // Middle ring
                            Transform.scale(
                              scale: s,
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.lightBlueAccent
                                      .withValues(alpha: 0.04 + 0.06 * g),
                                  border: Border.all(
                                    color: Colors.lightBlueAccent
                                        .withValues(alpha: 0.15 + 0.15 * g),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.lightBlueAccent
                                          .withValues(alpha: 0.12 * g),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Inner core
                            Transform.scale(
                              scale: s,
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.lightBlueAccent
                                      .withValues(alpha: 0.08 + 0.10 * g),
                                  border: Border.all(
                                    color: Colors.lightBlueAccent
                                        .withValues(alpha: 0.25 + 0.20 * g),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 48),
                  // Breathing text
                  FadeTransition(
                    opacity: _textCtrl,
                    child: Text(
                      _breathingIn ? 'Breathe in...' : 'Breathe out...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _breathingIn
                        ? 'Inhale slowly through your nose'
                        : 'Exhale gently through your mouth',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    'Tap anywhere to close',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
