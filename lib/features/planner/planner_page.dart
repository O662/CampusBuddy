import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/ics_import.dart';
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

/// Which calendar the planner's main panel shows.
enum _PlannerView { week, agenda, month, gantt }

/// One thing happening on a day — either a calendar [event] or a due
/// [task]/assignment. Used for the calendars' markers and the month
/// view's selected-day agenda.
class _Agenda {
  const _Agenda({
    required this.when,
    required this.color,
    this.event,
    this.task,
  });

  final DateTime when;
  final Color color;
  final EventItem? event;
  final TaskItem? task;
}

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

const _weekdayShort = {
  1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu',
  5: 'Fri', 6: 'Sat', 7: 'Sun',
};

/// Month-agenda subtitle for a task row: "Assignment due" / "Task due",
/// suffixed with a time when the user set one (so a 9:00 AM class
/// quiz reads "Assignment due · 9:00 AM" instead of hiding the time).
String _taskAgendaSubtitle(TaskItem t, BuildContext context) {
  final base = t.isAssignment ? 'Assignment due' : 'Task due';
  if (t.due == null || !hasExplicitDueTime(t.due!)) return base;
  return '$base · ${TimeOfDay.fromDateTime(t.due!).format(context)}';
}

/// Human label for an event's recurrence — falls back to the enum's
/// default label for the simple cadences, and renders the picked day
/// list (e.g. "Mon · Wed · Fri") for [Recurrence.custom].
String _recurrenceLabel(EventItem e) {
  if (e.recurrence != Recurrence.custom) return e.recurrence.label;
  if (e.recurrenceDays.isEmpty) return 'Custom days';
  final sorted = [...e.recurrenceDays]..sort();
  return sorted.map((d) => _weekdayShort[d] ?? '?').join(' · ');
}

/// Accent per event type so lectures/exams read at a glance.
Color _eventColor(EventType t) => switch (t) {
      EventType.classSession => AppPalette.periwinkle,
      EventType.exam => AppPalette.rose,
      EventType.deadline => AppPalette.peach,
      EventType.personal => AppPalette.mint,
    };

/// A task's colour: its course, else its folder's linked course, else the
/// folder, else a neutral accent. Shared by the backlog and the calendars.
Color taskColor(
  TaskItem t,
  Map<String, Course> courses,
  List<TaskFolder> folders,
) {
  var courseId = t.courseId;
  TaskFolder? folder;
  for (final f in folders) {
    if (f.id == t.folderId) folder = f;
  }
  courseId ??= folder?.courseId;
  if (courseId != null && courses[courseId] != null) {
    return courses[courseId]!.color;
  }
  return folder?.color ?? AppPalette.lavender;
}

/// Groups every event and due-task by day, soonest-first within a day.
/// Watches the relevant providers so the calendars refresh on any change.
/// Completed tasks are included unless the global hide-completed switch is
/// on (mirrors how the To-do board honors the same flag). Recurring events
/// are expanded into one entry per occurrence so a weekly class shows up
/// on every matching day, capped at a year past today.
Map<DateTime, List<_Agenda>> _buildDayMap(WidgetRef ref) {
  final courses = ref.watch(coursesByIdProvider);
  final folders = ref.watch(foldersProvider);
  final hideDone = ref.watch(hideCompletedTasksProvider);
  final map = <DateTime, List<_Agenda>>{};
  void add(DateTime when, _Agenda a) =>
      map.putIfAbsent(_dayKey(when), () => <_Agenda>[]).add(a);

  // Expansion window: anchor on `start` so old past occurrences (last
  // semester's class, etc.) stay accessible if the user scrolls back,
  // and look ahead a year so the upcoming term is fully populated.
  final today = _midnight(DateTime.now());
  final windowFrom = today.subtract(const Duration(days: 365));
  final windowTo = today.add(const Duration(days: 365));
  for (final e in ref.watch(eventsProvider)) {
    for (final occ in e.expandOccurrences(windowFrom, windowTo)) {
      add(occ, _Agenda(when: occ, color: _eventColor(e.type), event: e));
    }
  }
  for (final t in ref.watch(tasksProvider)) {
    if (t.due == null) continue;
    if (t.done && hideDone) continue;
    add(t.due!,
        _Agenda(when: t.due!, color: taskColor(t, courses, folders), task: t));
  }
  for (final list in map.values) {
    list.sort((a, b) => a.when.compareTo(b.when));
  }
  return map;
}

/// Up to four colour-coded dots under any day that has events/tasks.
CalendarBuilders<_Agenda> _markerBuilders() => CalendarBuilders<_Agenda>(
      markerBuilder: (context, day, items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Positioned(
          bottom: 5,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in items.take(4))
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration:
                      BoxDecoration(color: a.color, shape: BoxShape.circle),
                ),
            ],
          ),
        );
      },
    );

class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  DateTime _focusedDay = DateTime.now();
  late DateTime _weekStartDay = _weekStart(DateTime.now());
  _PlannerView _view = _PlannerView.week;

  void _selectDay(DateTime sel) => setState(() {
        _focusedDay = sel;
        _weekStartDay = _weekStart(sel);
      });

  /// Shift the Week view by [deltaWeeks] (negative = back, positive =
  /// forward). Updates both the visible week and the selected day so the
  /// Month view's focused day follows along if the user switches modes.
  void _shiftWeek(int deltaWeeks) => setState(() {
        final delta = Duration(days: deltaWeeks * 7);
        _weekStartDay = _weekStartDay.add(delta);
        _focusedDay = _focusedDay.add(delta);
      });

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Planner',
      subtitle: switch (_view) {
        _PlannerView.week =>
          'Drag a to-do onto a day, then slide it to block out time.',
        _PlannerView.agenda =>
          'Everything that\'s coming up, in the order it\'ll happen.',
        _PlannerView.month =>
          'Your month at a glance — tap a day to see and edit its events.',
        _PlannerView.gantt =>
          'Each bar shows how long a task has to land — tap a bar to edit.',
      },
      scrollable: false,
      actions: [
        SoftButton(
          label: 'Today',
          icon: Icons.today_rounded,
          tall: true,
          onTap: () => _selectDay(DateTime.now()),
        ),
        const SizedBox(width: 8),
        _ViewToggle(
          view: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'New event',
          icon: Icons.event_rounded,
          tall: true,
          onTap: () async {
            final e =
                await showEventDialog(context, initialDate: _focusedDay);
            if (e != null) ref.read(eventsProvider.notifier).upsert(e);
          },
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'New task',
          filled: true,
          tall: true,
          onTap: () async {
            final t = await showTaskDialog(context,
                folders: ref.read(foldersProvider),
                courses: ref.read(coursesProvider),
                categories: ref.read(gradeCategoriesProvider));
            if (t != null) ref.read(tasksProvider.notifier).save(t);
          },
        ),
        const SizedBox(width: 4),
        const _PlannerOverflowMenu(),
      ],
      child: Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 980;
          // When narrow the whole page scrolls, so the panel must not
          // introduce its own (unbounded) scroll view inside it.
          // The to-do backlog is only useful in Week view, where rows are
          // drop targets for scheduling time blocks. Month and Gantt have
          // no drop behaviour, so hide it and give the main area full width.
          final showSide = _view == _PlannerView.week;
          final Widget main = switch (_view) {
            _PlannerView.week => _WeekView(
                weekStart: _weekStartDay,
                onShiftWeek: _shiftWeek,
              ),
            _PlannerView.agenda => _AgendaView(
                focusedDay: _focusedDay,
                onDaySelected: _selectDay,
              ),
            _PlannerView.month => _MonthView(
                focusedDay: _focusedDay,
                onDaySelected: _selectDay,
              ),
            _PlannerView.gantt => const _GanttView(),
          };
          if (narrow) {
            final mainHeight = switch (_view) {
              _PlannerView.week => 560.0,
              _PlannerView.agenda => 660.0,
              _PlannerView.month => 660.0,
              _PlannerView.gantt => 620.0,
            };
            return SingleChildScrollView(
              child: Column(
                children: [
                  if (showSide) ...[
                    _SidePanel(scroll: false),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(height: mainHeight, child: main),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSide) ...[
                const SizedBox(width: 320, child: _SidePanel()),
                const SizedBox(width: 16),
              ],
              Expanded(child: main),
            ],
          );
        }),
      ),
    );
  }
}

