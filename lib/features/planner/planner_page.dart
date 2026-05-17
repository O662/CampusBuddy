import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Visible hour window for the week grid.
const _startHour = 6;
const _endHour = 24;
const _hourHeight = 60.0; // 1px == 1 minute (perMinute = 1)
const _snap = 15; // snap minutes

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Sunday that begins the week containing [d].
DateTime _weekStart(DateTime d) {
  final m = _midnight(d);
  return m.subtract(Duration(days: m.weekday % 7)); // Sun=7%7=0
}

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  DateTime _focusedDay = DateTime.now();
  late DateTime _weekStartDay = _weekStart(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Planner',
      subtitle: 'Drag an assignment onto a day, then slide it to block out time.',
      scrollable: false,
      actions: [
        SoftButton(
          label: 'This week',
          icon: Icons.today_rounded,
          onTap: () => setState(() {
            _focusedDay = DateTime.now();
            _weekStartDay = _weekStart(DateTime.now());
          }),
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'New assignment',
          filled: true,
          onTap: () async {
            final a = await showAssignmentDialog(context,
                courses: ref.read(coursesProvider));
            if (a != null) ref.read(assignmentsProvider.notifier).upsert(a);
          },
        ),
      ],
      child: Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 980;
          final side = _SidePanel(
            focusedDay: _focusedDay,
            // When narrow the whole page scrolls, so the panel must not
            // introduce its own (unbounded) scroll view inside it.
            scroll: !narrow,
            onDaySelected: (sel) => setState(() {
              _focusedDay = sel;
              _weekStartDay = _weekStart(sel);
            }),
          );
          final week = _WeekView(weekStart: _weekStartDay);
          if (narrow) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  side,
                  const SizedBox(height: 16),
                  SizedBox(height: 560, child: week),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: side),
              const SizedBox(width: 16),
              Expanded(child: week),
            ],
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left: month calendar + draggable unscheduled assignments
// ---------------------------------------------------------------------------

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.focusedDay,
    required this.onDaySelected,
    this.scroll = true,
  });

  final DateTime focusedDay;
  final ValueChanged<DateTime> onDaySelected;
  final bool scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(upcomingAssignmentsProvider);
    final courses = ref.watch(coursesByIdProvider);

    final content = Column(
      children: [
          GlassContainer(
            padding: const EdgeInsets.all(12),
            child: TableCalendar(
              firstDay: DateTime.utc(2020),
              lastDay: DateTime.utc(2100),
              focusedDay: focusedDay,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              selectedDayPredicate: (d) => isSameDay(d, focusedDay),
              onDaySelected: (sel, foc) => onDaySelected(sel),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: AppPalette.textSecondary),
                weekendStyle: TextStyle(color: AppPalette.lavender),
              ),
              calendarStyle: CalendarStyle(
                defaultTextStyle:
                    const TextStyle(color: AppPalette.textPrimary),
                weekendTextStyle:
                    const TextStyle(color: AppPalette.textSecondary),
                outsideTextStyle:
                    const TextStyle(color: AppPalette.textFaint),
                todayDecoration: BoxDecoration(
                  color: AppPalette.mint.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppPalette.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            title: 'Assignments to schedule',
            icon: Icons.drag_indicator_rounded,
            child: assignments.isEmpty
                ? const EmptyHint('Nothing to schedule. 🎈')
                : Column(
                    children: [
                      for (final a in assignments)
                        _AssignmentChip(
                          assignment: a,
                          color: a.courseId == null
                              ? AppPalette.lavender
                              : courses[a.courseId]?.color ??
                                  AppPalette.lavender,
                        ),
                    ],
                  ),
          ),
        ],
      );

    return scroll ? SingleChildScrollView(child: content) : content;
  }
}

class _AssignmentChip extends StatelessWidget {
  const _AssignmentChip({required this.assignment, required this.color});

  final Assignment assignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 270,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(assignment.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    'Due ${relativeDay(assignment.dueDate)} · ~${assignment.estimatedMinutes}m',
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );

