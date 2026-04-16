import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/schedule_block.dart';
import '../../models/todo_category.dart';
import '../../providers/todo_provider.dart';

class AddScheduleBlockDialog extends StatefulWidget {
  final ScheduleBlock? existing;
  final int? initialDay;
  final int? initialStartMinutes;

  const AddScheduleBlockDialog({
    super.key,
    this.existing,
    this.initialDay,
    this.initialStartMinutes,
  });

  @override
  State<AddScheduleBlockDialog> createState() =>
      _AddScheduleBlockDialogState();
}

class _AddScheduleBlockDialogState extends State<AddScheduleBlockDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late List<int> _selectedDays;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _categoryId;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _selectedDays = e?.daysOfWeek.toList() ??
        (widget.initialDay != null ? [widget.initialDay!] : [DateTime.monday]);
    final startMin = e?.startMinutes ?? widget.initialStartMinutes ?? 9 * 60;
    final endMin = e?.endMinutes ?? startMin + 60;
    _startTime = TimeOfDay(hour: startMin ~/ 60, minute: startMin % 60);
    _endTime = TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60);
    _categoryId = e?.categoryId;
    _colorValue = e?.colorValue ?? TodoCategory.palette[4];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        // Auto-advance end time if needed
        if (_toMinutes(picked) >= _toMinutes(_endTime)) {
          final newEnd = picked.hour * 60 + picked.minute + 60;
          _endTime = TimeOfDay(
              hour: (newEnd ~/ 60).clamp(0, 23), minute: newEnd % 60);
        }
      } else {
        _endTime = picked;
      }
    });
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one day')));
      return;
    }
    if (_toMinutes(_startTime) >= _toMinutes(_endTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time')));
      return;
    }

    final cat = _categoryId != null
        ? context.read<TodoProvider>().categoryById(_categoryId!)
        : null;

    final block = ScheduleBlock(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: _titleCtrl.text.trim(),
      categoryId: _categoryId,
      daysOfWeek: List.from(_selectedDays),
      startMinutes: _toMinutes(_startTime),
      endMinutes: _toMinutes(_endTime),
      colorValue: cat?.colorValue ?? _colorValue,
      notes: _notesCtrl.text.trim(),
    );
    Navigator.of(context).pop(block);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);
    final categories = context.watch<TodoProvider>().categories;
    final selectedCat = _categoryId != null
        ? categories.cast<TodoCategory?>().firstWhere(
            (c) => c?.id == _categoryId,
            orElse: () => null)
        : null;
    final activeColor =
        selectedCat != null ? selectedCat.color : Color(_colorValue);

    const dayLabels = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return AlertDialog(
      title: Text(isEdit ? 'Edit Block' : 'New Schedule Block'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Block Title',
                    hintText: 'e.g. Math Study, Physics Lab',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 16),
                // Link to category
                if (categories.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(
                      labelText: 'Link to Class (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— None —')),
                      ...categories.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Row(children: [
                              Icon(c.icon, size: 16, color: c.color),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ]),
                          )),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 16),
                ],
                // Days of week
                Text('Days', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    final day = i + 1; // 1=Mon … 7=Sun
                    final selected = _selectedDays.contains(day);
                    return FilterChip(
                      label: Text(dayLabels[day]),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                      }),
                      selectedColor: activeColor.withValues(alpha: 0.2),
                      checkmarkColor: activeColor,
                      side: selected
                          ? BorderSide(color: activeColor)
                          : null,
                      labelStyle: TextStyle(
                          color: selected ? activeColor : null,
                          fontWeight: selected ? FontWeight.w600 : null),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                // Time range
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'Start',
                        time: _fmtTime(_startTime),
                        color: activeColor,
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeButton(
                        label: 'End',
                        time: _fmtTime(_endTime),
                        color: activeColor,
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ],
                ),
                // Custom color (only shown when no category linked)
                if (selectedCat == null) ...[
                  const SizedBox(height: 16),
                  Text('Color', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: TodoCategory.palette.map((c) {
                      final selected = c == _colorValue;
                      return GestureDetector(
                        onTap: () => setState(() => _colorValue = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? theme.colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: activeColor),
          child: Text(isEdit ? 'Save' : 'Add Block'),
        ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 2),
            Text(time,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
