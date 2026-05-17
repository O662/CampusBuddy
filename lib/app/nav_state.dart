import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../state/app_state.dart';
import 'nav.dart';

/// Holds the user's (re)ordered primary + secondary menus, persisted to the
/// local `settings` box so a custom order survives restarts. The profile
/// item is intentionally not part of this — it stays pinned in the rail.
class NavOrder {
  const NavOrder(this.primary, this.secondary);
  final List<NavItem> primary;
  final List<NavItem> secondary;
}

class NavOrderNotifier extends Notifier<NavOrder> {
  static const _kPrimary = 'navPrimaryOrder';
  static const _kSecondary = 'navSecondaryOrder';

  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  NavOrder build() => NavOrder(
        _ordered(primaryNav, _box.get(_kPrimary)),
        _ordered(secondaryNav, _box.get(_kSecondary)),
      );

  /// Rebuild the ordered list from saved routes, tolerating missing/new items
  /// (unknown saved routes are dropped, brand-new items are appended).
  List<NavItem> _ordered(List<NavItem> defaults, dynamic saved) {
    if (saved is! List) return List.of(defaults);
    final byRoute = {for (final n in defaults) n.route: n};
    final result = <NavItem>[];
    for (final route in saved) {
      final item = byRoute[route.toString()];
      if (item != null && !result.contains(item)) result.add(item);
    }
    for (final n in defaults) {
      if (!result.contains(n)) result.add(n);
    }
    return result;
  }

  /// Moves [moving] to where [target] currently sits and persists the order.
  Future<void> reorder({
    required bool primary,
    required NavItem moving,
    required NavItem target,
  }) async {
    final list = List<NavItem>.of(primary ? state.primary : state.secondary);
    final from = list.indexOf(moving);
    final targetIndex = list.indexOf(target);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;

    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexOf(target) + 1 // moved down → drop after target
        : list.indexOf(target); //   moved up   → drop before target
    list.insert(insertAt, moving);

    await _box.put(
      primary ? _kPrimary : _kSecondary,
      list.map((e) => e.route).toList(),
    );
    state = primary
        ? NavOrder(list, state.secondary)
        : NavOrder(state.primary, list);
  }
}

final navOrderProvider =
    NotifierProvider<NavOrderNotifier, NavOrder>(NavOrderNotifier.new);
