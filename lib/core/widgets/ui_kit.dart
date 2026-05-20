import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'glass.dart';

/// Column count for a responsive card grid given the available width.
int responsiveColumns(double width) {
  if (width >= 1180) return 3;
  if (width >= 760) return 2;
  return 1;
}

/// Lays [children] into [columns] balanced vertical lists (a simple masonry).
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.spacing = 16});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = responsiveColumns(c.maxWidth);
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final w in children)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing),
                  child: w,
                ),
            ],
          );
        }
        final buckets = List.generate(cols, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          buckets[i % cols].add(Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: children[i],
          ));
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cols; i++) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buckets[i],
                ),
              ),
              if (i != cols - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.message, {super.key, this.icon = Icons.spa_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, color: AppPalette.textFaint, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.textFaint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A page scaffold: scroll-safe padded body with a heading row.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: const TextStyle(
                        color: AppPalette.textSecondary, fontSize: 13)),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 20),
        child,
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: scrollable
          ? SingleChildScrollView(child: content)
          : content,
    );
  }
}

/// Styled glass dialog wrapper.
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> Function(BuildContext dialogContext) actions,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: Theme.of(dialogContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              content,
              const SizedBox(height: 22),
              Builder(
                builder: (dialogContext) {
                  final acts = actions(dialogContext);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < acts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        acts[i],
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Swatch picker over [AppPalette.categorySwatches]. Returns the chosen
/// index, or null if cancelled. Reused anywhere a model carries a colorSeed.
Future<int?> showColorSeedPicker(
  BuildContext context,
  int currentSeed, {
  String title = 'Pick a colour',
}) {
  final swatches = AppPalette.categorySwatches;
  final current = currentSeed.abs() % swatches.length;
  return showGlassDialog<int>(
    context,
    title: title,
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

/// Compact pill button used as a card action ("+ Add").
class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_rounded,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: filled
                ? AppPalette.accent
                : AppPalette.accent.withValues(alpha: 0.16),
            border: Border.all(
                color: AppPalette.accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: filled
                      ? const Color(0xFF15132B)
                      : AppPalette.lavender),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: filled
                          ? const Color(0xFF15132B)
                          : AppPalette.lavender)),
            ],
          ),
        ),
      ),
    );
  }
}

String relativeDay(DateTime date) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return 'In $diff days';
  if (diff < 0) return '${-diff} days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}';
}

/// Reusable destructive-action confirmation. Returns true if confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showGlassDialog<bool>(
    context,
    title: title,
    content: Text(message,
        style: const TextStyle(
            color: AppPalette.textSecondary, height: 1.4)),
    actions: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: AppPalette.danger,
            foregroundColor: const Color(0xFF15132B)),
        onPressed: () => Navigator.pop(dialogContext, true),
        child: const Text('Delete'),
      ),
    ],
  );
  return result ?? false;
}

String hhmm(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final ampm = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $ampm';
}
