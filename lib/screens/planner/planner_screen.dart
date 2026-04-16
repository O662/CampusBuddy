import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/todo_task.dart';
import '../../providers/todo_provider.dart';
import '../../providers/task_planner_provider.dart';

// Layout constants
const double _kLeftWidth = 264.0;
const double _kRightWidth = 228.0;
const double _kLabelColWidth = 64.0;
const double _kHourHeight = 60.0;
const double _kStartHour = 7;
const double _kEndHour = 22;

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// ── Root screen ───────────────────────────────────────────────────────────────

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late DateTime _weekStart;
  late DateTime _selectedDay;
  late DateTime _calMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _weekStart = _mondayOf(now);
    _calMonth = DateTime(now.year, now.month, 1);
  }

  static DateTime _mondayOf(DateTime d) {
    final m = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(m.year, m.month, m.day);
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDay = DateTime(now.year, now.month, now.day);
      _weekStart = _mondayOf(now);
      _calMonth = DateTime(now.year, now.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _kLeftWidth,
          child: _LeftPanel(
            calMonth: _calMonth,
            selectedDay: _selectedDay,
            weekStart: _weekStart,
            onMonthChanged: (m) => setState(() => _calMonth = m),
            onDaySelected: (d) => setState(() {
              _selectedDay = d;
              _weekStart = _mondayOf(d);
            }),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _WeekGrid(
            weekStart: _weekStart,
            selectedDay: _selectedDay,
            onPrevWeek: () => setState(
                () => _weekStart = _weekStart.subtract(const Duration(days: 7))),
            onNextWeek: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7))),
            onToday: _goToday,
            onDaySelected: (d) => setState(() => _selectedDay = d),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        SizedBox(
          width: _kRightWidth,
          child: _DayPanel(selectedDay: _selectedDay),
        ),
      ],
    );
  }
}

