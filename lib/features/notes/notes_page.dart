import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/note_editing.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'note_window_bridge.dart';

/// A board of free-text sticky notes laid out as a responsive masonry.
/// Each note has a title, body and tags, and auto-saves as you type.
/// Drag a note (mouse: click-drag; touch: long-press) by any non-interactive
/// part of the card to reorder. Search + tag filters narrow the board;
/// reordering is disabled while a filter is active.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _searchC = TextEditingController();
  String _query = '';

  /// Active tag filters, stored lower-cased for case-insensitive matching.
  final Set<String> _selectedTags = {};

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  void _newNote() {
    final all = ref.read(notesProvider);
    // Drop the new note in at the top of the board.
    final order = all.isEmpty
        ? 0
        : all.map((n) => n.order).reduce((a, b) => a < b ? a : b) - 1;
    ref.read(notesProvider.notifier).upsert(
          Note(id: newId(), order: order, updatedAt: DateTime.now()),
        );
  }

  /// Mirror the nav's reorder semantics: dropping [moving] onto [target]
  /// moves it into the target's slot.
  void _reorder(List<Note> ordered, Note moving, Note target) {
    if (moving.id == target.id) return;
    final list = [...ordered];
    final from = list.indexWhere((n) => n.id == moving.id);
    final targetIndex = list.indexWhere((n) => n.id == target.id);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;
    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexWhere((n) => n.id == target.id) + 1
        : list.indexWhere((n) => n.id == target.id);
    list.insert(insertAt, moving);
    ref.read(notesProvider.notifier).reorder(list);
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider).toList()
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        // Legacy notes (order 0) keep most-recent-first behaviour.
        final byTime = b.updatedAt.compareTo(a.updatedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    // Distinct tags across all notes (first-seen display form, sorted).
    final allTags = <String, String>{};
    for (final n in notes) {
      for (final t in n.tags) {
        allTags.putIfAbsent(t.toLowerCase(), () => t);
      }
    }
    final tagList = allTags.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final q = _query.toLowerCase();
    final visible = notes.where((n) {
      final matchesText = q.isEmpty ||
          n.title.toLowerCase().contains(q) ||
          n.body.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q));
      final noteTags = n.tags.map((t) => t.toLowerCase()).toSet();
      final matchesTags =
          _selectedTags.every((t) => noteTags.contains(t));
      return matchesText && matchesTags;
    }).toList();

    final filtering = _query.isNotEmpty || _selectedTags.isNotEmpty;
    final canReorder = !filtering;

    return PageBody(
      title: 'Notes',
      subtitle: notes.isEmpty
          ? 'Capture quick thoughts — they save as you type.'
          : '${notes.length} note${notes.length == 1 ? '' : 's'} · '
              'saved automatically.',
      actions: [
        SoftButton(
          label: 'New note',
          icon: Icons.add_rounded,
          filled: true,
          onTap: _newNote,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes.isNotEmpty) ...[
            _SearchField(
              controller: _searchC,
              onChanged: (v) => setState(() => _query = v.trim()),
              onClear: () {
                _searchC.clear();
                setState(() => _query = '');
              },
              hasQuery: _query.isNotEmpty,
            ),
            if (tagList.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tagList)
                    TagChip(
                      label: t,
                      selected:
                          _selectedTags.contains(t.toLowerCase()),
                      onTap: () => setState(() {
                        final k = t.toLowerCase();
                        _selectedTags.contains(k)
                            ? _selectedTags.remove(k)
                            : _selectedTags.add(k);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
          ],
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyHint(
                'No notes yet. Tap “New note” to start one.',
                icon: Icons.sticky_note_2_outlined,
              ),
            )
          else if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyHint(
                'No notes match your filters.',
                icon: Icons.search_off_rounded,
              ),
            )
          else
            CardGrid(
              children: [
                for (final n in visible)
                  if (canReorder)
                    _ReorderableNote(
                      key: ValueKey(n.id),
                      note: n,
                      onReorder: (moving) => _reorder(notes, moving, n),
                    )
                  else
                    _NoteCard(key: ValueKey(n.id), note: n),
              ],
            ),
        ],
      ),
    );
  }
}

/// Wraps a [_NoteCard] in the drag-source / drop-target plumbing. The
/// [AdaptiveDraggable] only claims the gesture once the pointer moves
/// (mouse) or after a long-press (touch), so taps and drags inside the
/// title/body fields and buttons still work normally.
class _ReorderableNote extends StatelessWidget {
  const _ReorderableNote({
    super.key,
    required this.note,
    required this.onReorder,
  });

