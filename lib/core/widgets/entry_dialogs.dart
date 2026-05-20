import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../features/study/card_image_store.dart';
import '../theme/app_palette.dart';
import 'markdown_lite.dart';
import 'ui_kit.dart';

/// Reusable create/edit dialogs. Each returns the new/updated model (with a
/// fresh id when creating) or null if cancelled. Persisting is the caller's
/// job so these stay decoupled from Riverpod.

TextField _field(TextEditingController c, String hint,
        {int maxLines = 1, TextInputType? keyboard}) =>
    TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(hintText: hint),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppPalette.accent,
          surface: Color(0xFF241F45),
        ),
      ),
      child: child!,
    ),
  );
}

/// Create / edit a countdown timer: name, H:M:S length and accent colour.
/// Returns the chosen values, or null if cancelled. Persisting is the
/// caller's job (kept Riverpod-free like the other dialogs here).
Future<({String name, int seconds, int colorSeed})?> showTimerDurationDialog(
  BuildContext context, {
  String name = '',
  int initialSeconds = 5 * 60,
  int colorSeed = 0,
  bool isNew = true,
}) async {
  final nameC = TextEditingController(text: name);
  var h = initialSeconds ~/ 3600;
  var m = (initialSeconds % 3600) ~/ 60;
  var s = initialSeconds % 60;
  var seed = colorSeed;

  Widget unit(
    String label,
    int value,
    int maxVal,
    void Function(int) onChanged,
  ) {
    void bump(int delta) {
      var v = value + delta;
      if (v < 0) v = maxVal;
      if (v > maxVal) v = 0;
      onChanged(v);
    }

    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: () => bump(1),
        ),
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.glassStroke),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppPalette.textSecondary)),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => bump(-1),
        ),
      ],
    );
  }

  return showGlassDialog<({String name, int seconds, int colorSeed})>(
    context,
    title: isNew ? 'New timer' : 'Edit timer',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Timer name (optional)'),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              unit('hours', h, 23, (v) => setState(() => h = v)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(':',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              unit('min', m, 59, (v) => setState(() => m = v)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(':',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              unit('sec', s, 59, (v) => setState(() => s = v)),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0;
                  i < AppPalette.categorySwatches.length;
                  i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            seed == i ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final total = h * 3600 + m * 60 + s;
          if (total <= 0) return; // a 0-second timer is meaningless
          Navigator.pop(context, (
            name: nameC.text.trim(),
            seconds: total,
            colorSeed: seed,
          ));
        },
        child: const Text('Save'),
      ),
    ],
  ).whenComplete(nameC.dispose);
}

/// Create / edit a Pomodoro preset: name, focus / short break / long break
/// minutes, rounds-before-long, accent colour. Returns the chosen values
/// (the caller persists). One vertical stack of labelled steppers — clearer
/// than four side-by-side dials for whole-minute lengths.
Future<({
  String name,
  int focusMinutes,
  int shortBreakMinutes,
  int longBreakMinutes,
  int roundsBeforeLong,
  int colorSeed,
})?> showPomodoroPresetDialog(
  BuildContext context, {
  String name = '',
  int focusMinutes = 25,
  int shortBreakMinutes = 5,
  int longBreakMinutes = 15,
  int roundsBeforeLong = 4,
  int colorSeed = 0,
  bool isNew = true,
}) async {
  final nameC = TextEditingController(text: name);
  var f = focusMinutes;
  var sb = shortBreakMinutes;
  var lb = longBreakMinutes;
  var rounds = roundsBeforeLong;
  var seed = colorSeed;

  Widget stepperRow(
    String label,
    int value,
    String suffix,
    int min,
    int max,
    int step,
    void Function(int) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppPalette.textSecondary)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: value > min
                ? () => onChanged((value - step).clamp(min, max))
                : null,
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$value $suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: value < max
                ? () => onChanged((value + step).clamp(min, max))
                : null,
          ),
        ],
      ),
    );
  }

  return showGlassDialog<({
    String name,
    int focusMinutes,
    int shortBreakMinutes,
    int longBreakMinutes,
    int roundsBeforeLong,
    int colorSeed,
  })>(
    context,
    title: isNew ? 'New Pomodoro' : 'Edit Pomodoro',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Name (e.g. Deep work, Study sprint)'),
          const SizedBox(height: 12),
          stepperRow('Focus session', f, 'min', 5, 120, 5,
              (v) => setState(() => f = v)),
          stepperRow('Short break', sb, 'min', 1, 30, 1,
              (v) => setState(() => sb = v)),
          stepperRow('Long break', lb, 'min', 5, 60, 5,
              (v) => setState(() => lb = v)),
          stepperRow('Rounds before long break', rounds, '', 2, 8, 1,
              (v) => setState(() => rounds = v)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0;
                  i < AppPalette.categorySwatches.length;
                  i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: seed == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          name: nameC.text.trim(),
          focusMinutes: f,
          shortBreakMinutes: sb,
          longBreakMinutes: lb,
          roundsBeforeLong: rounds,
          colorSeed: seed,
        )),
        child: const Text('Save'),
      ),
    ],
  ).whenComplete(nameC.dispose);
}

