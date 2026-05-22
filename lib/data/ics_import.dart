import 'dart:convert';

import 'local_store.dart';
import 'models.dart';

/// Outcome of an .ics import — used to drive the post-import summary so the
/// user can see what was added vs. updated vs. skipped without us having to
/// reach into the persistence layer twice.
class IcsImportResult {
  IcsImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.warnings,
  });

  /// Brand-new events written to storage.
  final List<EventItem> added;

  /// Events whose stored copy was overwritten (same UID re-imported).
  final List<EventItem> updated;

  /// VEVENTs the parser had to drop — bad/missing DTSTART, unsupported
  /// recurrence rule we couldn't map, etc. Surfaced as a count + reasons
  /// so the user knows their file wasn't fully consumed.
  final List<String> skipped;

  /// Non-fatal notes worth telling the user (e.g. "8 weekly classes"
  /// or "ignored an RRULE we don't support yet").
  final List<String> warnings;

  int get total => added.length + updated.length;
  bool get isEmpty => added.isEmpty && updated.isEmpty;
}

/// Parse an iCalendar text payload into a list of [EventItem]s. The parser
/// is intentionally narrow: it covers the properties Gmail / iCloud /
/// Outlook all emit for normal events (UID, SUMMARY, LOCATION, DTSTART,
/// DTEND, RRULE) and ignores everything else. Anything we can't map cleanly
/// is recorded in [IcsImportResult.skipped] / `warnings` so the caller can
/// tell the user what happened instead of silently dropping data.
class IcsParser {
  /// Parse [text] and return the events it contains. Each VEVENT becomes
  /// one [EventItem]; their ids derive from the VEVENT UID prefixed with
  /// `ics:` so re-importing the same file overwrites instead of duplicating.
  static IcsParseOutcome parse(String text) {
    final lines = _unfold(text);
    final events = <EventItem>[];
    final skipped = <String>[];
    final warnings = <String>[];

    Map<String, String>? current; // property name (uppercased) → raw value
    List<String>? currentParamsLines; // raw lines for params we need later

    for (final raw in lines) {
      final line = raw;
      if (line.isEmpty) continue;
      if (line.toUpperCase() == 'BEGIN:VEVENT') {
        current = {};
        currentParamsLines = [];
        continue;
      }
      if (line.toUpperCase() == 'END:VEVENT') {
        if (current == null) continue;
        final result = _buildEvent(current, currentParamsLines ?? const []);
        if (result.event != null) {
          events.add(result.event!);
          if (result.warning != null) warnings.add(result.warning!);
        } else {
          skipped.add(result.skipReason ?? 'unparseable VEVENT');
        }
        current = null;
        currentParamsLines = null;
        continue;
      }
      if (current == null) continue;
      currentParamsLines!.add(line);

      // Split on the first ':' to separate "NAME;params" from value.
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final left = line.substring(0, colon);
      final value = line.substring(colon + 1);
      final semi = left.indexOf(';');
      final name = (semi < 0 ? left : left.substring(0, semi)).toUpperCase();
      // Last-write-wins is fine — calendars don't legitimately repeat a
      // single-value property like SUMMARY within one VEVENT.
      current[name] = value;
    }

    return IcsParseOutcome(
      events: events,
      skippedReasons: skipped,
      warnings: warnings,
    );
  }