  final Note note;
  final ValueChanged<Note> onReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Note>(
      onWillAcceptWithDetails: (d) => d.data.id != note.id,
      onAcceptWithDetails: (d) => onReorder(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<Note>(
          data: note,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.95,
              child: SizedBox(
                width: 300,
                child: _NoteDragPreview(note: note),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _NoteDragPreview(note: note),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: _NoteCard(note: note),
          ),
        );
      },
    );
  }
}

/// Lightweight stand-in shown while a note is being dragged.
class _NoteDragPreview extends StatelessWidget {
  const _NoteDragPreview({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: note.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              note.title.trim().isEmpty ? 'Untitled note' : note.title,
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        hintText: 'Search notes',
        suffixIcon: hasQuery
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
                tooltip: 'Clear',
              )
            : null,
      ),
    );
  }
}

class _NoteCard extends ConsumerStatefulWidget {
  const _NoteCard({super.key, required this.note});

  final Note note;

  @override
  ConsumerState<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<_NoteCard> {
  late final TextEditingController _titleC;
  late final TextEditingController _bodyC;

  @override
  void initState() {
    super.initState();
    // Seed once; we never write back to the controllers from the provider
    // so typing can't fight the cursor.
    _titleC = TextEditingController(text: widget.note.title);
    _bodyC = TextEditingController(text: widget.note.body);
  }

  @override
  void dispose() {
    _titleC.dispose();
    _bodyC.dispose();
    super.dispose();
  }

  void _save(Note next) => ref.read(notesProvider.notifier).upsert(next);

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete note?',
      message: 'This note will be permanently removed.',
    );
    if (ok) ref.read(notesProvider.notifier).remove(widget.note.id);
  }

  Future<void> _pickColor() async {
    final picked =
        await showNoteColorPicker(context, widget.note.colorSeed);
    if (picked != null) {
      _save(widget.note
          .copyWith(colorSeed: picked, updatedAt: DateTime.now()));
    }
  }

  Future<void> _addTag() async {
    final note = widget.note;
    final onNote = note.tags.map((t) => t.toLowerCase()).toSet();
    // Suggest tags used elsewhere that aren't already on this note.
    final suggestions = <String, String>{};
    for (final n in ref.read(notesProvider)) {
      for (final t in n.tags) {
        final k = t.toLowerCase();
        if (!onNote.contains(k)) suggestions.putIfAbsent(k, () => t);
      }
    }
    final entered = await showAddTagDialog(context,
        suggestions: suggestions.values);
    final tag = entered?.trim() ?? '';
    if (tag.isEmpty) return;
    if (note.tags.any((e) => e.toLowerCase() == tag.toLowerCase())) return;
    _save(note.copyWith(
        tags: [...note.tags, tag], updatedAt: DateTime.now()));
  }

  void _removeTag(String tag) {
    final note = widget.note;
    _save(note.copyWith(
      tags: note.tags.where((e) => e != tag).toList(),
      updatedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Tap the dot to choose the note's accent colour.
              GestureDetector(
                onTap: _pickColor,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: note.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _titleC,
                  onChanged: (v) => _save(note.copyWith(
                      title: v, updatedAt: DateTime.now())),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                ),
              ),
              if (note.favorite) ...[
                const Icon(Icons.star_rounded,
                    size: 18, color: AppPalette.warning),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Note options',
                onSelected: (v) {
                  if (v == 'popout') {
                    popOutNote(context, note.id);
                  } else if (v == 'favorite') {
                    _save(note.copyWith(
                        favorite: !note.favorite,
                        updatedAt: DateTime.now()));
                  } else if (v == 'tag') {
                    _addTag();
                  } else if (v == 'delete') {
                    _delete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'popout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          Icon(Icons.open_in_new_rounded, size: 20),
                      title: Text('Pop out'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'favorite',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          note.favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 20,
                          color: AppPalette.warning),
                      title: Text(note.favorite
                          ? 'Remove favourite'
                          : 'Add to favourites'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'tag',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.label_outline_rounded, size: 20),
                      title: Text('Add tag'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Divider(color: note.color.withValues(alpha: 0.4), height: 16),
          const SizedBox(height: 2),
          TextField(
            controller: _bodyC,
            minLines: 4,
            maxLines: 12,
            onChanged: (v) =>
                _save(note.copyWith(body: v, updatedAt: DateTime.now())),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Jot anything here…',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in note.tags)
                TagChip(label: t, onRemove: () => _removeTag(t)),
              AddTagButton(onTap: _addTag),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Edited ${relativeDay(note.updatedAt)}',
            style: const TextStyle(
                fontSize: 11, color: AppPalette.textFaint),
          ),
        ],
      ),
    );
  }
}
