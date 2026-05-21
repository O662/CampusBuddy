import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// A class's own page: live grade, per-class grading criteria, weighted
/// categories, extra credit, and every grade item with inline editing.
class CourseDetailPage extends ConsumerWidget {
  const CourseDetailPage({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref
        .watch(coursesProvider)
        .where((c) => c.id == courseId)
        .firstOrNull;

    if (course == null) {
      return PageBody(
        title: 'Course',
        subtitle: 'This class no longer exists.',
        actions: [
          SoftButton(
            label: 'Back to grades',
            icon: Icons.arrow_back_rounded,
            onTap: () => context.go('/grades'),
          ),
        ],
        child: GlassContainer(
          child: const EmptyHint('It may have been deleted.',
              icon: Icons.school_outlined),
        ),
      );
    }

    final inst =
        ref.watch(institutionsByIdProvider)[course.institutionId];
    final allCats = ref.watch(gradeCategoriesProvider);
    final cats = [
      for (final c in allCats)
        if (c.courseId == course.id) c,
    ]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0
            ? byOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final entries = [
      for (final g in ref.watch(gradesProvider))
        if (g.courseId == course.id) g,
    ]..sort((a, b) => b.date.compareTo(a.date));

    final pct = courseWeightedPercent(course, allCats, entries);
    final earnedPoints = courseEarnedPoints(course, entries);
    final result =
        courseResult(course, inst, pct, earnedPoints: earnedPoints);
    // Mirror the Grades page card: when the institution scores in GPA
    // points the per-grade value (e.g. "4.0") just echoes what the %
    // already says — show the course's credit hours instead.
    final hrs = course.creditHours;
    final hrsLabel =
        '${hrs.toStringAsFixed(hrs == hrs.roundToDouble() ? 0 : 1)} hrs';
    final showsGpaPoints =
        course.gradingMode == CourseGradingMode.graded &&
            (inst?.gradeSystem ?? GradeSystem.percent) ==
                GradeSystem.points;
    final secondary = showsGpaPoints ? hrsLabel : result;

    // Running grade history: cumulative weighted % of graded, non-extra
    // items in date order — a calm trend that leads into today's grade.
    final history = <double>[];
    {
      final chron = [
        for (final g in entries)
          if (g.isGraded) g,
      ]..sort((a, b) => a.date.compareTo(b.date));
      var w = 0.0, wp = 0.0;
      for (final g in chron) {
        // Honour the course's grading style so the trend matches the
        // headline average — explicit weights in percent mode, point
        // totals in points mode.
        final iw = course.weightOf(g);
        w += iw;
        wp += g.effectivePercent! * iw;
        if (w > 0) history.add(wp / w);
      }
    }

    return PageBody(
      title: course.name,
      subtitle:
          '${inst?.name ?? 'No institution'} · ${course.gradingMode.label}',
      actions: [
        SoftButton(
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          onTap: () => context.go('/grades'),
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'Add grade',
          filled: true,
          icon: Icons.add_chart_rounded,
          onTap: () async {
            final g = await showGradeDialog(
              context,
              courses: ref.read(coursesProvider),
              lockedCourseId: course.id,
              categories: ref.read(gradeCategoriesProvider),
            );
            if (g != null) ref.read(gradesProvider.notifier).upsert(g);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final bigText =
                  pct == null ? '—' : '${pct.toStringAsFixed(1)}%';
              final summary = GlassContainer(
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                          color: course.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current grade',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppPalette.textSecondary)),
                        const SizedBox(height: 4),
                        Text(bigText,
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: course.color)),
                        if (secondary != bigText) ...[
                          const SizedBox(height: 2),
                          Text(secondary,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.textSecondary)),
                        ],
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: history.length < 2
                          ? const SizedBox()
                          // Fixed height: a chart has no intrinsic size,
                          // and the row sits in an IntrinsicHeight. A
                          // tight SizedBox stops the intrinsic pass from
                          // recursing into fl_chart's LayoutBuilder.
                          : SizedBox(
                              height: 56,
                              child: _GradeSparkline(
                                  values: history,
                                  color: course.color),
                            ),
                    ),
                  ],
                ),
              );
              final extraCredit = _ExtraCreditCard(course: course);
              final criteria =
                  _CriteriaCard(course: course, institution: inst);

              if (c.maxWidth < 980) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: 16),
                    extraCredit,
                    const SizedBox(height: 16),
                    criteria,
                    const SizedBox(height: 16),
                    _CategoriesCard(
                        course: course,
                        categories: cats,
                        stretch: false),
                  ],
                );
              }
              // Equal-height columns. The left column splits its height
              // evenly between Current grade and Extra credit (a 16px
              // buffer between), so the two halves match each other and
              // their stack equals Grading criteria / Categories.
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: summary),
                          const SizedBox(height: 16),
                          Expanded(child: extraCredit),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: criteria),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _CategoriesCard(
                          course: course,
                          categories: cats,
                          stretch: true),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _AssignmentsCard(
              course: course, categories: cats, entries: entries),
        ],
      ),
    );
  }
}