Future<TaskItem?> showTaskDialog(
  BuildContext context, {
  TaskItem? existing,
  required List<TaskFolder> folders,
  required List<Course> courses,
  List<GradeCategory> categories = const [],
  String? presetFolderId,
}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final estC = TextEditingController(
      text: (existing?.estimatedMinutes ?? 60).toString());
  var priority = existing?.priority ?? Priority.medium;
  DateTime? due = existing?.due;
  String? folderId = existing?.folderId ?? presetFolderId;
  var isAssignment = existing?.isAssignment ?? false;
  String? courseId = existing?.courseId;
  String? categoryId = existing?.categoryId;
  var recurrence = existing?.recurrence ?? Recurrence.none;

  String? folderCourseId(String? fid) {
    if (fid == null) return null;
    for (final f in folders) {
      if (f.id == fid) return f.courseId;
    }
    return null;
  }

  Course? courseById(String? id) {
    if (id == null) return null;
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  return showGlassDialog<TaskItem>(
    context,
    title: existing == null ? 'New task' : 'Edit task',
    content: StatefulBuilder(
      builder: (context, setState) {
        final inheritedCourseId = folderCourseId(folderId);
        final resolvedCourseId = courseId ?? inheritedCourseId;
        final catsForCourse = resolvedCourseId == null
            ? const <GradeCategory>[]
            : (categories
                .where((c) => c.courseId == resolvedCourseId)
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order)));
        // Drop a stale category id when the resolved class no longer
        // covers it (e.g. user switched class mid-edit).
        if (categoryId != null &&
            !catsForCourse.any((c) => c.id == categoryId)) {
          categoryId = null;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldLabel('Task'),
            TextField(
              controller: titleC,
              autofocus: existing == null,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'What needs doing?',
              ),
            ),
            const SizedBox(height: 14),
            _FieldLabel('Priority'),
            _PriorityPicker(
              priority: priority,
              onChanged: (p) => setState(() => priority = p),
            ),
            const SizedBox(height: 14),
            _FieldLabel('Folder'),
            _FolderDropdown(
              value: folderId,
              folders: folders,
              onChanged: (v) => setState(() => folderId = v),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Due date'),
                      _DueDateField(
                        due: due,
                        onChanged: (v) => setState(() => due = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 118,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Estimate'),
                      TextField(
                        controller: estC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '60',
                          suffixText: 'min',
                          suffixStyle: TextStyle(
                              color: AppPalette.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FieldLabel('Repeat'),
            DropdownButtonFormField<Recurrence>(
              initialValue: recurrence,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.refresh_rounded, size: 18),
              ),
              items: [
                for (final r in Recurrence.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) =>
                  setState(() => recurrence = v ?? recurrence),
            ),
            if (recurrence.repeats && due == null)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Tip: set a due date so each repeat lands on the right '
                  'day.',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary),
                ),
              ),
            const SizedBox(height: 14),
            _AssignmentToggle(
              isAssignment: isAssignment,
              onChanged: (v) => setState(() => isAssignment = v),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !isAssignment
                  ? const SizedBox(width: double.infinity)
                  : _AssignmentPanel(
                      courses: courses,
                      courseId: courseId,
                      inheritedCourse: courseById(inheritedCourseId),
                      categoryId: categoryId,
                      catsForCourse: catsForCourse,
                      hasAnyCategories: categories.isNotEmpty,
                      onCourseChanged: (v) => setState(() {
                        courseId = v;
                        // Clear category eagerly when the explicit class
                        // changes — the next build's validator would do
                        // the same, but doing it here keeps the dropdown
                        // from showing a stale label for one frame.
                        categoryId = null;
                      }),
                      onCategoryChanged: (v) =>
                          setState(() => categoryId = v),
                    ),
            ),
          ],
        );
      },
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (titleC.text.trim().isEmpty) return;
          final base = existing ??
              TaskItem(
                  id: newId(), title: '', createdAt: DateTime.now());
          Navigator.pop(
            context,
            base.copyWith(
              title: titleC.text.trim(),
              priority: priority,
              due: due,
              clearDue: due == null,
              folderId: folderId,
              clearFolder: folderId == null,
              isAssignment: isAssignment,
              courseId: courseId,
              clearCourse: courseId == null,
              categoryId: categoryId,
              clearCategory: categoryId == null,
              estimatedMinutes: int.tryParse(estC.text) ?? 60,
              recurrence: recurrence,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  ).whenComplete(() {
    titleC.dispose();
    estC.dispose();
  });
}

/// Small uppercase-ish caption rendered above each form field. Keeps the
/// dialog scannable — the user can see at a glance which field is which
/// without having to read the placeholder text inside it.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppPalette.textSecondary,
        ),
      ),
    );
  }
}

/// Three-segment pill for [Priority]. Each option shows a small dot in the
/// priority's colour; the active segment fills with that colour at a low
/// alpha so the dialog stays calm.
class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker({required this.priority, required this.onChanged});

  final Priority priority;
  final ValueChanged<Priority> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(Priority p) {
      final selected = priority == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? p.color.withValues(alpha: 0.28)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: p.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        children: [for (final p in Priority.values) seg(p)],
      ),
    );
  }
}

