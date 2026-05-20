import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
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
          'Drag a card to rearrange (long-press on touch).',
      actions: [
        SoftButton(
          label: 'Customize',
          icon: Icons.tune_rounded,
          onTap: () => context.go('/customize'),
        ),
      ],
      child: const _ReorderableDashboard(),
    );
  }
}

/// Resolves a stable card id to its widget. Keep keys in sync with
/// [kDashboardCardIds]. Public so the Customize page can preview each card.
const dashboardCards = <String, Widget>{
  'clock': ClockCard(),
  'weather': WeatherCard(),
  'stats': _StatsStrip(),
  'countdown': CountdownCard(),
  'agenda': _AgendaCard(),
  'overview': TwoWeekOverviewCard(),
  'quickadd': QuickAddCard(),
  'dictionary': DictionaryCard(),
  'notes': NotesPreviewCard(),
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
    final hidden = ref.watch(dashboardHiddenProvider);
    final visible = [for (final id in order) if (!hidden.contains(id)) id];

    if (visible.isEmpty) {
      return const EmptyHint(
        'Every card is hidden. Tap “Customize” above to bring some back.',
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = responsiveColumns(c.maxWidth);
        final colWidth =
            (c.maxWidth - _spacing * (cols - 1)) / cols;

        final notifier = ref.read(dashboardOrderProvider.notifier);
        Widget slot(String id) => _DashSlot(
              id: id,
              feedbackWidth: colWidth,
              onBeginDrag: () => notifier.beginDrag(id),
              onMoveOver: notifier.moveOver,
              onEndDrag: notifier.endDrag,
              child: dashboardCards[id] ?? const SizedBox.shrink(),
            );

        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final id in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: _spacing),
                  child: slot(id),
                ),
            ],
          );
        }

        final buckets = List.generate(cols, (_) => <Widget>[]);
        for (var i = 0; i < visible.length; i++) {
          buckets[i % cols].add(Padding(
            padding: const EdgeInsets.only(bottom: _spacing),
            child: slot(visible[i]),
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
    required this.onBeginDrag,
    required this.onMoveOver,
    required this.onEndDrag,
  });

  final String id;
  final Widget child;
  final double feedbackWidth;
  final VoidCallback onBeginDrag;
  final void Function(String target) onMoveOver;
  final Future<void> Function() onEndDrag;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onMove: (_) => onMoveOver(id),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<String>(
          data: id,
          onDragStarted: onBeginDrag,
          onDragEnd: onEndDrag,
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
        .watch(upcomingTasksProvider)
        .where((t) => t.due!.difference(DateTime.now()).inDays <= 3)
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
        .watch(tasksProvider)
        .where((t) => !t.done && t.due != null && sameDay(t.due!))
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
                    leading: Icon(
                        a.isAssignment
                            ? Icons.school_rounded
                            : Icons.flag_outlined,
                        color: AppPalette.peach,
                        size: 20),
                    title: Text(a.title),
                    subtitle:
                        Text(a.isAssignment ? 'Assignment due today' : 'Due today'),
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

/// Unified to-do + assignments list (the two cards were merged).
class _TasksCard extends ConsumerWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesById = ref.watch(coursesByIdProvider);
    final folders = ref.watch(foldersProvider);

    String? courseIdFor(TaskItem t) {
      if (t.courseId != null) return t.courseId;
      if (t.folderId == null) return null;
      for (final f in folders) {
        if (f.id == t.folderId) return f.courseId;
      }
      return null;
    }

    final open = ref.watch(tasksProvider).where((t) => !t.done).toList()
      ..sort((a, b) {
        if ((a.due == null) != (b.due == null)) return a.due == null ? 1 : -1;
        if (a.due != null && b.due != null) {
          final byDue = a.due!.compareTo(b.due!);
          if (byDue != 0) return byDue;
        }
        return b.priority.index.compareTo(a.priority.index);
      });
    final list = open.take(6).toList();

    return GlassCard(
      title: 'To-do & assignments',
      icon: Icons.checklist_rounded,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final t = await showTaskDialog(context,
              folders: ref.read(foldersProvider),
              courses: ref.read(coursesProvider),
              categories: ref.read(gradeCategoriesProvider));
          if (t != null) ref.read(tasksProvider.notifier).save(t);
        },
      ),
      child: list.isEmpty
          ? const EmptyHint('All caught up. Nice work!')
          : Column(
              children: [
                for (final t in list)
                  InkWell(
                    onTap: () => ref
                        .read(tasksProvider.notifier)
                        .save(t.copyWith(done: true)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(
                              t.isAssignment
                                  ? Icons.school_rounded
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: t.isAssignment
                                  ? (coursesById[courseIdFor(t)]?.color ??
                                      AppPalette.lavender)
                                  : AppPalette.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(t.title),
                                if (t.due != null)
                                  Text('Due ${relativeDay(t.due!)}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color:
                                              AppPalette.textSecondary)),
                              ],
                            ),
                          ),
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
