import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/timer_format.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/timer_view.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'pomodoro_view.dart';
import 'timer_window_bridge.dart';

/// Top-right toggle on the Timer page: which surface is showing.
enum _Mode { timers, pomodoro }

/// One-tap suggested timer durations. Tapping creates a brand-new timer with
/// the given length at the top of the board — no dialog, no friction.
const List<int> _kSuggestedSeconds = [
  60,
  3 * 60,
  5 * 60,
  10 * 60,
  15 * 60,
  25 * 60,
  30 * 60,
  45 * 60,
  60 * 60,
];

/// The Timer page. The default surface is **My Timers** (user-created
/// countdown timers, drag-to-reorder, popped out into their own
/// always-on-top windows like Notes). The top-right toggle flips over to the
/// classic Focus / Pomodoro experience (unchanged), which still reads
/// focus/break lengths from Profile.
class TimerPage extends ConsumerStatefulWidget {
  const TimerPage({super.key});

  @override
  ConsumerState<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends ConsumerState<TimerPage> {
  _Mode _mode = _Mode.timers;

  Future<void> _newTimer() async {
    final result = await showTimerDurationDialog(context);
    if (result == null) return;
    final all = ref.read(timersProvider);
    final topOrder = all.isEmpty
        ? 0
        : all.map((t) => t.order).reduce((a, b) => a < b ? a : b) - 1;
    final timer = TimerItem(
      id: newId(),
      name: result.name,
      durationSeconds: result.seconds,
      colorSeed: result.colorSeed,
      order: topOrder,
      updatedAt: DateTime.now(),
    );
    await ref.read(timersProvider.notifier).upsert(timer);
    await ref.read(timerRecentsProvider.notifier).push(result.seconds);
  }

  Future<void> _newPomodoro() async {
    final result = await showPomodoroPresetDialog(context);
    if (result == null) return;
    final all = ref.read(pomodorosProvider);
    final topOrder = all.isEmpty
        ? 0
        : all.map((p) => p.order).reduce((a, b) => a < b ? a : b) - 1;
    final seed = result.colorSeed != 0
        ? result.colorSeed
        : all.length % AppPalette.categorySwatches.length;
    final preset = PomodoroPreset(
      id: newId(),
      name: result.name,
      focusMinutes: result.focusMinutes,
      shortBreakMinutes: result.shortBreakMinutes,
      longBreakMinutes: result.longBreakMinutes,
      roundsBeforeLong: result.roundsBeforeLong,
      colorSeed: seed,
      order: topOrder,
      createdAt: DateTime.now(),
    );
    await ref.read(pomodorosProvider.notifier).upsert(preset);
  }

  Future<void> _quickCreate(int seconds) async {
    final all = ref.read(timersProvider);
    final topOrder = all.isEmpty
        ? 0
        : all.map((t) => t.order).reduce((a, b) => a < b ? a : b) - 1;
    // Rotate the accent colour by the number of existing timers so the
    // board doesn't end up monochrome from repeated one-taps.
    final seed = all.length % AppPalette.categorySwatches.length;
    final timer = TimerItem(
      id: newId(),
      name: fmtDurationLabel(seconds),
      durationSeconds: seconds,
      colorSeed: seed,
      order: topOrder,
      updatedAt: DateTime.now(),
    );
    await ref.read(timersProvider.notifier).upsert(timer);
    await ref.read(timerRecentsProvider.notifier).push(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final isPomodoro = _mode == _Mode.pomodoro;

    return PageBody(
      title: 'Timer',
      subtitle: isPomodoro
          ? 'Build your own Pomodoros — tap one to drop into a focused, '
              'full-screen session.'
          : 'Create as many countdowns as you like — pop any of them out '
              'into their own always-on-top window.',
      actions: [
        _ModeToggle(
            mode: _mode, onChanged: (m) => setState(() => _mode = m)),
        const SizedBox(width: 10),
        SoftButton(
          label: isPomodoro ? 'New Pomodoro' : 'New timer',
          icon: Icons.add_rounded,
          filled: true,
          onTap: isPomodoro ? _newPomodoro : _newTimer,
        ),
      ],
      child: isPomodoro
          ? const PomodoroView()
          : _TimersBoard(onQuickCreate: _quickCreate),
    );
  }
}

/// Segmented [Timers | Pomodoro] selector that lives in the page's top-right.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, _Mode m, IconData icon) {
      final selected = mode == m;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? const Color(0xFF15132B)
                      : AppPalette.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFF15132B)
                          : AppPalette.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Timers', _Mode.timers, Icons.timer_outlined),
          seg('Pomodoro', _Mode.pomodoro, Icons.spa_outlined),
        ],
      ),
    );
  }
}

/// The "My Timers" surface: suggested presets, recent durations, then a
/// reorderable masonry of user timers.
class _TimersBoard extends ConsumerWidget {
  const _TimersBoard({required this.onQuickCreate});

  final ValueChanged<int> onQuickCreate;

