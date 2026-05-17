import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'dashboard_state.dart';
import 'dictionary.dart';
import 'extra_cards.dart';
import 'tools.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';

    return PageBody(
      title: '$greeting, ${profile.name} 👋',
      subtitle: 'Here is everything on your plate today. '
          'Long-press a card to rearrange your dashboard.',
      child: const _ReorderableDashboard(),
    );
  }
}

/// Resolves a stable card id to its widget. Keep keys in sync with
/// [kDashboardCardIds].
const _dashboardCards = <String, Widget>{
  'clock': ClockCard(),
  'weather': WeatherCard(),
  'stats': _StatsStrip(),
  'countdown': CountdownCard(),
  'agenda': _AgendaCard(),
  'overview': TwoWeekOverviewCard(),
  'assignments': _UpcomingAssignmentsCard(),
  'quickadd': QuickAddCard(),
  'dictionary': DictionaryCard(),
  'notes': StickyNoteCard(),
  'grades': _GradeProgressCard(),
  'tasks': _TasksCard(),
  'events': _EventsCard(),
  'word': WordOfDayCard(),
  'quote': QuoteCard(),
};

/// The dashboard grid with long-press drag-to-reorder. Cards are laid out
/// into balanced columns (same masonry as [CardGrid]); dropping one card
/// onto another reorders the persisted list via [dashboardOrderProvider].
class _ReorderableDashboard extends ConsumerWidget {
  const _ReorderableDashboard();

  static const _spacing = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(dashboardOrderProvider);

    return LayoutBuilder(
      builder: (context, c) {
        final cols = responsiveColumns(c.maxWidth);
        final colWidth =
            (c.maxWidth - _spacing * (cols - 1)) / cols;

        Widget slot(String id) => _DashSlot(
              id: id,
              feedbackWidth: colWidth,
              onReorder: (moving, target) => ref
                  .read(dashboardOrderProvider.notifier)
                  .reorder(moving, target),
              child: _dashboardCards[id] ?? const SizedBox.shrink(),
            );

        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final id in order)
                Padding(
                  padding: const EdgeInsets.only(bottom: _spacing),
                  child: slot(id),
                ),
            ],
          );
        }

        final buckets = List.generate(cols, (_) => <Widget>[]);
        for (var i = 0; i < order.length; i++) {
          buckets[i % cols].add(Padding(
            padding: const EdgeInsets.only(bottom: _spacing),
            child: slot(order[i]),
          ));
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cols; i++) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buckets[i],
                ),
              ),
              if (i != cols - 1) const SizedBox(width: _spacing),
            ],
          ],
        );
      },
    );
  }
}

class _DashSlot extends StatelessWidget {
  const _DashSlot({
    required this.id,
    required this.child,
    required this.feedbackWidth,
    required this.onReorder,
  });

  final String id;
  final Widget child;
  final double feedbackWidth;
  final void Function(String moving, String target) onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onAcceptWithDetails: (d) => onReorder(d.data, id),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return LongPressDraggable<String>(
          data: id,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.9,
              child: SizedBox(width: feedbackWidth, child: child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: hovering
                    ? AppPalette.accent.withValues(alpha: 0.7)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallGradeProvider);
    final dueCards = ref.watch(dueCardCountProvider);
    final openTasks =
        ref.watch(tasksProvider).where((t) => !t.done).length;
    final dueSoon = ref
        .watch(upcomingAssignmentsProvider)
        .where((a) =>
            a.dueDate.difference(DateTime.now()).inDays <= 3)
        .length;

    Widget stat(IconData i, String v, String l, Color c) => Expanded(
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Column(
              children: [
                Icon(i, color: c, size: 22),
                const SizedBox(height: 8),
                Text(v,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(l,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: AppPalette.textSecondary)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        stat(Icons.school_rounded,
            overall == null ? '—' : '${overall.toStringAsFixed(0)}%',
            'Overall grade', AppPalette.mint),
        const SizedBox(width: 12),
        stat(Icons.assignment_outlined, '$dueSoon', 'Due in 3 days',
            AppPalette.peach),
        const SizedBox(width: 12),
        stat(Icons.checklist_rounded, '$openTasks', 'Open tasks',
            AppPalette.periwinkle),
        const SizedBox(width: 12),
        stat(Icons.style_rounded, '$dueCards', 'Cards to review',
            AppPalette.lavender),
      ],
    );
  }
}

class _AgendaCard extends ConsumerWidget {
  const _AgendaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    bool sameDay(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    final events = ref.watch(eventsProvider).where((e) => sameDay(e.start)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final due = ref
        .watch(assignmentsProvider)
        .where((a) => !a.isDone && sameDay(a.dueDate))
        .toList();

    return GlassCard(
      title: "Today's agenda",
      icon: Icons.today_rounded,
      child: (events.isEmpty && due.isEmpty)
          ? const EmptyHint('Nothing scheduled — enjoy the calm.')
          : Column(
              children: [
                for (final e in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(e.type.icon,
                        color: AppPalette.lavender, size: 20),
                    title: Text(e.title),
                    subtitle: Text(
                        '${TimeOfDay.fromDateTime(e.start).format(context)}'
                        '${e.location.isEmpty ? '' : ' · ${e.location}'}'),
                  ),
                for (final a in due)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.flag_outlined,
                        color: AppPalette.peach, size: 20),
                    title: Text(a.title),
                    subtitle: const Text('Due today'),
                  ),
              ],
            ),
    );
  }
}

class _UpcomingAssignmentsCard extends ConsumerWidget {
  const _UpcomingAssignmentsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(upcomingAssignmentsProvider).take(5).toList();
    final courses = ref.watch(coursesByIdProvider);

