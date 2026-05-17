import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../state/app_state.dart';

/// Stable ids for the dashboard cards, in their default order. The widget
/// for each id is resolved in `dashboard_page.dart`.
const kDashboardCardIds = <String>[
  'clock',
  'weather',
  'stats',
  'countdown',
  'agenda',
  'overview',
  'assignments',
  'quickadd',
  'dictionary',
  'notes',
  'grades',
  'tasks',
  'events',
  'word',
  'quote',
];

/// Holds the user's dashboard card order, persisted to the local `settings`
/// box so a rearranged dashboard survives restarts. Tolerates ids that were
/// added or removed between versions.
class DashboardOrderNotifier extends Notifier<List<String>> {
  static const _key = 'dashboardOrder';

  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  List<String> build() {
    final saved = _box.get(_key);
    if (saved is! List) return List.of(kDashboardCardIds);
    final result = <String>[];
    for (final raw in saved) {
      final id = raw.toString();
      if (kDashboardCardIds.contains(id) && !result.contains(id)) {
        result.add(id);
      }
    }
    for (final id in kDashboardCardIds) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  /// Moves [moving] to where [target] currently sits, then persists.
  Future<void> reorder(String moving, String target) async {
    final list = List<String>.of(state);
    final from = list.indexOf(moving);
    final targetIndex = list.indexOf(target);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;

    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexOf(target) + 1
        : list.indexOf(target);
    list.insert(insertAt, moving);

    await _box.put(_key, list);
    state = list;
  }
}

final dashboardOrderProvider =
    NotifierProvider<DashboardOrderNotifier, List<String>>(
        DashboardOrderNotifier.new);