/// Tiny grade-history line that dissolves toward the left (where the
/// current % and GPA sit), so the trend visually leads into today's grade.
class _GradeSparkline extends StatelessWidget {
  const _GradeSparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i]),
    ];
    final lo = (values.reduce((a, b) => a < b ? a : b) - 4)
        .clamp(0, 100)
        .toDouble();
    final hi = (values.reduce((a, b) => a > b ? a : b) + 4)
        .clamp(0, 100)
        .toDouble();
    // Opaque on the right (older history) → transparent on the left,
    // toward the numbers, so it fades as it "reaches" the current grade.
    const fade = [Alignment.centerRight, Alignment.centerLeft];

    return LineChart(
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
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            gradient: LinearGradient(
              begin: fade[0],
              end: fade[1],
              colors: [color, color.withValues(alpha: 0.0)],
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: fade[0],
                end: fade[1],
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-class grading scheme + letter cutoffs. Auto-saves: the mode
/// persists on change, numeric fields persist when focus leaves them.
/// (Extra credit is its own card.)
class _CriteriaCard extends ConsumerStatefulWidget {
  const _CriteriaCard({required this.course, required this.institution});

  final Course course;
  final Institution? institution;

  @override
  ConsumerState<_CriteriaCard> createState() => _CriteriaCardState();
}

class _CriteriaCardState extends ConsumerState<_CriteriaCard> {
  late CourseGradingMode _mode;
  late bool _byPoints;
  late final TextEditingController _pass;
  late final TextEditingController _a;
  late final TextEditingController _b;
  late final TextEditingController _c;
  late final TextEditingController _d;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _mode = c.gradingMode;
    _byPoints = c.cutoffsArePoints;
    _pass = TextEditingController(text: _fmt(c.passCutoff));
    _a = TextEditingController(text: _fmt(c.cutoffA));
    _b = TextEditingController(text: _fmt(c.cutoffB));
    _c = TextEditingController(text: _fmt(c.cutoffC));
    _d = TextEditingController(text: _fmt(c.cutoffD));
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  @override
  void dispose() {
    for (final t in [_pass, _a, _b, _c, _d]) {
      t.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController t, double fallback) =>
      double.tryParse(t.text.trim()) ?? fallback;

  /// Cap: 100 for percent cutoffs, a generous 1,000,000 for points so a
  /// huge-total syllabus (e.g. 5000 pts) isn't artificially clamped.
  double _bound(double v) =>
      v.clamp(0, _byPoints ? 1000000 : 100).toDouble();

  void _persist() {
    final c = widget.course;
    ref.read(coursesProvider.notifier).upsert(c.copyWith(
          gradingMode: _mode,
          cutoffsArePoints: _byPoints,
          passCutoff: _bound(_num(_pass, c.passCutoff)),
          cutoffA: _bound(_num(_a, c.cutoffA)),
          cutoffB: _bound(_num(_b, c.cutoffB)),
          cutoffC: _bound(_num(_c, c.cutoffC)),
          cutoffD: _bound(_num(_d, c.cutoffD)),
        ));
  }

  Widget _numField(String label, TextEditingController c) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textSecondary)),
            const SizedBox(height: 4),
            // Persist when focus leaves the field (clicked/tabbed away)
            // or the user submits.
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _persist();
              },
              child: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _persist(),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: _byPoints ? 'pts' : '%',
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final graded = _mode == CourseGradingMode.graded;
    final unit = _byPoints ? 'pts' : '%';
    return GlassCard(
      title: 'Grading criteria',
      icon: Icons.rule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<CourseGradingMode>(
            initialValue: _mode,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Grading mode'),
            items: [
              for (final m in CourseGradingMode.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (v) => setState(() {
              _mode = v ?? _mode;
              _persist();
            }),
          ),
          const SizedBox(height: 12),
          // Percent vs points cutoff style — the values stay in their
          // controllers so the user can review/edit them after switching.
          Row(
            children: [
              const Text('Cutoffs in',
                  style: TextStyle(
                      fontSize: 12, color: AppPalette.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<bool>(
                  initialValue: _byPoints,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF241F45),
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(
                        value: false, child: Text('Percent (e.g. 90%)')),
                    DropdownMenuItem(
                        value: true,
                        child: Text('Points (e.g. 1200 pts)')),
                  ],
                  onChanged: (v) => setState(() {
                    _byPoints = v ?? _byPoints;
                    _persist();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (graded) ...[
            Text('Letter cutoffs (minimum $unit)',
                style: const TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                _numField('A ≥', _a),
                const SizedBox(width: 8),
                _numField('B ≥', _b),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _numField('C ≥', _c),
                const SizedBox(width: 8),
                _numField('D ≥', _d),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.institution == null
                  ? 'Below D ≥ is an F.'
                  : 'Shown as ${widget.institution!.gradeSystem.label.toLowerCase()}; '
                      'below D ≥ is an F.',
              style: const TextStyle(
                  fontSize: 11, color: AppPalette.textFaint),
            ),
            if (_byPoints) ...[
              const SizedBox(height: 4),
              const Text(
                'Letter is decided by total earned points across this '
                'class, not the running %.',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.textFaint),
              ),
            ],
          ] else
            Row(
              children: [
                _numField(
                    _mode == CourseGradingMode.passFail
                        ? 'Pass at ≥ $unit'
                        : 'Satisfactory at ≥ $unit',
                    _pass),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
          const SizedBox(height: 10),
          const Text('Changes save automatically.',
              style:
                  TextStyle(fontSize: 11, color: AppPalette.textFaint)),
        ],
      ),
    );
  }
}

enum _XcPhase { none, choosing, editing }

/// Course-level extra credit / curve. Starts as a button; the user picks
/// points vs percentage, then types a value that auto-saves on blur.
class _ExtraCreditCard extends ConsumerStatefulWidget {
  const _ExtraCreditCard({required this.course});

  final Course course;

  @override
  ConsumerState<_ExtraCreditCard> createState() =>
      _ExtraCreditCardState();
}

class _ExtraCreditCardState extends ConsumerState<_ExtraCreditCard> {
  late final TextEditingController _xc;
  late bool _isPoints;
  late _XcPhase _phase;

  @override
  void initState() {
    super.initState();
    final v = widget.course.extraCreditPct;
    _isPoints = widget.course.extraCreditIsPoints;
    _xc = TextEditingController(
        text: v == 0
            ? ''
            : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1));
    _phase = v != 0 ? _XcPhase.editing : _XcPhase.none;
  }

  @override
  void dispose() {
    _xc.dispose();
    super.dispose();
  }

  void _persist() {
    final c = widget.course;
    ref.read(coursesProvider.notifier).upsert(c.copyWith(
          extraCreditPct:
              (double.tryParse(_xc.text.trim()) ?? 0).clamp(0, 1000),
          extraCreditIsPoints: _isPoints,
        ));
  }

  @override
  Widget build(BuildContext context) {
    const hint = Text(
      'Per-assignment extra credit is set on each grade item.',
      style: TextStyle(fontSize: 11, color: AppPalette.textFaint),
    );

    Widget body;
    switch (_phase) {
      case _XcPhase.none:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SoftButton(
                label: 'Add extra credit / curve',
                icon: Icons.add_rounded,
                onTap: () =>
                    setState(() => _phase = _XcPhase.choosing),
              ),
            ),
            const SizedBox(height: 10),
            hint,
          ],
        );
      case _XcPhase.choosing:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Is it points or a percentage?',
                style: TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary)),
            const SizedBox(height: 10),
            Row(
              children: [
                SoftButton(
                  label: 'Points',
                  icon: Icons.tag_rounded,
                  onTap: () => setState(() {
                    _isPoints = true;
                    _phase = _XcPhase.editing;
                  }),
                ),
                const SizedBox(width: 10),
                SoftButton(
                  label: 'Percentage',
                  icon: Icons.percent_rounded,
                  onTap: () => setState(() {
                    _isPoints = false;
                    _phase = _XcPhase.editing;
                  }),
                ),
              ],
            ),
          ],
        );
      case _XcPhase.editing:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_isPoints ? 'Points' : 'Percentage',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textSecondary)),
                const Spacer(),
                InkWell(
                  onTap: () =>
                      setState(() => _phase = _XcPhase.choosing),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('Change',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.accent,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) _persist();
              },
              child: TextField(
                controller: _xc,
                keyboardType: TextInputType.number,
                autofocus: _xc.text.isEmpty,
                onSubmitted: (_) => _persist(),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: _isPoints ? 'pts' : '%',
                ),
              ),
            ),
            const SizedBox(height: 8),
            hint,
          ],
        );
    }

    return GlassCard(
      title: 'Extra credit / curve',
      icon: Icons.star_rounded,
      child: body,
    );
  }
}

