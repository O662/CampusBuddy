import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/grades_provider.dart';
import '../../providers/todo_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/todo_task.dart';

class HomeDashboard extends StatelessWidget {
  final VoidCallback onGoToPlanner;
  final VoidCallback onGoToGrades;
  final VoidCallback onGoToTodo;

  const HomeDashboard({
    super.key,
    required this.onGoToPlanner,
    required this.onGoToGrades,
    required this.onGoToTodo,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userName = context.watch<UserProvider>().name;
    final today = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(today);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + Greeting
          Text(dateStr,
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_greeting()}, $userName.',
                  style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
              ),
              _EditNameButton(userName: userName),
            ],
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _TasksWeekCard(onGoToTodo: onGoToTodo),
              _AgendaCard(onViewAll: onGoToTodo),
              _GpaSummaryCard(onViewAll: onGoToGrades),
              _UpcomingCard(onViewAll: onGoToTodo),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Edit name ─────────────────────────────────────────────────────────────────

class _EditNameButton extends StatelessWidget {
  final String userName;
  const _EditNameButton({required this.userName});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.edit_outlined, size: 20),
      tooltip: 'Edit name',
      onPressed: () async {
        final ctrl = TextEditingController(text: userName);
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Your Name'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  child: const Text('Save')),
            ],
          ),
        );
        if (result != null && context.mounted) {
          await context.read<UserProvider>().setName(result);
        }
      },
    );
  }
}

// ── Agenda card (today's tasks) ───────────────────────────────────────────────

