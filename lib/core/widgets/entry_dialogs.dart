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

Future<Assignment?> showAssignmentDialog(
  BuildContext context, {
  Assignment? existing,
  required List<Course> courses,
  DateTime? presetDate,
}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final notesC = TextEditingController(text: existing?.notes ?? '');
  final estC = TextEditingController(
      text: (existing?.estimatedMinutes ?? 60).toString());
  var due = existing?.dueDate ?? presetDate ?? DateTime.now();
  String? courseId = existing?.courseId;

  return showGlassDialog<Assignment>(
    context,
    title: existing == null ? 'New assignment' : 'Edit assignment',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(titleC, 'Assignment title'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: courseId,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Course (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No course')),
              for (final c in courses)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => courseId = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _pickDate(context, due);
                    if (picked != null) setState(() => due = picked);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Due ${relativeDay(due)}'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: _field(estC, 'Est. min',
                    keyboard: TextInputType.number),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(notesC, 'Notes (optional)', maxLines: 3),
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
          final base = existing ??
              Assignment(id: newId(), title: '', dueDate: due);
          Navigator.pop(
            context,
            base.copyWith(
              title: titleC.text.trim(),
              courseId: courseId,
              clearCourse: courseId == null,
              dueDate: due,
              estimatedMinutes: int.tryParse(estC.text) ?? 60,
              notes: notesC.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<TaskItem?> showTaskDialog(BuildContext context,
    {TaskItem? existing}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  var priority = existing?.priority ?? Priority.medium;
  DateTime? due = existing?.due;

  return showGlassDialog<TaskItem>(
    context,
    title: existing == null ? 'New task' : 'Edit task',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
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
          OutlinedButton.icon(
            onPressed: () async {
              final picked =
                  await _pickDate(context, due ?? DateTime.now());
              if (picked != null) setState(() => due = picked);
            },
            icon: const Icon(Icons.event, size: 18),
            label: Text(due == null ? 'No due date' : 'Due ${relativeDay(due!)}'),
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
          final base = existing ??
              TaskItem(
                  id: newId(),
                  title: '',
                  createdAt: DateTime.now());
          Navigator.pop(
            context,
            base.copyWith(
                title: titleC.text.trim(),
                priority: priority,
                due: due,
                clearDue: due == null),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<Course?> showCourseDialog(BuildContext context,
    {Course? existing}) async {
  final nameC = TextEditingController(text: existing?.name ?? '');
  var seed = existing?.colorSeed ?? 0;
  return showGlassDialog<Course>(
    context,
    title: existing == null ? 'New course' : 'Edit course',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(nameC, 'Course name'),
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
          final base = existing ?? Course(id: newId(), name: '');
          Navigator.pop(context,
              base.copyWith(name: nameC.text.trim(), colorSeed: seed));
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
}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final earnedC =
      TextEditingController(text: existing?.earned.toString() ?? '');
  final totalC =
      TextEditingController(text: existing?.total.toString() ?? '100');
  final weightC =
      TextEditingController(text: (existing?.weight ?? 1).toString());
  String? courseId = existing?.courseId ?? courses.firstOrNull?.id;

  return showGlassDialog<GradeEntry>(
    context,
    title: existing == null ? 'Add grade' : 'Edit grade',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: courseId,
            isExpanded: true,
            dropdownColor: const Color(0xFF241F45),
            decoration: const InputDecoration(hintText: 'Course'),
            items: [
              for (final c in courses)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => courseId = v),
          ),
          const SizedBox(height: 12),
          _field(titleC, 'Item (e.g. Quiz 2)'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _field(earnedC, 'Earned',
                      keyboard: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(totalC, 'Out of',
                      keyboard: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(weightC, 'Weight',
                      keyboard: TextInputType.number)),
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
          if (courseId == null || titleC.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            GradeEntry(
              id: existing?.id ?? newId(),
              courseId: courseId!,
              title: titleC.text.trim(),
              earned: double.tryParse(earnedC.text) ?? 0,
              total: double.tryParse(totalC.text) ?? 100,
              weight: double.tryParse(weightC.text) ?? 1,
              date: existing?.date ?? DateTime.now(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<EventItem?> showEventDialog(BuildContext context,
    {EventItem? existing}) async {
  final titleC = TextEditingController(text: existing?.title ?? '');
  final locC = TextEditingController(text: existing?.location ?? '');
  var when = existing?.start ?? DateTime.now().add(const Duration(hours: 1));
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