// ── Left panel ────────────────────────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  final DateTime calMonth;
  final DateTime selectedDay;
  final DateTime weekStart;
  final void Function(DateTime) onMonthChanged;
  final void Function(DateTime) onDaySelected;

  const _LeftPanel({
    required this.calMonth,
    required this.selectedDay,
    required this.weekStart,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todoProvider = context.watch<TodoProvider>();
    final plannerProvider = context.watch<TaskPlannerProvider>();

    final allPending =
        todoProvider.allTasks.where((t) => !t.isCompleted).toList();
    final unplanned =
        allPending.where((t) => !plannerProvider.isPlanned(t.id)).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueToday = allPending
        .where((t) =>
            t.dueDate != null &&
            DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) ==
                today)
        .toList();

    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${_monthAbbr[weekStart.month - 1]} ${weekStart.day} – ${weekEnd.day}';

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniCalendar(
            month: calMonth,
            selectedDay: selectedDay,
            onMonthChanged: onMonthChanged,
            onDaySelected: onDaySelected,
          ),
          Divider(height: 1, color: theme.dividerColor),
          // Week range row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Week', style: theme.textTheme.labelSmall),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    weekLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Unplanned count pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_note_outlined,
                      size: 14, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 6),
                  Text(
                    '${unplanned.length} Unplanned',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Drag hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 13,
                    color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pick a task + drag it to the right',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (dueToday.isNotEmpty) ...[
                  _TaskSection(
                    title: '${dueToday.length} Due Today',
                    tasks: dueToday,
                    accentColor: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 6),
                ],
                if (unplanned.isNotEmpty)
                  _TaskSection(
                    title: 'Unplanned',
                    tasks: unplanned,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini calendar ─────────────────────────────────────────────────────────────

class _MiniCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final void Function(DateTime) onMonthChanged;
  final void Function(DateTime) onDaySelected;

  const _MiniCalendar({
    required this.month,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Sunday-first: DateTime.sunday=7, so weekday%7 gives Sun=0..Sat=6
    final firstOfMonth = month;
    final offset = firstOfMonth.weekday % 7;
    final startDate = firstOfMonth.subtract(Duration(days: offset));
    final days =
        List.generate(42, (i) => startDate.add(Duration(days: i)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Row(
            children: [
              Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _CalNavBtn(
                icon: Icons.chevron_left,
                onTap: () =>
                    onMonthChanged(DateTime(month.year, month.month - 1)),
              ),
              _CalNavBtn(
                icon: Icons.chevron_right,
                onTap: () =>
                    onMonthChanged(DateTime(month.year, month.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Day-of-week headers (S M T W T F S)
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((h) => Expanded(
                      child: Text(
                        h,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 2),
          // 6 weeks
          for (int w = 0; w < 6; w++)
            Row(
              children: List.generate(7, (d) {
                final day = days[w * 7 + d];
                final inMonth = day.month == month.month;
                final isToday = day == today;
                final isSelected = day == selectedDay;

                Color bg = Colors.transparent;
                Color fg = inMonth
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.25);

                if (isSelected) {
                  bg = theme.colorScheme.primary;
                  fg = theme.colorScheme.onPrimary;
                } else if (isToday) {
                  bg = theme.colorScheme.primaryContainer;
                  fg = theme.colorScheme.onPrimaryContainer;
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onDaySelected(day),
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 11,
                          color: fg,
                          fontWeight: isToday || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _CalNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CalNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon,
            size: 16,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6)),
      ),
    );
  }
}

// ── Task section in left sidebar ──────────────────────────────────────────────

class _TaskSection extends StatefulWidget {
  final String title;
  final List<TodoTask> tasks;
  final Color? accentColor;

  const _TaskSection({
    required this.title,
    required this.tasks,
    this.accentColor,
  });

  @override
  State<_TaskSection> createState() => _TaskSectionState();
}

class _TaskSectionState extends State<_TaskSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.tasks.map((task) => _DraggableTaskCard(task: task)),
      ],
    );
  }
}

// ── Draggable task card ───────────────────────────────────────────────────────

class _DraggableTaskCard extends StatelessWidget {
  final TodoTask task;
  const _DraggableTaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category =
        context.read<TodoProvider>().categoryById(task.categoryId);
    final color = category?.color ?? theme.colorScheme.primary;
    final isPlanned =
        context.watch<TaskPlannerProvider>().isPlanned(task.id);

    final cardContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category?.name ?? 'No course',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  task.title,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.dueDate != null)
                  Row(
                    children: [
                      Text(
                        'Due ${_fmtDate(task.dueDate!)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.star,
                          size: 9,
                          color: color.withValues(alpha: 0.7)),
                    ],
                  ),
              ],
            ),
          ),
          if (isPlanned)
            GestureDetector(
              onTap: () =>
                  context.read<TaskPlannerProvider>().unplan(task.id),
              child: Icon(Icons.close,
                  size: 14,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            )
          else
            Icon(Icons.drag_indicator,
                size: 14,
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () =>
                context.read<TodoProvider>().toggleComplete(task.id),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Draggable<TodoTask>(
      data: task,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.transparent,
        child: SizedBox(width: _kLeftWidth - 20, child: cardContent),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: cardContent),
      child: cardContent,
    );
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    if (dd == today) return 'Today';
    if (dd == today.add(const Duration(days: 1))) return 'Tomorrow';
    return '${_monthAbbr[d.month - 1]} ${d.day}';
  }
}

// ── Week grid ─────────────────────────────────────────────────────────────────

class _WeekGrid extends StatelessWidget {
  final DateTime weekStart;
  final DateTime selectedDay;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onToday;
  final void Function(DateTime) onDaySelected;

  const _WeekGrid({
    required this.weekStart,
    required this.selectedDay,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onToday,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekDays =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final startLbl =
        '${_monthAbbr[weekStart.month - 1]} ${weekStart.day}';
    final endLbl = weekEnd.month == weekStart.month
        ? '${weekEnd.day}'
        : '${_monthAbbr[weekEnd.month - 1]} ${weekEnd.day}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor))),
          child: Row(
            children: [
              _IconBtn(icon: Icons.chevron_left, onTap: onPrevWeek),
              _IconBtn(icon: Icons.chevron_right, onTap: onNextWeek),
              const SizedBox(width: 8),
              Text('$startLbl – $endLbl',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              InkWell(
                onTap: onToday,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Today',
                      style: theme.textTheme.labelSmall),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        // Header + Due + Planned rows
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Labels column
              SizedBox(
                width: _kLabelColWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Matches day header height
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: theme.dividerColor))),
                    ),
                    _RowLabel(label: 'Due'),
                    _RowLabel(label: 'Planned', isLast: true),
                  ],
                ),
              ),
              // 7 day columns
              ...weekDays.map((day) {
                final isToday = day == today;
                final dayIdx = day.weekday - 1;
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Day header
                      GestureDetector(
                        onTap: () => onDaySelected(day),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isToday
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.05)
                                : null,
                            border: Border(
                              left: BorderSide(
                                  color: theme.dividerColor
                                      .withValues(alpha: 0.5)),
                              bottom:
                                  BorderSide(color: theme.dividerColor),
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Text(
                                '${_dayNames[dayIdx]} ${_monthAbbr[day.month - 1]} ${day.day}',
                                style:
                                    theme.textTheme.labelSmall?.copyWith(
                                  color: isToday
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                  fontWeight: isToday
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              if (isToday)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.primary,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Today',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color:
                                          theme.colorScheme.onPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Due cell
                      _DueDayCell(date: day),
                      // Planned cell
                      _PlannedDayCell(date: day),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowLabel extends StatelessWidget {
  final String label;
  final bool isLast;
  const _RowLabel({required this.label, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: theme.dividerColor),
            right: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon,
            size: 18,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7)),
      ),
    );
  }
}

// ── Due day cell ──────────────────────────────────────────────────────────────

class _DueDayCell extends StatelessWidget {
  final DateTime date;
  const _DueDayCell({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todoProvider = context.watch<TodoProvider>();

    final allDue = todoProvider.allTasks
        .where((t) =>
            t.dueDate != null &&
            DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) ==
                date)
        .toList();

    return DragTarget<TodoTask>(
      onAcceptWithDetails: (details) =>
          context.read<TaskPlannerProvider>().plan(details.data.id, date),
      builder: (ctx, candidateData, _) {
        final hovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : null,
            border: Border(
              left: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.5)),
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          constraints: const BoxConstraints(minHeight: 36),
          child: allDue.isEmpty
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: allDue
                      .map((t) => _DueChip(task: t))
                      .toList(),
                ),
        );
      },
    );
  }
}

