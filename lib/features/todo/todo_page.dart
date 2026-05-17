import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final open = tasks.where((t) => !t.done).toList()
      ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
    final done = tasks.where((t) => t.done).toList();

    return PageBody(
      title: 'To-do',
      subtitle: '${open.length} open · ${done.length} done',
      actions: [
        SoftButton(
          label: 'New task',
          filled: true,
          onTap: () async {
            final t = await showTaskDialog(context);
            if (t != null) ref.read(tasksProvider.notifier).upsert(t);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
            child: open.isEmpty
                ? const EmptyHint('Nothing to do — take a breath. 🌿')
                : Column(
                    children: [
                      for (final t in open)
                        _TaskRow(task: t, onToggle: () {
                          ref
                              .read(tasksProvider.notifier)
                              .upsert(t.copyWith(done: true));
                        }, onEdit: () async {
                          final e = await showTaskDialog(context,
                              existing: t);
                          if (e != null) {
                            ref.read(tasksProvider.notifier).upsert(e);
                          }
                        }, onDelete: () {
                          ref.read(tasksProvider.notifier).remove(t.id);
                        }),
                    ],
                  ),
          ),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            GlassCard(
              title: 'Completed',
              icon: Icons.done_all_rounded,
              child: Column(
                children: [
                  for (final t in done)
                    _TaskRow(
                      task: t,
                      onToggle: () => ref
                          .read(tasksProvider.notifier)
                          .upsert(t.copyWith(done: false)),
                      onDelete: () =>
                          ref.read(tasksProvider.notifier).remove(t.id),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(999),
            child: Icon(
              task.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: task.done ? AppPalette.success : AppPalette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    decoration:
                        task.done ? TextDecoration.lineThrough : null,
                    color: task.done
                        ? AppPalette.textFaint
                        : AppPalette.textPrimary,
                  ),
                ),
                if (task.due != null)
                  Text('Due ${relativeDay(task.due!)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
          GlassChip(label: task.priority.label, color: task.priority.color),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppPalette.textSecondary,
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppPalette.textSecondary,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
