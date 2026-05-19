import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_palette.dart';
import 'glass.dart';
import 'ui_kit.dart';

/// Shared note-editing pieces used by both the full Notes board and the
/// dashboard Notes widget, so the two stay consistent.

/// A small tag pill. Used as a filter toggle (tap to (de)select) and, with
/// [onRemove], as a removable chip on a note.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = selected ? AppPalette.accent : AppPalette.lavender;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withValues(alpha: selected ? 0.30 : 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 13, color: c),
                const SizedBox(width: 4),
              ],
              Text(
                '#$label',
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(Icons.close_rounded, size: 13, color: c),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed "＋ Tag" pill used to start adding a tag.
class AddTagButton extends StatelessWidget {
  const AddTagButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppPalette.glassStroke),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded,
                size: 13, color: AppPalette.textSecondary),
            SizedBox(width: 4),
            Text('Tag',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Swatch picker for a note's accent colour. Resolves to the chosen
/// [AppPalette.categorySwatches] index, or null if cancelled.
Future<int?> showNoteColorPicker(BuildContext context, int currentSeed) {
  final swatches = AppPalette.categorySwatches;
  final current = currentSeed.abs() % swatches.length;
  return showGlassDialog<int>(
    context,
    title: 'Note colour',
    content: Builder(
      builder: (dialogCtx) => Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (var i = 0; i < swatches.length; i++)
            GestureDetector(
              onTap: () => Navigator.of(dialogCtx).pop(i),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: swatches[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == current
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.2),
                    width: i == current ? 3 : 1,
                  ),
                ),
                child: i == current
                    ? const Icon(Icons.check_rounded,
                        size: 20, color: Color(0xFF15132B))
                    : null,
              ),
            ),
        ],
      ),
    ),
    actions: (dialogCtx) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogCtx),
        child: const Text('Cancel'),
      ),
    ],
  );
}

/// Prompt for a tag. Returns the raw entered/selected text (the caller
/// trims + de-dupes), or null if cancelled. [suggestions] are offered as
/// one-tap chips.
Future<String?> showAddTagDialog(
  BuildContext context, {
  required Iterable<String> suggestions,
}) {
  final c = TextEditingController();
  return showGlassDialog<String>(
    context,
    title: 'Add tag',
    content: Builder(
      builder: (dialogCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(dialogCtx, v),
            decoration: const InputDecoration(hintText: 'New tag'),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Existing tags',
                style:
                    TextStyle(fontSize: 12, color: AppPalette.textFaint)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in suggestions)
                  TagChip(
                    label: t,
                    onTap: () => Navigator.pop(dialogCtx, t),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
    actions: (dialogCtx) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogCtx),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogCtx, c.text),
        child: const Text('Add'),
      ),
    ],
  ).whenComplete(c.dispose);
}

/// The full single-note editor card (title, body, colour, favourite, tags),
/// shared by the in-app pop-out fallback page and the real pop-out OS
/// window. It is storage-agnostic: every change is handed back via
/// [onSave] and the caller decides how to persist (Riverpod on the board
/// side, the inter-window bridge on the pop-out side).
///
/// The title/body controllers are seeded once so typing never fights the
/// cursor; an external update to the *same* note (e.g. edited on the board
/// while popped out) is folded back in only while that field is unfocused.
class NoteEditorView extends StatefulWidget {
  const NoteEditorView({
    super.key,
    required this.note,
    required this.onSave,
    required this.onClose,
    this.tagSuggestions = const [],
    this.pinned,
    this.onTogglePin,
  });

  final Note note;
  final ValueChanged<Note> onSave;
  final VoidCallback onClose;

  /// Tags used on other notes, offered as one-tap chips when adding a tag.
  final List<String> tagSuggestions;

  /// Pin (always-on-top) state, or null when there is no real OS window to
  /// pin (the non-desktop in-app fallback) — the control is then hidden.
  final bool? pinned;
  final VoidCallback? onTogglePin;

  @override
  State<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends State<NoteEditorView> {
  late final TextEditingController _titleC;
  late final TextEditingController _bodyC;
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleC = TextEditingController(text: widget.note.title);
    _bodyC = TextEditingController(text: widget.note.body);
  }

  @override
  void didUpdateWidget(NoteEditorView old) {
    super.didUpdateWidget(old);
    // Reflect a change made elsewhere to this note, but never yank the
    // cursor out from under active typing.
    if (!_titleFocus.hasFocus && _titleC.text != widget.note.title) {
      _titleC.text = widget.note.title;
    }
    if (!_bodyFocus.hasFocus && _bodyC.text != widget.note.body) {
      _bodyC.text = widget.note.body;
    }
  }

  @override
  void dispose() {
    _titleC.dispose();
    _bodyC.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Note get _note => widget.note;
  void _save(Note next) => widget.onSave(next);

  Future<void> _pickColor() async {
    final picked = await showNoteColorPicker(context, _note.colorSeed);
    if (picked != null) {
      _save(_note.copyWith(colorSeed: picked, updatedAt: DateTime.now()));
    }
  }

  Future<void> _addTag() async {
    final onNote = _note.tags.map((t) => t.toLowerCase()).toSet();
    final suggestions = [
      for (final t in widget.tagSuggestions)
        if (!onNote.contains(t.toLowerCase())) t,
    ];
    final entered =
        await showAddTagDialog(context, suggestions: suggestions);
    final tag = entered?.trim() ?? '';
    if (tag.isEmpty) return;
    if (_note.tags.any((e) => e.toLowerCase() == tag.toLowerCase())) return;
    _save(_note.copyWith(
        tags: [..._note.tags, tag], updatedAt: DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
                  focusNode: _titleFocus,
                  onChanged: (v) => _save(
                      note.copyWith(title: v, updatedAt: DateTime.now())),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                ),
              ),
              InkWell(
                onTap: () => _save(note.copyWith(
                    favorite: !note.favorite,
                    updatedAt: DateTime.now())),
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    note.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: AppPalette.warning,
                  ),
                ),
              ),
              if (widget.pinned != null && widget.onTogglePin != null)
                Tooltip(
                  message:
                      widget.pinned! ? 'Unpin from top' : 'Keep on top',
                  child: InkWell(
                    onTap: widget.onTogglePin,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        widget.pinned!
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 19,
                        color: widget.pinned!
                            ? AppPalette.accent
                            : AppPalette.textSecondary,
                      ),
                    ),
                  ),
                ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 19, color: AppPalette.textSecondary),
                ),
              ),
            ],
          ),
          Divider(color: note.color.withValues(alpha: 0.4), height: 16),
          Expanded(
            child: TextField(
              controller: _bodyC,
              focusNode: _bodyFocus,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (v) =>
                  _save(note.copyWith(body: v, updatedAt: DateTime.now())),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Jot anything here…',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in note.tags)
                TagChip(
                  label: t,
                  onRemove: () => _save(note.copyWith(
                      tags: note.tags.where((e) => e != t).toList(),
                      updatedAt: DateTime.now())),
                ),
              AddTagButton(onTap: _addTag),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.cloud_done_rounded,
                  size: 14, color: AppPalette.textFaint),
              SizedBox(width: 5),
              Text('Saved automatically',
                  style:
                      TextStyle(fontSize: 11, color: AppPalette.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown in a pop-out (window or fallback page) when its note has been
/// deleted elsewhere.
class NoteDeletedView extends StatelessWidget {
  const NoteDeletedView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.note_alt_outlined,
              size: 32, color: AppPalette.textFaint),
          const SizedBox(height: 10),
          const Text('This note was deleted.',
              style: TextStyle(color: AppPalette.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