/// Built on a raw [GlassContainer] (not [GlassCard]) so the weight-total
/// footer can be pinned to the bottom with a [Spacer] when the card is
/// height-stretched (wide layout). [stretch] is passed by the parent — no
/// LayoutBuilder here, which would crash inside the IntrinsicHeight row.
class _CategoriesCard extends ConsumerWidget {
  const _CategoriesCard({
    required this.course,
    required this.categories,
    required this.stretch,
  });

  final Course course;
  final List<GradeCategory> categories;
  final bool stretch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total =
        categories.fold<double>(0, (s, c) => s + c.weightPercent);

    final header = Row(
      children: [
        const Icon(Icons.donut_small_rounded,
            size: 18, color: AppPalette.lavender),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Categories',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        SoftButton(
          label: 'Add',
          onTap: () async {
            final c =
                await showCategoryDialog(context, courseId: course.id);
            if (c != null) {
              // New category goes to the bottom of the list.
              ref
                  .read(gradeCategoriesProvider.notifier)
                  .upsert(c.copyWith(order: categories.length));
            }
          },
        ),
      ],
    );

    final footer = Text(
      total == 100
          ? 'Weights total 100%.'
          : 'Weights total ${total.toStringAsFixed(0)}% — the '
              'remaining ${(100 - total).toStringAsFixed(0)}% '
              'covers uncategorized items'
              '${total > 100 ? ' (over 100%, will be normalized)' : ''}.',
      style:
          const TextStyle(fontSize: 11, color: AppPalette.textFaint),
    );

    // Drag [moving] to where [target] sits, then renumber order indices
    // and persist only the ones that changed.
    void reorder(GradeCategory moving, GradeCategory target) {
      if (moving.id == target.id) return;
      final list = [...categories]; // already sorted by order
      final from = list.indexWhere((x) => x.id == moving.id);
      final ti = list.indexWhere((x) => x.id == target.id);
      if (from < 0 || ti < 0 || from == ti) return;
      list.removeAt(from);
      final insertAt = from < ti
          ? list.indexWhere((x) => x.id == target.id) + 1
          : list.indexWhere((x) => x.id == target.id);
      list.insert(insertAt, moving);
      final changed = [
        for (var i = 0; i < list.length; i++)
          if (list[i].order != i) list[i].copyWith(order: i),
      ];
      if (changed.isNotEmpty) {
        ref.read(gradeCategoriesProvider.notifier).upsertAll(changed);
      }
    }

    Widget catRow(GradeCategory c) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator_rounded,
                size: 18, color: AppPalette.textFaint),
            const SizedBox(width: 8),
            Expanded(
                child: Text(c.name,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600))),
            GlassChip(
                label: '${c.weightPercent.toStringAsFixed(0)}%',
                color: AppPalette.lavender),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  size: 18, color: AppPalette.textSecondary),
              color: const Color(0xFF241F45),
              tooltip: 'Category options',
              onSelected: (v) async {
                if (v == 'edit') {
                  final e = await showCategoryDialog(context,
                      courseId: course.id, existing: c);
                  if (e != null) {
                    ref
                        .read(gradeCategoriesProvider.notifier)
                        .upsert(e);
                  }
                } else if (v == 'delete') {
                  final ok = await confirmDelete(
                    context,
                    title: 'Delete ${c.name}?',
                    message:
                        'Items in this category become uncategorized.',
                  );
                  if (ok) {
                    ref
                        .read(gradeCategoriesProvider.notifier)
                        .remove(c.id);
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

      return DragTarget<GradeCategory>(
        onWillAcceptWithDetails: (d) => d.data.id != c.id,
        onAcceptWithDetails: (d) => reorder(d.data, c),
        builder: (ctx, cand, rej) {
          final hovering = cand.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
            ),
            child: AdaptiveDraggable<GradeCategory>(
              data: c,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.92,
                  child: SizedBox(
                      width: 300,
                      child: GlassContainer(child: content)),
                ),
              ),
              childWhenDragging:
                  Opacity(opacity: 0.3, child: content),
              child: content,
            ),
          );
        },
      );
    }

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: (stretch && categories.isNotEmpty)
            ? MainAxisSize.max
            : MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: 16),
          if (categories.isEmpty)
            const EmptyHint(
                'No categories — the grade is a flat weighted average '
                'of all items.')
          else ...[
            for (final c in categories) catRow(c),
            const SizedBox(height: 4),
            const Text('Drag to reorder.',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.textFaint)),
            // Push the total to the very bottom when the card is
            // stretched to match its siblings; otherwise a small gap.
            if (stretch) const Spacer() else const SizedBox(height: 14),
            const Divider(height: 18),
            footer,
          ],
        ],
      ),
    );
  }
}

