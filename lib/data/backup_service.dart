import 'dart:convert';

import 'package:flutter/material.dart';

import 'local_store.dart';
import 'models.dart';

/// Plain export/import of the local Hive data as a single portable JSON
/// document. No code generation, no platform plugins here — file I/O is the
/// caller's job; this only (de)serializes and merges.
///
/// Envelope:
/// ```json
/// {"app":"CampusBuddy","format":1,"exportedAt":"<iso>",
///  "sections":{"profile":{...}, "courses":[...], ...}}
/// ```
/// Each collection section is the raw list of stored maps; `profile` is the
/// single [UserProfile] map. Import is a *merge*: items are upserted by id
/// (decoded through the models so the schema is validated and legacy
/// migrations run), and anything not in the file is left untouched.

const String kBackupAppId = 'CampusBuddy';
const int kBackupFormat = 1;

/// A user-facing group of data the user can tick on/off when exporting or
/// importing. Each maps to one or more Hive sections.
enum BackupCategory {
  profile,
  coursesGrades,
  academicHistory,
  todos,
  planner,
  flashcards,
  notes,
  timers,
  pomodoros,
}

extension BackupCategoryX on BackupCategory {
  String get label => switch (this) {
        BackupCategory.profile => 'Profile, preferences & layout',
        BackupCategory.coursesGrades => 'Courses & grades',
        BackupCategory.academicHistory => 'Academic history',
        BackupCategory.todos => 'To-dos & folders',
        BackupCategory.planner => 'Planner (blocks & events)',
        BackupCategory.flashcards => 'Flashcards',
        BackupCategory.notes => 'Notes',
        BackupCategory.timers => 'Timers',
        BackupCategory.pomodoros => 'Pomodoros',
      };

  IconData get icon => switch (this) {
        BackupCategory.profile => Icons.person_rounded,
        BackupCategory.coursesGrades => Icons.school_rounded,
        BackupCategory.academicHistory => Icons.account_balance_rounded,
        BackupCategory.todos => Icons.checklist_rounded,
        BackupCategory.planner => Icons.calendar_month_rounded,
        BackupCategory.flashcards => Icons.style_rounded,
        BackupCategory.notes => Icons.sticky_note_2_rounded,
        BackupCategory.timers => Icons.timer_rounded,
        BackupCategory.pomodoros => Icons.spa_rounded,
      };

  /// Special single-value section storing the [UserProfile] map.
  static const String profileSection = 'profile';

  /// Hive box names (== section keys) this category covers. The `profile`
  /// category instead owns the single [profileSection] map.
  List<String> get sectionKeys => switch (this) {
        BackupCategory.profile => const [profileSection],
        BackupCategory.coursesGrades => const [
            LocalStore.courses,
            LocalStore.grades,
            LocalStore.gradeCategories,
          ],
        BackupCategory.academicHistory => const [
            LocalStore.institutions,
            LocalStore.semesters,
            LocalStore.pastCourses,
          ],
        BackupCategory.todos => const [LocalStore.tasks, LocalStore.folders],
        BackupCategory.planner => const [LocalStore.blocks, LocalStore.events],
        BackupCategory.flashcards => const [
            LocalStore.decks,
            LocalStore.deckGroups,
            LocalStore.cards,
          ],
        BackupCategory.notes => const [LocalStore.notes],
        BackupCategory.timers => const [LocalStore.timers],
        BackupCategory.pomodoros => const [LocalStore.pomodoros],
      };
}

/// Round-trips a stored map through its model so importing validates the
/// schema, drops unknown junk, and runs any legacy `fromJson` migrations.
/// Keyed by section name (which equals the Hive box name).
final Map<String, Map<String, dynamic> Function(Map)> _roundTrip = {
  LocalStore.courses: (m) => Course.fromJson(m).toJson(),
  LocalStore.grades: (m) => GradeEntry.fromJson(m).toJson(),
  LocalStore.gradeCategories: (m) => GradeCategory.fromJson(m).toJson(),
  LocalStore.institutions: (m) => Institution.fromJson(m).toJson(),
  LocalStore.semesters: (m) => Semester.fromJson(m).toJson(),
  LocalStore.pastCourses: (m) => PastCourse.fromJson(m).toJson(),
  LocalStore.tasks: (m) => TaskItem.fromJson(m).toJson(),
  LocalStore.folders: (m) => TaskFolder.fromJson(m).toJson(),
  LocalStore.blocks: (m) => TimeBlock.fromJson(m).toJson(),
  LocalStore.events: (m) => EventItem.fromJson(m).toJson(),
  LocalStore.decks: (m) => Deck.fromJson(m).toJson(),
  LocalStore.deckGroups: (m) => DeckGroup.fromJson(m).toJson(),
  LocalStore.cards: (m) => Flashcard.fromJson(m).toJson(),
  LocalStore.notes: (m) => Note.fromJson(m).toJson(),
  LocalStore.timers: (m) => TimerItem.fromJson(m).toJson(),
  LocalStore.pomodoros: (m) => PomodoroPreset.fromJson(m).toJson(),
};

