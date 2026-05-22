import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
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

/// Sentinel selection key used by the list view to mean "the Unfiled
/// bucket" (distinct from a folder id, which is always a uuid).
const String _kUnfiledKey = '__unfiled__';

/// Sentinel selection key for the Completed pane — surfaced in the folder
/// sidebar so finished tasks live in their own "page" instead of fighting
/// the body for vertical space at the bottom.
const String _kCompletedKey = '__completed__';

class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  /// Which row is highlighted in list mode. `null` means "pick a sensible
  /// default" — build() will fall back to the first folder, or to Unfiled
  /// if there are no folders but some unfiled tasks exist.
  String? _selectedKey;

  /// Branches task deletion on whether the task has a linked gradebook
  /// entry. Plain tasks delete immediately (matching the previous one-tap
  /// behaviour); assignments prompt so the user can choose whether to
  /// also remove the gradebook entry or keep it as a standalone item.
  Future<void> _deleteTask(TaskItem t) async {
    final tasksNotifier = ref.read(tasksProvider.notifier);
    final linked = ref
        .read(gradesProvider)
        .where((g) => g.id == 'task-${t.id}')
        .firstOrNull;

    if (linked == null) {
      await tasksNotifier.delete(t.id);
      return;
    }

    final coursesById = ref.read(coursesByIdProvider);
    final courseName =
        coursesById[linked.courseId]?.name ?? 'this class';
    final removeBoth = await confirmDeleteTaskWithGrade(
      context,
      taskTitle: t.title.isEmpty ? 'this task' : t.title,
      courseName: courseName,
      hasScore: linked.isGraded,
    );
    if (removeBoth == null) return; // cancelled
    await tasksNotifier.delete(t.id, keepGrade: !removeBoth);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final folders = ref.watch(foldersProvider);
    final courses = ref.watch(coursesProvider);
    final coursesById = ref.watch(coursesByIdProvider);
    final gradeCategories = ref.watch(gradeCategoriesProvider);
    final viewMode = ref.watch(todoViewModeProvider);
    final hideDone = ref.watch(hideCompletedTasksProvider);

    final open = tasks.where((t) => !t.done).toList();
    // When the global hide-completed switch is on, drop finished tasks
    // entirely — the Completed pane and sidebar row go with them.
    final done =
        hideDone ? const <TaskItem>[] : tasks.where((t) => t.done).toList();

    int cmp(TaskItem a, TaskItem b) {
      final byPriority = b.priority.index.compareTo(a.priority.index);
      if (byPriority != 0) return byPriority;
      if (a.due == null && b.due == null) return 0;
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    }

    final folderIds = {for (final f in folders) f.id};
    // Folders are laid out by manual order; the name tiebreaker keeps the
    // layout stable for legacy folders that haven't been reordered yet.
    final orderedFolders = [...folders]
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

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
          folders: folders,
          courses: courses,
          categories: gradeCategories,
          presetFolderId: folderId);
      if (t != null) tasksNotifier.save(t);
    }

    Future<void> editTask(TaskItem t) async {
      final e = await showTaskDialog(context,
          existing: t,
          folders: folders,
          courses: courses,
          categories: gradeCategories);
      if (e != null) tasksNotifier.save(e);
    }

    Future<void> newFolder() async {
      final f = await showFolderDialog(context, courses: courses);
      if (f == null) return;
      // Drop new folders at the end so the existing layout stays put.
      final isNew = !folderIds.contains(f.id);
      TaskFolder toSave = f;
      if (isNew && folders.isNotEmpty) {
        final maxOrder =
            folders.map((x) => x.order).reduce((a, b) => a > b ? a : b);
        toSave = f.copyWith(order: maxOrder + 1);
      }
      await foldersNotifier.upsert(toSave);
      // In list mode, jump straight to the new folder so the user sees the
      // empty pane and can start adding tasks immediately.
      if (isNew && viewMode == TodoViewMode.list) {
        setState(() => _selectedKey = toSave.id);
      }
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
      await foldersNotifier.remove(f.id);
      // If the deleted folder was the selected one, let build() pick a
      // fresh default next frame.
      if (_selectedKey == f.id) {
        setState(() => _selectedKey = null);
      }
    }

    /// Drop [moving] into [target]'s slot and persist the new sequence.
    void reorderFolder(TaskFolder moving, TaskFolder target) {
      if (moving.id == target.id) return;
      final list = [...orderedFolders];
      final from = list.indexWhere((x) => x.id == moving.id);
      final targetIndex = list.indexWhere((x) => x.id == target.id);
      if (from < 0 || targetIndex < 0 || from == targetIndex) return;
      list.removeAt(from);
      final insertAt = from < targetIndex
          ? list.indexWhere((x) => x.id == target.id) + 1
          : list.indexWhere((x) => x.id == target.id);
      list.insert(insertAt, moving);
      foldersNotifier.reorder(list);
    }

    /// Builds the Completed pane — same glass-card shape as a folder so it
    /// drops into either the list-mode detail area or the grid as the last
    /// card without looking out of place.
    Widget completedPane() {
      final items = [...done]..sort(cmp);
      return _CompletedGroup(
        tasks: items,
        rowBuilder: (t) => _TaskRow(
          task: t,
          course: t.isAssignment
              ? coursesById[_courseIdFor(t, folders)]
              : null,
          onToggle: () =>
              tasksNotifier.save(t.copyWith(done: false)),
          onDelete: () => _deleteTask(t),
        ),
      );
    }

    /// Builds the card shown for one folder (or the Unfiled bucket when
    /// folder ops are null).
    Widget groupCard(TaskFolder? folder, List<TaskItem> items) {
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
            onDelete: () => _deleteTask(t),
          );
        },
        onAddTask: () => newTask(folderId: folder?.id),
        onEditFolder: folder == null ? null : () => editFolder(folder),
        onDeleteFolder: folder == null ? null : () => deleteFolder(folder),
      );
    }

    // ----- Resolve the effective selection for list mode ------------------
    // _selectedKey may be stale (folder deleted, or null on first build).
    // We never mutate state here — we just compute the key that should
    // actually drive the right pane this frame.
    String? resolveSelection() {
      String? fallback() {
        if (orderedFolders.isNotEmpty) return orderedFolders.first.id;
        if (unfiled.isNotEmpty) return _kUnfiledKey;
        if (done.isNotEmpty) return _kCompletedKey;
        return null;
      }

      final key = _selectedKey;
      if (key == null) return fallback();
      if (key == _kUnfiledKey) {
        return unfiled.isNotEmpty ? _kUnfiledKey : fallback();
      }
      if (key == _kCompletedKey) {
        return done.isNotEmpty ? _kCompletedKey : fallback();
      }
      if (orderedFolders.any((f) => f.id == key)) return key;
      return fallback();
    }

    final selection = resolveSelection();

    Widget body() {
      if (open.isEmpty && folders.isEmpty) {
        return GlassContainer(
          child: const EmptyHint(
              'Nothing to do — take a breath. 🌿\n'
              'Make a folder to group tasks by class or area of life.'),
        );
      }
      if (viewMode == TodoViewMode.list) {
        return _ListView(
          folders: orderedFolders,
          counts: {
            for (final f in orderedFolders) f.id: openIn(f.id).length,
          },
          coursesById: coursesById,
          unfiledCount: unfiled.length,
          completedCount: done.length,
          selectedKey: selection,
          onSelect: (key) => setState(() => _selectedKey = key),
          onReorder: reorderFolder,
          detail: () {
            if (selection == null) {
              return GlassContainer(
                child: const EmptyHint(
                  'Pick a folder on the left, or create one to get started.',
                  icon: Icons.folder_open_rounded,
                ),
              );
            }
            if (selection == _kUnfiledKey) return groupCard(null, unfiled);
            if (selection == _kCompletedKey) return completedPane();
            final folder =
                orderedFolders.firstWhere((f) => f.id == selection);
            return groupCard(folder, openIn(folder.id));
          }(),
        );
      }
      // Grid view — the original masonry of draggable folder cards.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (orderedFolders.isNotEmpty)
            CardGrid(
              children: [
                for (final f in orderedFolders)
                  _ReorderableFolder(
                    key: ValueKey(f.id),
                    folder: f,
                    onReorder: (moving) => reorderFolder(moving, f),
                    child: groupCard(f, openIn(f.id)),
                  ),
              ],
            ),
          if (unfiled.isNotEmpty) ...[
            groupCard(null, unfiled),
            const SizedBox(height: 16),
          ],
          if (done.isNotEmpty) completedPane(),
        ],
      );
    }

    final doneTotal = tasks.where((t) => t.done).length;
    return PageBody(
      title: 'To-do',
      subtitle: '${open.length} open · $doneTotal done · '
          '${folders.length} folder${folders.length == 1 ? '' : 's'}',
      actions: [
        _TodoViewToggle(
          mode: viewMode,
          onChanged: (m) =>
              ref.read(todoViewModeProvider.notifier).set(m),
        ),
        const SizedBox(width: 10),
        SoftButton(
            label: 'New folder',
            icon: Icons.create_new_folder_outlined,
            onTap: newFolder),
        const SizedBox(width: 8),
        SoftButton(
            label: 'New task', filled: true, onTap: () => newTask()),
        const SizedBox(width: 4),
        _TodoOverflowMenu(
          hideDone: hideDone,
          onToggleHideDone: () =>
              ref.read(hideCompletedTasksProvider.notifier).toggle(),
        ),
      ],
      child: body(),
    );
  }
}