    return GlassCard(
      title: 'Upcoming assignments',
      icon: Icons.assignment_outlined,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final a = await showAssignmentDialog(context,
              courses: ref.read(coursesProvider));
          if (a != null) ref.read(assignmentsProvider.notifier).upsert(a);
        },
      ),
      child: list.isEmpty
          ? const EmptyHint('No assignments yet. Add your first one!')
          : Column(
              children: [
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 36,
                          decoration: BoxDecoration(
                            color: a.courseId == null
                                ? AppPalette.textFaint
                                : courses[a.courseId]?.color ??
                                    AppPalette.textFaint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${courses[a.courseId]?.name ?? 'General'} · ~${a.estimatedMinutes}m',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        GlassChip(
                          label: relativeDay(a.dueDate),
                          color: a.dueDate
                                      .difference(DateTime.now())
                                      .inDays <=
                                  1
                              ? AppPalette.danger
                              : AppPalette.lavender,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _GradeProgressCard extends ConsumerWidget {
  const _GradeProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);
    final grades = ref.watch(gradesProvider);

    return GlassCard(
      title: 'Grade progress',
      icon: Icons.insights_rounded,
      child: courses.isEmpty
          ? const EmptyHint('Add courses on the Grades page.')
          : Column(
              children: [
                for (final c in courses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _GradeBar(
                      label: c.name,
                      color: c.color,
                      percent: courseGrade(grades, c.id),
                      target: c.targetGrade,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _GradeBar extends StatelessWidget {
  const _GradeBar({
    required this.label,
    required this.color,
    required this.percent,
    required this.target,
  });

  final String label;
  final Color color;
  final double? percent;
  final double target;

  @override
  Widget build(BuildContext context) {
    final p = (percent ?? 0) / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(
              percent == null ? 'No grades' : '${percent!.toStringAsFixed(1)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 9, color: Colors.white.withValues(alpha: 0.08)),
              FractionallySizedBox(
                widthFactor: p.clamp(0.0, 1.0),
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.7), color]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TasksCard extends ConsumerWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider).where((t) => !t.done).take(6).toList();
    return GlassCard(
      title: 'Tasks',
      icon: Icons.checklist_rounded,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final t = await showTaskDialog(context);
          if (t != null) ref.read(tasksProvider.notifier).upsert(t);
        },
      ),
      child: tasks.isEmpty
          ? const EmptyHint('All caught up. Nice work!')
          : Column(
              children: [
                for (final t in tasks)
                  InkWell(
                    onTap: () => ref
                        .read(tasksProvider.notifier)
                        .upsert(t.copyWith(done: true)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          const Icon(Icons.radio_button_unchecked,
                              size: 18, color: AppPalette.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t.title)),
                          GlassChip(
                              label: t.priority.label,
                              color: t.priority.color),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EventsCard extends ConsumerWidget {
  const _EventsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref
        .watch(eventsProvider)
        .where((e) => e.start.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final next = events.take(5).toList();

    return GlassCard(
      title: 'Upcoming events',
      icon: Icons.event_available_rounded,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final e = await showEventDialog(context);
          if (e != null) ref.read(eventsProvider.notifier).upsert(e);
        },
      ),
      child: next.isEmpty
          ? const EmptyHint('No upcoming events.')
          : Column(
              children: [
                for (final e in next)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(e.type.icon,
                        color: AppPalette.mint, size: 20),
                    title: Text(e.title),
                    subtitle: Text(
                        '${relativeDay(e.start)} · ${TimeOfDay.fromDateTime(e.start).format(context)}'),
                  ),
              ],
            ),
    );
  }
}