/// Compact Week ⇄ Month segmented control for the planner header.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _PlannerView view;
  final ValueChanged<_PlannerView> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, IconData icon, _PlannerView v) {
      final sel = view == v;
      final fg =
          sel ? const Color(0xFF15132B) : AppPalette.textSecondary;
      return GestureDetector(
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Week', Icons.view_week_rounded, _PlannerView.week),
          seg('Agenda', Icons.view_agenda_rounded, _PlannerView.agenda),
          seg('Month', Icons.calendar_month_rounded, _PlannerView.month),
          seg('Gantt', Icons.view_timeline_rounded, _PlannerView.gantt),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left: draggable unscheduled to-dos / assignments backlog
// ---------------------------------------------------------------------------

class _SidePanel extends ConsumerWidget {
  const _SidePanel({this.scroll = true});

  final bool scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(unscheduledTasksProvider);
    final courses = ref.watch(coursesByIdProvider);
    final folders = ref.watch(foldersProvider);

    Color colorFor(TaskItem t) => taskColor(t, courses, folders);

    final content = GlassCard(
      title: 'To-do to schedule',
      icon: Icons.drag_indicator_rounded,
      child: tasks.isEmpty
          ? const EmptyHint('Nothing to schedule. 🎈')
          : Column(
              children: [
                for (final t in tasks)
                  _TaskChip(task: t, color: colorFor(t)),
              ],
            ),
    );

    return scroll ? SingleChildScrollView(child: content) : content;
  }
}

class _TaskChip extends StatelessWidget {
  const _TaskChip({required this.task, required this.color});

  final TaskItem task;
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
          Icon(
              task.isAssignment
                  ? Icons.school_rounded
                  : Icons.drag_indicator_rounded,
              size: 18,
              color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '${task.due == null ? 'No due date' : formatTaskDue(task.due!, context)} · ~${task.estimatedMinutes}m',
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );

    return AdaptiveDraggable<TaskItem>(
      data: task,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Opacity(opacity: 0.9, child: Material(
          color: Colors.transparent, child: card)),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// Right (Month view): full month calendar + selected-day agenda. Events can
// be created, edited and deleted right here; tasks open their editor.
// ---------------------------------------------------------------------------

/// Ordering applied to the Month view's selected-day agenda. Time is the
/// natural calendar order; the rest are user-chosen ways to scan a busy
/// day ("biggest first", "by class", "what's most important next").
enum _DaySortMode {
  time('Time', Icons.schedule_rounded),
  importance('Importance', Icons.priority_high_rounded),
  className('Class', Icons.school_outlined),
  duration('Duration', Icons.hourglass_bottom_rounded);

  const _DaySortMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What kinds of items appear on the selected day. Matches the legend
/// users carry from the month-grid markers.
enum _DayItemFilter {
  all('All', Icons.layers_rounded),
  events('Events', Icons.event_rounded),
  tasks('Tasks', Icons.checklist_rounded);

  const _DayItemFilter(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _MonthView extends ConsumerStatefulWidget {
  const _MonthView({required this.focusedDay, required this.onDaySelected});

  final DateTime focusedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  ConsumerState<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<_MonthView> {
  _DaySortMode _sort = _DaySortMode.time;
  _DayItemFilter _filter = _DayItemFilter.all;

  /// Course/folder name for a task — same fallback chain the Gantt uses,
  /// but inlined here to keep the comparator local. Returns an empty
  /// string for events (they have no class) so the class sort drops them
  /// to the bottom of the day's list.
  String _classKey(
    _Agenda a,
    Map<String, Course> courses,
    List<TaskFolder> folders,
  ) {
    final t = a.task;
    if (t == null) return '';
    var courseId = t.courseId;
    if (courseId == null && t.folderId != null) {
      for (final f in folders) {
        if (f.id == t.folderId) {
          courseId = f.courseId;
          break;
        }
      }
    }
    if (courseId != null && courses[courseId] != null) {
      return courses[courseId]!.name.toLowerCase();
    }
    for (final f in folders) {
      if (f.id == t.folderId) return f.name.toLowerCase();
    }
    return '';
  }

  /// Apply [filter] + [sort] to the day's raw chronological list.
  List<_Agenda> _filteredAndSorted(
    List<_Agenda> items,
    Map<String, Course> courses,
    List<TaskFolder> folders,
  ) {
    final visible = items.where((a) {
      switch (_filter) {
        case _DayItemFilter.all:
          return true;
        case _DayItemFilter.events:
          return a.event != null;
        case _DayItemFilter.tasks:
          return a.task != null;
      }
    }).toList();

    switch (_sort) {
      case _DaySortMode.time:
        visible.sort((a, b) => a.when.compareTo(b.when));
      case _DaySortMode.importance:
        // High priority first. Events don't carry priority — sink them
        // beneath tasks so the "most important" view is a clean task list
        // at the top, with events listed after by their start time.
        visible.sort((a, b) {
          final aIsTask = a.task != null;
          final bIsTask = b.task != null;
          if (aIsTask != bIsTask) return aIsTask ? -1 : 1;
          if (aIsTask && bIsTask) {
            final cmp =
                b.task!.priority.index.compareTo(a.task!.priority.index);
            if (cmp != 0) return cmp;
          }
          return a.when.compareTo(b.when);
        });
      case _DaySortMode.className:
        visible.sort((a, b) {
          final ka = _classKey(a, courses, folders);
          final kb = _classKey(b, courses, folders);
          // Unclassified (empty string) sinks to the bottom rather than
          // floating to the top with the default string compare.
          if (ka.isEmpty != kb.isEmpty) return ka.isEmpty ? 1 : -1;
          final cmp = ka.compareTo(kb);
          if (cmp != 0) return cmp;
          return a.when.compareTo(b.when);
        });
      case _DaySortMode.duration:
        visible.sort((a, b) {
          // Longest first. Events have no duration on this model, so
          // treat them as 0 and let them fall to the bottom.
          final da = a.task?.estimatedMinutes ?? 0;
          final db = b.task?.estimatedMinutes ?? 0;
          final cmp = db.compareTo(da);
          if (cmp != 0) return cmp;
          return a.when.compareTo(b.when);
        });
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final focusedDay = widget.focusedDay;
    final onDaySelected = widget.onDaySelected;
    final days = _buildDayMap(ref);
    final allForDay = days[_dayKey(focusedDay)] ?? const <_Agenda>[];
    final courses = ref.watch(coursesProvider);
    final folders = ref.watch(foldersProvider);
    final coursesById = ref.watch(coursesByIdProvider);
    final theme = Theme.of(context);
    final selected =
        _filteredAndSorted(allForDay, coursesById, folders);

    final calendar = GlassContainer(
      padding: const EdgeInsets.all(12),
      child: TableCalendar<_Agenda>(
        firstDay: DateTime.utc(2020),
        lastDay: DateTime.utc(2100),
        focusedDay: focusedDay,
        rowHeight: 54,
        startingDayOfWeek: StartingDayOfWeek.sunday,
        selectedDayPredicate: (d) => isSameDay(d, focusedDay),
        onDaySelected: (sel, foc) => onDaySelected(sel),
        eventLoader: (d) => days[_dayKey(d)] ?? const <_Agenda>[],
        calendarBuilders: _markerBuilders(),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle:
              TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(color: AppPalette.textSecondary),
          weekendStyle: TextStyle(color: AppPalette.lavender),
        ),
        calendarStyle: CalendarStyle(
          markersMaxCount: 4,
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
    );

    final agenda = GlassContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_rounded,
                  size: 18, color: AppPalette.lavender),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  relativeDay(focusedDay),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SoftButton(
                label: 'New event',
                icon: Icons.event_rounded,
                onTap: () async {
                  final e = await showEventDialog(context,
                      initialDate: focusedDay);
                  if (e != null) {
                    ref.read(eventsProvider.notifier).upsert(e);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DayAgendaControls(
            sort: _sort,
            filter: _filter,
            onSortChanged: (m) => setState(() => _sort = m),
            onFilterChanged: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          if (allForDay.isEmpty)
            const EmptyHint('Nothing scheduled this day.')
          else if (selected.isEmpty)
            EmptyHint(
              _filter == _DayItemFilter.events
                  ? 'No events on this day.'
                  : 'No tasks due this day.',
            )
          else
            for (final a in selected)
              _AgendaRow(
                agenda: a,
                courses: courses,
                folders: folders,
              ),
        ],
      ),
    );

    // Side-by-side when there's room, stacked when narrow. In wide mode
    // each pane scrolls independently inside the row (the parent supplies
    // a bounded height); in narrow mode the whole layout scrolls together
    // so the agenda flows under the calendar instead of squeezing it.
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 880;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(child: calendar),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: SingleChildScrollView(child: agenda),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              calendar,
              const SizedBox(height: 16),
              agenda,
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Agenda view: every event/task with a date, grouped by day, chronological.
// Past items are tinted so the "what's next" line stays obvious. The first
// build auto-scrolls so today sits a little inset from the top.
// ---------------------------------------------------------------------------

class _AgendaView extends ConsumerStatefulWidget {
  const _AgendaView({required this.focusedDay, required this.onDaySelected});

  final DateTime focusedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  ConsumerState<_AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends ConsumerState<_AgendaView> {
  final _scroll = ScrollController();
  // Approximate per-day section height used to pre-scroll to today. Real
  // sections vary, so we land "near" today rather than pixel-perfect; the
  // user can scroll from there.
  static const _approxSectionHeight = 120.0;

  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildDayMap(ref);
    final courses = ref.watch(coursesProvider);
    final folders = ref.watch(foldersProvider);
    final today = _midnight(DateTime.now());

    // Drop items older than two weeks — past-due history isn't useful here
    // and would push "what's coming up" below the fold. Future has no cap.
    final cutoff = today.subtract(const Duration(days: 14));
    final sortedKeys = days.keys
        .where((k) => !k.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.compareTo(b));

    if (sortedKeys.isEmpty) {
      return const GlassContainer(
        child: EmptyHint(
          'Nothing scheduled. Add an event or due task to see it here.',
          icon: Icons.view_agenda_rounded,
        ),
      );
    }

    // First frame after a non-empty build: jump the scroll so today (or the
    // next upcoming day) lines up near the top. Skipped on later builds so
    // the user's manual scroll position is preserved.
    if (!_didInitialScroll) {
      _didInitialScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        var idx = sortedKeys.indexWhere((d) => !d.isBefore(today));
        if (idx < 0) idx = sortedKeys.length - 1;
        final target = (idx * _approxSectionHeight)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(target);
      });
    }

    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.view_agenda_rounded,
                    size: 18, color: AppPalette.lavender),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Upcoming agenda',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                SoftButton(
                  label: 'Jump to today',
                  icon: Icons.today_rounded,
                  onTap: () {
                    widget.onDaySelected(today);
                    if (!_scroll.hasClients) return;
                    var idx = sortedKeys.indexWhere(
                        (d) => !d.isBefore(today));
                    if (idx < 0) idx = sortedKeys.length - 1;
                    final target = (idx * _approxSectionHeight)
                        .clamp(0.0, _scroll.position.maxScrollExtent);
                    _scroll.animateTo(
                      target,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final key in sortedKeys)
                    _AgendaDaySection(
                      day: key,
                      items: days[key]!,
                      isPast: key.isBefore(today),
                      isToday: key == today,
                      isSelected: isSameDay(key, widget.focusedDay),
                      courses: courses,
                      folders: folders,
                      onSelect: () => widget.onDaySelected(key),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One day section in the agenda view: a sticky-looking date header plus
/// a list of agenda rows. Tapping the header bubbles the day selection up
/// to the parent (matches the Month view's "selected day" plumbing).
class _AgendaDaySection extends StatelessWidget {
  const _AgendaDaySection({
    required this.day,
    required this.items,
    required this.isPast,
    required this.isToday,
    required this.isSelected,
    required this.courses,
    required this.folders,
    required this.onSelect,
  });

  final DateTime day;
  final List<_Agenda> items;
  final bool isPast;
  final bool isToday;
  final bool isSelected;
  final List<Course> courses;
  final List<TaskFolder> folders;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final color = isToday
        ? AppPalette.accent
        : (isPast ? AppPalette.textFaint : AppPalette.lavender);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppPalette.accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    relativeDay(day),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 1,
                      color:
                          AppPalette.glassStroke.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length} item${items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppPalette.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Opacity(
              opacity: isPast ? 0.6 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in items)
                    _AgendaRow(
                      agenda: a,
                      courses: courses,
                      folders: folders,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the month view's day agenda. Events are editable/deletable
/// inline; tasks open the task editor.
class _AgendaRow extends ConsumerWidget {
  const _AgendaRow({
    required this.agenda,
    required this.courses,
    required this.folders,
  });

  final _Agenda agenda;
  final List<Course> courses;
  final List<TaskFolder> folders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = agenda;

    if (a.event != null) {
      final e = a.event!;
      final loc = e.location.isEmpty ? '' : ' · ${e.location}';
      // Recurring events get a small "↻ weekly" badge so it's obvious
      // why the same item shows up on multiple days, and the delete
      // dialog warns the user that removal affects the whole series.
      final repeats = e.recurrence.repeats;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(e.type.icon, color: a.color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (repeats) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.refresh_rounded,
                            size: 13, color: a.color),
                      ],
                    ],
                  ),
                  Text(
                    '${TimeOfDay.fromDateTime(a.when).format(context)} · '
                    '${e.type.label}$loc'
                    '${repeats ? ' · ${_recurrenceLabel(e)}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: repeats ? 'Edit series' : 'Edit event',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: () async {
                final upd = await showEventDialog(context, existing: e);
                if (upd != null) {
                  ref.read(eventsProvider.notifier).upsert(upd);
                }
              },
            ),
            IconButton(
              tooltip: repeats ? 'Delete series' : 'Delete event',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () async {
                final ok = await confirmDelete(
                  context,
                  title: repeats ? 'Delete series?' : 'Delete event?',
                  message: repeats
                      ? '“${e.title}” repeats ${_recurrenceLabel(e).toLowerCase()}. '
                          'Every occurrence will be permanently removed.'
                      : '“${e.title}” will be permanently removed.',
                );
                if (ok) ref.read(eventsProvider.notifier).remove(e.id);
              },
            ),
          ],
        ),
      );
    }

    final t = a.task!;
    return InkWell(
      onTap: () async {
        final upd = await showTaskDialog(context,
            existing: t,
            folders: folders,
            courses: courses,
            categories: ref.read(gradeCategoriesProvider));
        if (upd != null) ref.read(tasksProvider.notifier).save(upd);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
                t.isAssignment
                    ? Icons.school_rounded
                    : Icons.flag_outlined,
                color: a.color,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                      _taskAgendaSubtitle(t, context),
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textSecondary)),
                ],
              ),
            ),
            GlassChip(label: t.priority.label, color: t.priority.color),
          ],
        ),
      ),
    );
  }
}

