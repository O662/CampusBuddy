import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            final created = <Semester>[];
            final c = await showCourseDialog(context,
                institutions: ref.read(institutionsProvider),
                semesters: ref.read(semestersProvider),
                createdSemesters: created,
                onCreateSemester: (institutionId) => showSemesterDialog(
                    context, institutionId: institutionId));
            if (c != null) {
              // Commit inline-created semesters only now the course is
              // saved; discarded entirely if the dialog was cancelled.
              for (final s in created) {
                ref.read(semestersProvider.notifier).upsert(s);
              }
              ref.read(coursesProvider.notifier).upsert(c);
            }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The chart + calculator get their own row so they aren't
          // squeezed in among the course cards.
          CardGrid(
            children: [
              const _GradeTrendCard(),
              if (courses.isNotEmpty) const _FinalGradeCalculator(),
            ],
          ),
          const SizedBox(height: 20),
          // Courses section — mirrors the Academic history header style.
          Row(
            children: [
              const Icon(Icons.school_rounded,
                  size: 20, color: AppPalette.lavender),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Courses',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (courses.isNotEmpty)
            CardGrid(
              children: [
                for (final c in courses)
                  _CourseCard(
                    course: c,
                    entries: grades
                        .where((g) => g.courseId == c.id)
                        .toList()
                      ..sort((a, b) => b.date.compareTo(a.date)),
                  ),
              ],
            )
          else
            GlassContainer(
              child: const EmptyHint(
                  'No current courses yet. Create one to track live '
                  'grades, or log finished classes in Academic history '
                  'below.',
                  icon: Icons.school_outlined),
            ),
          const SizedBox(height: 20),
          const _AcademicHistory(),
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
    final cats = ref.watch(gradeCategoriesProvider);
    final avg = courseWeightedPercent(course, cats, entries);
    final inst = ref.watch(institutionsByIdProvider)[course.institutionId];
    final sem = course.semesterId == null
        ? null
        : ref
            .watch(semestersProvider)
            .where((s) => s.id == course.semesterId)
            .firstOrNull;
    final bigText = avg == null ? '—' : '${avg.toStringAsFixed(1)}%';
    final result = courseResult(course, inst, avg);

    Future<void> editCourse() async {
      final created = <Semester>[];
      final edited = await showCourseDialog(context,
          existing: course,
          institutions: ref.read(institutionsProvider),
          semesters: ref.read(semestersProvider),
          createdSemesters: created,
          onCreateSemester: (institutionId) => showSemesterDialog(
              context, institutionId: institutionId));
      if (edited != null) {
        // Commit inline-created semesters only now the course is saved.
        for (final s in created) {
          ref.read(semestersProvider.notifier).upsert(s);
        }
        ref.read(coursesProvider.notifier).upsert(edited);
      }
    }

    // The class's own categories, in their manual order — we summarise
    // grades by category instead of listing every assignment.
    final courseCats = [
      for (final c in cats)
        if (c.courseId == course.id) c,
    ]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0
            ? byOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final catIds = {for (final c in courseCats) c.id};
    final uncategorized = entries
        .where((g) =>
            g.categoryId == null || !catIds.contains(g.categoryId))
        .toList();

    // Weighted average of an iterable's graded items (same rule as the
    // course average: ungraded skipped, own extra credit baked in).
    double? catAvg(Iterable<GradeEntry> items) {
      var w = 0.0, wp = 0.0;
      for (final g in items) {
        if (!g.isGraded) continue;
        wp += g.effectivePercent! * g.weight;
        w += g.weight;
      }
      return w == 0 ? null : wp / w;
    }

    Widget summaryRow(String name, String? weightLabel, double? a) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (weightLabel != null) ...[
                Text(weightLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textSecondary)),
                const SizedBox(width: 10),
              ],
              GlassChip(
                label: a == null ? '—' : '${a.toStringAsFixed(0)}%',
                color: a == null
                    ? AppPalette.textFaint
                    : (a >= course.targetGrade
                        ? AppPalette.success
                        : AppPalette.warning),
              ),
            ],
          ),
        );

    return GlassContainer(
      onTap: () => context.go('/course/${course.id}'),
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
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bigText,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: course.color),
                  ),
                  if (result != bigText)
                    Text(
                      result,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textSecondary),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Course options',
                onSelected: (v) async {
                  if (v == 'edit') {
                    await editCourse();
                  } else if (v == 'delete') {
                    final n = entries.length;
                    final linked = entries
                        .where((g) => g.id.startsWith('task-'))
                        .length;
                    final linkedNote = linked == 0
                        ? ''
                        : ' $linked linked to-do'
                            "${linked == 1 ? '' : 's'} will be deleted "
                            'too.';
                    final ok = await confirmDelete(
                      context,
                      title: 'Delete ${course.name}?',
                      message: n == 0
                          ? 'This class will be removed.'
                          : 'This class and its $n grade'
                              "${n == 1 ? '' : 's'} will be permanently "
                              'removed.$linkedNote',
                    );
                    if (ok) {
                      final tasks = ref.read(tasksProvider.notifier);
                      for (final g in entries) {
                        ref.read(gradesProvider.notifier).remove(g.id);
                        if (g.id.startsWith('task-')) {
                          tasks.remove(g.id.substring('task-'.length));
                        }
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
          Builder(builder: (_) {
            final parts = [
              if (inst != null) inst.name,
              if (sem != null) sem.label,
            ].join(' · ');
            return Text(
                parts.isEmpty ? 'No semester set' : parts,
                style: const TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary));
          }),
          if (course.semesterId == null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: editCourse,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AppPalette.accent.withValues(alpha: 0.14),
                    border: Border.all(
                        color: AppPalette.accent.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_rounded,
                          size: 14, color: AppPalette.accent),
                      SizedBox(width: 6),
                      Text('Pin to a semester to track GPA',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.accent)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 24),
          if (courseCats.isEmpty && entries.isEmpty)
            const EmptyHint('No grades recorded yet.')
          else ...[
            for (final c in courseCats)
              summaryRow(
                c.name,
                '${c.weightPercent.toStringAsFixed(0)}%',
                catAvg(entries.where((g) => g.categoryId == c.id)),
              ),
            if (uncategorized.isNotEmpty)
              summaryRow(
                courseCats.isEmpty ? 'All grades' : 'Uncategorized',
                null,
                catAvg(uncategorized),
              ),
            const SizedBox(height: 6),
            const Text('Tap the class to see every grade.',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// Per-semester GPA with a running cumulative line, scoped to one
/// institution (picked via the header dropdown; defaults to the
/// institution of the most-recent semester). Credit-weighted.
class _GradeTrendCard extends ConsumerStatefulWidget {
  const _GradeTrendCard();

  @override
  ConsumerState<_GradeTrendCard> createState() => _GradeTrendCardState();
}

class _GradeTrendCardState extends ConsumerState<_GradeTrendCard> {
  String? _institutionId;

  @override
  Widget build(BuildContext context) {
    final insts = ref.watch(institutionsWithHistoryProvider);

    if (insts.isEmpty) {
      return const GlassCard(
        title: 'GPA by semester',
        icon: Icons.trending_up_rounded,
        child: EmptyHint(
            'Pin a course to a semester, or log past classes in Academic '
            'history, to see your GPA trend.',
            icon: Icons.show_chart_rounded),
      );
    }

    // Default to the latest semester's institution (insts is ordered
    // most-recent first); honour the user's pick while it still has data.
    final selectedId =
        (_institutionId != null && insts.any((i) => i.id == _institutionId))
            ? _institutionId!
            : insts.first.id;
    final series = ref.watch(gpaSeriesProvider(selectedId));

    final Widget? trailing = insts.length < 2
        ? null
        : Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppPalette.glassStroke),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isDense: true,
                dropdownColor: const Color(0xFF241F45),
                borderRadius: BorderRadius.circular(14),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary),
                icon: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.expand_more_rounded,
                      size: 18, color: AppPalette.textSecondary),
                ),
                items: [
                  for (final i in insts)
                    DropdownMenuItem(value: i.id, child: Text(i.name)),
                ],
                onChanged: (v) => setState(() => _institutionId = v),
              ),
            ),
          );

    Widget content;
    if (series.isEmpty) {
      content = const EmptyHint(
          'No classes recorded for this institution yet.',
          icon: Icons.show_chart_rounded);
    } else {
      final cumulative = series.last.cumulative;
      final maxPoint = series
          .map((p) => p.gpa > p.cumulative ? p.gpa : p.cumulative)
          .fold(4.0, (m, v) => v > m ? v : m);
      final maxY = (maxPoint.ceilToDouble()).clamp(4.0, 6.0);
      final semSpots = [
        for (var i = 0; i < series.length; i++)
          FlSpot(i.toDouble(), series[i].gpa),
      ];
      final cumSpots = [
        for (var i = 0; i < series.length; i++)
          FlSpot(i.toDouble(), series[i].cumulative),
      ];

      LineChartBarData bar(List<FlSpot> spots, Color c,
              {bool area = false}) =>
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: c,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: area,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.withValues(alpha: 0.25),
                  c.withValues(alpha: 0.0),
                ],
              ),
            ),
          );

      Widget legendDot(Color c, String label) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary)),
            ],
          );

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(cumulative.toStringAsFixed(3),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              const Text('cumulative GPA',
                  style: TextStyle(
                      fontSize: 12, color: AppPalette.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              legendDot(AppPalette.accent, 'Semester'),
              const SizedBox(width: 16),
              legendDot(AppPalette.mint, 'Cumulative'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    // Keep the tooltip inside the chart so edge points
                    // aren't clipped by the card.
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => const Color(0xFF241F45),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipBorder: const BorderSide(
                        color: AppPalette.glassStroke),
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    getTooltipItems: (touchedSpots) => [
                      for (final s in touchedSpots)
                        LineTooltipItem(
                          () {
                            final i = s.x.round();
                            final label =
                                (i >= 0 && i < series.length)
                                    ? series[i].semester.shortLabel
                                    : '';
                            final v = s.y.toStringAsFixed(3);
                            return s.barIndex == 1
                                ? 'Cumulative  $v'
                                : '$label · Semester  $v';
                          }(),
                          TextStyle(
                            color: s.barIndex == 1
                                ? AppPalette.mint
                                : AppPalette.accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                minX: 0,
                maxX: (series.length - 1).toDouble().clamp(0.0, 1e9),
                minY: 0,
                maxY: maxY.toDouble(),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppPalette.textFaint),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final i = v.round();
                        if (i < 0 || i >= series.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            series[i].semester.shortLabel,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppPalette.textFaint),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  bar(semSpots, AppPalette.accent, area: true),
                  bar(cumSpots, AppPalette.mint),
                ],
              ),
            ),
          ),
          if (series.length < 2) ...[
            const SizedBox(height: 10),
            const Text('Add another semester to see the trend.',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.textSecondary)),
          ],
        ],
      );
    }

    return GlassCard(
      title: 'GPA by semester',
      icon: Icons.trending_up_rounded,
      trailing: trailing,
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

String _gpaText(double? v) => v == null ? '—' : v.toStringAsFixed(3);

Color _gpaColor(double? v) {
  if (v == null) return AppPalette.textFaint;
  if (v >= 3.0) return AppPalette.success;
  if (v >= 2.0) return AppPalette.warning;
  return AppPalette.danger;
}

// ---------------------------------------------------------------------------
// Academic history: institutions → semesters → past classes. Entirely
// separate from the live Course/GradeEntry tracking above.
// ---------------------------------------------------------------------------

class _AcademicHistory extends ConsumerWidget {
  const _AcademicHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Order by attendance: the institution of the most recent semester
    // first. Schools with no semesters yet sink to the bottom (then by
    // name), so the list tracks where you've been, not the alphabet.
    final allSems = ref.watch(semestersProvider);
    int recency(Institution i) {
      var best = -1;
      for (final s in allSems) {
        if (s.institutionId == i.id && s.sortKey > best) {
          best = s.sortKey;
        }
      }
      return best;
    }

    final institutions = [...ref.watch(institutionsProvider)]
      ..sort((a, b) {
        final byRecency = recency(b).compareTo(recency(a));
        return byRecency != 0
            ? byRecency
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.history_edu_rounded,
                size: 20, color: AppPalette.lavender),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Academic history',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            SoftButton(
              label: 'Add institution',
              icon: Icons.account_balance_rounded,
              onTap: () async {
                final i = await showInstitutionDialog(context);
                if (i != null) {
                  ref.read(institutionsProvider.notifier).upsert(i);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (institutions.isEmpty)
          GlassContainer(
            child: const EmptyHint(
                'Add a school to log finished classes and chart your '
                'semester GPA.',
                icon: Icons.account_balance_outlined),
          )
        else
          for (final inst in institutions)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _InstitutionCard(
                  key: ValueKey(inst.id), institution: inst),
            ),
      ],
    );
  }
}

