import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// The Pomodoro surface on the Timer page: a board of user-created
/// Pomodoro presets. Tapping a card jumps to a full-screen, immersive
/// session (route `/pomodoro/:id`) that lives **outside** the app shell
/// — no rail, no top bar — with the running Pomodoro centred on screen.
///
/// "New Pomodoro" lives on the parent [TimerPage]'s top-right action so the
/// affordance sits in the same place as "New timer" on the Timers tab.
class PomodoroView extends ConsumerWidget {
  const PomodoroView({super.key});

  /// One-tap recipes. The label doubles as the preset's name when created.
  static const _suggestions = <_Suggestion>[
    _Suggestion('Classic', 25, 5, 15, 4),
    _Suggestion('Long focus', 50, 10, 20, 3),
    _Suggestion('Sprint', 15, 3, 10, 4),
  ];

  Future<void> _create(WidgetRef ref, _Suggestion s) async {
    final all = ref.read(pomodorosProvider);
    final topOrder = all.isEmpty
        ? 0
        : all.map((p) => p.order).reduce((a, b) => a < b ? a : b) - 1;
    final seed = all.length % AppPalette.categorySwatches.length;
    final preset = PomodoroPreset(
      id: newId(),
      name: s.name,
      focusMinutes: s.focus,
      shortBreakMinutes: s.shortBreak,
      longBreakMinutes: s.longBreak,
      roundsBeforeLong: s.rounds,
      colorSeed: seed,
      order: topOrder,
      createdAt: DateTime.now(),
    );
    await ref.read(pomodorosProvider.notifier).upsert(preset);
  }

  void _reorder(
    WidgetRef ref,
    List<PomodoroPreset> ordered,
    PomodoroPreset moving,
    PomodoroPreset target,
  ) {
    if (moving.id == target.id) return;
    final list = [...ordered];
    final from = list.indexWhere((p) => p.id == moving.id);
    final targetIndex = list.indexWhere((p) => p.id == target.id);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;
    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexWhere((p) => p.id == target.id) + 1
        : list.indexWhere((p) => p.id == target.id);
    list.insert(insertAt, moving);
    ref.read(pomodorosProvider.notifier).reorder(list);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(pomodorosProvider).toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.createdAt.compareTo(b.createdAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SuggestedPomodoroRow(
          suggestions: _suggestions,
          onTap: (s) => _create(ref, s),
        ),
        const SizedBox(height: 22),
        if (presets.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 28),
            child: EmptyHint(
              'No Pomodoros yet. Tap a Suggested preset, or "New Pomodoro".',
              icon: Icons.spa_outlined,
            ),
          )
        else
          CardGrid(
            children: [
              for (final p in presets)
                _ReorderablePomodoro(
                  key: ValueKey(p.id),
                  preset: p,
                  onReorder: (moving) =>
                      _reorder(ref, presets, moving, p),
                ),
            ],
          ),
      ],
    );
  }
}

class _Suggestion {
  const _Suggestion(
      this.name, this.focus, this.shortBreak, this.longBreak, this.rounds);
  final String name;
  final int focus;
  final int shortBreak;
  final int longBreak;
  final int rounds;

  String get summary => '$focus / $shortBreak / $longBreak · $rounds rounds';
}

class _SuggestedPomodoroRow extends StatelessWidget {
  const _SuggestedPomodoroRow({
    required this.suggestions,
    required this.onTap,
  });

  final List<_Suggestion> suggestions;
  final ValueChanged<_Suggestion> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.auto_awesome_outlined,
                size: 14, color: AppPalette.textSecondary),
            SizedBox(width: 6),
            Text('Suggested',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppPalette.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              _SuggestionPill(suggestion: s, onTap: () => onTap(s)),
          ],
        ),
      ],
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  const _SuggestionPill({required this.suggestion, required this.onTap});

  final _Suggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppPalette.glassStroke),
            color: Colors.white.withValues(alpha: 0.04),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded,
                  size: 14, color: AppPalette.lavender),
              const SizedBox(width: 5),
              Text(
                '${suggestion.name} · ${suggestion.summary}',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.lavender),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drag-source / drop-target wrapper around a [_PomodoroCard] — same gesture
/// plumbing as the Notes / Timers boards.
class _ReorderablePomodoro extends StatelessWidget {
  const _ReorderablePomodoro({
    super.key,
    required this.preset,
    required this.onReorder,
  });

  final PomodoroPreset preset;
  final ValueChanged<PomodoroPreset> onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<PomodoroPreset>(
      onWillAcceptWithDetails: (d) => d.data.id != preset.id,
      onAcceptWithDetails: (d) => onReorder(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<PomodoroPreset>(
          data: preset,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: SizedBox(
                width: 300,
                child: _PomodoroDragPreview(preset: preset),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _PomodoroDragPreview(preset: preset),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: _PomodoroCard(preset: preset),
          ),
        );
      },
    );
  }
}

class _PomodoroDragPreview extends StatelessWidget {
  const _PomodoroDragPreview({required this.preset});

  final PomodoroPreset preset;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: preset.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              preset.name.trim().isEmpty ? 'Pomodoro' : preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: AppPalette.textFaint),
        ],
      ),
    );
  }
}

class _PomodoroCard extends ConsumerWidget {
  const _PomodoroCard({required this.preset});

  final PomodoroPreset preset;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showPomodoroPresetDialog(
      context,
      name: preset.name,
      focusMinutes: preset.focusMinutes,
      shortBreakMinutes: preset.shortBreakMinutes,
      longBreakMinutes: preset.longBreakMinutes,
      roundsBeforeLong: preset.roundsBeforeLong,
      colorSeed: preset.colorSeed,
      isNew: false,
    );
    if (result == null) return;
    await ref.read(pomodorosProvider.notifier).upsert(preset.copyWith(
          name: result.name,
          focusMinutes: result.focusMinutes,
          shortBreakMinutes: result.shortBreakMinutes,
          longBreakMinutes: result.longBreakMinutes,
          roundsBeforeLong: result.roundsBeforeLong,
          colorSeed: result.colorSeed,
        ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete Pomodoro?',
      message: 'This preset will be permanently removed.',
    );
    if (ok) await ref.read(pomodorosProvider.notifier).remove(preset.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title =
        preset.name.trim().isEmpty ? 'Pomodoro' : preset.name.trim();
    return GlassContainer(
      // The whole card is the affordance — tap anywhere outside the menu
      // to drop into the immersive session screen.
      onTap: () => context.go('/pomodoro/${preset.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: preset.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Pomodoro options',
                onSelected: (v) {
                  if (v == 'edit') {
                    _edit(context, ref);
                  } else if (v == 'delete') {
                    _delete(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune_rounded, size: 20),
                      title: Text('Edit'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Divider(
              color: preset.color.withValues(alpha: 0.4), height: 18),
          Row(
            children: [
              Icon(Icons.spa_outlined,
                  size: 16, color: preset.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.summary,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: preset.color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: preset.color.withValues(alpha: 0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 16, color: preset.color),
                    const SizedBox(width: 4),
                    Text('Start session',
                        style: TextStyle(
                            color: preset.color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
