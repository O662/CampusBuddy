import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// Course a task's grade resolves to: explicit link first, else the folder's.
String? _courseIdFor(TaskItem t, List<TaskFolder> folders) {
  if (t.courseId != null) return t.courseId;
  if (t.folderId == null) return null;
  for (final f in folders) {
    if (f.id == t.folderId) return f.courseId;
  }
  return null;
}

class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final folders = ref.watch(foldersProvider);
    final courses = ref.watch(coursesProvider);
    final coursesById = ref.watch(coursesByIdProvider);

    final open = tasks.where((t) => !t.done).toList();
    final done = tasks.where((t) => t.done).toList();

    int cmp(TaskItem a, TaskItem b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      if (a.due == null && b.due == null) return 0;
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    }

    final folderIds = {for (final f in folders) f.id};
    List<TaskItem> openIn(String? id) =>
        open.where((t) => t.folderId == id).toList()..sort(cmp);
    final unfiled = open
        .where(
            (t) => t.folderId == null || !folderIds.contains(t.folderId))
        .toList()
      ..sort(cmp);

    final tasksNotifier = ref.read(tasksProvider.notifier);
    final foldersNotifier = ref.read(foldersProvider.notifier);

    Future<void> newTask({String? folderId}) async {
      final t = await showTaskDialog(context,
          folders: folders, courses: courses, presetFolderId: folderId);
      if (t != null) tasksNotifier.save(t);
    }

    Future<void> editTask(TaskItem t) async {
      final e = await showTaskDialog(context,
          existing: t, folders: folders, courses: courses);
      if (e != null) tasksNotifier.save(e);
    }

    Future<void> newFolder() async {
      final f = await showFolderDialog(context, courses: courses);
      if (f != null) foldersNotifier.upsert(f);
    }

    Future<void> editFolder(TaskFolder f) async {
      final e =
          await showFolderDialog(context, existing: f, courses: courses);
      if (e != null) foldersNotifier.upsert(e);
    }

    Future<void> deleteFolder(TaskFolder f) async {
      final n = tasks.where((t) => t.folderId == f.id).length;
      final ok = await confirmDelete(
        context,
        title: 'Delete "${f.name}"?',
        message: n == 0
            ? 'The folder will be removed.'
            : 'The folder will be removed and its $n task'
                "${n == 1 ? '' : 's'} moved to Unfiled.",
      );
      if (!ok) return;
      for (final t in tasks.where((t) => t.folderId == f.id)) {
        await tasksNotifier.save(t.copyWith(clearFolder: true));
      }
      foldersNotifier.remove(f.id);
    }

    Widget group(TaskFolder? folder, List<TaskItem> items) {
      final courseId = folder?.courseId;
      final course = courseId == null ? null : coursesById[courseId];
      return _TaskGroup(
        name: folder?.name ?? 'Unfiled',
        color: folder?.color ?? AppPalette.textFaint,
        course: course,
        tasks: items,
        rowBuilder: (t) {
          final c = t.isAssignment
              ? coursesById[_courseIdFor(t, folders)]
              : null;
          return _TaskRow(
            task: t,
            course: c,
            onToggle: () =>
                tasksNotifier.save(t.copyWith(done: !t.done)),
            onEdit: () => editTask(t),
            onDelete: () => tasksNotifier.delete(t.id),
          );
        },
        onAddTask: () => newTask(folderId: folder?.id),
        onEditFolder: folder == null ? null : () => editFolder(folder),
        onDeleteFolder: folder == null ? null : () => deleteFolder(folder),
      );
    }

    return PageBody(
      title: 'To-do',
      subtitle: '${open.length} open · ${done.length} done · '
          '${folders.length} folder${folders.length == 1 ? '' : 's'}',
      actions: [
        SoftButton(label: 'New folder', icon: Icons.create_new_folder_outlined, onTap: newFolder),
        const SizedBox(width: 8),
        SoftButton(
            label: 'New task', filled: true, onTap: () => newTask()),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open.isEmpty && folders.isEmpty)
            GlassContainer(
              child: const EmptyHint(
                  'Nothing to do — take a breath. 🌿\n'
                  'Make a folder to group tasks by class or area of life.'),
            ),
          for (final f in folders) ...[
            group(f, openIn(f.id)),
            const SizedBox(height: 16),
          ],
          if (unfiled.isNotEmpty) ...[
            group(null, unfiled),
            const SizedBox(height: 16),
          ],
          if (done.isNotEmpty)
            GlassCard(
              title: 'Completed (${done.length})',
              icon: Icons.done_all_rounded,
              child: Column(
                children: [
                  for (final t in done..sort(cmp))
                    _TaskRow(
                      task: t,
                      course: t.isAssignment
                          ? coursesById[_courseIdFor(t, folders)]
                          : null,
                      onToggle: () =>
                          tasksNotifier.save(t.copyWith(done: false)),
                      onDelete: () => tasksNotifier.delete(t.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One folder's card (or the "Unfiled" bucket when folder ops are null).
class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    required this.name,
    required this.color,
    required this.course,
    required this.tasks,
    required this.rowBuilder,
    required this.onAddTask,
    this.onEditFolder,
    this.onDeleteFolder,
  });

  final String name;
  final Color color;
  final Course? course;
  final List<TaskItem> tasks;
  final Widget Function(TaskItem) rowBuilder;
  final VoidCallback onAddTask;
  final VoidCallback? onEditFolder;
  final VoidCallback? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    final hasFolderOps = onEditFolder != null || onDeleteFolder != null;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (course != null) ...[
                GlassChip(
                    label: course!.name,
                    color: course!.color,
                    icon: Icons.school_rounded),
                const SizedBox(width: 6),
              ],
              GlassChip(label: '${tasks.length}'),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                color: AppPalette.lavender,
                tooltip: 'Add task here',
                onPressed: onAddTask,
              ),
              if (hasFolderOps)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: AppPalette.textSecondary),
                  color: const Color(0xFF241F45),
                  tooltip: 'Folder options',
                  onSelected: (v) {
                    if (v == 'edit') onEditFolder?.call();
                    if (v == 'delete') onDeleteFolder?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 20),
                        title: Text('Edit folder'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            size: 20, color: AppPalette.danger),
                        title: Text('Delete folder'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(height: 22),
          if (tasks.isEmpty)
            const EmptyHint('Nothing here yet.')
          else
            for (final t in tasks) rowBuilder(t),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onToggle,
    this.course,
    this.onEdit,
    this.onDelete,
  });

  final TaskItem task;
  final Course? course;
  final VoidCallback onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (task.due != null) 'Due ${relativeDay(task.due!)}',
      if (task.isAssignment) course?.name ?? 'Assignment',
    ].join(' · ');

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
              color:
                  task.done ? AppPalette.success : AppPalette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.done
                              ? AppPalette.textFaint
                              : AppPalette.textPrimary,
                        ),
                      ),
                    ),
                    if (task.isAssignment) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.school_rounded,
                          size: 13,
                          color: (course?.color ?? AppPalette.lavender)),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta,
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
