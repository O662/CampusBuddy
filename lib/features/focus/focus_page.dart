import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;
  final _intentC = TextEditingController();
  Timer? _ticker;
  int _elapsed = 0;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
  }

  void _toggle() {
    if (_active) {
      _ticker?.cancel();
      _breath.stop();
      setState(() => _active = false);
      return;
    }
    setState(() => _active = true);
    _breath.repeat(reverse: true);
    _ticker = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _elapsed++));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _breath.dispose();
    _intentC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final ss = (_elapsed % 60).toString().padLeft(2, '0');

    return PageBody(
      title: 'Focus',
      subtitle: 'A quiet space. Breathe with the circle and sink in.',
      scrollable: false,
      child: Expanded(
        child: Center(
          child: GlassContainer(
            width: 480,
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_active) ...[
                  TextField(
                    controller: _intentC,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                        hintText: "What are you focusing on?"),
                  ),
                  const SizedBox(height: 32),
                ] else if (_intentC.text.trim().isNotEmpty) ...[
                  Text(_intentC.text.trim(),
                      style: const TextStyle(
                          fontSize: 16,
                          color: AppPalette.textSecondary)),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  height: 240,
                  child: AnimatedBuilder(
                    animation: _breath,
                    builder: (context, _) {
                      final t = _active
                          ? Curves.easeInOut.transform(_breath.value)
                          : 0.5;
                      final size = 130 + t * 90;
                      return Center(
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              AppPalette.periwinkle
                                  .withValues(alpha: 0.55),
                              AppPalette.mint.withValues(alpha: 0.15),
                            ]),
                            boxShadow: [
                              BoxShadow(
                                color: AppPalette.periwinkle
                                    .withValues(alpha: 0.4),
                                blurRadius: 50,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              !_active
                                  ? 'Ready'
                                  : (t > 0.5 ? 'Breathe in' : 'Breathe out'),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text('$mm:$ss',
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                SoftButton(
                  label: _active ? 'End session' : 'Begin',
                  icon: _active
                      ? Icons.stop_rounded
                      : Icons.self_improvement_rounded,
                  filled: true,
                  onTap: _toggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
