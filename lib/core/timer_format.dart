/// Formatting helpers shared by the Timer board, the pop-out window and the
/// in-app fallback page so a timer reads identically everywhere.
library;

/// Countdown digits: `H:MM:SS` once an hour or more, else `MM:SS`.
String fmtCountdown(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// A configured length spelled out, e.g. `1h 30m`, `25m`, `45s`.
String fmtDurationLabel(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final parts = <String>[
    if (h > 0) '${h}h',
    if (m > 0) '${m}m',
    if (s > 0 || (h == 0 && m == 0)) '${s}s',
  ];
  return parts.join(' ');
}

/// Wall-clock time a running timer fires, e.g. `3:45 PM`. Adds the day when
/// it lands on a different calendar date than now.
String fmtGoesOff(DateTime endsAt) {
  final now = DateTime.now();
  final h = endsAt.hour;
  final ampm = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final t = '$h12:${endsAt.minute.toString().padLeft(2, '0')} $ampm';
  final sameDay = endsAt.year == now.year &&
      endsAt.month == now.month &&
      endsAt.day == now.day;
  if (sameDay) return t;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow = endsAt.year == tomorrow.year &&
      endsAt.month == tomorrow.month &&
      endsAt.day == tomorrow.day;
  return isTomorrow ? '$t tomorrow' : '$t (${endsAt.month}/${endsAt.day})';
}