    return LongPressDraggable<Assignment>(
      data: assignment,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Opacity(opacity: 0.9, child: Material(
          color: Colors.transparent, child: card)),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// Right: Sunday→Saturday week grid with drop targets and resizable blocks
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerWidget {
  const _WeekView({required this.weekStart});

  final DateTime weekStart;

  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = _midnight(DateTime.now());

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 44),
              for (final d in days)
                Expanded(
                  child: Column(
                    children: [
                      Text(_dayNames[d.weekday % 7],
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppPalette.textSecondary)),
                      const SizedBox(height: 2),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSameDay(d, today)
                              ? AppPalette.accent
                              : Colors.transparent,
                        ),
                        child: Text('${d.day}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isSameDay(d, today)
                                    ? const Color(0xFF15132B)
                                    : AppPalette.textPrimary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: (_endHour - _startHour) * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HourGutter(),
                    for (final d in days)
                      Expanded(
                        child: _DayColumn(
                          day: d,
                          blocks: blocks
                              .where((b) => isSameDay(b.day, d))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Column(
        children: [
          for (var h = _startHour; h < _endHour; h++)
            SizedBox(
              height: _hourHeight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Text(
                  hhmm(h * 60),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 10, color: AppPalette.textFaint),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends ConsumerStatefulWidget {
  const _DayColumn({required this.day, required this.blocks});

  final DateTime day;
  final List<TimeBlock> blocks;

  @override
  ConsumerState<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends ConsumerState<_DayColumn> {
  final _key = GlobalKey();

  int _minuteFromGlobal(Offset global) {
    final box = _key.currentContext!.findRenderObject() as RenderBox;
    final local = box.globalToLocal(global);
    var minute = _startHour * 60 + local.dy.round();
    minute = (minute / _snap).round() * _snap;
    return minute.clamp(_startHour * 60, _endHour * 60 - _snap).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      builder: (context, candidate, rejected) {
        return Container(
          key: _key,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: AppPalette.glassStroke),
            ),
            color: candidate.isNotEmpty
                ? AppPalette.accent.withValues(alpha: 0.08)
                : null,
          ),
          child: Stack(
            children: [
              // hour grid lines
              Column(
                children: [
                  for (var h = _startHour; h < _endHour; h++)
                    Container(
                      height: _hourHeight,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.05)),
                        ),
                      ),
                    ),
                ],
              ),
              for (final b in widget.blocks)
                _BlockWidget(
                  block: b,
                  onResize: (newEnd) => ref
                      .read(blocksProvider.notifier)
                      .upsert(b.copyWith(endMinute: newEnd)),
                  onDelete: () =>
                      ref.read(blocksProvider.notifier).remove(b.id),
                ),
            ],
          ),
        );
      },
      onAcceptWithDetails: (details) {
        final minute = _minuteFromGlobal(details.offset);
        final data = details.data;
        final notifier = ref.read(blocksProvider.notifier);
        if (data is Assignment) {
          final dur = data.estimatedMinutes.clamp(_snap, 600).toInt();
          notifier.upsert(TimeBlock(
            id: newId(),
            title: data.title,
            assignmentId: data.id,
            day: _midnight(widget.day),
            startMinute: minute,
            endMinute:
                (minute + dur).clamp(minute + _snap, _endHour * 60).toInt(),
            colorSeed: data.title.hashCode,
          ));
        } else if (data is TimeBlock) {
          final dur = data.durationMinutes;
          notifier.upsert(data.copyWith(
            day: _midnight(widget.day),
            startMinute: minute,
            endMinute:
                (minute + dur).clamp(minute + _snap, _endHour * 60).toInt(),
          ));
        }
      },
    );
  }
}

class _BlockWidget extends StatelessWidget {
  const _BlockWidget({
    required this.block,
    required this.onResize,
    required this.onDelete,
  });

  final TimeBlock block;
  final ValueChanged<int> onResize;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final top = (block.startMinute - _startHour * 60).toDouble();
    final double height = block.durationMinutes
        .toDouble()
        .clamp(_snap.toDouble(), 2000.0)
        .toDouble();
    final color = block.color;

    final body = Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(block.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          Text(
              '${hhmm(block.startMinute)} – ${hhmm(block.endMinute)}',
              style: const TextStyle(
                  fontSize: 10, color: AppPalette.textSecondary)),
        ],
      ),
    );

    return Positioned(
      top: top,
      left: 3,
      right: 3,
      height: height,
      child: LongPressDraggable<TimeBlock>(
        data: block,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: SizedBox(
          width: 150,
          height: height,
          child: Opacity(opacity: 0.85, child: Material(
              color: Colors.transparent, child: body)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: body),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _menu(context),
                child: body,
              ),
            ),
            // bottom resize handle
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 14,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) {
                  final newEnd = ((block.endMinute + d.delta.dy.round()) /
                              _snap)
                          .round() *
                      _snap;
                  onResize(newEnd
                      .clamp(block.startMinute + _snap, _endHour * 60)
                      .toInt());
                },
                child: Center(
                  child: Container(
                    width: 28,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context) {
    showGlassDialog<void>(
      context,
      title: block.title,
      content: Text(
        '${hhmm(block.startMinute)} – ${hhmm(block.endMinute)}'
        '  ·  ${block.durationMinutes} min',
        style: const TextStyle(color: AppPalette.textSecondary),
      ),
      actions: (context) => [
        TextButton(
          onPressed: () {
            onDelete();
            Navigator.pop(context);
          },
          child: const Text('Remove from planner'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
