import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_palette.dart';
import '../core/widgets/adaptive_draggable.dart';
import '../core/widgets/animated_gradient_background.dart';
import '../core/widgets/glass.dart';
import 'nav.dart';
import 'nav_state.dart';

/// The persistent app frame: animated gradient backdrop, a glass vertical
/// rail on the left (primary menu) and a glass top bar holding the secondary
/// menu, right-aligned. Both menus are draggable to reorder (click-drag on
/// mouse, long-press on touch) and the order is saved. The routed page
/// renders in the large glass area.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LeftRail(location: location, compact: compact),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          _TopBar(location: location, compact: compact),
                          const SizedBox(height: 16),
                          Expanded(
                            child: GlassContainer(
                              padding: EdgeInsets.zero,
                              borderRadius: 28,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: child,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LeftRail extends ConsumerWidget {
  const _LeftRail({required this.location, required this.compact});

  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = ref.watch(navOrderProvider).primary;

    return GlassContainer(
      width: compact ? 86 : 164,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppPalette.periwinkle, AppPalette.mint],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.school_rounded,
                  color: Color(0xFF15132B), size: 24),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            const Text('CampusBuddy',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary)),
          ],
          const SizedBox(height: 40),
          _ReorderableMenu(
            items: primary,
            primary: true,
            axis: Axis.vertical,
            builder: (item) => _RailButton(
              item: item,
              selected: location.startsWith(item.route),
              compact: compact,
            ),
          ),
          const Spacer(),
          // Profile stays pinned at the bottom (not reorderable).
          _RailButton(
            item: profileNav,
            selected: location.startsWith(profileNav.route),
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.selected,
    required this.compact,
  });

  final NavItem item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppPalette.textPrimary : AppPalette.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tooltip(
        message: compact ? item.label : '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => context.go(item.route),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: selected
                    ? LinearGradient(colors: [
                        AppPalette.accent.withValues(alpha: 0.35),
                        AppPalette.accent.withValues(alpha: 0.12),
                      ])
                    : null,
                border: Border.all(
                  color: selected
                      ? AppPalette.accent.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, color: color, size: 27),
                  if (!compact) ...[
                    const SizedBox(height: 8),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: color,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.location, required this.compact});

  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = ref.watch(navOrderProvider).secondary;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      borderRadius: 24,
      child: Row(
        children: [
          // The title yields (ellipsizes); the menu keeps its natural
          // width so no item is ever clipped.
          if (!compact)
            Expanded(
              child: Text(
                titleForRoute(location),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          _ReorderableMenu(
            items: secondary,
            primary: false,
            axis: Axis.horizontal,
            builder: (item) => _PillButton(
              item: item,
              selected: location.startsWith(item.route),
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.item,
    required this.selected,
    required this.compact,
  });

  final NavItem item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? const Color(0xFF15132B) : AppPalette.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => context.go(item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected ? AppPalette.accent : Colors.transparent,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : AppPalette.glassStroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 16, color: color),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(item.label,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps each item in an [AdaptiveDraggable] + [DragTarget] so the menu can
/// be reordered (mouse = click-drag, touch = long-press; a plain click
/// falls straight through to the button — no gesture-arena lag). Dropping a
/// dragged item onto another swaps its position via [NavOrderNotifier.reorder],
/// which persists the new order.
class _ReorderableMenu extends ConsumerWidget {
  const _ReorderableMenu({
    required this.items,
    required this.primary,
    required this.axis,
    required this.builder,
  });

  final List<NavItem> items;
  final bool primary;
  final Axis axis;
  final Widget Function(NavItem item) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = [
      for (final item in items) _slot(context, ref, item),
    ];
    return axis == Axis.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: slots)
        : Row(mainAxisSize: MainAxisSize.min, children: slots);
  }

  Widget _slot(BuildContext context, WidgetRef ref, NavItem item) {
    final content = builder(item);
    final radius = BorderRadius.circular(axis == Axis.vertical ? 20 : 999);

    return DragTarget<NavItem>(
      onWillAcceptWithDetails: (d) => !identical(d.data, item),
      onAcceptWithDetails: (d) => ref.read(navOrderProvider.notifier).reorder(
            primary: primary,
            moving: d.data,
            target: item,
          ),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AdaptiveDraggable<NavItem>(
          data: item,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.92,
              child: SizedBox(
                width: axis == Axis.vertical ? 136 : null,
                child: content,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: content),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: content,
          ),
        );
      },
    );
  }
}