  void _reorder(
    WidgetRef ref,
    List<TimerItem> ordered,
    TimerItem moving,
    TimerItem target,
  ) {
    if (moving.id == target.id) return;
    final list = [...ordered];
    final from = list.indexWhere((t) => t.id == moving.id);
    final targetIndex = list.indexWhere((t) => t.id == target.id);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;
    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexWhere((t) => t.id == target.id) + 1
        : list.indexWhere((t) => t.id == target.id);
    list.insert(insertAt, moving);
    ref.read(timersProvider.notifier).reorder(list);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the engine forces the board to rebuild every second while any
    // timer is counting, so each card's dial advances. When nothing is
    // running the engine is idle and this is a no-op.
    ref.watch(timerEngineProvider);

    final timers = ref.watch(timersProvider).toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final recents = ref.watch(timerRecentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetRow(
          title: 'Suggested',
          icon: Icons.auto_awesome_outlined,
          seconds: _kSuggestedSeconds,
          onTap: onQuickCreate,
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PresetRow(
            title: 'Recent',
            icon: Icons.history_rounded,
            seconds: recents,
            onTap: onQuickCreate,
          ),
        ],
        const SizedBox(height: 22),
        if (timers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 28),
            child: EmptyHint(
              'No timers yet. Tap a Suggested preset, or “New timer”.',
              icon: Icons.timer_outlined,
            ),
          )
        else
          CardGrid(
            children: [
              for (final t in timers)
                _ReorderableTimer(
                  key: ValueKey(t.id),
                  timer: t,
                  onReorder: (moving) => _reorder(ref, timers, moving, t),
                ),
            ],
          ),
      ],
    );
  }
}

/// Horizontal scroll of duration pills — used for both "Suggested" and the
/// "Recent" history. Tapping a pill creates a new timer of that length.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.title,
    required this.icon,
    required this.seconds,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final List<int> seconds;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppPalette.textSecondary),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
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
            for (final s in seconds)
              _DurationPill(label: fmtDurationLabel(s), onTap: () => onTap(s)),
          ],
        ),
      ],
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.label, required this.onTap});

  final String label;
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
              Text(label,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.lavender)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drag-source / drop-target wrapper around a [_TimerCard], mirroring the
/// reorder plumbing used on the Notes board so feels identical.
class _ReorderableTimer extends StatelessWidget {
  const _ReorderableTimer({
    super.key,
    required this.timer,
    required this.onReorder,
  });

  final TimerItem timer;
  final ValueChanged<TimerItem> onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TimerItem>(
      onWillAcceptWithDetails: (d) => d.data.id != timer.id,
      onAcceptWithDetails: (d) => onReorder(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<TimerItem>(
          data: timer,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: SizedBox(
                width: 300,
                child: _TimerDragPreview(timer: timer),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _TimerDragPreview(timer: timer),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: _TimerCard(timer: timer),
          ),
        );
      },
    );
  }
}

class _TimerDragPreview extends StatelessWidget {
  const _TimerDragPreview({required this.timer});

  final TimerItem timer;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: timer.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              timer.name.trim().isEmpty
                  ? fmtDurationLabel(timer.durationSeconds)
                  : timer.name,
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

class _TimerCard extends ConsumerStatefulWidget {
  const _TimerCard({required this.timer});

  final TimerItem timer;

  @override
  ConsumerState<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends ConsumerState<_TimerCard> {
  late final TextEditingController _nameC =
      TextEditingController(text: widget.timer.name);
  final _nameFocus = FocusNode();

  @override
  void didUpdateWidget(_TimerCard old) {
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

  TimerNotifier get _notifier => ref.read(timersProvider.notifier);

  void _save(TimerItem next) => _notifier.upsert(next);

  Future<void> _pickColor() async {
    final picked = await showColorSeedPicker(context, widget.timer.colorSeed,
        title: 'Timer colour');
    if (picked != null) await _notifier.recolor(widget.timer.id, picked);
  }

  Future<void> _editDuration() async {
    final t = widget.timer;
    final result = await showTimerDurationDialog(
      context,
      name: t.name,
      initialSeconds: t.durationSeconds,
      colorSeed: t.colorSeed,
      isNew: false,
    );
    if (result == null) return;
    // Combine rename + recolor + duration in one upsert; the duration
    // change resets the timer to a fresh full countdown (see
    // [TimerNotifier.setDuration]).
    await _notifier.upsert(t
        .copyWith(
          name: result.name,
          colorSeed: result.colorSeed,
          durationSeconds: result.seconds,
          updatedAt: DateTime.now(),
        )
        .resetToFull());
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete timer?',
      message: 'This timer will be permanently removed.',
    );
    if (ok) await _notifier.remove(widget.timer.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.timer;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickColor,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: t.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameC,
                  focusNode: _nameFocus,
                  onChanged: (v) => _save(
                      t.copyWith(name: v, updatedAt: DateTime.now())),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Timer name',
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Timer options',
                onSelected: (v) {
                  if (v == 'edit') {
                    _editDuration();
                  } else if (v == 'popout') {
                    popOutTimer(context, t.id);
                  } else if (v == 'mute') {
                    _save(t.copyWith(
                        notify: !t.notify, updatedAt: DateTime.now()));
                  } else if (v == 'delete') {
                    _delete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune_rounded, size: 20),
                      title: Text('Edit duration'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'popout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.open_in_new_rounded, size: 20),
                      title: Text('Pop out'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'mute',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        t.notify
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_outlined,
                        size: 20,
                      ),
                      title: Text(t.notify
                          ? 'Mute notifications'
                          : 'Turn on notifications'),
                    ),
                  ),
                  const PopupMenuItem(
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
          const SizedBox(height: 14),
          Center(child: TimerDial(timer: t, size: 200)),
          const SizedBox(height: 18),
          TimerControls(timer: t, onChanged: _save),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