  /// Unfold RFC 5545 line continuations (a line starting with space/tab
  /// continues the previous line) and normalise to LF-terminated rows.
  static List<String> _unfold(String text) {
    // Strip a UTF-8 BOM if the file came from Windows / Outlook.
    var t = text;
    if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) t = t.substring(1);
    final raw = const LineSplitter().convert(t);
    final out = <String>[];
    for (final r in raw) {
      if (r.isNotEmpty && (r.startsWith(' ') || r.startsWith('\t')) &&
          out.isNotEmpty) {
        out[out.length - 1] = out.last + r.substring(1);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  static _BuildResult _buildEvent(
    Map<String, String> props,
    List<String> rawLines,
  ) {
    final summary = _unescape(props['SUMMARY'] ?? '');
    if (summary.trim().isEmpty) {
      return const _BuildResult.skipped('VEVENT had no SUMMARY');
    }
    final dtStartRaw = _findFullLine(rawLines, 'DTSTART');
    if (dtStartRaw == null) {
      return const _BuildResult.skipped('VEVENT had no DTSTART');
    }
    final start = _parseDateTime(dtStartRaw);
    if (start == null) {
      return _BuildResult.skipped('couldn\'t parse DTSTART: $dtStartRaw');
    }
    final uid = (props['UID'] ?? '').trim();
    final id = uid.isEmpty ? 'ics:${newId()}' : 'ics:$uid';
    final location = _unescape(props['LOCATION'] ?? '');

    // RRULE → Recurrence. We support the cadences the rest of the app
    // already models (daily/weekly/biweekly/monthly with a sane interval).
    // Anything else falls back to a one-off event so the user at least
    // gets the seed occurrence on their calendar.
    Recurrence rec = Recurrence.none;
    DateTime? until;
    String? rruleWarning;
    final rrule = props['RRULE'];
    if (rrule != null && rrule.isNotEmpty) {
      final parsed = _parseRRule(rrule);
      rec = parsed.recurrence;
      until = parsed.until;
      if (rec == Recurrence.none && parsed.hadFreq) {
        rruleWarning =
            '"$summary" uses a recurrence pattern we don\'t support — '
            'only the first occurrence was imported.';
      }
    }

    final type = _guessType(summary);
    return _BuildResult.ok(
      EventItem(
        id: id,
        title: summary,
        start: start,
        type: type,
        location: location,
        recurrence: rec,
        recurrenceEnd: until,
      ),
      warning: rruleWarning,
    );
  }

  /// Heuristic event-type assignment for imported items. Calendar exports
  /// don't carry our type taxonomy, so we lean on common keywords; anything
  /// that doesn't match drops into [EventType.personal] (the existing
  /// default for new events).
  static EventType _guessType(String title) {
    final t = title.toLowerCase();
    if (t.contains('exam') ||
        t.contains('midterm') ||
        t.contains('final') ||
        t.contains('quiz')) {
      return EventType.exam;
    }
    if (t.contains('class') ||
        t.contains('lecture') ||
        t.contains('lab') ||
        t.contains('seminar') ||
        t.contains('recitation')) {
      return EventType.classSession;
    }
    if (t.contains('due') ||
        t.contains('deadline') ||
        t.contains('assignment')) {
      return EventType.deadline;
    }
    return EventType.personal;
  }

  /// Find a property line (with its params, before the colon) so we can
  /// inspect parameters like TZID or VALUE=DATE. Returns the value half
  /// joined with any TZID context we need.
  static String? _findFullLine(List<String> lines, String name) {
    final upperName = name.toUpperCase();
    for (final l in lines) {
      final colon = l.indexOf(':');
      if (colon < 0) continue;
      final left = l.substring(0, colon).toUpperCase();
      if (left == upperName || left.startsWith('$upperName;')) {
        return l;
      }
    }
    return null;
  }

  /// Parse `DTSTART[;params]:value` into a [DateTime]. We honour:
  ///   - `VALUE=DATE` and bare `YYYYMMDD` → midnight local
  ///   - `YYYYMMDDTHHMMSSZ` → UTC (returned as local-equivalent instant)
  ///   - `YYYYMMDDTHHMMSS` → treated as local wall-clock
  ///   - `TZID=...` → TZID label is ignored; the wall-clock is taken as
  ///     local time (full timezone resolution would need a tz database
  ///     we deliberately don't ship).
  static DateTime? _parseDateTime(String line) {
    final colon = line.indexOf(':');
    if (colon < 0) return null;
    final left = line.substring(0, colon);
    final value = line.substring(colon + 1).trim();
    final isDateOnly = left.toUpperCase().contains('VALUE=DATE') &&
        !left.toUpperCase().contains('VALUE=DATE-TIME');

    if (isDateOnly || (value.length == 8 && !value.contains('T'))) {
      // YYYYMMDD
      if (value.length < 8) return null;
      final y = int.tryParse(value.substring(0, 4));
      final m = int.tryParse(value.substring(4, 6));
      final d = int.tryParse(value.substring(6, 8));
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    // YYYYMMDDTHHMMSS[Z]
    final isUtc = value.endsWith('Z');
    final v = isUtc ? value.substring(0, value.length - 1) : value;
    if (v.length < 15 || v[8] != 'T') return null;
    final y = int.tryParse(v.substring(0, 4));
    final m = int.tryParse(v.substring(4, 6));
    final d = int.tryParse(v.substring(6, 8));
    final hh = int.tryParse(v.substring(9, 11));
    final mm = int.tryParse(v.substring(11, 13));
    final ss = int.tryParse(v.substring(13, 15));
    if ([y, m, d, hh, mm, ss].any((x) => x == null)) return null;
    if (isUtc) {
      return DateTime.utc(y!, m!, d!, hh!, mm!, ss!).toLocal();
    }
    return DateTime(y!, m!, d!, hh!, mm!, ss!);
  }

  static _RRuleParse _parseRRule(String value) {
    final parts = <String, String>{};
    for (final p in value.split(';')) {
      final eq = p.indexOf('=');
      if (eq < 0) continue;
      parts[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1);
    }
    final freq = parts['FREQ']?.toUpperCase();
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    final untilRaw = parts['UNTIL'];
    DateTime? until;
    if (untilRaw != null && untilRaw.isNotEmpty) {
      // UNTIL uses the same encoding as DTSTART — reuse the same parser
      // by wrapping it back into the "PROP:VALUE" shape it expects.
      until = _parseDateTime('UNTIL:$untilRaw');
    }
    Recurrence rec = Recurrence.none;
    if (freq == 'DAILY' && interval == 1) {
      rec = Recurrence.daily;
    } else if (freq == 'WEEKLY' && interval == 1) {
      rec = Recurrence.weekly;
    } else if (freq == 'WEEKLY' && interval == 2) {
      rec = Recurrence.biweekly;
    } else if (freq == 'MONTHLY' && interval == 1) {
      rec = Recurrence.monthly;
    }
    return _RRuleParse(
      recurrence: rec,
      until: until,
      hadFreq: freq != null,
    );
  }

  /// Reverse the RFC 5545 text escaping (`\\`, `\,`, `\;`, `\n`/`\N`).
  static String _unescape(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '\\' && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == 'n' || next == 'N') {
          buf.write('\n');
        } else {
          buf.write(next);
        }
        i++;
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }
}

/// Bag of everything the parser pulled out of one .ics document.
class IcsParseOutcome {
  IcsParseOutcome({
    required this.events,
    required this.skippedReasons,
    required this.warnings,
  });

  final List<EventItem> events;
  final List<String> skippedReasons;
  final List<String> warnings;
}

class _BuildResult {
  const _BuildResult.ok(this.event, {this.warning}) : skipReason = null;
  const _BuildResult.skipped(String reason)
      : event = null,
        warning = null,
        skipReason = reason;

  final EventItem? event;
  final String? warning;
  final String? skipReason;
}

class _RRuleParse {
  const _RRuleParse({
    required this.recurrence,
    required this.until,
    required this.hadFreq,
  });
  final Recurrence recurrence;
  final DateTime? until;
  final bool hadFreq;
}
