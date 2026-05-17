import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import 'dashboard_page.dart';
import 'dashboard_state.dart';

/// A gallery of every dashboard card rendered as a real (but non-interactive)
/// preview, with a tap-to-show/hide toggle. Lets the user curate which
/// widgets appear on the dashboard.
class CustomizePage extends ConsumerWidget {
  const CustomizePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(dashboardHiddenProvider);
    final shown = kDashboardCardIds.length - hidden.length;

    return PageBody(
      title: 'Customize dashboard',
      subtitle: 'Tap a widget to show or hide it — '
          '$shown of ${kDashboardCardIds.length} shown.',
      actions: [
        SoftButton(
          label: 'Done',
          icon: Icons.check_rounded,
          filled: true,
          onTap: () => context.go('/dashboard'),
        ),
      ],
      child: CardGrid(
        children: [
          for (final id in kDashboardCardIds) _GalleryTile(id: id),
        ],
      ),
    );
  }
}

class _GalleryTile extends ConsumerWidget {
  const _GalleryTile({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHidden = ref.watch(dashboardHiddenProvider).contains(id);
    final meta = kDashboardCardMeta[id];
    final label = meta?.$1 ?? id;
    final icon = meta?.$2 ?? Icons.widgets_rounded;

    return GlassContainer(
      onTap: () => ref.read(dashboardHiddenProvider.notifier).toggle(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppPalette.lavender),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              GlassChip(
                label: isHidden ? 'Hidden' : 'Shown',
                color: isHidden ? AppPalette.textFaint : AppPalette.mint,
                icon: isHidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isHidden ? 'Tap to add it back' : 'Tap to hide it',
            style: const TextStyle(
                fontSize: 11, color: AppPalette.textSecondary),
          ),
          const Divider(height: 22),
          // A real but inert preview, dimmed while hidden, so it looks just
          // like it will on the dashboard. IgnorePointer keeps the card's
          // own buttons from firing and lets the tap toggle visibility.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isHidden ? 0.35 : 1,
            child: IgnorePointer(
              child: dashboardCards[id] ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
