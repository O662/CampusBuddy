import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import '../../models/course.dart';
import '../../providers/grades_provider.dart';
import 'add_course_dialog.dart';

class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  Color _gradeColor(double percent) {
    if (percent >= 90) return Colors.green;
    if (percent >= 80) return Colors.lightGreen;
    if (percent >= 70) return Colors.orange;
    if (percent >= 60) return Colors.deepOrange;
    return Colors.red;
  }

  Future<void> _showAddDialog(BuildContext context, [Course? existing]) async {
    final result = await showDialog<Course>(
      context: context,
      builder: (_) => AddCourseDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;
    final provider = context.read<GradesProvider>();
    if (existing != null) {
      await provider.updateCourse(result);
    } else {
      await provider.addCourse(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GradesProvider>();
    final courses = provider.courses;
    final gpa = provider.gpa;
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          _GpaBanner(gpa: gpa, totalCredits: provider.totalCredits),
          Expanded(
            child: courses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('No courses yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5))),
                        const SizedBox(height: 8),
                        Text('Tap + to add your first course',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: courses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final c = courses[i];
                      return _CourseCard(
                        course: c,
                        gradeColor: _gradeColor(c.gradePercent),
                        onEdit: () => _showAddDialog(context, c),
                        onDelete: () =>
                            context.read<GradesProvider>().removeCourse(c.id),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Course'),
      ),
    );
  }
}

class _GpaBanner extends StatelessWidget {
  final double gpa;
  final double totalCredits;

  const _GpaBanner({required this.gpa, required this.totalCredits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = gpa >= 3.5
        ? Colors.green
        : gpa >= 3.0
            ? Colors.lightGreen
            : gpa >= 2.0
                ? Colors.orange
                : Colors.red;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      child: Row(
        children: [
          CircularPercentIndicator(
            radius: 50,
            lineWidth: 8,
            percent: (gpa / 4.0).clamp(0.0, 1.0),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gpa.toStringAsFixed(2),
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: color),
                ),
                Text('GPA',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
            progressColor: color,
            backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cumulative GPA',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${totalCredits.toStringAsFixed(0)} credit hours tracked',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final Color gradeColor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CourseCard({
    required this.course,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: gradeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  course.letterGrade,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: gradeColor, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${course.gradePercent.toStringAsFixed(1)}%  •  ${course.credits.toStringAsFixed(0)} credits  •  ${course.gpaPoints.toStringAsFixed(1)} pts',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              color: theme.colorScheme.error,
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Remove Course'),
                    content: Text(
                        'Remove "${course.name}" from your grade tracker?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Remove')),
                    ],
                  ),
                ).then((confirmed) {
                  if (confirmed == true) onDelete();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
