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
enum _PlannerView { week, month }

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
      subtitle: _view == _PlannerView.week
          ? 'Drag a to-do onto a day, then slide it to block out time.'
          : 'Your month at a glance — tap a day to see and edit its events.',
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
          final side = _SidePanel(scroll: !narrow);
          final Widget main = _view == _PlannerView.week
              ? _WeekView(weekStart: _weekStartDay)
              : _MonthView(
                  focusedDay: _focusedDay,
                  onDaySelected: _selectDay,
                );
          if (narrow) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  side,
                  const SizedBox(height: 16),
                  SizedBox(
                    height: _view == _PlannerView.week ? 560 : 660,
                    child: main,
                  ),
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: side),
              const SizedBox(width: 16),
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
