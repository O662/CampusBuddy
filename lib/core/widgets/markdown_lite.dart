import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

/// Renders the tiny markdown subset used by flashcards (and anywhere else
/// in the app that wants a hint of formatting without pulling in a full
/// CommonMark dependency):
///
/// - `**bold**`
/// - `*italic*` or `_italic_`
/// - `` `code` ``
/// - lines starting with `- ` or `* ` → bullets
/// - lines starting with `1. ` (any digits) → numbered list
///
/// Anything that isn't recognised falls through as plain text — so a
/// legacy card written before this feature still renders correctly.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? DefaultTextStyle.of(context).style);
    final lines = text.split('\n');
    final children = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trimLeft();
      String content = raw;
      String? leader; // bullet/number marker, rendered in a fixed gutter

      // Bullets: "- " or "* " (single marker, single space).
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        leader = '•';
        content = trimmed.substring(2);
      } else {
        // Numbered: leading digits + ". ".
        final match = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
        if (match != null) {
          leader = '${match.group(1)}.';
          content = match.group(2)!;
        }
      }

      final span = TextSpan(
        style: base,
        children: _parseInline(content, base),
      );

      if (leader != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text(leader,
                    textAlign: TextAlign.left,
                    style: base.copyWith(
                        color: base.color
                                ?.withValues(alpha: 0.7) ??
                            AppPalette.textSecondary)),
              ),
              Expanded(child: RichText(text: span, textAlign: textAlign)),
            ],
          ),
        ));
      } else if (content.isEmpty) {
        // Preserve blank lines as paragraph spacing rather than collapsing.
        children.add(const SizedBox(height: 8));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(text: span, textAlign: textAlign),
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: _crossFor(textAlign),
      children: children,
    );
  }

  CrossAxisAlignment _crossFor(TextAlign a) => switch (a) {
        TextAlign.center => CrossAxisAlignment.center,
        TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      };

  /// Tokenises a single line into styled spans. Strategy: scan left to
  /// right, peek for a marker, emit the plain prefix as one span and the
  /// styled chunk as another, then keep going. We deliberately keep the
  /// parser dumb — no nested styling — so the rules stay predictable for
  /// authors and the rendering stays cheap.
  List<TextSpan> _parseInline(String input, TextStyle base) {
    final out = <TextSpan>[];
    var i = 0;
    final buf = StringBuffer();

    void flushPlain() {
      if (buf.isEmpty) return;
      out.add(TextSpan(text: buf.toString(), style: base));
      buf.clear();
    }

    bool tryMarker(String marker, TextStyle styled) {
      // Match marker..marker with at least one char between them and no
      // newline. Greedy but anchored to the next marker to keep things
      // simple.
      if (!input.startsWith(marker, i)) return false;
      final end = input.indexOf(marker, i + marker.length);
      if (end <= i + marker.length) return false;
      final inner = input.substring(i + marker.length, end);
      if (inner.contains('\n')) return false;
      flushPlain();
      out.add(TextSpan(text: inner, style: styled));
      i = end + marker.length;
      return true;
    }

    while (i < input.length) {
      // Bold first so `**` wins over `*`.
      if (tryMarker('**', base.copyWith(fontWeight: FontWeight.w700))) {
        continue;
      }
      if (tryMarker('*', base.copyWith(fontStyle: FontStyle.italic))) {
        continue;
      }
      if (tryMarker('_', base.copyWith(fontStyle: FontStyle.italic))) {
        continue;
      }
      if (tryMarker(
          '`',
          base.copyWith(
            fontFamily: 'monospace',
            backgroundColor:
                AppPalette.glassFill.withValues(alpha: 0.35),
          ))) {
        continue;
      }
      buf.write(input[i]);
      i++;
    }
    flushPlain();
    return out;
  }
}

/// Compact button strip that inserts markdown markers into a
/// [TextEditingController]. Wraps the current selection when there is one
/// (so the user can highlight a word and tap **B**); otherwise drops the
/// markers around a placeholder and selects the placeholder so the next
/// keystroke replaces it.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tooltip, VoidCallback onTap) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
            child: Icon(icon,
                size: 16, color: AppPalette.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.format_bold, 'Bold',
              () => _wrap(controller, '**', '**', 'bold')),
          btn(Icons.format_italic, 'Italic',
              () => _wrap(controller, '*', '*', 'italic')),
          btn(Icons.code, 'Inline code',
              () => _wrap(controller, '`', '`', 'code')),
          btn(Icons.format_list_bulleted, 'Bullet list',
              () => _linePrefix(controller, '- ')),
          btn(Icons.format_list_numbered, 'Numbered list',
              () => _linePrefix(controller, '1. ')),
        ],
      ),
    );
  }

  /// Wraps `controller`'s current selection with `left` / `right`. If
  /// nothing is selected, inserts the markers around `placeholder` and
  /// selects the placeholder so the user can immediately type over it.
  static void _wrap(TextEditingController controller, String left,
      String right, String placeholder) {
    final value = controller.value;
    final sel = value.selection;
    final text = value.text;

    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final inner = (start == end) ? placeholder : text.substring(start, end);
    final replaced =
        text.replaceRange(start, end, '$left$inner$right');
    final newSelStart = start + left.length;
    controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection(
        baseOffset: newSelStart,
        extentOffset: newSelStart + inner.length,
      ),
    );
  }

  /// Inserts `prefix` at the start of the current (or last) line. Used by
  /// the bullet / numbered buttons so the user doesn't have to position
  /// the caret precisely.
  static void _linePrefix(
      TextEditingController controller, String prefix) {
    final value = controller.value;
    final text = value.text;
    final caret = value.selection.baseOffset.clamp(0, text.length);
    final lineStart = text.lastIndexOf('\n', caret - 1) + 1;
    // If the line already starts with the prefix, do nothing — keeps
    // double-tap from compounding into "- - foo".
    if (text.startsWith(prefix, lineStart)) {
      SystemSound.play(SystemSoundType.click);
      return;
    }
    final replaced = text.replaceRange(lineStart, lineStart, prefix);
    final newCaret = caret + prefix.length;
    controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: newCaret),
    );
  }
}
