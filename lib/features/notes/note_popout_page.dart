import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/note_editing.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

/// In-app single-note editor at `/note/:id`. This is the **fallback** used
/// on platforms with no OS windows (web, Android). On desktop, "Pop out"
/// instead opens a real, independent, always-on-top window — see
/// `note_window_bridge.dart` / `note_window.dart`. The editor itself is the
/// shared [NoteEditorView]; here it is wired straight to Riverpod.
class NotePopoutPage extends ConsumerWidget {
  const NotePopoutPage({super.key, required this.noteId});

  final String noteId;

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/notes');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    Note? note;
    for (final n in notes) {
      if (n.id == noteId) {
        note = n;
        break;
      }
    }

    // Tags used elsewhere, offered as one-tap chips when adding a tag.
    final suggestions = <String, String>{};
    for (final n in notes) {
      for (final t in n.tags) {
        suggestions.putIfAbsent(t.toLowerCase(), () => t);
      }
    }

    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: note == null
                ? NoteDeletedView(onClose: () => _close(context))
                : NoteEditorView(
                    note: note,
                    tagSuggestions: suggestions.values.toList(),
                    onSave: (next) =>
                        ref.read(notesProvider.notifier).upsert(next),
                    onClose: () => _close(context),
                  ),
          ),
        ),
      ),
    );
  }
}