/// Dropdown that shows a coloured dot next to each folder name so the
/// caller can see at a glance which bucket the task lands in.
class _FolderDropdown extends StatelessWidget {
  const _FolderDropdown({
    required this.value,
    required this.folders,
    required this.onChanged,
  });

  final String? value;
  final List<TaskFolder> folders;
  final ValueChanged<String?> onChanged;

  Widget _label(String text, {Color? dot}) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot ?? AppPalette.textFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: const Color(0xFF241F45),
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.folder_outlined, size: 18),
      ),
      items: [
        DropdownMenuItem(value: null, child: _label('No folder')),
        for (final f in folders)
          DropdownMenuItem(value: f.id, child: _label(f.name, dot: f.color)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Field-shaped tile for picking (or clearing) the due date — matches the
/// rest of the form's outlined glass-fill look so the form reads as one
/// coherent surface instead of a button-vs-field patchwork.
class _DueDateField extends StatelessWidget {
  const _DueDateField({required this.due, required this.onChanged});

  final DateTime? due;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasDate = due != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await _pickDate(context, due ?? DateTime.now());
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppPalette.glassFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.glassStroke),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_rounded,
                  size: 18, color: AppPalette.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasDate ? 'Due ${relativeDay(due!)}' : 'No due date',
                  style: TextStyle(
                    color: hasDate
                        ? AppPalette.textPrimary
                        : AppPalette.textFaint,
                  ),
                ),
              ),
              if (hasDate)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(null),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppPalette.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Track as assignment" row — a single tappable surface with a switch on
/// the right. Lower visual weight than the old [SwitchListTile] block.
class _AssignmentToggle extends StatelessWidget {
  const _AssignmentToggle({
    required this.isAssignment,
    required this.onChanged,
  });

  final bool isAssignment;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!isAssignment),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isAssignment
                      ? AppPalette.accent.withValues(alpha: 0.18)
                      : AppPalette.glassFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.glassStroke),
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: 18,
                  color: isAssignment
                      ? AppPalette.lavender
                      : AppPalette.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Track as assignment',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      'Adds a placeholder in the gradebook.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isAssignment,
                activeThumbColor: AppPalette.accent,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inset class + category picker shown under [_AssignmentToggle] when
/// the user marks a task as an assignment. The category dropdown is the
/// new piece — it routes the placeholder grade to the right bucket
/// (e.g. Exams vs Homework) in the gradebook.
class _AssignmentPanel extends StatelessWidget {
  const _AssignmentPanel({
    required this.courses,
    required this.courseId,
    required this.inheritedCourse,
    required this.categoryId,
    required this.catsForCourse,
    required this.hasAnyCategories,
    required this.onCourseChanged,
    required this.onCategoryChanged,
  });

  final List<Course> courses;
  final String? courseId;
  final Course? inheritedCourse;
  final String? categoryId;
  final List<GradeCategory> catsForCourse;
  final bool hasAnyCategories;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onCategoryChanged;