/// Sort + filter controls for the Month view's selected-day agenda. Two
/// compact pill bars: a type filter on top (All / Events / Tasks), and a
/// sort selector below (Time / Importance / Class / Duration). Sits inside
/// the agenda card so the controls only show when there *is* an agenda.
class _DayAgendaControls extends StatelessWidget {
  const _DayAgendaControls({
    required this.sort,
    required this.filter,
    required this.onSortChanged,
    required this.onFilterChanged,
  });

  final _DaySortMode sort;
  final _DayItemFilter filter;
  final ValueChanged<_DaySortMode> onSortChanged;
  final ValueChanged<_DayItemFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter pills — three short labels fit in a row even on narrow.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in _DayItemFilter.values)
              _PillSegment(
                label: f.label,
                icon: f.icon,
                selected: filter == f,
                onTap: () => onFilterChanged(f),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Sort row: a small "Sort" label then the four mode pills.
        Row(
          children: [
            const Text(
              'Sort',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppPalette.textFaint,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _DaySortMode.values)
                    _PillSegment(
                      label: m.label,
                      icon: m.icon,
                      selected: sort == m,
                      onTap: () => onSortChanged(m),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact pill button used by [_DayAgendaControls]. Mirrors the look of
/// the planner's view toggle so the controls feel native to the page.
class _PillSegment extends StatelessWidget {
  const _PillSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg =
        selected ? const Color(0xFF15132B) : AppPalette.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppPalette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppPalette.accent
                : AppPalette.glassStroke.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact previous / range / next bar sitting above the week grid.
/// Visually matches the Gantt window nav so users who've used one already
/// know how this one behaves; the centre label highlights when the
/// current real-world week is *not* on screen, hinting that tapping it
/// will scroll back to "this week".
class _WeekNav extends StatelessWidget {
  const _WeekNav({
    required this.weekStart,
    required this.weekEnd,
    required this.today,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final DateTime today;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final isThisWeek =
        !today.isBefore(weekStart) && !today.isAfter(weekEnd);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppPalette.glassStroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous week',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: AppPalette.textSecondary,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrev,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Text(
                  '${_fmt(weekStart)} – ${_fmt(weekEnd)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isThisWeek
                        ? AppPalette.textSecondary
                        : AppPalette.lavender,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: AppPalette.textSecondary,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right (Week view): Sunday→Saturday week grid with drop targets + blocks
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerWidget {
  const _WeekView({
    required this.weekStart,
    required this.onShiftWeek,
  });

  final DateTime weekStart;

  /// Called when the user taps the prev/next chevrons; positive = forward
  /// in time, negative = back. The parent owns the actual week state.
  final void Function(int deltaWeeks) onShiftWeek;

  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = _midnight(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 6));

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // Week navigator: prev / "Mar 5 – Mar 11" / next. The label is
          // tap-to-jump-back-to-this-week — handy after panning far away.
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WeekNav(
              weekStart: weekStart,
              weekEnd: weekEnd,
              today: today,
              onPrev: () => onShiftWeek(-1),
              onNext: () => onShiftWeek(1),
            ),
          ),
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
                  key: ValueKey(b.id),
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
        if (data is TaskItem) {
          final dur = data.estimatedMinutes.clamp(_snap, 600).toInt();
          notifier.upsert(TimeBlock(
            id: newId(),
            title: data.title,
            taskId: data.id,
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

class _BlockWidget extends StatefulWidget {
  const _BlockWidget({
    super.key,
    required this.block,
    required this.onResize,
    required this.onDelete,
  });

  final TimeBlock block;
  final ValueChanged<int> onResize;
  final VoidCallback onDelete;

  @override
  State<_BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<_BlockWidget> {
  /// Un-snapped end (minutes from midnight) while a resize drag is active;
  /// null when not resizing. Tracking raw pixels makes the bottom edge
  /// follow the finger/mouse smoothly instead of jumping in 15-min steps;
  /// the value is snapped and committed once on release.
  double? _liveEnd;

  int get _snappedLiveEnd =>
      ((_liveEnd! / _snap).round() * _snap)
          .clamp(widget.block.startMinute + _snap, _endHour * 60)
          .toInt();

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final top = (block.startMinute - _startHour * 60).toDouble();
    final endMinute = _liveEnd ?? block.endMinute.toDouble();
    final double height = (endMinute - block.startMinute)
        .clamp(_snap.toDouble(), 2000.0)
        .toDouble();
    final color = block.color;
    // While resizing, show the snapped end the user will land on.
    final shownEnd = _liveEnd == null ? block.endMinute : _snappedLiveEnd;
    final handleH = (height * 0.4).clamp(14.0, 22.0).toDouble();

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
              '${hhmm(block.startMinute)} – ${hhmm(shownEnd)}',
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
      child: Stack(
        children: [
          Positioned.fill(
            child: AdaptiveDraggable<TimeBlock>(
              data: block,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: SizedBox(
                width: 150,
                height: height,
                child: Opacity(opacity: 0.85, child: Material(
                    color: Colors.transparent, child: body)),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: body),
              child: GestureDetector(
                onTap: () => _menu(context),
                child: body,
              ),
            ),
          ),
          // Resize grip — a sibling layered *above* the draggable (not a
          // descendant) and opaque, so a drag starting here always resizes
          // (never moves) the block. A roomy hit area + resize cursor make
          // it easy to grab with either a finger or a mouse.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: handleH,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(
                    () => _liveEnd = block.endMinute.toDouble()),
                onVerticalDragUpdate: (d) => setState(() {
                  _liveEnd = ((_liveEnd ?? block.endMinute.toDouble()) +
                          d.delta.dy)
                      .clamp((block.startMinute + _snap).toDouble(),
                          (_endHour * 60).toDouble());
                }),
                onVerticalDragEnd: (_) {
                  if (_liveEnd != null) widget.onResize(_snappedLiveEnd);
                  setState(() => _liveEnd = null);
                },
                child: Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // One-tap remove. Layered above the draggable so its tap is
          // isolated; removing the block returns the to-do to the backlog.
          Positioned(
            top: 2,
            right: 2,
            child: Tooltip(
              message: block.taskId != null
                  ? 'Remove (back to backlog)'
                  : 'Remove from planner',
              child: Material(
                color: Colors.black.withValues(alpha: 0.28),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _sendBack(context),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: AppPalette.textPrimary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Remove this block. If it came from a to-do, that to-do reappears in
  /// the planner backlog (see [unscheduledTasksProvider]); a brief snackbar
  /// confirms where it went.
  void _sendBack(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final linked = widget.block.taskId != null;
    final title = widget.block.title;
    widget.onDelete();
    messenger.showSnackBar(SnackBar(
      content: Text(linked
          ? '"$title" sent back to the backlog'
          : '"$title" removed from the planner'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _menu(BuildContext context) {
    final block = widget.block;
    final pageContext = context;
    showGlassDialog<void>(
      context,
      title: block.title,
      content: Text(
        '${hhmm(block.startMinute)} – ${hhmm(block.endMinute)}'
        '  ·  ${block.durationMinutes} min',
        style: const TextStyle(color: AppPalette.textSecondary),
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            _sendBack(pageContext);
          },
          child: Text(block.taskId != null
              ? 'Send back to backlog'
              : 'Remove from planner'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right (Gantt view): horizontally-scrolling chart of every open due task,
// drawn as a bar from plannedStart (or createdAt) → due. Three sort modes;
// in Manual mode rows are draggable to reorder. Drag a bar's left edge to
// set its planned start; tap the bar to open the task editor.
// ---------------------------------------------------------------------------

/// How rows are arranged in the Gantt. Manual is the only mode that allows
/// drag-to-reorder; the other two recompute order on every build.
enum _GanttSortMode {
  manual('Manual', Icons.drag_handle_rounded),
  byClass('Class', Icons.school_outlined),
  byDueDate('Due date', Icons.event_rounded);

  const _GanttSortMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Course or folder name a task rolls up under in the Gantt's left column.
/// Null means the task is unfiled, in which case the bar still appears but
/// without a group label.
String? _ganttGroupName(
  TaskItem t,
  Map<String, Course> courses,
  List<TaskFolder> folders,
) {
  var courseId = t.courseId;
  TaskFolder? folder;
  for (final f in folders) {
    if (f.id == t.folderId) folder = f;
  }
  courseId ??= folder?.courseId;
  if (courseId != null && courses[courseId] != null) {
    return courses[courseId]!.name;
  }
  return folder?.name;
}

/// Apply [mode] to a copy of [tasks] in place. Manual mode puts tasks the
/// user has explicitly placed (`ganttOrder > 0`) first, then untouched ones
/// in due-date order — that way the very first reorder doesn't shuffle
/// every unrelated row.
void _sortGanttTasks(
  List<TaskItem> tasks,
  _GanttSortMode mode,
  Map<String, Course> courses,
  List<TaskFolder> folders,
) {
  tasks.sort((a, b) {
    switch (mode) {
      case _GanttSortMode.manual:
        final aOrd = a.ganttOrder == 0 ? 1 << 30 : a.ganttOrder;
        final bOrd = b.ganttOrder == 0 ? 1 << 30 : b.ganttOrder;
        if (aOrd != bOrd) return aOrd.compareTo(bOrd);
        return a.due!.compareTo(b.due!);
      case _GanttSortMode.byClass:
        final ga = _ganttGroupName(a, courses, folders) ?? '~';
        final gb = _ganttGroupName(b, courses, folders) ?? '~';
        final cmp = ga.toLowerCase().compareTo(gb.toLowerCase());
        if (cmp != 0) return cmp;
        return a.due!.compareTo(b.due!);
      case _GanttSortMode.byDueDate:
        return a.due!.compareTo(b.due!);
    }
  });
}

class _GanttView extends ConsumerStatefulWidget {
  const _GanttView();

  @override
  ConsumerState<_GanttView> createState() => _GanttViewState();
}

class _GanttViewState extends ConsumerState<_GanttView> {
  /// Window: default look-back so just-overdue items stay visible, and a
  /// generous look-ahead so a typical term's worth of work fits on one chart.
  /// The Earlier/Later nav buttons shift `_windowOffsetDays` in 30-day
  /// chunks so the user can pan into the past or future indefinitely.
  static const _defaultDaysBefore = 7;
  static const _defaultDaysAfter = 84;
  static const _dayWidth = 32.0;
  static const _rowHeight = 44.0;
  static const _headerHeight = 56.0;
  static const _labelWidth = 220.0;
  static const _panStepDays = 30;
  static const int _totalDays = _defaultDaysBefore + _defaultDaysAfter;

  final _hHeader = ScrollController();
  final _hBody = ScrollController();

  late final DateTime _today = _midnight(DateTime.now());

  /// Signed pan offset (days) applied on top of the default window start.
  /// Negative shifts the window into the past, positive into the future.
  int _windowOffsetDays = 0;

  DateTime get _windowStart => _today
      .subtract(const Duration(days: _defaultDaysBefore))
      .add(Duration(days: _windowOffsetDays));

  _GanttSortMode _sortMode = _GanttSortMode.manual;

  @override
  void initState() {
    super.initState();
    // Keep the date header visually pinned to the body's horizontal scroll.
    // The header itself is NeverScrollable so the user can only drive scroll
    // from the body region, and we mirror that offset up here.
    _hBody.addListener(() {
      if (!_hHeader.hasClients) return;
      final target =
          _hBody.offset.clamp(0.0, _hHeader.position.maxScrollExtent);
      if (_hHeader.offset != target) _hHeader.jumpTo(target);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  /// Jump the body horizontal scroll so "today" sits a little inset from
  /// the left edge. Safe to call before the controllers are attached.
  void _scrollToToday() {
    if (!_hBody.hasClients) return;
    final daysFromWindowStart = _today.difference(_windowStart).inDays;
    final target = (daysFromWindowStart * _dayWidth - 24)
        .clamp(0.0, _hBody.position.maxScrollExtent);
    _hBody.jumpTo(target);
  }

  /// Shift the visible window by [days] (negative = earlier, positive =
  /// later). After the rebuild, scroll so the previously-leftmost edge is
  /// what's now in view — so "Earlier" actually reveals earlier dates
  /// instead of staying parked at the same scroll position.
  void _shiftWindow(int days) {
    setState(() => _windowOffsetDays += days);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hBody.hasClients) return;
      if (days < 0) {
        // Reveal the new earlier dates on the left.
        _hBody.jumpTo(0);
      } else {
        // Reveal the new later dates on the right.
        _hBody.jumpTo(_hBody.position.maxScrollExtent);
      }
    });
  }

  void _resetWindow() {
    if (_windowOffsetDays == 0) {
      _scrollToToday();
      return;
    }
    setState(() => _windowOffsetDays = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  /// Swap [srcId] into [dstIndex] of the currently visible [tasks] list and
  /// persist the new manual order. Called from a label cell's DragTarget.
  void _handleReorder(List<TaskItem> tasks, String srcId, int dstIndex) {
    if (_sortMode != _GanttSortMode.manual) return;
    final srcIndex = tasks.indexWhere((t) => t.id == srcId);
    if (srcIndex == -1 || srcIndex == dstIndex) return;
    final next = List<TaskItem>.from(tasks);
    final moved = next.removeAt(srcIndex);
    // When dragging downward the target index shifts left by 1 because the
    // source has been removed above it; correct for that so the dropped row
    // lands where the user actually pointed.
    final insertAt = srcIndex < dstIndex ? dstIndex - 1 : dstIndex;
    next.insert(insertAt.clamp(0, next.length), moved);
    ref.read(tasksProvider.notifier).reorderGantt(next);
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesByIdProvider);
    final folders = ref.watch(foldersProvider);
    final hideDone = ref.watch(hideCompletedTasksProvider);
    final tasks = ref
        .watch(tasksProvider)
        .where((t) => t.due != null && (!hideDone || !t.done))
        .toList();
    _sortGanttTasks(tasks, _sortMode, courses, folders);

    const totalWidth = _totalDays * _dayWidth;
    final windowStart = _windowStart;
    final navBar = _GanttWindowNav(
      windowStart: windowStart,
      totalDays: _totalDays,
      isShifted: _windowOffsetDays != 0,
      onEarlier: () => _shiftWindow(-_panStepDays),
      onLater: () => _shiftWindow(_panStepDays),
      onReset: _resetWindow,
    );

    if (tasks.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                navBar,
                const Spacer(),
                _GanttSortToggle(
                  mode: _sortMode,
                  onChanged: (m) => setState(() => _sortMode = m),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const EmptyHint(
                'No tasks with a due date yet. Add one to chart it. 📊'),
          ],
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Top bar: window navigation on the left, sort toggle on the
          // right. The "Drag to reorder" hint sits below the nav when
          // Manual is active so users know rows are draggable.
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 2, bottom: 10),
            child: Row(
              children: [
                navBar,
                const Spacer(),
                _GanttSortToggle(
                  mode: _sortMode,
                  onChanged: (m) => setState(() => _sortMode = m),
                ),
              ],
            ),
          ),
          if (_sortMode == _GanttSortMode.manual)
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Drag a row by its title to reorder.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.textFaint,
                  ),
                ),
              ),
            ),
          // Header strip: fixed left "Task" cell + horizontally-scrolling
          // month/day strip. The body drives the scroll; the header mirrors.
          SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                Container(
                  width: _labelWidth,
                  alignment: Alignment.bottomLeft,
                  padding:
                      const EdgeInsets.only(left: 4, bottom: 8, right: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: AppPalette.glassStroke),
                      bottom: BorderSide(color: AppPalette.glassStroke),
                    ),
                  ),
                  child: const Text(
                    'Task',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: SingleChildScrollView(
                      controller: _hHeader,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: totalWidth,
                        height: _headerHeight,
                        child: CustomPaint(
                          painter: _GanttHeaderPainter(
                            start: _windowStart,
                            totalDays: _totalDays,
                            dayWidth: _dayWidth,
                            today: _today,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body: a single vertical scroll, then inside it a row of
          // [fixed labels | horizontal-scroll bars].
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _labelWidth,
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: AppPalette.glassStroke),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < tasks.length; i++)
                          _GanttLabelCell(
                            task: tasks[i],
                            color: taskColor(tasks[i], courses, folders),
                            groupName:
                                _ganttGroupName(tasks[i], courses, folders),
                            height: _rowHeight,
                            draggable: _sortMode == _GanttSortMode.manual,
                            onDropped: (srcId) =>
                                _handleReorder(tasks, srcId, i),
                            onPickStart: () => _pickStart(tasks[i]),
                            onPickCompletion: () =>
                                _pickCompletion(tasks[i]),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: SingleChildScrollView(
                        controller: _hBody,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          child: Stack(
                            children: [
                              // Grid + weekend bands + today line, painted
                              // once behind every row instead of per-row.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _GanttGridPainter(
                                      start: _windowStart,
                                      totalDays: _totalDays,
                                      dayWidth: _dayWidth,
                                      today: _today,
                                    ),
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final t in tasks)
                                    _GanttBarRow(
                                      key: ValueKey(t.id),
                                      task: t,
                                      color: taskColor(t, courses, folders),
                                      windowStart: _windowStart,
                                      totalDays: _totalDays,
                                      dayWidth: _dayWidth,
                                      rowHeight: _rowHeight,
                                      today: _today,
                                      onTap: () => _editTask(t),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTask(TaskItem t) async {
    final upd = await showTaskDialog(
      context,
      existing: t,
      folders: ref.read(foldersProvider),
      courses: ref.read(coursesProvider),
      categories: ref.read(gradeCategoriesProvider),
    );
    if (upd != null) ref.read(tasksProvider.notifier).save(upd);
  }

  /// Pick a new planned start for [t]. Defaults to its current start (or
  /// createdAt if none); the picker can't go past the due date so the bar
  /// always has positive length.
  Future<void> _pickStart(TaskItem t) async {
    final due = _midnight(t.due!);
    final created = _midnight(t.createdAt);
    final initial = t.plannedStart != null
        ? _midnight(t.plannedStart!)
        : (created.isAfter(due) ? due : created);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(due) ? due : initial,
      // Allow scheduling well before the task was created so the user
      // isn't stuck with the bar pinned at createdAt for old items.
      firstDate: DateTime(2020),
      lastDate: due,
      helpText: 'Pick a start date for the Gantt bar',
    );
    if (picked == null) return;
    final newStart = _midnight(picked);
    // Treat "set to createdAt or earlier" as clearing the override so the
    // bar falls back to the default rule and the field shows no chip.
    final isDefault = !newStart.isAfter(created);
    ref.read(tasksProvider.notifier).save(
          isDefault
              ? t.copyWith(clearPlannedStart: true)
              : t.copyWith(plannedStart: newStart),
        );
  }

  /// Ask for a new completion % (0..100). Persists immediately on confirm;
  /// flipping to 100% does *not* auto-complete the task — the user keeps
  /// that gesture in the task editor or the to-do board.
  Future<void> _pickCompletion(TaskItem t) async {
    final controller =
        TextEditingController(text: t.completionPercent.toString());
    final result = await showGlassDialog<int>(
      context,
      title: 'Set completion',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Percent complete (0–100)',
              suffixText: '%',
            ),
          ),
        ],
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final raw = int.tryParse(controller.text.trim()) ?? 0;
            Navigator.pop(dialogContext, raw.clamp(0, 100));
          },
          child: const Text('Save'),
        ),
      ],
    );
    if (result == null) return;
    ref.read(tasksProvider.notifier).save(
          t.copyWith(completionPercent: result),
        );
  }
}

/// Earlier / Today / Later pan controls for the Gantt's date window. The
/// label cycles through the currently visible date range so the user can
/// see at a glance how far they've panned.
class _GanttWindowNav extends StatelessWidget {
  const _GanttWindowNav({
    required this.windowStart,
    required this.totalDays,
    required this.isShifted,
    required this.onEarlier,
    required this.onLater,
    required this.onReset,
  });

  final DateTime windowStart;
  final int totalDays;
  final bool isShifted;
  final VoidCallback onEarlier;
  final VoidCallback onLater;
  final VoidCallback onReset;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final end = windowStart.add(Duration(days: totalDays - 1));
    final rangeLabel = '${_fmt(windowStart)} – ${_fmt(end)}';
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Show earlier dates',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: AppPalette.textSecondary,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onEarlier,
          ),
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                rangeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isShifted
                      ? AppPalette.lavender
                      : AppPalette.textSecondary,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Show later dates',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: AppPalette.textSecondary,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onLater,
          ),
        ],
      ),
    );
  }
}

/// Overflow menu shown to the right of the "New task" button in the
/// planner header. Holds settings and one-shot actions that don't warrant
/// their own pill — the hide-completed switch and the .ics calendar
/// import live here together.
class _PlannerOverflowMenu extends ConsumerWidget {
  const _PlannerOverflowMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideCompletedTasksProvider);
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert_rounded,
          size: 20, color: AppPalette.textSecondary),
      color: const Color(0xFF241F45),
      onSelected: (key) async {
        if (key == 'hide-done') {
          ref.read(hideCompletedTasksProvider.notifier).toggle();
        } else if (key == 'import-ics') {
          await _importCalendar(context, ref);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'hide-done',
          checked: hidden,
          child: const Text('Hide completed tasks'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'import-ics',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.file_download_outlined, size: 20),
            title: Text('Import calendar (.ics)…'),
            subtitle: Text(
              'Gmail, iCloud, or Outlook export',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

/// File-picker → parse → upsert pipeline for one .ics file. The summary
/// dialog tells the user exactly what landed (and what got skipped) so
/// importing the same file twice doesn't feel like silent breakage.
Future<void> _importCalendar(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  const group = XTypeGroup(label: 'Calendar (.ics)', extensions: ['ics']);
  final picked = await openFile(acceptedTypeGroups: const [group]);
  if (picked == null) return;

  String text;
  try {
    text = await picked.readAsString();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Couldn\'t read file: $e')));
    return;
  }

  IcsParseOutcome outcome;
  try {
    outcome = IcsParser.parse(text);
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('That file doesn\'t look like a valid .ics ($e).')));
    return;
  }

  if (outcome.events.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(outcome.skippedReasons.isEmpty
          ? 'No events found in that file.'
          : 'No events imported (${outcome.skippedReasons.length} skipped).'),
    ));
    return;
  }

  final existingIds = {for (final e in ref.read(eventsProvider)) e.id};
  final added = <EventItem>[];
  final updated = <EventItem>[];
  for (final e in outcome.events) {
    if (existingIds.contains(e.id)) {
      updated.add(e);
    } else {
      added.add(e);
    }
  }
  await ref.read(eventsProvider.notifier).upsertAll(outcome.events);

  if (!context.mounted) return;
  await _showImportSummary(
    context,
    fileName: picked.name,
    result: IcsImportResult(
      added: added,
      updated: updated,
      skipped: outcome.skippedReasons,
      warnings: outcome.warnings,
    ),
  );
}

/// Quick recap dialog after an import. Kept light — three numbers and an
/// optional bulleted list of warnings — so it stays useful without
/// turning into a full report screen.
Future<void> _showImportSummary(
  BuildContext context, {
  required String fileName,
  required IcsImportResult result,
}) {
  return showGlassDialog<void>(
    context,
    title: 'Calendar imported',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fileName,
          style: const TextStyle(
              fontSize: 12, color: AppPalette.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        _ImportStatRow(
          icon: Icons.add_circle_outline_rounded,
          label: 'Added',
          count: result.added.length,
          tint: AppPalette.mint,
        ),
        _ImportStatRow(
          icon: Icons.refresh_rounded,
          label: 'Updated',
          count: result.updated.length,
          tint: AppPalette.lavender,
        ),
        _ImportStatRow(
          icon: Icons.remove_circle_outline_rounded,
          label: 'Skipped',
          count: result.skipped.length,
          tint: AppPalette.textFaint,
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            'Notes',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppPalette.textFaint,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final w in result.warnings.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $w',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textSecondary,
                ),
              ),
            ),
          if (result.warnings.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '…and ${result.warnings.length - 4} more.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textFaint,
                ),
              ),
            ),
        ],
      ],
    ),
    actions: (dialogContext) => [
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Done'),
      ),
    ],
  );
}