/// Thrown when an imported file isn't a recognisable CampusBuddy backup.
class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A parsed, validated backup file: the raw sections plus which categories
/// it actually carries data for.
class ParsedBackup {
  ParsedBackup(this._sections, this.categories);

  final Map<String, dynamic> _sections;

  /// Categories present in the file (so the import UI can pre-tick exactly
  /// what's restorable and grey out the rest).
  final Set<BackupCategory> categories;

  DateTime? get exportedAt {
    final raw = _sections['__exportedAt'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }
}

class BackupService {
  BackupService(this._store);

  final LocalStore _store;

  /// Key under which UI preferences ride along inside the profile
  /// section. Underscore-prefixed so `UserProfile.fromJson` (which only
  /// reads known names) silently ignores it on legacy import paths.
  static const String _prefsKey = '_prefs';

  /// Builds the pretty-printed JSON backup for [selected].
  String buildJson(Set<BackupCategory> selected) {
    final sections = <String, dynamic>{};
    for (final cat in selected) {
      for (final key in cat.sectionKeys) {
        if (key == BackupCategoryX.profileSection) {
          // Bundle UI preferences alongside the profile so a restore on a
          // fresh machine doesn't reset hide-done, view modes, recents,
          // and the Grades widget order. Empty pref map is omitted to
          // keep older clients happy.
          final profileMap = _store.readProfile().toJson();
          final prefs = _store.readBackupPrefs();
          if (prefs.isNotEmpty) profileMap[_prefsKey] = prefs;
          sections[key] = profileMap;
        } else {
          sections[key] = [
            for (final v in _store.box(key).values.whereType<Map>())
              _stringKeyed(v),
          ];
        }
      }
    }
    final envelope = {
      'app': kBackupAppId,
      'format': kBackupFormat,
      'exportedAt': DateTime.now().toIso8601String(),
      'sections': sections,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Parses + validates a backup file's [text]. Throws
  /// [BackupFormatException] if it isn't a CampusBuddy backup.
  static ParsedBackup parse(String text) {
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw BackupFormatException("That file isn't valid JSON.");
    }
    if (decoded is! Map || decoded['app'] != kBackupAppId) {
      throw BackupFormatException("That file isn't a CampusBuddy backup.");
    }
    final sections = decoded['sections'];
    if (sections is! Map) {
      throw BackupFormatException('The backup file is missing its data.');
    }
    final present = <BackupCategory>{};
    for (final cat in BackupCategory.values) {
      final hasAny = cat.sectionKeys.any((k) {
        final s = sections[k];
        return k == BackupCategoryX.profileSection
            ? s is Map
            : s is List && s.isNotEmpty;
      });
      if (hasAny) present.add(cat);
    }
    if (present.isEmpty) {
      throw BackupFormatException('The backup file has no data to import.');
    }
    final flat = <String, dynamic>{
      for (final e in sections.entries) e.key.toString(): e.value,
      '__exportedAt': decoded['exportedAt'],
    };
    return ParsedBackup(flat, present);
  }

  /// Merges the [selected] categories from [backup] into local storage:
  /// every item is upserted by id; existing data not in the file is kept.
  /// Returns the categories that were actually written.
  Future<Set<BackupCategory>> applyMerge(
    ParsedBackup backup,
    Set<BackupCategory> selected,
  ) async {
    final applied = <BackupCategory>{};
    for (final cat in selected) {
      if (!backup.categories.contains(cat)) continue;
      for (final key in cat.sectionKeys) {
        final raw = backup._sections[key];
        if (key == BackupCategoryX.profileSection) {
          if (raw is Map) {
            await _store.writeProfile(UserProfile.fromJson(raw));
            // Restore UI preferences when the backup carried them.
            // Older backups (pre-`_prefs`) simply skip this branch.
            final prefs = raw[_prefsKey];
            if (prefs is Map) {
              await _store.writeBackupPrefs(
                  {for (final e in prefs.entries) e.key.toString(): e.value});
            }
            applied.add(cat);
          }
          continue;
        }
        if (raw is! List) continue;
        final box = _store.box(key);
        final convert = _roundTrip[key];
        for (final item in raw.whereType<Map>()) {
          final clean = convert!(item);
          await box.put(clean['id'], clean);
        }
        applied.add(cat);
      }
    }
    return applied;
  }

  /// Hive can hand back `Map<dynamic, dynamic>`; jsonEncode needs String
  /// keys. Our stored maps are flat primitives, so a shallow copy is enough.
  static Map<String, dynamic> _stringKeyed(Map m) =>
      {for (final e in m.entries) e.key.toString(): e.value};
}
