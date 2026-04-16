import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/todo_task.dart';
import '../../providers/todo_provider.dart';

class AddTodoTaskDialog extends StatefulWidget {
  final TodoTask? existing;
  final String? initialCategoryId;
  const AddTodoTaskDialog({super.key, this.existing, this.initialCategoryId});

  @override
  State<AddTodoTaskDialog> createState() => _AddTodoTaskDialogState();
}

class _AddTodoTaskDialogState extends State<AddTodoTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late String _categoryId;
  late TaskPriority _priority;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _priority = e?.priority ?? TaskPriority.medium;
    _dueDate = e?.dueDate;

    final categories =
        context.read<TodoProvider>().categories;
    final firstId =
        categories.isNotEmpty ? categories.first.id : '';
    _categoryId =
        e?.categoryId ?? widget.initialCategoryId ?? firstId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dueDate != null
          ? TimeOfDay.fromDateTime(_dueDate!)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null) return;
    setState(() {
      _dueDate = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final task = TodoTask(
      id: widget.existing?.id ?? const Uuid().v4(),
      categoryId: _categoryId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      dueDate: _dueDate,
      priority: _priority,
      isCompleted: widget.existing?.isCompleted ?? false,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final categories = context.watch<TodoProvider>().categories;
    final theme = Theme.of(context);

    final priorityColors = {
      TaskPriority.low: Colors.green,
      TaskPriority.medium: Colors.orange,
      TaskPriority.high: Colors.red,
    };

    return AlertDialog(
      title: Text(isEdit ? 'Edit Task' : 'New Task'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category selector
                if (categories.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: categories.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(c.icon,
                                size: 18,
                                color: c.color),
                            const SizedBox(width: 8),
                            Text(c.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _categoryId = v!),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    hintText: 'e.g. Chapter 4 Homework',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a title'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // Priority selector
                Text('Priority',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: TaskPriority.values.map((p) {
                    final selected = _priority == p;
                    final color = priorityColors[p]!;
                    return Padding(
                      padding:
                          const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _priority = p),
                        selectedColor:
                            color.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: selected ? color : null,
                          fontWeight: selected
                              ? FontWeight.w600
                              : null,
                        ),
                        side: selected
                            ? BorderSide(color: color)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Due date/time
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDateTime,
                        icon: const Icon(
                            Icons.calendar_today,
                            size: 16),
                        label: Text(_dueDate != null
                            ? DateFormat('MMM d, h:mm a')
                                .format(_dueDate!)
                            : 'Set Due Date'),
                      ),
                    ),
                    if (_dueDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear,
                            size: 18),
                        tooltip: 'Clear due date',
                        onPressed: () =>
                            setState(() => _dueDate = null),
                      ),
                    ],
                  ],
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
          child: Text(isEdit ? 'Save' : 'Add Task'),
        ),
      ],
    );
  }
}