class _ImportStatRow extends StatelessWidget {
  const _ImportStatRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: count == 0 ? AppPalette.textFaint : tint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three-segment pill toggle: Manual / Class / Due date. Visually matches
/// the Week/Month/Gantt toggle but a touch smaller so it sits inside the
/// chart card without crowding it.
class _GanttSortToggle extends StatelessWidget {
  const _GanttSortToggle({required this.mode, required this.onChanged});

  final _GanttSortMode mode;
  final ValueChanged<_GanttSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(_GanttSortMode m) {
      final sel = mode == m;
      final fg = sel ? const Color(0xFF15132B) : AppPalette.textSecondary;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(m.icon, size: 13, color: fg),
              const SizedBox(width: 5),
              Text(
                m.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _GanttSortMode.values) seg(m),
        ],
      ),
    );
  }
}

/// Left-column cell for one Gantt row: task title + course/folder subtitle,
/// with a thin color tab tying it to its bar. In Manual sort mode the cell
/// is both a Draggable (source) and a DragTarget (destination) so the user
/// can drag any row onto any other row to reorder; outside Manual mode the
/// cell is inert.
class _GanttLabelCell extends StatelessWidget {
  const _GanttLabelCell({
    required this.task,
    required this.color,
    required this.groupName,
    required this.height,
    required this.draggable,
    required this.onDropped,
    required this.onPickStart,
    required this.onPickCompletion,
  });

