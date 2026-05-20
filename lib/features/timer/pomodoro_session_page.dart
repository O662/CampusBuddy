import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// The three phases of a running Pomodoro session.
enum _Phase { focus, shortBreak, longBreak }

extension _PhaseX on _Phase {
  Color get color => switch (this) {
        _Phase.focus => AppPalette.periwinkle,
        _Phase.shortBreak => AppPalette.mint,
        _Phase.longBreak => AppPalette.lavender,
      };
  String get label => switch (this) {
        _Phase.focus => 'Focus',
        _Phase.shortBreak => 'Short break',
        _Phase.longBreak => 'Long break',
      };
}

/// Full-screen, immersive Pomodoro session. Lives *outside* the app shell at
/// `/pomodoro/:id` so the rail and top bar are gone and the running timer
/// sits centred on the whole window — the same "step out" treatment used by
/// the Center breathing screen.
///
/// Layout: timer card on the left, goals + checklist box on the right — they
/// stack into a single scrollable column on narrower windows. The goals and
/// checklist persist on the [PomodoroPreset] so reopening "Deep work" next
/// time still shows the same goal and unticked items.
///
/// Session state (current phase, remaining seconds, completed sessions) is
/// transient and lives only in this page: closing it resets the session,
/// matching how the page worked before and keeping it free of any
/// background ticker that would compete with the main Timer engine.
class PomodoroSessionPage extends ConsumerStatefulWidget {
  const PomodoroSessionPage({super.key, required this.presetId});

  final String presetId;

  @override
  ConsumerState<PomodoroSessionPage> createState() =>
      _PomodoroSessionPageState();
}

class _PomodoroSessionPageState
    extends ConsumerState<PomodoroSessionPage> {
  Timer? _ticker;

  _Phase _phase = _Phase.focus;
  int _remaining = 0; // seeded once we know which preset we're running
  bool _running = false;
  int _completed = 0;
  bool _seeded = false;
  String? _lastPresetSig;

  int _durationFor(PomodoroPreset p, _Phase phase) => switch (phase) {
        _Phase.focus => p.focusMinutes,
        _Phase.shortBreak => p.shortBreakMinutes,
        _Phase.longBreak => p.longBreakMinutes,
      } *
      60;

  /// Seed [_remaining] once the preset is known, and re-seed (only when the
  /// session is idle) if the preset is edited while open.
  void _seedFor(PomodoroPreset p) {
    final sig =
        '${p.focusMinutes}/${p.shortBreakMinutes}/${p.longBreakMinutes}';
    if (!_seeded) {
      _seeded = true;
      _lastPresetSig = sig;
      _remaining = _durationFor(p, _phase);
    } else if (sig != _lastPresetSig && !_running) {
      _lastPresetSig = sig;
      _remaining = _durationFor(p, _phase);
    }
  }

  void _toggle(PomodoroPreset p) {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
      // Paused: the drawer entry stops being meaningful.
      unawaited(AppNotifications.instance.cancelPomodoro());
      return;
    }
    setState(() => _running = true);
    // Push on Start, then re-push every minute as the countdown drops so
    // the drawer's "X left" stays live. `silent: true` on the underlying
    // notification keeps the OS quiet on each refresh.
    _pushNotif(p);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _advance(p);
      } else {
        setState(() => _remaining--);
        if (AppNotifications.instance.pomodoroBucketChanged(_remaining)) {
          _pushNotif(p);
        }
      }
    });
  }

  void _advance(PomodoroPreset p) {
    _ticker?.cancel();
    setState(() {
      _running = false;
      if (_phase == _Phase.focus) {
        _completed++;
        _phase = (_completed % p.roundsBeforeLong == 0)
            ? _Phase.longBreak
            : _Phase.shortBreak;
      } else {
        _phase = _Phase.focus;
      }
      _remaining = _durationFor(p, _phase);
    });
    // After advance the session is paused at the start of the new phase
    // (the original behaviour); drawer entry only reappears on next Start.
    unawaited(AppNotifications.instance.cancelPomodoro());
  }

  void _reset(PomodoroPreset p) {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remaining = _durationFor(p, _phase);
    });
    unawaited(AppNotifications.instance.cancelPomodoro());
  }

  void _selectPhase(PomodoroPreset p, _Phase next) {
    _ticker?.cancel();
    setState(() {
      _phase = next;
      _running = false;
      _remaining = _durationFor(p, next);
    });
    unawaited(AppNotifications.instance.cancelPomodoro());
  }

  void _close() {
    unawaited(AppNotifications.instance.cancelPomodoro());
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/timer');
    }
  }

  /// Push the session's current state out to the OS drawer. Cheap: the
  /// service no-ops when init failed or when we're between minute buckets.
  void _pushNotif(PomodoroPreset p) {
    final round = (_completed % p.roundsBeforeLong) + 1;
    unawaited(AppNotifications.instance.showPomodoro(
      name: p.name,
      phaseLabel: _phase.label,
      remainingSeconds: _remaining,
      round: round,
      totalRounds: p.roundsBeforeLong,
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Belt-and-suspenders cleanup (_close already cancels, but back-button
    // / OS-level navigation can skip it).
    unawaited(AppNotifications.instance.cancelPomodoro());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(pomodorosProvider);
    PomodoroPreset? preset;
    for (final p in presets) {
      if (p.id == widget.presetId) {
        preset = p;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: preset == null
              ? _DeletedView(onClose: _close)
              : _SessionBody(
                  preset: preset,
                  onBuildOnce: _seedFor,
                  state: this,
                ),
        ),
      ),
    );
  }
}

/// The actual centred Pomodoro UI. Split out so the session [State] keeps the
/// transient phase data and the timer, while this widget just renders.
class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.preset,
    required this.onBuildOnce,
    required this.state,
  });

  final PomodoroPreset preset;
  final ValueChanged<PomodoroPreset> onBuildOnce;
  final _PomodoroSessionPageState state;

  /// Min window width at which timer and goals sit side-by-side. Below this
  /// the two cards stack into a single scrollable column.
  static const _sideBySideMinWidth = 940.0;

  @override
  Widget build(BuildContext context) {
    // Seeding can't happen in initState (we don't have the preset until the
    // first build), so do it here — guarded inside [_seedFor] to be a no-op
    // after the first run.
    onBuildOnce(preset);

    final timerCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: _TimerCard(preset: preset, state: state),
    );
    // A bounded-height goals card so the "Add an item…" field stays anchored
    // at the bottom; the checklist inside scrolls when items exceed the
    // available space instead of pushing the field off-card (or overflowing).
    final goalsCard = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 380,
        minWidth: 300,
        minHeight: 360,
        maxHeight: 520,
      ),
      child: _GoalsBox(preset: preset),
    );

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= _sideBySideMinWidth;
            // Top-align in the row: the goals card has its own height bound
            // and shouldn't get stretched to match the (taller) timer card.
            final body = wide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      timerCard,
                      const SizedBox(width: 20),
                      goalsCard,
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      timerCard,
                      const SizedBox(height: 16),
                      goalsCard,
                    ],
                  );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
              child: Center(child: body),
            );
          },
        ),
        // Top-left close — out of the way of the centred timer.
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: state._close,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppPalette.glassStroke),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          size: 16, color: AppPalette.lavender),
                      SizedBox(width: 6),
                      Text('Back',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.lavender)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The phase chips + dial + controls — the timer itself, factored out of