class _InstitutionCard extends ConsumerStatefulWidget {
  const _InstitutionCard({super.key, required this.institution});

  final Institution institution;

  @override
  ConsumerState<_InstitutionCard> createState() => _InstitutionCardState();
}

class _InstitutionCardState extends ConsumerState<_InstitutionCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final institution = widget.institution;
    final semesters = [
      for (final s in ref.watch(semestersProvider))
        if (s.institutionId == institution.id) s,
      // Most-recent semester first.
    ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    final allPast = ref.watch(pastCoursesProvider);
    final semIds = {for (final s in semesters) s.id};
    final instGpa = semesterGpa(
        allPast.where((p) => semIds.contains(p.semesterId)));

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 160),
                          turns: _expanded ? 0 : -0.25,
                          child: const Icon(Icons.expand_more_rounded,
                              size: 20,
                              color: AppPalette.textSecondary),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.account_balance_rounded,
                            size: 18, color: AppPalette.lavender),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(institution.name,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassChip(
                  label: 'GPA ${_gpaText(instGpa)}',
                  color: _gpaColor(instGpa)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Institution options',
                onSelected: (v) async {
                  if (v == 'edit') {
                    final e = await showInstitutionDialog(context,
                        existing: institution);
                    if (e != null) {
                      ref
                          .read(institutionsProvider.notifier)
                          .upsert(e);
                    }
                  } else if (v == 'delete') {
                    final n = allPast
                        .where((p) => semIds.contains(p.semesterId))
                        .length;
                    final ok = await confirmDelete(
                      context,
                      title: 'Delete ${institution.name}?',
                      message:
                          'This school, its ${semesters.length} semester'
                          "${semesters.length == 1 ? '' : 's'} and $n "
                          "class${n == 1 ? '' : 'es'} will be permanently "
                          'removed.',
                    );
                    if (ok) {
                      final pc =
                          ref.read(pastCoursesProvider.notifier);
                      for (final p in allPast) {
                        if (semIds.contains(p.semesterId)) {
                          pc.remove(p.id);
                        }
                      }
                      final sem =
                          ref.read(semestersProvider.notifier);
                      for (final s in semesters) {
                        sem.remove(s.id);
                      }
                      ref
                          .read(institutionsProvider.notifier)
                          .remove(institution.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined, size: 20),
                      title: Text('Edit institution'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete institution'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SoftButton(
                label: 'Add semester',
                icon: Icons.event_note_rounded,
                onTap: () async {
                  final s = await showSemesterDialog(context,
                      institutionId: institution.id);
                  if (s != null) {
                    ref.read(semestersProvider.notifier).upsert(s);
                  }
                },
              ),
            ),
            if (semesters.isNotEmpty) const Divider(height: 24),
            for (final s in semesters)
              _SemesterBlock(key: ValueKey(s.id), semester: s),
          ],
        ],
      ),
    );
  }
}

