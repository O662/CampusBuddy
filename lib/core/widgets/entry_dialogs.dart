import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../data/models.dart';
import '../theme/app_palette.dart';
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
  var recurrence = existing?.recurrence ?? Recurrence.none;

  String? folderCourseId(String? fid) {
    if (fid == null) return null;
    for (final f in folders) {
      if (f.id == fid) return f.courseId;
    }
    return null;
  }

  return showGlassDialog<TaskItem>(
    context,
    title: existing == null ? 'New task' : 'Edit task',
    content: StatefulBuilder(
      builder: (context, setState) {
        final inherited = folderCourseId(folderId);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(titleC, 'What needs doing?'),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final p in Priority.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: priority == p,
                        selectedColor: p.color.withValues(alpha: 0.3),
                        onSelected: (_) => setState(() => priority = p),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: folderId,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(hintText: 'Folder'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('No folder')),
                for (final f in folders)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => folderId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickDate(
                          context, due ?? DateTime.now());
                      if (picked != null) setState(() => due = picked);
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(due == null
                        ? 'No due date'
                        : 'Due ${relativeDay(due!)}'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: _field(estC, 'Est. min',
                      keyboard: TextInputType.number),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Recurrence>(
              initialValue: recurrence,
              isExpanded: true,
              dropdownColor: const Color(0xFF241F45),
              decoration: const InputDecoration(hintText: 'Repeat'),
              items: [
                for (final r in Recurrence.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) =>
                  setState(() => recurrence = v ?? recurrence),
            ),
            if (recurrence.repeats && due == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Tip: set a due date so each repeat lands on the right '
                  'day.',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('This is an assignment'),
              subtitle: const Text(
                'Tracks a placeholder grade under its class',
                style: TextStyle(fontSize: 11),
              ),
              value: isAssignment,
              activeThumbColor: AppPalette.accent,
              onChanged: (v) => setState(() => isAssignment = v),
            ),
            if (isAssignment) ...[
              const SizedBox(height: 4),
              DropdownButtonFormField<String?>(
                initialValue: courseId,
                isExpanded: true,
                dropdownColor: const Color(0xFF241F45),
                decoration: const InputDecoration(hintText: 'Class'),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(inherited == null
                        ? 'No class'
                        : "Use folder's class"),
                  ),
                  for (final c in courses)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => courseId = v),
              ),
              if (inherited == null && courseId == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Pick a class (or link the folder to one) so the '
                    'grade has a home.',
                    style: TextStyle(
                        fontSize: 11, color: AppPalette.textSecondary),
                  ),
                ),
            ],
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
              estimatedMinutes: int.tryParse(estC.text) ?? 60,
              recurrence: recurrence,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
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

Future<Deck?> showDeckDialog(BuildContext context, {Deck? existing}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  final descC = TextEditingController(text: existing?.description ?? '');
  var seed = existing?.colorSeed ?? 0;
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
                  colorSeed: seed));
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
  return showGlassDialog<Flashcard>(
    context,
    title: existing == null ? 'New card' : 'Edit card',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(frontC, 'Front (question)', maxLines: 3),
        const SizedBox(height: 12),
        _field(backC, 'Back (answer)', maxLines: 3),
      ],
    ),
    actions: (context) => [
      TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (frontC.text.trim().isEmpty || backC.text.trim().isEmpty) {
            return;
          }
          final base = existing ??
              Flashcard(
                  id: newId(),
                  deckId: deckId,
                  front: '',
                  back: '');
          Navigator.pop(context,
              base.copyWith(front: frontC.text.trim(), back: backC.text.trim()));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