/// [_SessionBody] so the side-by-side and stacked layouts can size it as
/// either an unflexible block (left) or full-width (stacked).
class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.preset, required this.state});

  final PomodoroPreset preset;
  final _PomodoroSessionPageState state;

  @override
  Widget build(BuildContext context) {
    final total = state._durationFor(preset, state._phase);
    final progress = total == 0 ? 0.0 : 1 - (state._remaining / total);
    final mm = (state._remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (state._remaining % 60).toString().padLeft(2, '0');
    final accent = state._phase.color;
    final untilLong = preset.roundsBeforeLong -
        (state._completed % preset.roundsBeforeLong);
    final title = preset.name.trim().isEmpty
        ? 'Pomodoro session'
        : preset.name.trim();

    return GlassContainer(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: preset.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${state._completed} focus session'
            '${state._completed == 1 ? '' : 's'} done '
            '· long break in $untilLong',
            style: const TextStyle(
                color: AppPalette.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final p in _Phase.values)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  child: _phaseChip(p, state),
                ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 12,
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
                            fontSize: 62,
                            fontWeight: FontWeight.w800)),
                    Text(state._phase.label,
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SoftButton(
                label: state._running ? 'Pause' : 'Start',
                icon: state._running
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                filled: true,
                onTap: () => state._toggle(preset),
              ),
              const SizedBox(width: 10),
              SoftButton(
                label: 'Reset',
                icon: Icons.refresh_rounded,
                onTap: () => state._reset(preset),
              ),
              const SizedBox(width: 10),
              SoftButton(
                label: 'Skip',
                icon: Icons.skip_next_rounded,
                onTap: () => state._advance(preset),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phaseChip(_Phase p, _PomodoroSessionPageState s) {
    final selected = s._phase == p;
    return GestureDetector(
      onTap: () => s._selectPhase(preset, p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.color : Colors.transparent,
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

/// Goal + checklist surface. Autosaves on every keystroke / toggle — the
/// whole preset is upserted through Riverpod, so the next time the user
/// taps this Pomodoro they land back on exactly the same goal and items.
class _GoalsBox extends ConsumerStatefulWidget {
  const _GoalsBox({required this.preset});

  final PomodoroPreset preset;

  @override
  ConsumerState<_GoalsBox> createState() => _GoalsBoxState();
}

class _GoalsBoxState extends ConsumerState<_GoalsBox> {
  late final TextEditingController _goalsC =
      TextEditingController(text: widget.preset.goals);
  final _goalsFocus = FocusNode();
  final TextEditingController _newItemC = TextEditingController();
  final _newItemFocus = FocusNode();

  /// Drives the inner checklist scroll area so the scrollbar attaches to the
  /// same viewport (and so we can keep newly-added items visible).
  final _itemsScroll = ScrollController();

  @override
  void didUpdateWidget(_GoalsBox old) {
    super.didUpdateWidget(old);
    // Reflect an outside edit (rare here, but cheap to support) — but never
    // yank the cursor mid-typing.
    if (!_goalsFocus.hasFocus && _goalsC.text != widget.preset.goals) {
      _goalsC.text = widget.preset.goals;
    }
  }

  @override
  void dispose() {
    _goalsC.dispose();
    _goalsFocus.dispose();
    _newItemC.dispose();
    _newItemFocus.dispose();
    _itemsScroll.dispose();
    super.dispose();
  }

  void _save(PomodoroPreset next) =>
      ref.read(pomodorosProvider.notifier).upsert(next);

  void _addItem() {
    final text = _newItemC.text.trim();
    if (text.isEmpty) return;
    final item = PomodoroChecklistItem(id: newId(), text: text);
    _save(widget.preset
        .copyWith(checklist: [...widget.preset.checklist, item]));
    _newItemC.clear();
    _newItemFocus.requestFocus();
    // After the new row is laid out, slide the list down to it so the user
    // can see what they just added (only matters once the list overflows).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemsScroll.hasClients) return;
      _itemsScroll.animateTo(
        _itemsScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleItem(String id) {
    _save(widget.preset.copyWith(checklist: [
      for (final i in widget.preset.checklist)
        if (i.id == id) i.copyWith(done: !i.done) else i,
    ]));
  }

  void _editItem(String id, String text) {
    _save(widget.preset.copyWith(checklist: [
      for (final i in widget.preset.checklist)
        if (i.id == id) i.copyWith(text: text) else i,
    ]));
  }

  void _removeItem(String id) {
    _save(widget.preset.copyWith(checklist: [
      for (final i in widget.preset.checklist)
        if (i.id != id) i,
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.preset.color;
    final checklist = widget.preset.checklist;
    final doneCount = checklist.where((i) => i.done).length;

    // The card has a bounded height (set on the parent ConstrainedBox), so
    // the Column fills it and the checklist gets the leftover middle via
    // Expanded — items scroll inside that band while the goal field at the
    // top and the "Add an item…" row at the bottom stay put.
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text('Your goal',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
            ],
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.glassStroke),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: TextField(
                controller: _goalsC,
                focusNode: _goalsFocus,
                minLines: 3,
                maxLines: 6,
                onChanged: (v) =>
                    _save(widget.preset.copyWith(goals: v)),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      'What are you trying to accomplish this session?',
                  hintStyle: TextStyle(
                      color: AppPalette.textSecondary, fontSize: 13.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text('Checklist',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
              const Spacer(),
              if (checklist.isNotEmpty)
                Text(
                  '$doneCount / ${checklist.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textFaint),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // The flexible middle: scrolls when items don't fit. `Expanded`
          // keeps the add-item row pinned to the bottom of the card.
          Expanded(
            child: checklist.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Add the things you want to get done — tick them '
                        'off as you go.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppPalette.textFaint),
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _itemsScroll,
                    child: ListView.builder(
                      controller: _itemsScroll,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: checklist.length,
                      itemBuilder: (context, i) {
                        final item = checklist[i];
                        return _ChecklistRow(
                          key: ValueKey(item.id),
                          item: item,
                          accent: accent,
                          onToggle: () => _toggleItem(item.id),
                          onChanged: (text) => _editItem(item.id, text),
                          onDelete: () => _removeItem(item.id),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newItemC,
                  focusNode: _newItemFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addItem(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Add an item…',
                    hintStyle: TextStyle(
                        color: AppPalette.textSecondary, fontSize: 13.5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _addItem,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.18),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 18, color: accent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of the checklist. Owns its TextEditingController so editing
/// is smooth and a state-restoration rebuild doesn't yank the cursor. Use
/// `key: ValueKey(item.id)` from the parent so the state survives reorders.
class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    super.key,
    required this.item,
    required this.accent,
    required this.onToggle,
    required this.onChanged,
    required this.onDelete,
  });

  final PomodoroChecklistItem item;
  final Color accent;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _c =
      TextEditingController(text: widget.item.text);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_ChecklistRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.item.text) {
      _c.text = widget.item.text;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.item.done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: done,
              onChanged: (_) => widget.onToggle(),
              activeColor: widget.accent,
              checkColor: const Color(0xFF15132B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focus,
              onChanged: widget.onChanged,
              style: TextStyle(
                fontSize: 13.5,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done
                    ? AppPalette.textFaint
                    : AppPalette.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          InkWell(
            onTap: widget.onDelete,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 16, color: AppPalette.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletedView extends StatelessWidget {
  const _DeletedView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.spa_outlined,
              size: 32, color: AppPalette.textFaint),
          const SizedBox(height: 10),
          const Text('This Pomodoro was deleted.',
              style: TextStyle(color: AppPalette.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('Back')),
        ],
      ),
    );
  }
}
