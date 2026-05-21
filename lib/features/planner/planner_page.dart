import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
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
enum _PlannerView { week, month, gantt }

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

/// Groups every event and open due-task by day, soonest-first within a day.
/// Watches the relevant providers so the calendars refresh on any change.
Map<DateTime, List<_Agenda>> _buildDayMap(WidgetRef ref) {
  final courses = ref.watch(coursesByIdProvider);
  final folders = ref.watch(foldersProvider);
  final map = <DateTime, List<_Agenda>>{};
  void add(DateTime when, _Agenda a) =>
      map.putIfAbsent(_dayKey(when), () => <_Agenda>[]).add(a);

  for (final e in ref.watch(eventsProvider)) {
    add(e.start, _Agenda(when: e.start, color: _eventColor(e.type), event: e));
  }
  for (final t in ref.watch(tasksProvider)) {
    if (t.due == null || t.done) continue;
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

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Planner',
      subtitle: switch (_view) {
        _PlannerView.week =>
          'Drag a to-do onto a day, then slide it to block out time.',
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
          onTap: () async {
            final t = await showTaskDialog(context,
                folders: ref.read(foldersProvider),
                courses: ref.read(coursesProvider),
                categories: ref.read(gradeCategoriesProvider));
            if (t != null) ref.read(tasksProvider.notifier).save(t);
          },
        ),
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
            _PlannerView.week => _WeekView(weekStart: _weekStartDay),
            _PlannerView.month => _MonthView(
                focusedDay: _focusedDay,
                onDaySelected: _selectDay,
              ),
            _PlannerView.gantt => const _GanttView(),
          };
          if (narrow) {
            final mainHeight = switch (_view) {
              _PlannerView.week => 560.0,
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
                    '${task.due == null ? 'No due date' : 'Due ${relativeDay(task.due!)}'} · ~${task.estimatedMinutes}m',
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

class _MonthView extends ConsumerWidget {
  const _MonthView({required this.focusedDay, required this.onDaySelected});

  final DateTime focusedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = _buildDayMap(ref);
    final selected = days[_dayKey(focusedDay)] ?? const <_Agenda>[];
    final courses = ref.watch(coursesProvider);
    final folders = ref.watch(foldersProvider);
    final theme = Theme.of(context);

    // The whole view scrolls as one: the calendar keeps its natural height
    // and the agenda flows under it, so a short window scrolls instead of
    // squeezing the agenda card past its minimum (which overflowed).
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
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
        ),
          const SizedBox(height: 16),
          GlassContainer(
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
                const SizedBox(height: 16),
                if (selected.isEmpty)
                  const EmptyHint('Nothing scheduled this day.')
                else
                  for (final a in selected)
                    _AgendaRow(
                      agenda: a,
                      courses: courses,
                      folders: folders,
                    ),
              ],
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
                  Text(e.title,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${TimeOfDay.fromDateTime(e.start).format(context)} · '
                    '${e.type.label}$loc',
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit event',
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
              tooltip: 'Delete event',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: () async {
                final ok = await confirmDelete(
                  context,
                  title: 'Delete event?',
                  message: '“${e.title}” will be permanently removed.',
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
                  Text(t.isAssignment ? 'Assignment due' : 'Task due',
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

// ---------------------------------------------------------------------------
// Right (Week view): Sunday→Saturday week grid with drop targets + blocks
// ---------------------------------------------------------------------------

class _WeekView extends ConsumerWidget {
  const _WeekView({required this.weekStart});

  final DateTime weekStart;

  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final today = _midnight(DateTime.now());

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
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
  /// Window: a short look-back so just-overdue items stay visible, and a
  /// generous look-ahead so a typical term's worth of work fits on one chart.
  static const _daysBefore = 7;
  static const _daysAfter = 84;
  static const _dayWidth = 32.0;
  static const _rowHeight = 38.0;
  static const _headerHeight = 56.0;
  static const _labelWidth = 220.0;

  final _hHeader = ScrollController();
  final _hBody = ScrollController();

  late final DateTime _today = _midnight(DateTime.now());
  late final DateTime _windowStart =
      _today.subtract(const Duration(days: _daysBefore));
  static const int _totalDays = _daysBefore + _daysAfter;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hBody.hasClients) return;
      // Scroll so "today" sits a little inset from the left edge.
      final target = (_daysBefore * _dayWidth - 24)
          .clamp(0.0, _hBody.position.maxScrollExtent);
      _hBody.jumpTo(target);
    });
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
    final tasks = ref
        .watch(tasksProvider)
        .where((t) => !t.done && t.due != null)
        .toList();
    _sortGanttTasks(tasks, _sortMode, courses, folders);

    const totalWidth = _totalDays * _dayWidth;

    if (tasks.isEmpty) {
      return GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _GanttSortToggle(
                mode: _sortMode,
                onChanged: (m) => setState(() => _sortMode = m),
              ),
            ),
            const SizedBox(height: 12),
            const EmptyHint(
                'No open tasks with a due date yet. Add one to chart it. 📊'),
          ],
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Top bar: sort toggle on the right, a quick hint on the left when
          // Manual is active so users know rows are draggable.
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 2, bottom: 10),
            child: Row(
              children: [
                if (_sortMode == _GanttSortMode.manual)
                  const Expanded(
                    child: Text(
                      'Drag a row by its title to reorder.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.textFaint,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                _GanttSortToggle(
                  mode: _sortMode,
                  onChanged: (m) => setState(() => _sortMode = m),
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(width: 8),
          if (draggable) ...[
            const Icon(
              Icons.drag_indicator_rounded,
              size: 14,
              color: AppPalette.textFaint,
            ),
            const SizedBox(width: 4),
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
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (groupName != null)
                  Text(
                    groupName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.15,
                      color: AppPalette.textSecondary,
                    ),
                  ),
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
          // resizes instead of triggering tap.
          Positioned(
            left: left + 8,
            top: 6,
            width: (width - 10).clamp(4.0, double.infinity),
            height: widget.rowHeight - 12,
            child: Tooltip(
              message: tooltipMsg,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.32),
                    border: Border.all(
                      color: overdue
                          ? AppPalette.danger.withValues(alpha: 0.85)
                          : widget.color.withValues(alpha: 0.75),
                      width: overdue ? 1.4 : 1,
                    ),
                    borderRadius: BorderRadius.horizontal(
                      left: const Radius.circular(2),
                      right: clippedRight
                          ? const Radius.circular(2)
                          : const Radius.circular(8),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
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