/// The "Completed" pane — same glass card shape as a [_TaskGroup] so it
/// drops into either the list-view detail area or the grid (as the last
/// card) without looking out of place. Rendered only when there is at
/// least one done task.
class _CompletedGroup extends StatelessWidget {
  const _CompletedGroup({
    required this.tasks,
    required this.rowBuilder,
  });

  final List<TaskItem> tasks;
  final Widget Function(TaskItem) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.done_all_rounded,
                  size: 18, color: AppPalette.lavender),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Completed',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              GlassChip(label: '${tasks.length}'),
            ],
          ),
          const Divider(height: 22),
          if (tasks.isEmpty)
            const EmptyHint('No finished tasks yet.')
          else
            for (final t in tasks) rowBuilder(t),
        ],
      ),
    );
  }
}

/// 3-dot overflow menu shown to the right of "New task" on the To-do
/// header. Currently holds the hide-completed switch; placeholder home
/// for any other page-wide preferences that don't warrant their own pill.
class _TodoOverflowMenu extends StatelessWidget {
  const _TodoOverflowMenu({
    required this.hideDone,
    required this.onToggleHideDone,
  });

  final bool hideDone;
  final VoidCallback onToggleHideDone;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert_rounded,
          size: 20, color: AppPalette.textSecondary),
      color: const Color(0xFF241F45),
      onSelected: (key) {
        if (key == 'hide-done') onToggleHideDone();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'hide-done',
          checked: hideDone,
          child: const Text('Hide completed tasks'),
        ),
      ],
    );
  }
}