  Widget _classLabel(String text, {Color? dot}) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot ?? AppPalette.textFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final hasResolvedClass =
        courseId != null || inheritedCourse != null;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.lavender.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('Class'),
          DropdownButtonFormField<String?>(
            initialValue: courseId,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.school_outlined, size: 18),
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: _classLabel(
                  inheritedCourse == null
                      ? 'No class'
                      : "Use folder's class · ${inheritedCourse!.name}",
                  dot: inheritedCourse?.color,
                ),
              ),
              for (final c in courses)
                DropdownMenuItem(
                  value: c.id,
                  child: _classLabel(c.name, dot: c.color),
                ),
            ],
            onChanged: onCourseChanged,
          ),
          if (!hasResolvedClass)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Pick a class (or link the folder to one) so the grade '
                'has a home.',
                style: TextStyle(
                    fontSize: 11, color: AppPalette.textSecondary),
              ),
            ),
          if (hasResolvedClass) ...[
            const SizedBox(height: 12),
            const _FieldLabel('Category'),
            DropdownButtonFormField<String?>(
              initialValue: categoryId,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon:
                    const Icon(Icons.category_outlined, size: 18),
                hintText: catsForCourse.isEmpty
                    ? 'No categories yet for this class'
                    : null,
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('No category')),
                for (final c in catsForCourse)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.weightPercent > 0
                        ? '${c.name} · ${c.weightPercent.toStringAsFixed(0)}%'
                        : c.name),
                  ),
              ],
              onChanged: catsForCourse.isEmpty ? null : onCategoryChanged,
            ),
            if (catsForCourse.isEmpty && hasAnyCategories)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'This class has no grade categories yet — add some on '
                  'the Grades page to bucket the placeholder.',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Future<TaskFolder?> showFolderDialog(
  BuildContext context, {
  TaskFolder? existing,
  required List<Course> courses,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  var seed = existing?.colorSeed ?? 0;
  String? courseId = existing?.courseId;
  return showGlassDialog<TaskFolder>(
    context,
    title: existing == null ? 'New folder' : 'Edit folder',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Folder name'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: courseId,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(
                hintText: 'Link to a class (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No class')),
              for (final c in courses)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => courseId = v),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0; i < AppPalette.categorySwatches.length; i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: seed == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ?? TaskFolder(id: newId(), name: '');
          Navigator.pop(
            context,
            base.copyWith(
              name: nameC.text.trim(),
              colorSeed: seed,
              courseId: courseId,
              clearCourse: courseId == null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Course?> showCourseDialog(
  BuildContext context, {
  Course? existing,
  List<Institution> institutions = const [],
  List<Semester> semesters = const [],
  Future<Semester?> Function(String institutionId)? onCreateSemester,
  List<Semester>? createdSemesters,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final creditsC = TextEditingController(
      text: (existing?.creditHours ?? 3).toString());
  var seed = existing?.colorSeed ?? 0;
  String? institutionId = existing?.institutionId ??
      (institutions.isNotEmpty ? institutions.first.id : null);
  if (institutionId != null &&
      !institutions.any((i) => i.id == institutionId)) {
    institutionId = institutions.isNotEmpty ? institutions.first.id : null;
  }
  String? semesterId = existing?.semesterId;
  // Local, mutable copy so a semester created inline shows up and can be
  // selected without waiting on the (snapshot) [semesters] argument.
  final sems = [...semesters];

  return showGlassDialog<Course>(
    context,
    title: existing == null ? 'New course' : 'Edit course',
    content: StatefulBuilder(
      builder: (context, setState) {
        // Only this institution's semesters, most-recent first; drop a
        // stale pick if the institution changed underneath it.
        final semsForInst = [
          for (final s in sems)
            if (s.institutionId == institutionId) s,
        ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
        if (semesterId != null &&
            !semsForInst.any((s) => s.id == semesterId)) {
          semesterId = null;
        }

        Future<void> addSemester() async {
          final created = await onCreateSemester!(institutionId!);
          if (created != null) {
            setState(() {
              sems.add(created);
              // Collected here, not persisted — the caller commits these
              // only if the course itself is saved.
              createdSemesters?.add(created);
              semesterId = created.id;
            });
          }
        }

        return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Course name'),
          const SizedBox(height: 12),
          if (institutions.isEmpty)
            const Text(
              'Add an institution in Profile to set this course’s '
              'grading system.',
              style:
                  TextStyle(fontSize: 11, color: AppPalette.textSecondary),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: institutionId,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(hintText: 'Institution'),
              items: [
                for (final i in institutions)
                  DropdownMenuItem(
                      value: i.id,
                      child: Text('${i.name} · ${i.gradeSystem.label}')),
              ],
              onChanged: (v) => setState(() => institutionId = v),
            ),
          if (institutions.isNotEmpty && institutionId != null) ...[
            const SizedBox(height: 12),
            if (semsForInst.isEmpty)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No semesters for this school yet — create one '
                      'to place this course in a term.',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppPalette.textSecondary),
                    ),
                  ),
                  if (onCreateSemester != null)
                    TextButton.icon(
                      onPressed: addSemester,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New semester'),
                    ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: semesterId,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF241F45),
                      decoration: const InputDecoration(
                          hintText: 'Semester (required)'),
                      items: [
                        for (final s in semsForInst)
                          DropdownMenuItem(
                              value: s.id, child: Text(s.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => semesterId = v),
                    ),
                  ),
                  if (onCreateSemester != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: addSemester,
                      child: const Text('New'),
                    ),
                  ],
                ],
              ),
            if (semesterId == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Every course needs a semester — pick or create one '
                  'before saving.',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(creditsC, 'Credit hours',
                    keyboard: TextInputType.number),
              ),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0; i < AppPalette.categorySwatches.length; i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: seed == i
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        );
      },
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          // A course must live in a semester — block the save (Cancel
          // still leaves any existing course untouched).
          if (semesterId == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                    Text('Pick or create a semester for this course.')));
            return;
          }
          final base = existing ?? Course(id: newId(), name: '');
          Navigator.pop(
            context,
            base.copyWith(
              name: nameC.text.trim(),
              colorSeed: seed,
              institutionId: institutionId,
              semesterId: semesterId,
              creditHours:
                  (double.tryParse(creditsC.text) ?? 3).clamp(0, 30),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<GradeEntry?> showGradeDialog(
  BuildContext context, {
  required List<Course> courses,
  GradeEntry? existing,
  List<GradeCategory> categories = const [],
  String? lockedCourseId,
}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final earnedC =
      TextEditingController(text: existing?.earned?.toString() ?? '');
  final totalC = TextEditingController(
      text: (existing != null && existing.total > 0 ? existing.total : 100)
          .toString());
  final weightC =
      TextEditingController(text: (existing?.weight ?? 1).toString());
  final ecValueC = TextEditingController(
      text: existing?.extraCreditValue?.toString() ?? '');
  String? courseId =
      lockedCourseId ?? existing?.courseId ?? courses.firstOrNull?.id;
  String? categoryId = existing?.categoryId;
  var extraCredit = existing?.extraCredit ?? false;
  var ecIsPoints = existing?.extraCreditIsPoints ?? false;

  Widget labeled(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppPalette.textSecondary)),
          const SizedBox(height: 4),
          field,
        ],
      );

  return showGlassDialog<GradeEntry>(
    context,
    title: existing == null ? 'Add grade' : 'Edit grade',
    content: StatefulBuilder(
      builder: (context, setState) {
        final catsForCourse =
            categories.where((c) => c.courseId == courseId).toList();
        final catSum = catsForCourse.fold<double>(
            0, (s, c) => s + c.weightPercent);
        // Categories already cover (nearly) the whole grade → a normal
        // item must be filed under one. EC items skip categories.
        final catRequired =
            catsForCourse.isNotEmpty && catSum >= 99;
        if (categoryId != null &&
            !catsForCourse.any((c) => c.id == categoryId)) {
          categoryId = null;
        }
        if (catRequired && categoryId == null) {
          categoryId = catsForCourse.first.id;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lockedCourseId == null) ...[
              labeled(
                'Course',
                DropdownButtonFormField<String?>(
                  initialValue: courseId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF241F45),
                  decoration:
                      const InputDecoration(isDense: true),
                  items: [
                    for (final c in courses)
                      DropdownMenuItem(
                          value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => courseId = v),
                ),
              ),
              const SizedBox(height: 12),
            ],
            labeled('Assignment name',
                _field(titleC, 'e.g. Quiz 2 / Final')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: labeled('Earned grade',
                        _field(earnedC, '',
                            keyboard: TextInputType.number))),
                const SizedBox(width: 10),
                Expanded(
                    child: labeled('Max grade',
                        _field(totalC, '',
                            keyboard: TextInputType.number))),
                const SizedBox(width: 10),
                Expanded(
                    child: labeled('Weight',
                        _field(weightC, '',
                            keyboard: TextInputType.number))),
              ],
            ),
            if (catsForCourse.isNotEmpty) ...[
              const SizedBox(height: 12),
              labeled(
                catRequired ? 'Category (required)' : 'Category',
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF241F45),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    if (!catRequired)
                      const DropdownMenuItem(
                          value: null, child: Text('No category')),
                    for (final c in catsForCourse)
                      DropdownMenuItem(
                          value: c.id,
                          child: Text(
                              '${c.name} · ${c.weightPercent.toStringAsFixed(0)}%')),
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
              ),
              if (catRequired)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Your categories cover the whole grade, so every '
                    'item needs one.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.textSecondary),
                  ),
                ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Extra credit / curve'),
              subtitle: const Text(
                'Adds a bonus on top of this grade — the score above '
                'is kept as-is',
                style: TextStyle(fontSize: 11),
              ),
              value: extraCredit,
              activeThumbColor: AppPalette.accent,
              onChanged: (v) => setState(() => extraCredit = v),
            ),
            if (extraCredit) ...[
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Is it points or a percentage?',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.textSecondary)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Points'),
                    selected: ecIsPoints,
                    selectedColor:
                        AppPalette.accent.withValues(alpha: 0.3),
                    onSelected: (_) =>
                        setState(() => ecIsPoints = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Percentage'),
                    selected: !ecIsPoints,
                    selectedColor:
                        AppPalette.accent.withValues(alpha: 0.3),
                    onSelected: (_) =>
                        setState(() => ecIsPoints = false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              labeled(
                ecIsPoints ? 'Extra points' : 'Extra percent',
                _field(ecValueC, ecIsPoints ? 'e.g. 5' : 'e.g. 3',
                    keyboard: TextInputType.number),
              ),
              const SizedBox(height: 8),
              Text(
                ecIsPoints
                    ? 'Added to the earned grade (e.g. 90 + 5 = 95).'
                    : "Added to this item's % (e.g. 90% + 3% = 93%).",
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Leave “Earned grade” blank to log it as not graded '
              'yet — it shows as “—” and stays out of the average '
              'until scored.',
              style: TextStyle(
                  fontSize: 11, color: AppPalette.textSecondary),
            ),
          ],
        );
      },
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (courseId == null || titleC.text.trim().isEmpty) return;
          final ecValue = double.tryParse(ecValueC.text.trim());
          // Extra credit is on but no bonus typed → nothing to save yet.
          if (extraCredit && ecValue == null) return;
          Navigator.pop(
            context,
            GradeEntry(
              id: existing?.id ?? newId(),
              courseId: courseId!,
              title: titleC.text.trim(),
              earned: earnedC.text.trim().isEmpty
                  ? null
                  : (double.tryParse(earnedC.text) ?? 0),
              total: double.tryParse(totalC.text) ?? 100,
              weight: double.tryParse(weightC.text) ?? 1,
              date: existing?.date ?? DateTime.now(),
              categoryId: categoryId,
              extraCredit: extraCredit,
              extraCreditIsPoints: ecIsPoints,
              extraCreditValue: extraCredit ? ecValue : null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<GradeCategory?> showCategoryDialog(
  BuildContext context, {
  required String courseId,
  GradeCategory? existing,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final weightC = TextEditingController(
      text: (existing?.weightPercent ?? 0).toStringAsFixed(0));

  return showGlassDialog<GradeCategory>(
    context,
    title: existing == null ? 'New category' : 'Edit category',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(nameC, 'Category (e.g. Exams, Homework)'),
        const SizedBox(height: 12),
        _field(weightC, 'Weight % of course grade',
            keyboard: TextInputType.number),
        const SizedBox(height: 8),
        const Text(
          'Weights across categories should add up to 100%. Anything '
          'left over covers uncategorized items.',
          style: TextStyle(fontSize: 11, color: AppPalette.textSecondary),
        ),
      ],
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ??
              GradeCategory(id: newId(), courseId: courseId, name: '');
          Navigator.pop(
            context,
            base.copyWith(
              name: nameC.text.trim(),
              weightPercent:
                  (double.tryParse(weightC.text) ?? 0).clamp(0, 100),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Institution?> showInstitutionDialog(BuildContext context,
    {Institution? existing}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  var system = existing?.gradeSystem ?? GradeSystem.points;
  var scaleMax = existing?.gpaScaleMax ?? 4.0;
  if (![4.0, 5.0, 6.0].contains(scaleMax)) scaleMax = 4.0;
  var weighted = existing?.weighted ?? false;
  var complex = existing?.gpaComplex ?? false;
  var usePlusMinus = existing?.usePlusMinus ?? false;

  return showGlassDialog<Institution>(
    context,
    title: existing == null ? 'New institution' : 'Edit institution',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'School / institution name'),
          const SizedBox(height: 12),
          DropdownButtonFormField<GradeSystem>(
            initialValue: system,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Grading system'),
            items: [
              for (final g in GradeSystem.values)
                DropdownMenuItem(value: g, child: Text(g.label)),
            ],
            onChanged: (v) => setState(() => system = v ?? system),
          ),
          if (system == GradeSystem.points) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              initialValue: scaleMax,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(hintText: 'GPA scale'),
              items: const [
                DropdownMenuItem(value: 4.0, child: Text('4.0')),
                DropdownMenuItem(value: 5.0, child: Text('5.0')),
                DropdownMenuItem(value: 6.0, child: Text('6.0')),
              ],
              onChanged: (v) => setState(() => scaleMax = v ?? scaleMax),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Weighted scale'),
              subtitle: Text(
                'Honors/AP raise the ceiling: '
                '${scaleMax.toStringAsFixed(0)} → '
                '${(scaleMax + 1).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11),
              ),
              value: weighted,
              activeThumbColor: AppPalette.accent,
              onChanged: (v) => setState(() => weighted = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(complex ? 'Complex GPA' : 'Simple GPA'),
              subtitle: const Text(
                'Simple: A = 4.0.  Complex: +/− split it '
                '(A 4.0, A− 3.7, B+ 3.3 …)',
                style: TextStyle(fontSize: 11),
              ),
              value: complex,
              activeThumbColor: AppPalette.accent,
              onChanged: (v) => setState(() => complex = v),
            ),
          ],
          if (system == GradeSystem.letter)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Use +/− letters (A-, B+ …)'),
              value: usePlusMinus,
              activeThumbColor: AppPalette.accent,
              onChanged: (v) => setState(() => usePlusMinus = v),
            ),
          const SizedBox(height: 8),
          const Text(
            'The grading system applies to every current course filed '
            'under this institution.',
            style: TextStyle(fontSize: 11, color: AppPalette.textSecondary),
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ?? Institution(id: newId(), name: '');
          Navigator.pop(
            context,
            base.copyWith(
              name: nameC.text.trim(),
              gradeSystem: system,
              gpaScaleMax: scaleMax,
              weighted: weighted,
              gpaComplex: complex,
              usePlusMinus: usePlusMinus,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Semester?> showSemesterDialog(
  BuildContext context, {
  required String institutionId,
  Semester? existing,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final yearC = TextEditingController(
      text: (existing?.year ?? DateTime.now().year).toString());
  var term = existing?.term ?? AcademicTerm.fall;

  return showGlassDialog<Semester>(
    context,
    title: existing == null ? 'New semester' : 'Edit semester',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AcademicTerm>(
                  initialValue: term,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF241F45),
                  decoration: const InputDecoration(hintText: 'Term'),
                  items: [
                    for (final t in AcademicTerm.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => term = v ?? term),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: _field(yearC, 'Year',
                    keyboard: TextInputType.number),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Custom label (optional)',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary)),
              const SizedBox(height: 4),
              _field(nameC, 'Summer 1, Winter Minimester, etc...'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Leave the label blank to use "Term Year".',
            style: TextStyle(fontSize: 11, color: AppPalette.textSecondary),
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final base = existing ??
              Semester(id: newId(), institutionId: institutionId);
          Navigator.pop(
            context,
            base.copyWith(
              institutionId: institutionId,
              term: term,
              year: int.tryParse(yearC.text) ?? DateTime.now().year,
              name: nameC.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<PastCourse?> showPastCourseDialog(
  BuildContext context, {
  required String semesterId,
  PastCourse? existing,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final creditsC = TextEditingController(
      text: (existing?.creditHours ?? 3).toString());
  final pointsC = TextEditingController(
      text: (existing?.gradePoints ?? 4).toString());

  return showGlassDialog<PastCourse>(
    context,
    title: existing == null ? 'Add past class' : 'Edit past class',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(nameC, 'Class name'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _field(creditsC, 'Credit hours',
                    keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(
                child: _field(pointsC, 'Grade points',
                    keyboard: TextInputType.number)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Grade points are per credit (e.g. A = 4.0, B+ = 3.3). GPA is '
          'credit-weighted automatically.',
          style: TextStyle(fontSize: 11, color: AppPalette.textSecondary),
        ),
      ],
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ??
              PastCourse(id: newId(), semesterId: semesterId, name: '');
          Navigator.pop(
            context,
            base.copyWith(
              semesterId: semesterId,
              name: nameC.text.trim(),
              creditHours:
                  (double.tryParse(creditsC.text) ?? 3).clamp(0, 30),
              gradePoints:
                  (double.tryParse(pointsC.text) ?? 4).clamp(0, 5),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<EventItem?> showEventDialog(BuildContext context,
    {EventItem? existing, DateTime? initialDate}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final locC = TextEditingController(text: existing?.location ?? '');
  // New event from a calendar day → default to 9:00 on that day; otherwise
  // an hour from now. Editing always keeps the event's own start.
  var when = existing?.start ??
      (initialDate == null
          ? DateTime.now().add(const Duration(hours: 1))
          : DateTime(
              initialDate.year, initialDate.month, initialDate.day, 9));
  var type = existing?.type ?? EventType.personal;

  return showGlassDialog<EventItem>(
    context,
    title: existing == null ? 'New event' : 'Edit event',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(titleC, 'Event title'),
          const SizedBox(height: 12),
          _field(locC, 'Location (optional)'),
          const SizedBox(height: 12),
          DropdownButtonFormField<EventType>(
            initialValue: type,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Type'),
            items: [
              for (final t in EventType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => type = v ?? type),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDate(context, when);
                    if (picked != null) {
                      setState(() => when = DateTime(picked.year,
                          picked.month, picked.day, when.hour, when.minute));
                    }
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(relativeDay(when)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(when));
                    if (t != null) {
                      setState(() => when = DateTime(when.year, when.month,
                          when.day, t.hour, t.minute));
                    }
                  },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(TimeOfDay.fromDateTime(when).format(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (titleC.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            EventItem(
              id: existing?.id ?? newId(),
              title: titleC.text.trim(),
              start: when,
              type: type,
              location: locC.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Deck?> showDeckDialog(
  BuildContext context, {
  Deck? existing,
  List<DeckGroup> groups = const [],
  String? presetGroupId,
}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final descC = TextEditingController(text: existing?.description ?? '');
  var seed = existing?.colorSeed ?? 0;
  String? groupId = existing?.groupId ?? presetGroupId;
  // Drop a stale id (group was deleted out from under the deck) so the
  // dropdown doesn't render an empty selection.
  if (groupId != null && !groups.any((g) => g.id == groupId)) {
    groupId = null;
  }
  return showGlassDialog<Deck>(
    context,
    title: existing == null ? 'New deck' : 'Edit deck',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Deck name'),
          const SizedBox(height: 12),
          _field(descC, 'Description (optional)'),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: groupId,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(
                  hintText: 'Group (optional)'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Ungrouped')),
                for (final g in groups)
                  DropdownMenuItem(value: g.id, child: Text(g.name)),
              ],
              onChanged: (v) => setState(() => groupId = v),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0; i < AppPalette.categorySwatches.length; i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            seed == i ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ??
              Deck(id: newId(), name: '', createdAt: DateTime.now());
          Navigator.pop(
            context,
            base.copyWith(
              name: nameC.text.trim(),
              description: descC.text.trim(),
              colorSeed: seed,
              groupId: groupId,
              clearGroup: groupId == null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

/// Create / edit a [DeckGroup]. Mirrors [showFolderDialog] in shape — a
/// name field plus a swatch picker — so the Study page can group decks
/// the same way the To-do page groups tasks.
Future<DeckGroup?> showDeckGroupDialog(BuildContext context,
    {DeckGroup? existing}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  var seed = existing?.colorSeed ?? 0;
  return showGlassDialog<DeckGroup>(
    context,
    title: existing == null ? 'New group' : 'Edit group',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Group name'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (var i = 0; i < AppPalette.categorySwatches.length; i++)
                GestureDetector(
                  onTap: () => setState(() => seed = i),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppPalette.categorySwatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            seed == i ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          final base = existing ??
              DeckGroup(
                  id: newId(),
                  name: '',
                  createdAt: DateTime.now());
          Navigator.pop(
            context,
            base.copyWith(name: nameC.text.trim(), colorSeed: seed),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Flashcard?> showCardDialog(BuildContext context,
    {required String deckId, Flashcard? existing}) async {
  final frontC = TextEditingController(text: existing?.front ?? '');
  final backC = TextEditingController(text: existing?.back ?? '');

  // Currently-attached image filenames; mutated by the picker buttons.
  String? frontImg = existing?.frontImagePath;
  String? backImg = existing?.backImagePath;

  // Originals captured at open so we can clean up the disk copies if the
  // user replaces or clears them on save.
  final originalFront = existing?.frontImagePath;
  final originalBack = existing?.backImagePath;

  // Track every image we've stored inside this dialog session — if the
  // user ultimately cancels (or replaces a freshly-picked one), the
  // orphaned files get removed so we don't leak space.
  final pendingPicks = <String>{};

  final result = await showGlassDialog<Flashcard>(
    context,
    title: existing == null ? 'New card' : 'Edit card',
    content: StatefulBuilder(builder: (context, setLocal) {
      Future<void> pickImage({required bool front}) async {
        final stored = await CardImageStore.pickAndStore();
        if (stored == null) return;
        final previous = front ? frontImg : backImg;
        // If we replaced an image we picked earlier in this same dialog,
        // delete the stale on-disk copy right away — the user never saw
        // it persist so they won't miss it.
        if (previous != null && pendingPicks.contains(previous)) {
          await CardImageStore.deleteByName(previous);
          pendingPicks.remove(previous);
        }
        pendingPicks.add(stored);
        setLocal(() {
          if (front) {
            frontImg = stored;
          } else {
            backImg = stored;
          }
        });
      }

      Future<void> clearImage({required bool front}) async {
        final current = front ? frontImg : backImg;
        if (current != null && pendingPicks.contains(current)) {
          await CardImageStore.deleteByName(current);
          pendingPicks.remove(current);
        }
        setLocal(() {
          if (front) {
            frontImg = null;
          } else {
            backImg = null;
          }
        });
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardSideEditor(
            label: 'Front (question)',
            controller: frontC,
            imageName: frontImg,
            onPickImage: () => pickImage(front: true),
            onClearImage: () => clearImage(front: true),
          ),
          const SizedBox(height: 16),
          _CardSideEditor(
            label: 'Back (answer)',
            controller: backC,
            imageName: backImg,
            onPickImage: () => pickImage(front: false),
            onClearImage: () => clearImage(front: false),
          ),
        ],
      );
    }),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          // Front/back may be just an image — accept that too, since a
          // picture-only card is a valid use case.
          final fText = frontC.text.trim();
          final bText = backC.text.trim();
          if (fText.isEmpty && frontImg == null) return;
          if (bText.isEmpty && backImg == null) return;
          final base = existing ??
              Flashcard(
                  id: newId(),
                  deckId: deckId,
                  front: '',
                  back: '');
          Navigator.pop(
            context,
            base.copyWith(
              front: fText,
              back: bText,
              frontImagePath: frontImg,
              backImagePath: backImg,
              clearFrontImage: frontImg == null,
              clearBackImage: backImg == null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );

  if (result == null) {
    // Cancelled — nothing committed, so wipe any files we wrote.
    for (final name in pendingPicks) {
      await CardImageStore.deleteByName(name);
    }
  } else {
    // Saved — delete originals if the user replaced or removed them.
    if (originalFront != null && originalFront != result.frontImagePath) {
      await CardImageStore.deleteByName(originalFront);
    }
    if (originalBack != null && originalBack != result.backImagePath) {
      await CardImageStore.deleteByName(originalBack);
    }
  }
  return result;
}

/// One face of a card in the edit dialog: optional thumbnail with attach/
/// replace/remove controls, the markdown toolbar, and the multiline text
/// field. Pulled out so front and back stay symmetrical and the picker
/// state stays local to its row.
class _CardSideEditor extends StatelessWidget {
  const _CardSideEditor({
    required this.label,
    required this.controller,
    required this.imageName,
    required this.onPickImage,
    required this.onClearImage,
  });

  final String label;
  final TextEditingController controller;
  final String? imageName;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppPalette.textSecondary,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CardImageThumb(name: imageName),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: onPickImage,
                    icon: Icon(
                        imageName == null
                            ? Icons.add_photo_alternate_outlined
                            : Icons.swap_horiz_rounded,
                        size: 16),
                    label:
                        Text(imageName == null ? 'Add image' : 'Replace'),
                  ),
                  if (imageName != null)
                    TextButton.icon(
                      onPressed: onClearImage,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: MarkdownToolbar(controller: controller),
        ),
        const SizedBox(height: 6),
        _field(controller, 'Use **bold**, *italic*, `code`, - bullets',
            maxLines: 4),
      ],
    );
  }
}

/// 64×48 image preview used by the card editor. Resolves the filename to
/// an absolute path via [CardImageStore] (async) and falls back to a
/// placeholder while waiting or if the file is missing.
class _CardImageThumb extends StatelessWidget {
  const _CardImageThumb({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    if (name == null) {
      return Container(
        width: 64,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppPalette.glassFill.withValues(alpha: 0.25),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        child: const Icon(Icons.image_outlined,
            size: 20, color: AppPalette.textFaint),
      );
    }
    return FutureBuilder<File>(
      future: CardImageStore.fileFor(name!),
      builder: (context, snap) {
        final file = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            height: 48,
            child: file == null
                ? const ColoredBox(color: Colors.black26)
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black26,
                      child: Icon(Icons.broken_image_outlined,
                          size: 18, color: AppPalette.textFaint),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