class _DueChip extends StatelessWidget {
  final TodoTask task;
  const _DueChip({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category =
        context.read<TodoProvider>().categoryById(task.categoryId);
    final color = category?.color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: task.isCompleted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.title,
            style: TextStyle(
              fontSize: 10,
              color: task.isCompleted
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                  : theme.colorScheme.onSurface,
              decoration:
                  task.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.star,
              size: 8, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 3),
          Text(
            'due 11:59pm',
            style: TextStyle(
              fontSize: 9,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: () =>
                context.read<TodoProvider>().toggleComplete(task.id),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.isCompleted ? color : null,
                border: Border.all(
                  color: task.isCompleted
                      ? color
                      : theme.colorScheme.outline
                          .withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: task.isCompleted
                  ? Icon(Icons.check,
                      size: 9, color: theme.colorScheme.onPrimary)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Planned day cell ──────────────────────────────────────────────────────────

class _PlannedDayCell extends StatelessWidget {
  final DateTime date;
  const _PlannedDayCell({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plannerProvider = context.watch<TaskPlannerProvider>();
    final todoProvider = context.watch<TodoProvider>();
    final allTasks = todoProvider.allTasks;

    final planned = plannerProvider.forDate(date);
    final plannedTasks = planned
        .map((p) => _findTask(allTasks, p.taskId))
        .whereType<TodoTask>()
        .toList();

    return DragTarget<TodoTask>(
      onAcceptWithDetails: (details) =>
          context.read<TaskPlannerProvider>().plan(details.data.id, date),
      builder: (ctx, candidateData, _) {
        final hovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : null,
            border: Border(
              left: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          constraints: const BoxConstraints(minHeight: 48),
          child: plannedTasks.isEmpty && !hovered
              ? Center(
                  child: Text(
                    'Drag to plan day',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.28),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children:
                      plannedTasks.map((t) => _PlannedChip(task: t)).toList(),
                ),
        );
      },
    );
  }
}

class _PlannedChip extends StatelessWidget {
  final TodoTask task;
  const _PlannedChip({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category =
        context.read<TodoProvider>().categoryById(task.categoryId);
    final color = category?.color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 4, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.title,
            style: TextStyle(
                fontSize: 10, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () =>
                context.read<TaskPlannerProvider>().unplan(task.id),
            child: Icon(Icons.close,
                size: 11,
                color: theme.colorScheme.onSurface
                    .withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

// ── Day panel (right) ─────────────────────────────────────────────────────────

class _DayPanel extends StatefulWidget {
  final DateTime selectedDay;
  const _DayPanel({required this.selectedDay});

  @override
  State<_DayPanel> createState() => _DayPanelState();
}

class _DayPanelState extends State<_DayPanel> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  void _scrollToNow() {
    if (!_scrollCtrl.hasClients) return;
    final now = DateTime.now();
    final hour =
        now.hour.clamp(_kStartHour.toInt(), (_kEndHour - 1).toInt()).toDouble();
    final offset =
        ((hour - _kStartHour) * _kHourHeight - 80).clamp(0.0, double.infinity);
    _scrollCtrl.animateTo(offset,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = widget.selectedDay == today;

    final todoProvider = context.watch<TodoProvider>();
    final plannerProvider = context.watch<TaskPlannerProvider>();
    final allTasks = todoProvider.allTasks;

    final dueTasks = allTasks
        .where((t) =>
            t.dueDate != null &&
            DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) ==
                widget.selectedDay)
        .toList();

    final plannedForDay = plannerProvider.forDate(widget.selectedDay);
    final allDayPlanned =
        plannedForDay.where((p) => p.startMinutes == null).toList();
    final timedPlanned =
        plannedForDay.where((p) => p.startMinutes != null).toList();

    final dayName = _dayNames[widget.selectedDay.weekday - 1];

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: theme.dividerColor))),
            child: Row(
              children: [
                Text('Schedule',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Icon(Icons.settings_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                const Spacer(),
                Icon(Icons.chevron_left,
                    size: 16,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                Icon(Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
              ],
            ),
          ),
          // Day badge
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Text(
                  '$dayName ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${widget.selectedDay.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isToday
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Due section
          if (dueTasks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Text('Due',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  )),
            ),
            ...dueTasks.map((t) => _RightTaskTile(task: t)),
            const SizedBox(height: 6),
          ],
          // Plan All-Day section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                Text('Plan',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(width: 4),
                Text('All-Day',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    )),
              ],
            ),
          ),
          // All-day drop target
          DragTarget<TodoTask>(
            onAcceptWithDetails: (details) =>
                context.read<TaskPlannerProvider>().plan(
                      details.data.id,
                      widget.selectedDay,
                    ),
            builder: (ctx, candidateData, _) {
              final hovered = candidateData.isNotEmpty;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: hovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hovered
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : theme.dividerColor,
                  ),
                ),
                child: allDayPlanned.isEmpty
                    ? Text(
                        hovered ? 'Drop here' : 'Drag to plan all-day',
                        style: TextStyle(
                          fontSize: 10,
                          color: hovered
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.35),
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      )
                    : Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: allDayPlanned
                            .map((p) {
                              final task = _findTask(allTasks, p.taskId);
                              if (task == null) return const SizedBox.shrink();
                              return _PlannedChip(task: task);
                            })
                            .toList(),
                      ),
              );
            },
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.dividerColor),
          // Time grid
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: SizedBox(
                height: (_kEndHour - _kStartHour) * _kHourHeight,
                child: Stack(
                  children: [
                    // Hour lines + labels
                    ...List.generate((_kEndHour - _kStartHour).toInt(), (i) {
                      final hour = _kStartHour.toInt() + i;
                      final label = hour < 12
                          ? '${hour}am'
                          : hour == 12
                              ? '12pm'
                              : '${hour - 12}pm';
                      return Positioned(
                        top: i * _kHourHeight,
                        left: 0,
                        right: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(
                                height: 1, color: theme.dividerColor),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 8, top: 2),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // Hour drop targets
                    ...List.generate((_kEndHour - _kStartHour).toInt(), (i) {
                      final startMins =
                          (_kStartHour.toInt() + i) * 60;
                      return Positioned(
                        top: i * _kHourHeight,
                        left: 0,
                        right: 0,
                        height: _kHourHeight,
                        child: _TimeSlotTarget(
                          date: widget.selectedDay,
                          startMinutes: startMins,
                        ),
                      );
                    }),
                    // Timed task blocks
                    ...timedPlanned.map((p) {
                      final task = _findTask(allTasks, p.taskId);
                      if (task == null) return const SizedBox.shrink();
                      final top = (p.startMinutes! - _kStartHour * 60) /
                          60.0 *
                          _kHourHeight;
                      final height = (p.durationMinutes /
                              60.0 *
                              _kHourHeight)
                          .clamp(22.0, double.infinity);
                      final cat = context
                          .read<TodoProvider>()
                          .categoryById(task.categoryId);
                      final color =
                          cat?.color ?? theme.colorScheme.primary;

                      return Positioned(
                        top: top + 1,
                        left: 36,
                        right: 4,
                        height: height - 2,
                        child: GestureDetector(
                          onTap: () => context
                              .read<TaskPlannerProvider>()
                              .unplan(task.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                  left: BorderSide(
                                      color: color, width: 3)),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (height > 30)
                                  Text(
                                    '${_fmtMins(p.startMinutes!)} – ${_fmtMins(p.startMinutes! + p.durationMinutes)}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color:
                                          color.withValues(alpha: 0.8),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    // Current time line
                    if (isToday) _currentTimeLine(theme),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentTimeLine(ThemeData theme) {
    final now = DateTime.now();
    final cur = now.hour * 60 + now.minute;
    final start = _kStartHour.toInt() * 60;
    final end = _kEndHour.toInt() * 60;
    if (cur < start || cur > end) return const SizedBox.shrink();
    final top = (cur - start) / 60.0 * _kHourHeight;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle)),
          Expanded(child: Container(height: 1.5, color: Colors.red)),
        ],
      ),
    );
  }
}

class _TimeSlotTarget extends StatelessWidget {
  final DateTime date;
  final int startMinutes;
  const _TimeSlotTarget(
      {required this.date, required this.startMinutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<TodoTask>(
      onAcceptWithDetails: (details) =>
          context.read<TaskPlannerProvider>().plan(
                details.data.id,
                date,
                startMinutes: startMinutes,
              ),
      builder: (ctx, candidateData, _) {
        final hovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          child: hovered
              ? Center(
                  child: Text(
                    'Drop to plan ${_fmtMins(startMinutes)}',
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _RightTaskTile extends StatelessWidget {
  final TodoTask task;
  const _RightTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat =
        context.read<TodoProvider>().categoryById(task.categoryId);
    final color = cat?.color ?? theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: task.isCompleted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.title,
              style: theme.textTheme.labelSmall?.copyWith(
                decoration: task.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
                color: task.isCompleted
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.star,
              size: 10, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () =>
                context.read<TodoProvider>().toggleComplete(task.id),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.isCompleted ? color : null,
                border: Border.all(
                  color: task.isCompleted
                      ? color
                      : theme.colorScheme.outline
                          .withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: task.isCompleted
                  ? Icon(Icons.check,
                      size: 9, color: theme.colorScheme.onPrimary)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

TodoTask? _findTask(List<TodoTask> tasks, String taskId) {
  for (final t in tasks) {
    if (t.id == taskId) return t;
  }
  return null;
}

String _fmtMins(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final period = h < 12 ? 'am' : 'pm';
  final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return m == 0
      ? '$dh$period'
      : '$dh:${m.toString().padLeft(2, '0')}$period';
}