class _AgendaCard extends StatelessWidget {
  final VoidCallback onViewAll;
  const _AgendaCard({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<TodoProvider>();
    final todayTasks = provider.tasksDueToday;

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.checklist_rounded,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Agenda',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('Due Today',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
              const SizedBox(height: 16),
              if (todayTasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.celebration_outlined,
                          color: theme.colorScheme.primary, size: 32),
                      const SizedBox(height: 8),
                      Text('All clear today!',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6))),
                    ]),
                  ),
                )
              else
                ...todayTasks.take(4).map((t) => _TaskRow(task: t, provider: provider)),
              if (todayTasks.length > 4)
                Text('+${todayTasks.length - 4} more',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TodoTask task;
  final TodoProvider provider;
  const _TaskRow({required this.task, required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = provider.categoryById(task.categoryId);
    final color = cat?.color ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(task.title,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (task.dueDate != null)
            Text(
              DateFormat('h:mm a').format(task.dueDate!),
              style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }
}

// ── GPA summary card ──────────────────────────────────────────────────────────

class _GpaSummaryCard extends StatelessWidget {
  final VoidCallback onViewAll;
  const _GpaSummaryCard({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<GradesProvider>();
    final gpa = provider.gpa;
    final courses = provider.courses;

    final gpaColor = gpa >= 3.5
        ? Colors.green
        : gpa >= 3.0
            ? Colors.lightGreen
            : gpa >= 2.0
                ? Colors.orange
                : Colors.red;

    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Grades',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              if (courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No courses added yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                )
              else ...[
                Row(
                  children: [
                    Text(gpa.toStringAsFixed(2),
                        style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.bold, color: gpaColor)),
                    const SizedBox(width: 8),
                    Text('/ 4.00',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5))),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${courses.length} courses tracked',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
                const SizedBox(height: 16),
                ...courses.take(3).map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(c.name,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Text(c.letterGrade,
                              style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upcoming deadlines card ───────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final VoidCallback onViewAll;
  const _UpcomingCard({required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = context.watch<TodoProvider>().tasksDueSoon;
    final now = DateTime.now();

    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.upcoming_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Upcoming',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('Next 7 days',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
              const SizedBox(height: 16),
              if (upcoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('Nothing due in the next 7 days.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5))),
                  ),
                )
              else
                ...upcoming.take(4).map((t) {
                  final daysLeft = t.dueDate!.difference(now).inDays;
                  final label = daysLeft == 0
                      ? 'Today'
                      : daysLeft == 1
                          ? 'Tomorrow'
                          : 'In $daysLeft days';
                  final urgent = daysLeft <= 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(t.title,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: urgent
                                ? Colors.red.withValues(alpha: 0.15)
                                : theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: urgent
                                      ? Colors.red
                                      : theme.colorScheme.primary)),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onViewAll,
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tasks week card ───────────────────────────────────────────────────────────

int _computeStreak(List<TodoTask> tasks) {
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);

  for (int d = 0; d <= 30; d++) {
    final day = todayDate.subtract(Duration(days: d));
    final dayTasks = tasks.where((t) {
      if (t.dueDate == null) return false;
      final td = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return td == day;
    }).toList();

    if (dayTasks.isEmpty) continue;
    if (dayTasks.every((t) => t.isCompleted)) continue;
    return d;
  }
  return 30;
}

class _TasksWeekCard extends StatefulWidget {
  final VoidCallback onGoToTodo;
  const _TasksWeekCard({required this.onGoToTodo});

  @override
  State<_TasksWeekCard> createState() => _TasksWeekCardState();
}

class _TasksWeekCardState extends State<_TasksWeekCard> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final offset = now.weekday % 7; // 0 = Sunday
    _weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: offset));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<TodoProvider>();
    final allTasks = provider.allTasks;

    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekTasks = allTasks.where((t) {
      if (t.dueDate == null) return false;
      final d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isBefore(_weekStart) && !d.isAfter(weekEnd);
    }).toList();

    final completedCount = weekTasks.where((t) => t.isCompleted).length;
    final totalCount = weekTasks.length;
    final pct = totalCount == 0 ? 1.0 : completedCount / totalCount;
    final pendingCount = weekTasks.where((t) => !t.isCompleted).length;
    final highCount = weekTasks
        .where((t) => t.priority == TaskPriority.high && !t.isCompleted)
        .length;
    final streak = _computeStreak(allTasks);
    final todayTasks = provider.tasksDueToday;
    final weekLabel =
        '${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d').format(weekEnd)}';

    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Streak
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$streak day${streak == 1 ? '' : 's'}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'without missing a task',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Icon(Icons.task_alt,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Tasks',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    onPressed: widget.onGoToTodo,
                    style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
              // Week navigation
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    onPressed: () => setState(() => _weekStart =
                        _weekStart.subtract(const Duration(days: 7))),
                    style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  Expanded(
                    child: Text(
                      weekLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    onPressed: () => setState(() => _weekStart =
                        _weekStart.add(const Duration(days: 7))),
                    style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Donut chart
              Center(
                child: SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(130, 130),
                        painter: _DonutPainter(
                          pct: pct,
                          color: theme.colorScheme.primary,
                          bgColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(pct * 100).round()}%',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '$completedCount/$totalCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatChip(
                      icon: Icons.campaign_outlined, count: highCount),
                  _StatChip(
                      icon: Icons.edit_note_outlined, count: pendingCount),
                  _StatChip(icon: Icons.check, count: completedCount),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // Today's tasks / empty state
              if (todayTasks.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '0',
                            style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('No tasks', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                )
              else
                ...todayTasks.take(3).map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: t.isCompleted,
                              onChanged: (_) => context
                                  .read<TodoProvider>()
                                  .toggleComplete(t.id),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(t.title,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 12),
              // Add task button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onGoToTodo,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('+ Add Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Donut chart painter ───────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  final double pct;
  final Color color;
  final Color bgColor;

  const _DonutPainter(
      {required this.pct, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const strokeWidth = 16.0;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    if (pct > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, -pi / 2, 2 * pi * pct, false, fgPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.pct != pct || old.color != color || old.bgColor != bgColor;
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final int count;

  const _StatChip({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 5),
          Text('$count',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
