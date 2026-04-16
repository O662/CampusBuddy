import 'dart:convert';
import 'package:flutter/material.dart';

class ScheduleBlock {
  final String id;
  final String title;
  final String? categoryId;
  /// Days of week this block repeats on. Uses DateTime constants:
  /// DateTime.monday=1 … DateTime.sunday=7
  final List<int> daysOfWeek;
  /// Start time as minutes from midnight (e.g. 9*60 = 9am)
  final int startMinutes;
  /// End time as minutes from midnight
  final int endMinutes;
  /// Fallback color when no category is linked
  final int colorValue;
  final String notes;

  ScheduleBlock({
    required this.id,
    required this.title,
    this.categoryId,
    required this.daysOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    required this.colorValue,
    this.notes = '',
  });

  TimeOfDay get startTime =>
      TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
  TimeOfDay get endTime =>
      TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);

  double get durationHours => (endMinutes - startMinutes) / 60.0;

  String get timeRangeLabel {
    String fmt(TimeOfDay t) {
      final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final m = t.minute.toString().padLeft(2, '0');
      final period = t.period == DayPeriod.am ? 'am' : 'pm';
      return t.minute == 0 ? '$h$period' : '$h:$m$period';
    }

    return '${fmt(startTime)} – ${fmt(endTime)}';
  }

  static const List<String> dayNames = [
    '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  ScheduleBlock copyWith({
    String? id,
    String? title,
    String? categoryId,
    bool clearCategory = false,
    List<int>? daysOfWeek,
    int? startMinutes,
    int? endMinutes,
    int? colorValue,
    String? notes,
  }) {
    return ScheduleBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      colorValue: colorValue ?? this.colorValue,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'categoryId': categoryId,
        'daysOfWeek': daysOfWeek,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'colorValue': colorValue,
        'notes': notes,
      };

  factory ScheduleBlock.fromJson(Map<String, dynamic> json) => ScheduleBlock(
        id: json['id'] as String,
        title: json['title'] as String,
        categoryId: json['categoryId'] as String?,
        daysOfWeek: List<int>.from(json['daysOfWeek'] as List),
        startMinutes: json['startMinutes'] as int,
        endMinutes: json['endMinutes'] as int,
        colorValue: json['colorValue'] as int,
        notes: json['notes'] as String? ?? '',
      );

  static List<ScheduleBlock> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list
        .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<ScheduleBlock> blocks) =>
      jsonEncode(blocks.map((b) => b.toJson()).toList());
}