  final TaskItem task;
  final Color color;
  final String? groupName;
  final double height;

  /// When false the cell is a plain row — no drag source, no drop target.
  final bool draggable;

  /// Called when another row was dropped onto this one, carrying the
  /// source task id. The parent rebuilds the manual order from it.
  final ValueChanged<String> onDropped;

  /// Tapping the "Start" chip in the row opens the date picker.
  final VoidCallback onPickStart;

  /// Tapping the "%" chip in the row opens the completion editor.
  final VoidCallback onPickCompletion;

  @override
  Widget build(BuildContext context) {
    // Subtitle: course/folder on the left, two interactive chips on the
    // right — a date chip that opens a picker for the Gantt start, and a
    // % chip that edits the task's completion. Both stay compact so the
    // row keeps the original height the bars are aligned to.
    final start = task.plannedStart;
    final startLabel = start == null ? 'Start' : relativeDay(start);
    final pct = task.completionPercent;

    final Widget subtitle = Row(
      children: [
        if (groupName != null) ...[
          Flexible(
            child: Text(
              groupName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                height: 1.15,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        _GanttMetaChip(
          icon: Icons.event_rounded,
          label: startLabel,
          emphasised: start != null,
          onTap: onPickStart,
        ),
        const SizedBox(width: 4),
        _GanttMetaChip(
          icon: Icons.percent_rounded,
          label: '$pct',
          emphasised: pct > 0,
          onTap: onPickCompletion,
        ),
      ],
    );

    final Widget content = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: AppPalette.glassStroke.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: height - 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          if (draggable) ...[
            const Icon(
              Icons.drag_indicator_rounded,
              size: 14,
              color: AppPalette.textFaint,
            ),
            const SizedBox(width: 2),
          ],
          Icon(
            task.isAssignment ? Icons.school_rounded : Icons.flag_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                    color: task.done
                        ? AppPalette.textSecondary
                        : AppPalette.textPrimary,
                  ),
                ),
                subtitle,
              ],
            ),
          ),
        ],
      ),
    );

    if (!draggable) return content;

    // Drag feedback shows a tinted floating copy of the row so the user
    // sees what they're carrying. Use the row's color for the fill so the
    // visual line back to the bar in the chart stays obvious.
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 220,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: content,
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != task.id,
      onAcceptWithDetails: (d) => onDropped(d.data),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        // Stack the hover indicators on top of the row so they paint over
        // it without taking layout space — the cell stays exactly [height]
        // tall so it lines up with the bars column on the right.
        return AdaptiveDraggable<String>(
          data: task.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.35, child: content),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                content,
                if (hovering) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppPalette.accent.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 2,
                    child: IgnorePointer(
                      child: ColoredBox(color: AppPalette.accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compact tap-to-edit chip used in a Gantt label row. The chip is dim
/// when [emphasised] is false (e.g. "no start set") and accent-tinted
/// once the user has filled it in, so the row reads as "start ✓ · X%" at
/// a glance. Tapping anywhere on the chip fires [onTap].
class _GanttMetaChip extends StatelessWidget {
  const _GanttMetaChip({
    required this.icon,
    required this.label,
    required this.emphasised,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool emphasised;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg =
        emphasised ? AppPalette.lavender : AppPalette.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: emphasised
              ? AppPalette.lavender.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: emphasised
                ? AppPalette.lavender.withValues(alpha: 0.35)
                : AppPalette.glassStroke.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Gantt row: a horizontal bar from the task's planned start (or its
/// createdAt fallback) to its due date, clipped to the visible window. The
/// bar's left edge is a drag handle that adjusts `plannedStart`; tapping
/// anywhere else opens the task editor. Overdue tasks get a red outline.
class _GanttBarRow extends ConsumerStatefulWidget {
  const _GanttBarRow({
    super.key,
    required this.task,
    required this.color,
    required this.windowStart,
    required this.totalDays,
    required this.dayWidth,
    required this.rowHeight,
    required this.today,
    required this.onTap,
  });

  final TaskItem task;
  final Color color;
  final DateTime windowStart;
  final int totalDays;
  final double dayWidth;
  final double rowHeight;
  final DateTime today;
  final VoidCallback onTap;

  @override
  ConsumerState<_GanttBarRow> createState() => _GanttBarRowState();
}

class _GanttBarRowState extends ConsumerState<_GanttBarRow> {
  /// Un-snapped start in pixel-days while a drag is active; null otherwise.
  /// Tracking the un-snapped value lets the left edge follow the cursor
  /// smoothly; the snapped value is committed once on release.
  double? _liveStartPx;

  /// Start of the bar after snapping, derived from [_liveStartPx]. Clamped
  /// to the visible window on the left and one day before due on the right
  /// so the bar always has visible length.
  DateTime get _snappedLiveStart {
    final due = _midnight(widget.task.due!);
    final snappedDayIdx = (_liveStartPx! / widget.dayWidth).round();
    final windowEndIdx = widget.totalDays - 1;
    final maxIdx = due.difference(widget.windowStart).inDays;
    final clampedIdx = snappedDayIdx
        .clamp(0, (maxIdx < windowEndIdx ? maxIdx : windowEndIdx));
    return widget.windowStart.add(Duration(days: clampedIdx));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final due = _midnight(t.due!);
    final created = _midnight(t.createdAt);
    final lastDay =
        widget.windowStart.add(Duration(days: widget.totalDays - 1));

    // Stored start (or createdAt fallback). Drag overrides this until release.
    final storedStart = t.plannedStart != null ? _midnight(t.plannedStart!) : (
        created.isAfter(widget.today) ? widget.today : created);
    final liveStart = _liveStartPx == null ? storedStart : _snappedLiveStart;

    final clippedStart =
        liveStart.isBefore(widget.windowStart) ? widget.windowStart : liveStart;
    final clippedEnd = due.isAfter(lastDay) ? lastDay : due;

    final emptyRow = Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: AppPalette.glassStroke.withValues(alpha: 0.5)),
        ),
      ),
    );

    if (clippedEnd.isBefore(clippedStart) ||
        clippedEnd.isBefore(widget.windowStart) ||
        clippedStart.isAfter(lastDay)) {
      return emptyRow;
    }

    final startIdx = clippedStart.difference(widget.windowStart).inDays;
    final endIdx = clippedEnd.difference(widget.windowStart).inDays;
    final left = startIdx * widget.dayWidth;
    final width = (endIdx - startIdx + 1) * widget.dayWidth;
    final overdue = due.isBefore(widget.today);
    final clippedLeft = liveStart.isBefore(widget.windowStart);
    final clippedRight = due.isAfter(lastDay);

    final tooltipMsg = '${t.title}\n'
        'Start ${relativeDay(liveStart)} · Due ${relativeDay(due)}'
        '${t.plannedStart == null ? '' : ' · custom start'}';

    return SizedBox(
      height: widget.rowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color:
                          AppPalette.glassStroke.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          // The bar body: tap to edit the task. Kept narrower than the
          // resize handle so dragging the leftmost few pixels always
          // resizes instead of triggering tap. A solid fill on the left
          // shows completion %, so partly-done work is obvious at a glance.
          Positioned(
            left: left + 8,
            top: 6,
            width: (width - 10).clamp(4.0, double.infinity),
            height: widget.rowHeight - 12,
            child: Tooltip(
              message: '$tooltipMsg · ${t.completionPercent}% done',
              child: GestureDetector(
                onTap: widget.onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(2),
                    right: clippedRight
                        ? const Radius.circular(2)
                        : const Radius.circular(8),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base track — light tint behind everything.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.22),
                        ),
                      ),
                      // Completion fill: a denser slice from the left out
                      // to `completionPercent` of the bar's width.
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor:
                            (t.completionPercent / 100.0).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      // Outline + title + trailing % readout.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: overdue
                                ? AppPalette.danger.withValues(alpha: 0.85)
                                : widget.color.withValues(alpha: 0.75),
                            width: overdue ? 1.4 : 1,
                          ),
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (t.completionPercent > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${t.completionPercent}%',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.textPrimary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Left-edge resize handle. Sibling of the bar (not a child) so
          // pointer events here never bubble to the bar's tap handler. Only
          // visible when the bar's start isn't already clipped against the
          // window's left edge (where the handle would be invisible).
          if (!clippedLeft)
            Positioned(
              left: left,
              top: 6,
              width: 10,
              height: widget.rowHeight - 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) => setState(
                      () => _liveStartPx = startIdx * widget.dayWidth),
                  onHorizontalDragUpdate: (d) => setState(() {
                    _liveStartPx = ((_liveStartPx ??
                                startIdx * widget.dayWidth) +
                            d.delta.dx)
                        .clamp(0.0,
                            (widget.totalDays - 1) * widget.dayWidth);
                  }),
                  onHorizontalDragEnd: (_) {
                    if (_liveStartPx != null) {
                      final newStart = _snappedLiveStart;
                      // Treat "dragged back to createdAt" (or earlier) as
                      // a request to clear the custom start.
                      final isDefault = !newStart.isAfter(created);
                      ref.read(tasksProvider.notifier).save(
                            isDefault
                                ? t.copyWith(clearPlannedStart: true)
                                : t.copyWith(plannedStart: newStart),
                          );
                    }
                    setState(() => _liveStartPx = null);
                  },
                  child: Center(
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Header strip: month-name band on top, then per-day number + weekday
/// letter, with today's column highlighted by an accent pill.
class _GanttHeaderPainter extends CustomPainter {
  _GanttHeaderPainter({
    required this.start,
    required this.totalDays,
    required this.dayWidth,
    required this.today,
  });

  final DateTime start;
  final int totalDays;
  final double dayWidth;
  final DateTime today;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _dows = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void paint(Canvas canvas, Size size) {
    const monthStyle = TextStyle(
      color: AppPalette.lavender,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    const dayStyle = TextStyle(
      color: AppPalette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    const weekendStyle = TextStyle(
      color: AppPalette.textSecondary,
      fontSize: 12,
    );
    const dowStyle = TextStyle(
      color: AppPalette.textFaint,
      fontSize: 9,
      letterSpacing: 0.3,
    );

    // Month bands across the top, one label per month-in-window.
    var i = 0;
    while (i < totalDays) {
      final d = start.add(Duration(days: i));
      final nextMonth = DateTime(d.year, d.month + 1, 1);
      final daysLeftInMonth = nextMonth.difference(d).inDays;
      final span = (i + daysLeftInMonth > totalDays)
          ? totalDays - i
          : daysLeftInMonth;
      final x = i * dayWidth;
      final w = span * dayWidth;
      final tp = TextPainter(
        text: TextSpan(
          text: '${_months[d.month - 1]} ${d.year}',
          style: monthStyle,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: w - 8);
      tp.paint(canvas, Offset(x + 6, 6));
      i += span;
    }

    // Per-day cells: highlight today, then draw day number + weekday letter.
    for (var k = 0; k < totalDays; k++) {
      final d = start.add(Duration(days: k));
      final x = k * dayWidth;
      final isWeekend =
          d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      final isToday = d == today;

      if (isToday) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 2, size.height - 32, dayWidth - 4, 28),
            const Radius.circular(8),
          ),
          Paint()..color = AppPalette.accent.withValues(alpha: 0.28),
        );
      }

      final dayTp = TextPainter(
        text: TextSpan(
          text: '${d.day}',
          style: isWeekend ? weekendStyle : dayStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: dayWidth);
      dayTp.paint(
        canvas,
        Offset(x + (dayWidth - dayTp.width) / 2, size.height - 28),
      );

      final dowTp = TextPainter(
        text: TextSpan(text: _dows[d.weekday % 7], style: dowStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: dayWidth);
      dowTp.paint(
        canvas,
        Offset(x + (dayWidth - dowTp.width) / 2, size.height - 12),
      );
    }

    // Hairline under the whole header so it reads as a separator.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = AppPalette.glassStroke,
    );
  }

  @override
  bool shouldRepaint(_GanttHeaderPainter old) =>
      old.start != start ||
      old.totalDays != totalDays ||
      old.dayWidth != dayWidth ||
      old.today != today;
}

/// Background painter for the bars region: weekend shading + daily vertical
/// gridlines + a vertical accent line marking today.
class _GanttGridPainter extends CustomPainter {
  _GanttGridPainter({
    required this.start,
    required this.totalDays,
    required this.dayWidth,
    required this.today,
  });

  final DateTime start;
  final int totalDays;
  final double dayWidth;
  final DateTime today;

  @override
  void paint(Canvas canvas, Size size) {
    final weekend = Paint()..color = Colors.white.withValues(alpha: 0.025);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    final todayLine = Paint()
      ..color = AppPalette.accent.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;

    for (var i = 0; i < totalDays; i++) {
      final d = start.add(Duration(days: i));
      final x = i * dayWidth;
      if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
        canvas.drawRect(Rect.fromLTWH(x, 0, dayWidth, size.height), weekend);
      }
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      if (d == today) {
        canvas.drawLine(
          Offset(x + dayWidth / 2, 0),
          Offset(x + dayWidth / 2, size.height),
          todayLine,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GanttGridPainter old) =>
      old.start != start ||
      old.totalDays != totalDays ||
      old.dayWidth != dayWidth ||
      old.today != today;
}
