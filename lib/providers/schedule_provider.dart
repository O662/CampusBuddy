import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_block.dart';

class ScheduleProvider extends ChangeNotifier {
  List<ScheduleBlock> _blocks = [];
  static const _key = 'schedule_blocks';

  List<ScheduleBlock> get allBlocks => List.unmodifiable(_blocks);

  List<ScheduleBlock> blocksForDay(int dayOfWeek) =>
      _blocks
          .where((b) => b.daysOfWeek.contains(dayOfWeek))
          .toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      _blocks = ScheduleBlock.listFromJson(data);
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, ScheduleBlock.listToJson(_blocks));
  }

  Future<void> addBlock(ScheduleBlock block) async {
    _blocks.add(block);
    notifyListeners();
    await _save();
  }

  Future<void> updateBlock(ScheduleBlock updated) async {
    final idx = _blocks.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _blocks[idx] = updated;
      notifyListeners();
      await _save();
    }
  }

  Future<void> removeBlock(String id) async {
    _blocks.removeWhere((b) => b.id == id);
    notifyListeners();
    await _save();
  }
}
