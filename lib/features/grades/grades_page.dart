import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

class GradesPage extends ConsumerWidget {
  const GradesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);
    final grades = ref.watch(gradesProvider);
    final overall = ref.watch(overallGradeProvider);

    return PageBody(
      title: 'Grades',
      subtitle: overall == null
          ? 'Track every course and watch your progress.'
          : 'Overall weighted average: ${overall.toStringAsFixed(1)}%',
      actions: [
        SoftButton(
          label: 'New course',
          onTap: () async {
            final c = await showCourseDialog(context);
            if (c != null) ref.read(coursesProvider.notifier).upsert(c);
          },
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'Add grade',
          filled: true,
          icon: Icons.add_chart_rounded,
          onTap: courses.isEmpty
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add a course first.')))
              : () async {
                  final g = await showGradeDialog(context,
                      courses: courses);
                  if (g != null) {
                    ref.read(gradesProvider.notifier).upsert(g);
                  }
                },
        ),
      ],
      child: courses.isEmpty
          ? GlassContainer(
              child: const EmptyHint(
                  'No courses yet. Create one to start tracking grades.',
                  icon: Icons.school_outlined),
            )
          : CardGrid(
              children: [
                const _GradeTrendCard(),
                const _FinalGradeCalculator(),
                for (final c in courses)
                  _CourseCard(
                    course: c,
                    entries: grades
                        .where((g) => g.courseId == c.id)
                        .toList()
                      ..sort((a, b) => b.date.compareTo(a.date)),
                  ),
              ],
            ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({required this.course, required this.entries});

  final Course course;
  final List<GradeEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avg = courseGrade(entries, course.id);
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: course.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(course.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Text(
                avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: course.color),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Course options',
                onSelected: (v) async {
                  if (v == 'edit') {
                    final edited =
                        await showCourseDialog(context, existing: course);
                    if (edited != null) {
                      ref.read(coursesProvider.notifier).upsert(edited);
                    }
                  } else if (v == 'delete') {
                    final n = entries.length;
                    final ok = await confirmDelete(
                      context,
                      title: 'Delete ${course.name}?',
                      message: n == 0
                          ? 'This class will be removed.'
                          : 'This class and its $n grade'
                              '${n == 1 ? '' : 's'} will be permanently '
                              'removed.',
                    );
                    if (ok) {
                      for (final g in entries) {
                        ref.read(gradesProvider.notifier).remove(g.id);
                      }
                      ref
                          .read(coursesProvider.notifier)
                          .remove(course.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined, size: 20),
                      title: Text('Edit class'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete class'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Target ${course.targetGrade.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 12, color: AppPalette.textSecondary)),
          const Divider(height: 24),
          if (entries.isEmpty)
            const EmptyHint('No grades recorded yet.')
          else
            for (final g in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(g.title)),
                    Text('${g.earned.toStringAsFixed(0)}/${g.total.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: AppPalette.textSecondary)),
                    const SizedBox(width: 10),
                    GlassChip(
                        label: '${g.percent.toStringAsFixed(0)}%',
                        color: g.percent >= course.targetGrade
                            ? AppPalette.success
                            : AppPalette.warning),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz,
                          size: 18, color: AppPalette.textSecondary),
                      color: const Color(0xFF241F45),
                      tooltip: 'Grade options',
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final edited = await showGradeDialog(context,
                              courses: ref.read(coursesProvider),
                              existing: g);
                          if (edited != null) {
                            ref
                                .read(gradesProvider.notifier)
                                .upsert(edited);
                          }
                        } else if (v == 'delete') {
                          final ok = await confirmDelete(
                            context,
                            title: 'Delete grade?',
                            message:
                                '"${g.title}" will be permanently removed.',
                          );
                          if (ok) {
                            ref
                                .read(gradesProvider.notifier)
                                .remove(g.id);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined, size: 20),
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
              ),
        ],
      ),
    );
  }
}

/// Running overall weighted average over time — a calm sparkline.
class _GradeTrendCard extends ConsumerWidget {
  const _GradeTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades = [...ref.watch(gradesProvider)]
      ..sort((a, b) => a.date.compareTo(b.date));

    Widget content;
    if (grades.length < 2) {
      content = const EmptyHint(
          'Add a couple of grades to see your trend.',
          icon: Icons.show_chart_rounded);
    } else {
      final spots = <FlSpot>[];
      var wSum = 0.0;
      var wpSum = 0.0;
      for (var i = 0; i < grades.length; i++) {
        wSum += grades[i].weight;
        wpSum += grades[i].percent * grades[i].weight;
        spots.add(FlSpot(i.toDouble(), wSum == 0 ? 0 : wpSum / wSum));
      }
      final ys = spots.map((s) => s.y).toList();
      final lo = (ys.reduce((a, b) => a < b ? a : b) - 5)
          .clamp(0, 100)
          .toDouble();
      final hi = (ys.reduce((a, b) => a > b ? a : b) + 5)
          .clamp(0, 100)
          .toDouble();

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${ys.last.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Builder(builder: (_) {
                final delta = ys.last - ys.first;
                final up = delta >= 0;
                return Text(
                  '${up ? '▲' : '▼'} ${delta.abs().toStringAsFixed(1)} pts',
                  style: TextStyle(
                      color: up ? AppPalette.success : AppPalette.danger,
                      fontWeight: FontWeight.w600),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                minX: 0,
                maxX: (spots.length - 1).toDouble(),
                minY: lo,
                maxY: hi,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppPalette.accent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppPalette.accent.withValues(alpha: 0.28),
                          AppPalette.accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return GlassCard(
      title: 'GPA / grade trend',
      icon: Icons.trending_up_rounded,
      child: content,
    );
  }
}

/// "What do I need on the final?" — works off the current weighted average.
class _FinalGradeCalculator extends ConsumerStatefulWidget {
  const _FinalGradeCalculator();

  @override
  ConsumerState<_FinalGradeCalculator> createState() =>
      _FinalGradeCalculatorState();
}

class _FinalGradeCalculatorState
    extends ConsumerState<_FinalGradeCalculator> {
  String? _courseId;
  final _current = TextEditingController();
  final _weight = TextEditingController(text: '30');
  final _target = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _weight.dispose();
    _target.dispose();
    super.dispose();
  }

  void _selectCourse(String? id, List<Course> courses,
      List<GradeEntry> grades) {
    setState(() {
      _courseId = id;
      if (id != null) {
        final cur = courseGrade(grades, id);
        _current.text = cur == null ? '' : cur.toStringAsFixed(1);
        final course = courses.firstWhere((c) => c.id == id);
        _target.text = course.targetGrade.toStringAsFixed(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider);
    final grades = ref.watch(gradesProvider);
    _courseId ??= courses.firstOrNull?.id;
    if (_courseId != null && _current.text.isEmpty && _target.text.isEmpty) {
      final cur = courseGrade(grades, _courseId!);
      _current.text = cur == null ? '' : cur.toStringAsFixed(1);
      _target.text = courses
          .firstWhere((c) => c.id == _courseId)
          .targetGrade
          .toStringAsFixed(0);
    }

    final cur = double.tryParse(_current.text);
    final wPct = double.tryParse(_weight.text);
    final target = double.tryParse(_target.text);

    String message = 'Enter your numbers to see what you need.';
    Color color = AppPalette.textSecondary;
    if (cur != null && wPct != null && target != null && wPct > 0) {
      final w = (wPct.clamp(0, 100)) / 100;
      final needed = (target - cur * (1 - w)) / w;
      final best = cur * (1 - w) + 100 * w;
      if (needed <= 0) {
        message =
            "You're set — even a 0 keeps you at or above ${target.toStringAsFixed(0)}%.";
        color = AppPalette.success;
      } else if (needed > 100) {
        message =
            'Out of reach: the best you can finish with is ${best.toStringAsFixed(1)}%.';
        color = AppPalette.danger;
      } else {
        message =
            'You need ${needed.toStringAsFixed(1)}% on the final '
            '(worth ${wPct.toStringAsFixed(0)}%) to reach ${target.toStringAsFixed(0)}%.';
        color = AppPalette.lavender;
      }
    }

    Widget field(String label, TextEditingController c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary)),
              const SizedBox(height: 4),
              TextField(
                controller: c,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true),
              ),
            ],
          ),
        );

    return GlassCard(
      title: 'Final grade calculator',
      icon: Icons.calculate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _courseId,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Course'),
            items: [
              for (final c in courses)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => _selectCourse(v, courses, grades),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              field('Current %', _current),
              const SizedBox(width: 10),
              field('Final weight %', _weight),
              const SizedBox(width: 10),
              field('Target %', _target),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(message,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// Reusable destructive-action confirmation. Returns true if confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showGlassDialog<bool>(
    context,
    title: title,
    content: Text(message,
        style: const TextStyle(
            color: AppPalette.textSecondary, height: 1.4)),
    actions: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: AppPalette.danger,
            foregroundColor: const Color(0xFF15132B)),
        onPressed: () => Navigator.pop(dialogContext, true),
        child: const Text('Delete'),
      ),
    ],
  );
  return result ?? false;
}
