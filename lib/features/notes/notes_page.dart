import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// A board of free-text sticky notes. Each note auto-saves as you type;
/// ordering is by creation (newest first) so a card never jumps around
/// under the cursor while editing.
class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider).toList()
      ..sort((a, b) {
        final byTime = b.updatedAt.compareTo(a.updatedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

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
          onTap: () => ref.read(notesProvider.notifier).upsert(
                Note(id: newId(), updatedAt: DateTime.now()),
              ),
        ),
      ],
      child: notes.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyHint(
                'No notes yet. Tap “New note” to start one.',
                icon: Icons.sticky_note_2_outlined,
              ),
            )
          : CardGrid(
              children: [
                for (final n in notes) _NoteCard(key: ValueKey(n.id), note: n),
              ],
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
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    // Seed once; we never write back to the controller from the provider so
    // typing can't fight the cursor (same approach as the old sticky note).
    _c = TextEditingController(text: widget.note.body);
  }

  @override
  void dispose() {
    _c.dispose();
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

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Tap the dot to cycle the note's accent colour.
              GestureDetector(
                onTap: () => _save(note.copyWith(
                    colorSeed: note.colorSeed + 1)),
                child: Container(
                  width: 18,
                  height: 18,
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
                child: Text(
                  'Edited ${relativeDay(note.updatedAt)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppPalette.textFaint),
                ),
              ),
              InkWell(
                onTap: _delete,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppPalette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: note.color.withValues(alpha: 0.4), height: 16),
          const SizedBox(height: 2),
          TextField(
            controller: _c,
            minLines: 4,
            maxLines: 12,
            onChanged: (v) => _save(note.copyWith(body: v)),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Jot anything here…',
            ),
          ),
        ],
      ),
    );
  }
}
