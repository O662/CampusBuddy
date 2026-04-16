import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/todo_category.dart';
import '../../models/todo_task.dart';
import '../../providers/todo_provider.dart';
import 'add_category_dialog.dart';
import 'add_todo_task_dialog.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  String? _selectedCategoryId;

  Future<void> _addOrEditCategory([TodoCategory? existing]) async {
    final result = await showDialog<TodoCategory>(
      context: context,
      builder: (_) => AddCategoryDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final provider = context.read<TodoProvider>();
    if (existing != null) {
      await provider.updateCategory(result);
    } else {
      await provider.addCategory(result);
      setState(() => _selectedCategoryId = result.id);
    }
  }

  Future<void> _addOrEditTask([TodoTask? existing]) async {
    final result = await showDialog<TodoTask>(
      context: context,
      builder: (_) => AddTodoTaskDialog(
        existing: existing,
        initialCategoryId: _selectedCategoryId,
      ),
    );
    if (result == null || !mounted) return;
    final provider = context.read<TodoProvider>();
    if (existing != null) {
      await provider.updateTask(result);
    } else {
      await provider.addTask(result);
    }
  }

  Future<void> _confirmDeleteCategory(
      BuildContext context, TodoCategory cat) async {
    final provider = context.read<TodoProvider>();
    final count = provider.totalCount(cat.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          count > 0
              ? 'Delete "${cat.name}" and its $count task${count == 1 ? "" : "s"}?'
              : 'Delete "${cat.name}"?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      if (_selectedCategoryId == cat.id) {
        setState(() => _selectedCategoryId = null);
      }
      await provider.removeCategory(cat.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final categories = provider.categories;

    // Auto-select first category if nothing selected
    if (_selectedCategoryId == null && categories.isNotEmpty) {
      _selectedCategoryId = categories.first.id;
    } else if (categories.isEmpty) {
      _selectedCategoryId = null;
    }

    final selectedCat = _selectedCategoryId != null
        ? provider.categoryById(_selectedCategoryId!)
        : null;

    return Row(
      children: [
        // ── Category sidebar ────────────────────────────────────────────────
        Container(
          width: 240,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                  color: Theme.of(context).dividerColor, width: 1),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('Classes',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      tooltip: 'Add category',
                      onPressed: _addOrEditCategory,
                      style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: categories.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text('No classes yet',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.5))),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _addOrEditCategory,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Class'),
                                style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        itemCount: categories.length,
                        itemBuilder: (ctx, i) {
                          final cat = categories[i];
                          final isSelected =
                              _selectedCategoryId == cat.id;
                          final pending = provider.pendingCount(cat.id);
                          return _CategoryTile(
                            category: cat,
                            isSelected: isSelected,
                            pendingCount: pending,
                            onTap: () => setState(
                                () => _selectedCategoryId = cat.id),
                            onEdit: () => _addOrEditCategory(cat),
                            onDelete: () =>
                                _confirmDeleteCategory(context, cat),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        // ── Task panel ───────────────────────────────────────────────────────
        Expanded(
          child: selectedCat == null
              ? _EmptyPrompt(onAddCategory: _addOrEditCategory)
              : _TaskPanel(
                  category: selectedCat,
                  onAddTask: _addOrEditTask,
                  onEditTask: _addOrEditTask,
                ),
        ),
      ],
    );
  }
}

// ── Category tile ─────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final TodoCategory category;
  final bool isSelected;
  final int pendingCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.pendingCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? category.color.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: category.color.withValues(alpha: 0.4),
                    width: 1)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(category.icon,
                    size: 16, color: category.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? category.color : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$pendingCount',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: category.color)),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 16,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 16),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Colors.red)),
                      ])),
                ],
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Task panel ────────────────────────────────────────────────────────────────

enum _TaskFilter { all, pending, completed }

class _TaskPanel extends StatefulWidget {
  final TodoCategory category;
  final VoidCallback onAddTask;
  final void Function(TodoTask) onEditTask;

  const _TaskPanel({
    required this.category,
    required this.onAddTask,
    required this.onEditTask,
  });

  @override
  State<_TaskPanel> createState() => _TaskPanelState();
}

class _TaskPanelState extends State<_TaskPanel> {
  _TaskFilter _filter = _TaskFilter.pending;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    final allTasks = provider.tasksForCategory(widget.category.id);
    final tasks = allTasks.where((t) {
      switch (_filter) {
        case _TaskFilter.all:
          return true;
        case _TaskFilter.pending:
          return !t.isCompleted;
        case _TaskFilter.completed:
          return t.isCompleted;
      }
    }).toList();
    final theme = Theme.of(context);
    final catColor = widget.category.color;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: BoxDecoration(
            border: Border(
                bottom:
                    BorderSide(color: theme.dividerColor, width: 1)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.category.icon,
                    size: 20, color: catColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.category.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(
                      '${allTasks.where((t) => !t.isCompleted).length} pending  •  ${allTasks.where((t) => t.isCompleted).length} completed',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              // Filter chips
              SegmentedButton<_TaskFilter>(
                segments: const [
                  ButtonSegment(
                      value: _TaskFilter.pending,
                      label: Text('Pending')),
                  ButtonSegment(
                      value: _TaskFilter.completed,
                      label: Text('Done')),
                  ButtonSegment(
                      value: _TaskFilter.all, label: Text('All')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) =>
                    setState(() => _filter = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: widget.onAddTask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Task'),
                style: FilledButton.styleFrom(
                    backgroundColor: catColor),
              ),
            ],
          ),
        ),
        // Task list
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt,
                          size: 64,
                          color: catColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _filter == _TaskFilter.completed
                            ? 'Nothing completed yet'
                            : 'All done! No pending tasks',
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final task = tasks[i];
                    return _TaskRow(
                      task: task,
                      categoryColor: catColor,
                      onToggle: () =>
                          provider.toggleComplete(task.id),
                      onEdit: () => widget.onEditTask(task),
                      onDelete: () => provider.removeTask(task.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Individual task row ───────────────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final TodoTask task;
  final Color categoryColor;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.categoryColor,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityColors = {
      TaskPriority.low: Colors.green,
      TaskPriority.medium: Colors.orange,
      TaskPriority.high: Colors.red,
    };
    final priorityColor = priorityColors[task.priority]!;

    bool isOverdue = !task.isCompleted &&
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now());

    return Card(
      elevation: 0,
      color: task.isCompleted
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: task.isCompleted
              ? Colors.transparent
              : categoryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Checkbox
            Transform.scale(
              scale: 1.1,
              child: Checkbox(
                value: task.isCompleted,
                onChanged: (_) => onToggle(),
                activeColor: categoryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 4),
            // Priority dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? Colors.transparent
                    : priorityColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            // Title + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      color: task.isCompleted
                          ? theme.colorScheme.onSurface
                              .withValues(alpha: 0.4)
                          : null,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Due date
            if (task.dueDate != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? Colors.red.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: isOverdue
                          ? Colors.red
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, h:mm a').format(task.dueDate!),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: isOverdue
                              ? Colors.red
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
            // Priority label
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: priorityColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(task.priority.label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: priorityColor)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: onEdit,
              style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 16, color: theme.colorScheme.error),
              onPressed: onDelete,
              style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyPrompt extends StatelessWidget {
  final VoidCallback onAddCategory;
  const _EmptyPrompt({required this.onAddCategory});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.class_outlined,
              size: 72,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text('Create a class to get started',
              style: theme.textTheme.titleLarge?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          Text('Add your classes, labs, and projects on the left',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add),
            label: const Text('Add a Class'),
          ),
        ],
      ),
    );
  }
}