/// Segmented [Grid | List] selector that mirrors the Timer page's mode
/// toggle so the two pages feel consistent.
class _TodoViewToggle extends StatelessWidget {
  const _TodoViewToggle({required this.mode, required this.onChanged});

  final TodoViewMode mode;
  final ValueChanged<TodoViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, TodoViewMode m, IconData icon) {
      final selected = mode == m;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? const Color(0xFF15132B)
                      : AppPalette.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFF15132B)
                          : AppPalette.textSecondary)),
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
          seg('Grid', TodoViewMode.grid, Icons.view_module_outlined),
          seg('List', TodoViewMode.list, Icons.view_list_outlined),
        ],
      ),
    );
  }
}

/// Two-pane layout for the To-do list view: a folder sidebar on the left
/// and the selected folder's tasks on the right. Falls back to a stacked
/// (list-above-detail) layout on narrow widths so the panes never get
/// squeezed below comfortable widths.
class _ListView extends StatelessWidget {
  const _ListView({
    required this.folders,
    required this.counts,
    required this.coursesById,
    required this.unfiledCount,
    required this.completedCount,
    required this.selectedKey,
    required this.onSelect,
    required this.onReorder,
    required this.detail,
  });

  final List<TaskFolder> folders;
  final Map<String, int> counts;
  final Map<String, Course> coursesById;
  final int unfiledCount;
  final int completedCount;
  final String? selectedKey;
  final ValueChanged<String> onSelect;
  final void Function(TaskFolder moving, TaskFolder target) onReorder;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final pane = _FolderListPane(
          folders: folders,
          counts: counts,
          coursesById: coursesById,
          unfiledCount: unfiledCount,
          completedCount: completedCount,
          selectedKey: selectedKey,
          onSelect: onSelect,
          onReorder: onReorder,
        );

        // Below ~700px the side-by-side layout starts squeezing the right
        // pane; stack instead so each surface keeps a usable width.
        if (c.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pane,
              const SizedBox(height: 16),
              detail,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 260, child: pane),
            const SizedBox(width: 16),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// The folder sidebar itself: one row per folder (drag-to-reorder) plus an
/// "Unfiled" row at the bottom when there are stray tasks.
class _FolderListPane extends StatelessWidget {
  const _FolderListPane({
    required this.folders,
    required this.counts,
    required this.coursesById,
    required this.unfiledCount,
    required this.completedCount,
    required this.selectedKey,
    required this.onSelect,
    required this.onReorder,
  });

  final List<TaskFolder> folders;
  final Map<String, int> counts;
  final Map<String, Course> coursesById;
  final int unfiledCount;
  final int completedCount;
  final String? selectedKey;
  final ValueChanged<String> onSelect;
  final void Function(TaskFolder moving, TaskFolder target) onReorder;

