import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  'quickadd',
  'dictionary',
  'notes',
  'grades',
  'tasks',
  'events',
  'word',
  'quote',
];

/// Human-friendly name + icon for every card id, used by the Customize
/// page. Keep keys in sync with [kDashboardCardIds].
const kDashboardCardMeta = <String, (String, IconData)>{
  'clock': ('Clock', Icons.schedule_rounded),
  'weather': ('Weather', Icons.wb_sunny_rounded),
  'stats': ('Quick stats', Icons.insights_rounded),
  'countdown': ('Next up', Icons.hourglass_top_rounded),
  'agenda': ("Today's agenda", Icons.today_rounded),
  'overview': ('Two-week overview', Icons.calendar_view_week_rounded),
  'quickadd': ('Quick add', Icons.bolt_rounded),
  'dictionary': ('Dictionary', Icons.menu_book_rounded),
  'notes': ('Notes', Icons.sticky_note_2_rounded),
  'grades': ('Grade progress', Icons.school_rounded),
  'tasks': ('To-do & assignments', Icons.checklist_rounded),
  'events': ('Upcoming events', Icons.event_available_rounded),
  'word': ('Word of the day', Icons.text_fields_rounded),
  'quote': ('Daily quote', Icons.format_quote_rounded),
};

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

  // --- Live drag-to-reorder -------------------------------------------------
  // While a card is dragged the grid reflows in memory only (no disk writes)
  // so the other cards visibly slide out of the way; the final order is
  // persisted once when the drag ends.
  //
  // Three guards stop the layout flickering under the cursor (worst when a
  // small card is dragged over a tall one, whose reflow slides a *different*
  // card under the pointer and retriggers a swap):
  //   * `_lastTarget`  — ignore the continuous stream of same-target hovers;
  //   * `_beforeMove`  — never apply a swap that just undoes the previous one
  //                      (kills A↔B ping-pong);
  //   * `_settle`      — leave a brief gap between swaps so a big reflow can
  //                      come to rest before another is accepted.

  String? _dragging;
  String? _lastTarget;
  List<String>? _beforeMove;
  DateTime _lastMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _settle = Duration(milliseconds: 90);

  List<String> _reordered(
      List<String> source, String moving, String target) {
    final list = List<String>.of(source);
    final from = list.indexOf(moving);
    final ti = list.indexOf(target);
    if (from < 0 || ti < 0 || from == ti) return list;
    list.removeAt(from);
    final insertAt =
        from < ti ? list.indexOf(target) + 1 : list.indexOf(target);
    list.insert(insertAt, moving);
    return list;
  }

  /// Pick [id] up. Call from the draggable's `onDragStarted`.
  void beginDrag(String id) {
    _dragging = id;
    _lastTarget = id;
    _beforeMove = null;
    _lastMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Slide the held card to where [target] sits (in-memory, no persist).
  /// Call from each slot's `DragTarget.onMove`.
  void moveOver(String target) {
    final moving = _dragging;
    if (moving == null || target == moving || target == _lastTarget) return;

    final next = _reordered(state, moving, target);
    if (listEquals(next, state)) return;
    // Don't immediately undo the last swap, and let a big reflow settle.
    if (_beforeMove != null && listEquals(next, _beforeMove)) return;
    if (DateTime.now().difference(_lastMoveAt) < _settle) return;

    _lastTarget = target;
    _beforeMove = state;
    _lastMoveAt = DateTime.now();
    state = next;
  }

  /// Commit the previewed order. Call from the draggable's `onDragEnd`
  /// (fires whether the drop was accepted or cancelled).
  Future<void> endDrag() async {
    _dragging = null;
    _lastTarget = null;
    _beforeMove = null;
    await _box.put(_key, List<String>.of(state));
  }
}

final dashboardOrderProvider =
    NotifierProvider<DashboardOrderNotifier, List<String>>(
        DashboardOrderNotifier.new);

/// The set of card ids the user has hidden from the dashboard. Default is
/// empty (everything visible); new cards in future versions show by default.
/// Managed from the Customize page; persisted to the `settings` box.
class DashboardHiddenNotifier extends Notifier<Set<String>> {
  static const _key = 'dashboardHidden';

  dynamic get _box => ref.read(localStoreProvider).box(LocalStore.settings);

  @override
  Set<String> build() {
    final saved = _box.get(_key);
    if (saved is! List) return <String>{};
    return {
      for (final raw in saved)
        if (kDashboardCardIds.contains(raw.toString())) raw.toString(),
    };
  }

  bool isHidden(String id) => state.contains(id);

  /// Show a hidden card / hide a visible one, then persist.
  Future<void> toggle(String id) async {
    final next = Set<String>.of(state);
    if (!next.add(id)) next.remove(id); // add() false ⇒ was present ⇒ unhide
    state = next;
    await _box.put(_key, next.toList());
  }
}

final dashboardHiddenProvider =
    NotifierProvider<DashboardHiddenNotifier, Set<String>>(
        DashboardHiddenNotifier.new);