class _AssignmentsCard extends ConsumerWidget {
  const _AssignmentsCard({
    required this.course,
    required this.categories,
    required this.entries,
  });

  final Course course;
  final List<GradeCategory> categories;
  final List<GradeEntry> entries;

  Future<void> _edit(
      BuildContext context, WidgetRef ref, GradeEntry g) async {
    final e = await showGradeDialog(
      context,
      courses: ref.read(coursesProvider),
      lockedCourseId: course.id,
      existing: g,
      categories: ref.read(gradeCategoriesProvider),
    );
    if (e != null) ref.read(gradesProvider.notifier).upsert(e);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, GradeEntry g) async {
    final linkedTask =
        g.id.startsWith('task-') ? g.id.substring('task-'.length) : null;
    final ok = await confirmDelete(
      context,
      title: 'Delete grade?',
      message: linkedTask == null
          ? '"${g.title}" will be permanently removed.'
          : '"${g.title}" will be removed and its matching to-do/'
              'assignment deleted too.',
    );
    if (!ok) return;
    ref.read(gradesProvider.notifier).remove(g.id);
    if (linkedTask != null) {
      ref.read(tasksProvider.notifier).remove(linkedTask);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by category id; null + unknown ids fall into "Uncategorized".
    final catIds = {for (final c in categories) c.id};
    // Implicit Uncategorized weight = whatever's left after the user's
    // named categories. Show the bucket whenever there's a meaningful
    // slice still uncovered, or whenever stray items exist — so the
    // section never silently swallows real assignments.
    final categoryWeightTotal =
        categories.fold<double>(0, (s, c) => s + c.weightPercent);
    final uncategorizedWeight =
        (100 - categoryWeightTotal).clamp(0, 100);
    // Per-entry chips display the item's own % (0–100), so the green/
    // amber threshold needs to be in percent too. In points-mode
    // courses `cutoffC` holds a point total (e.g. 700 pts) and would
    // make every chip read amber — fall back to a fixed 70 % so the
    // chip stays a meaningful per-assignment pass hint.
    final perEntryPassPct = course.cutoffsArePoints ? 70.0 : course.cutoffC;
    Widget row(GradeEntry g) {
      // The % that counts: raw score plus this item's own extra credit.
      final pct = g.effectivePercent;
      final ecv = g.extraCreditValue ?? 0;
      final hasEc = g.extraCredit && ecv != 0;
      final ecChip = GlassChip(
        label: '+${ecv.toStringAsFixed(ecv == ecv.roundToDouble() ? 0 : 1)}'
            '${g.extraCreditIsPoints ? ' pts' : '%'}',
        color: AppPalette.peach,
      );
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _edit(context, ref, g),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Text(g.title)),
                    if (hasEc) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppPalette.peach),
                    ],
                  ],
                ),
              ),
              if (g.isBonusOnly)
                // A stand-alone curve with no score of its own.
                ecChip
              else ...[
                if (hasEc) ...[
                  ecChip,
                  const SizedBox(width: 8),
                ],
                Text(
                    g.isGraded
                        ? '${g.earned!.toStringAsFixed(0)}/${g.total.toStringAsFixed(0)}'
                        : '—  /${g.total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: AppPalette.textSecondary)),
                const SizedBox(width: 10),
                GlassChip(
                  label:
                      pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                  color: pct == null
                      ? AppPalette.textFaint
                      : (pct >= perEntryPassPct
                          ? AppPalette.success
                          : AppPalette.warning),
                ),
              ],
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () => _delete(context, ref, g),
              ),
            ],
          ),
        ),
      );
    }

    Widget section(String title, List<GradeEntry> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary)),
          ),
          for (final g in items) row(g),
        ],
      );
    }

    return GlassCard(
      title: 'Assignments',
      icon: Icons.assignment_outlined,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final g = await showGradeDialog(
            context,
            courses: ref.read(coursesProvider),
            lockedCourseId: course.id,
            categories: ref.read(gradeCategoriesProvider),
          );
          if (g != null) ref.read(gradesProvider.notifier).upsert(g);
        },
      ),
      child: entries.isEmpty
          ? const EmptyHint('No grade items yet. Tap Add to log one.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in categories)
                  section(
                    '${c.name} · ${c.weightPercent.toStringAsFixed(0)}%',
                    entries
                        .where((g) => g.categoryId == c.id)
                        .toList(),
                  ),
                // Label the section with the implicit leftover weight
                // so its share is visible at a glance. `section()` hides
                // itself when there are no items, so a category set that
                // covers everything (no stray uncategorized assignments)
                // produces nothing here regardless of the percent.
                section(
                  'Uncategorized · '
                  '${uncategorizedWeight.toStringAsFixed(0)}%',
                  entries
                      .where((g) =>
                          g.categoryId == null ||
                          !catIds.contains(g.categoryId))
                      .toList(),
                ),
              ],
            ),
    );
  }
}
