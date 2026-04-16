import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import '../../models/course.dart';
import '../../models/institution.dart';
import '../../models/semester.dart';
import '../../providers/grades_provider.dart';
import 'add_course_dialog.dart';
import 'manage_grades_dialog.dart';

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
    final institutions = provider.institutions;

    return Scaffold(
      body: Column(
        children: [
          _GpaBanner(
            gpa: provider.gpa,
            totalCredits: provider.totalCredits,
            onManage: () => showManageGradesDialog(context),
          ),
          Expanded(
            child: courses.isEmpty
                ? _EmptyState(onAdd: () => _showAddDialog(context))
                : _CourseList(
                    provider: provider,
                    institutions: institutions,
                    courses: courses,
                    gradeColor: _gradeColor,
                    onEdit: (c) => _showAddDialog(context, c),
                    onDelete: (id) =>
                        context.read<GradesProvider>().removeCourse(id),
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

// ── GPA Banner ────────────────────────────────────────────────────────────────

class _GpaBanner extends StatelessWidget {
  final double gpa;
  final double totalCredits;
  final VoidCallback onManage;

  const _GpaBanner({
    required this.gpa,
    required this.totalCredits,
    required this.onManage,
  });

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
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
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
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
              ],
            ),
            progressColor: color,
            backgroundColor:
                theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cumulative GPA',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '${totalCredits.toStringAsFixed(0)} credit hours (GPA-counted)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Manage institutions & semesters',
            onPressed: onManage,
          ),
        ],
      ),
    );
  }
}

// ── Grouped course list ───────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  final GradesProvider provider;
  final List<Institution> institutions;
  final List<Course> courses;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;

  const _CourseList({
    required this.provider,
    required this.institutions,
    required this.courses,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final uncategorized = provider.uncategorizedCourses;

    return ListView(
      padding: const EdgeInsets.only(bottom: 88), // room for FAB
      children: [
        // One section per institution
        for (final inst in institutions)
          _InstitutionSection(
            institution: inst,
            provider: provider,
            gradeColor: gradeColor,
            onEdit: onEdit,
            onDelete: onDelete,
          ),

        // Courses with no institution assigned
        if (uncategorized.isNotEmpty)
          _UncategorizedSection(
            courses: uncategorized,
            gradeColor: gradeColor,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

// ── Institution section ───────────────────────────────────────────────────────

class _InstitutionSection extends StatelessWidget {
  final Institution institution;
  final GradesProvider provider;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;

  const _InstitutionSection({
    required this.institution,
    required this.provider,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semesters =
        provider.semestersForInstitution(institution.id);
    final unsorted =
        provider.unsortedCoursesForInstitution(institution.id);
    final gpa = provider.gpaForInstitution(institution.id);
    final scale = institution.gpaScale;

    final gpaColor = gpa >= (scale * 0.875)
        ? Colors.green
        : gpa >= (scale * 0.75)
            ? Colors.lightGreen
            : gpa >= (scale * 0.5)
                ? Colors.orange
                : Colors.red;

    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          gpa.toStringAsFixed(2),
          style: theme.textTheme.labelLarge?.copyWith(
              color: gpaColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(institution.name,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '/ ${scale.toStringAsFixed(1)} GPA scale',
        style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
      ),
      children: [
        // Semester sub-sections
        for (final sem in semesters)
          _SemesterSection(
            semester: sem,
            courses: provider.coursesForSemester(sem.id),
            semesterGpa: provider.gpaForSemester(sem.id),
            gradeColor: gradeColor,
            onEdit: onEdit,
            onDelete: onDelete,
          ),

        // Courses in this institution with no semester
        if (unsorted.isNotEmpty)
          _CourseGroup(
            label: 'Unsorted',
            courses: unsorted,
            gradeColor: gradeColor,
            onEdit: onEdit,
            onDelete: onDelete,
            labelColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}

// ── Semester sub-section ──────────────────────────────────────────────────────

class _SemesterSection extends StatelessWidget {
  final Semester semester;
  final List<Course> courses;
  final double semesterGpa;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;

  const _SemesterSection({
    required this.semester,
    required this.courses,
    required this.semesterGpa,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding:
          const EdgeInsets.only(left: 32, right: 16, top: 2, bottom: 2),
      leading: Icon(Icons.calendar_today_outlined,
          size: 18,
          color: theme.colorScheme.primary.withValues(alpha: 0.7)),
      title: Text(semester.name,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: courses.isEmpty
          ? null
          : Text(
              'GPA: ${semesterGpa.toStringAsFixed(2)}  •  ${courses.length} course${courses.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.5)),
            ),
      children: [
        if (courses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
            child: Text('No courses in this semester.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4))),
          )
        else
          _CourseCardList(
            courses: courses,
            gradeColor: gradeColor,
            onEdit: onEdit,
            onDelete: onDelete,
            indent: 16,
          ),
      ],
    );
  }
}

// ── Uncategorized section ─────────────────────────────────────────────────────

class _UncategorizedSection extends StatelessWidget {
  final List<Course> courses;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;

  const _UncategorizedSection({
    required this.courses,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CourseGroup(
      label: 'Uncategorized',
      courses: courses,
      gradeColor: gradeColor,
      onEdit: onEdit,
      onDelete: onDelete,
      labelColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );
  }
}

// ── Labelled group (unsorted / uncategorized) ─────────────────────────────────

class _CourseGroup extends StatelessWidget {
  final String label;
  final List<Course> courses;
  final Color labelColor;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;

  const _CourseGroup({
    required this.label,
    required this.courses,
    required this.labelColor,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 8, 16, 4),
          child: Text(label.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: labelColor, letterSpacing: 1.2)),
        ),
        _CourseCardList(
          courses: courses,
          gradeColor: gradeColor,
          onEdit: onEdit,
          onDelete: onDelete,
          indent: 16,
        ),
      ],
    );
  }
}

// ── Flat list of course cards ─────────────────────────────────────────────────

class _CourseCardList extends StatelessWidget {
  final List<Course> courses;
  final Color Function(double) gradeColor;
  final void Function(Course) onEdit;
  final void Function(String) onDelete;
  final double indent;

  const _CourseCardList({
    required this.courses,
    required this.gradeColor,
    required this.onEdit,
    required this.onDelete,
    this.indent = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 0, 16, 8),
      child: Column(
        children: [
          for (int i = 0; i < courses.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _CourseCard(
              course: courses[i],
              gradeColor: gradeColor(courses[i].gradePercent),
              onEdit: () => onEdit(courses[i]),
              onDelete: () => onDelete(courses[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Course Card ───────────────────────────────────────────────────────────────

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
            // Grade badge
            Container(
              width: 52,
              height: 52,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(course.name,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      if (!course.includeInGpa)
                        Tooltip(
                          message: 'Excluded from GPA',
                          child: Icon(Icons.block_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${course.gradePercent.toStringAsFixed(1)}%  •  ${course.credits.toStringAsFixed(0)} cr  •  ${course.gpaPoints.toStringAsFixed(1)} pts',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6)),
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
                              backgroundColor:
                                  theme.colorScheme.error),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined,
              size: 64,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.3)),
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
    );
  }
}