  @override
  Widget build(BuildContext context) {
    final hasAnyRow =
        folders.isNotEmpty || unfiledCount > 0 || completedCount > 0;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              'Folders',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          if (!hasAnyRow)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EmptyHint(
                'No folders yet.\nTap “New folder” to make one.',
                icon: Icons.create_new_folder_outlined,
              ),
            )
          else ...[
            for (final f in folders)
              _FolderListRow(
                key: ValueKey(f.id),
                folder: f,
                course: f.courseId == null ? null : coursesById[f.courseId],
                count: counts[f.id] ?? 0,
                selected: selectedKey == f.id,
                onTap: () => onSelect(f.id),
                onReorder: (moving) => onReorder(moving, f),
              ),
            if (unfiledCount > 0) ...[
              if (folders.isNotEmpty) const Divider(height: 14),
              _UnfiledListRow(
                count: unfiledCount,
                selected: selectedKey == _kUnfiledKey,
                onTap: () => onSelect(_kUnfiledKey),
              ),
            ],
            if (completedCount > 0) ...[
              if (folders.isNotEmpty || unfiledCount > 0)
                const Divider(height: 14),
              _CompletedListRow(
                count: completedCount,
                selected: selectedKey == _kCompletedKey,
                onTap: () => onSelect(_kCompletedKey),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A single folder row in the sidebar. Doubles as the drag source/target
/// so the same reorder gesture works in either view.
class _FolderListRow extends StatelessWidget {
  const _FolderListRow({
    super.key,
    required this.folder,
    required this.course,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onReorder,
  });

  final TaskFolder folder;
  final Course? course;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<TaskFolder> onReorder;

  @override
  Widget build(BuildContext context) {
    final inner = _rowChild(context, hovering: false);
    return DragTarget<TaskFolder>(
      onWillAcceptWithDetails: (d) => d.data.id != folder.id,
      onAcceptWithDetails: (d) => onReorder(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<TaskFolder>(
          data: folder,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: SizedBox(
                width: 260,
                child: _FolderDragPreview(folder: folder),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: inner),
          child: _rowChild(context, hovering: hovering),
        );
      },
    );
  }

  Widget _rowChild(BuildContext context, {required bool hovering}) {
    final base = selected
        ? AppPalette.accent.withValues(alpha: 0.18)
        : (hovering
            ? AppPalette.accent.withValues(alpha: 0.10)
            : Colors.transparent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: base,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: folder.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                ),
              ),
              if (course != null) ...[
                Icon(Icons.school_rounded,
                    size: 13, color: course!.color),
                const SizedBox(width: 6),
              ],
              GlassChip(label: '$count'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row for the catch-all "Unfiled" bucket. Mirrors [_FolderListRow]'s look
/// but isn't draggable — it isn't a real folder.
class _UnfiledListRow extends StatelessWidget {
  const _UnfiledListRow({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = selected
        ? AppPalette.accent.withValues(alpha: 0.18)
        : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: base,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppPalette.textFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Unfiled',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                ),
              ),
              GlassChip(label: '$count'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sidebar row for the Completed pane. Mirrors [_UnfiledListRow]'s look
/// but uses the done-all icon so it reads as the history bucket rather
/// than another folder.
class _CompletedListRow extends StatelessWidget {
  const _CompletedListRow({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = selected
        ? AppPalette.accent.withValues(alpha: 0.18)
        : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: base,
          ),
          child: Row(
            children: [
              const Icon(Icons.done_all_rounded,
                  size: 14, color: AppPalette.lavender),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                ),
              ),
              GlassChip(label: '$count'),
            ],
          ),
        ),
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
      if (task.due != null) formatTaskDue(task.due!, context),
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

/// Drag-source / drop-target wrapper around a folder's [_TaskGroup] card.
/// Same gesture plumbing as the Notes and Timers boards: a plain click-drag
/// engages immediately for a mouse, touch needs a long-press so finger-
/// scrolling the page still works. Taps on the row buttons fall through.
class _ReorderableFolder extends StatelessWidget {
  const _ReorderableFolder({
    super.key,
    required this.folder,
    required this.child,
    required this.onReorder,
  });

  final TaskFolder folder;
  final Widget child;
  final ValueChanged<TaskFolder> onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskFolder>(
      onWillAcceptWithDetails: (d) => d.data.id != folder.id,
      onAcceptWithDetails: (d) => onReorder(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<TaskFolder>(
          data: folder,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: SizedBox(
                width: 300,
                child: _FolderDragPreview(folder: folder),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _FolderDragPreview(folder: folder),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Compact stand-in shown while a folder card is being dragged.
class _FolderDragPreview extends StatelessWidget {
  const _FolderDragPreview({required this.folder});

  final TaskFolder folder;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: folder.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder.name.trim().isEmpty ? 'Folder' : folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: AppPalette.textFaint),
        ],
      ),
    );
  }
}