class _SemesterBlock extends ConsumerStatefulWidget {
  const _SemesterBlock({super.key, required this.semester});

  final Semester semester;

  @override
  ConsumerState<_SemesterBlock> createState() => _SemesterBlockState();
}

class _SemesterBlockState extends ConsumerState<_SemesterBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final semester = widget.semester;
    final classes = [
      for (final p in ref.watch(pastCoursesProvider))
        if (p.semesterId == semester.id) p,
    ]..sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final gpa = semesterGpa(classes);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 160),
                          turns: _expanded ? 0 : -0.25,
                          child: const Icon(Icons.expand_more_rounded,
                              size: 18,
                              color: AppPalette.textSecondary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(semester.label,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassChip(
                  label: 'GPA ${_gpaText(gpa)}',
                  color: _gpaColor(gpa)),
              IconButton(
                tooltip: 'Add class',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: () async {
                  final p = await showPastCourseDialog(context,
                      semesterId: semester.id);
                  if (p != null) {
                    ref.read(pastCoursesProvider.notifier).upsert(p);
                  }
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Semester options',
                onSelected: (v) async {
                  if (v == 'edit') {
                    final e = await showSemesterDialog(context,
                        institutionId: semester.institutionId,
                        existing: semester);
                    if (e != null) {
                      ref.read(semestersProvider.notifier).upsert(e);
                    }
                  } else if (v == 'delete') {
                    final ok = await confirmDelete(
                      context,
                      title: 'Delete ${semester.label}?',
                      message:
                          'This semester and its ${classes.length} '
                          "class${classes.length == 1 ? '' : 'es'} will "
                          'be permanently removed.',
                    );
                    if (ok) {
                      final pc =
                          ref.read(pastCoursesProvider.notifier);
                      for (final p in classes) {
                        pc.remove(p.id);
                      }
                      ref
                          .read(semestersProvider.notifier)
                          .remove(semester.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined, size: 20),
                      title: Text('Edit semester'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete semester'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Classes indented under their semester for readability.
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (classes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('No classes yet.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.textFaint)),
                    )
                  else
                    for (final p in classes) _PastCourseRow(course: p),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _PastCourseRow extends ConsumerWidget {
  const _PastCourseRow({required this.course});

  final PastCourse course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = course.creditHours;
    final creditLabel = credits == credits.roundToDouble()
        ? credits.toStringAsFixed(0)
        : credits.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(course.name)),
          Text('$creditLabel cr',
              style: const TextStyle(
                  fontSize: 12, color: AppPalette.textSecondary)),
          const SizedBox(width: 10),
          GlassChip(
              label: course.gradePoints.toStringAsFixed(1),
              color: _gpaColor(course.gradePoints)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz,
                size: 18, color: AppPalette.textSecondary),
            color: const Color(0xFF241F45),
            tooltip: 'Class options',
            onSelected: (v) async {
              if (v == 'edit') {
                final e = await showPastCourseDialog(context,
                    semesterId: course.semesterId, existing: course);
                if (e != null) {
                  ref.read(pastCoursesProvider.notifier).upsert(e);
                }
              } else if (v == 'delete') {
                final ok = await confirmDelete(
                  context,
                  title: 'Delete grade?',
                  message:
                      '"${course.name}" will be permanently removed.',
                );
                if (ok) {
                  ref
                      .read(pastCoursesProvider.notifier)
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
    );
  }
}

