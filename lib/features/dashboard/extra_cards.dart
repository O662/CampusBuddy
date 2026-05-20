import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'weather.dart';

// ---------------------------------------------------------------------------
// Clock & date
// ---------------------------------------------------------------------------

class ClockCard extends StatefulWidget {
  const ClockCard({super.key});

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 18, color: AppPalette.lavender),
              const SizedBox(width: 8),
              Text(DateFormat('EEEE').format(_now),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            DateFormat('h:mm').format(_now) +
                DateFormat(' a').format(_now).toLowerCase(),
            style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                height: 1.0),
          ),
          const SizedBox(height: 6),
          Text(DateFormat('MMMM d, y').format(_now),
              style: const TextStyle(
                  color: AppPalette.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Weather (Open-Meteo, no API key)
// ---------------------------------------------------------------------------

class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key});

  double _shown(double c, bool f) => f ? c * 9 / 5 + 32 : c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(weatherLocationProvider);
    final fahrenheit = ref.watch(weatherFahrenheitProvider);
    final async = ref.watch(weatherProvider);
    final unit = fahrenheit ? '°F' : '°C';

    Widget body;
    if (loc == null) {
      // No location yet: weatherProvider auto-detects via IP on first load.
      body = async.isLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  SizedBox(
                      width: 24,
                      height: 24,
                      child:
                          CircularProgressIndicator(strokeWidth: 2.4)),
                  SizedBox(height: 12),
                  Text('Finding your location…',
                      style: TextStyle(
                          color: AppPalette.textSecondary, fontSize: 13)),
                ],
              ),
            )
          : Column(
              children: [
                const EmptyHint(
                    "Couldn't detect your location automatically.",
                    icon: Icons.location_off_outlined),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    SoftButton(
                      label: 'Use my location',
                      icon: Icons.my_location_rounded,
                      filled: true,
                      onTap: () => _useMyLocation(ref),
                    ),
                    SoftButton(
                      label: 'Search a city',
                      icon: Icons.search_rounded,
                      onTap: () => _searchCity(context, ref),
                    ),
                  ],
                ),
              ],
            );
    } else {
      body = async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
        error: (_, _) => Column(
          children: [
            const EmptyHint('Could not load weather.',
                icon: Icons.cloud_off_rounded),
            const SizedBox(height: 8),
            SoftButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: () => ref.invalidate(weatherProvider),
            ),
          ],
        ),
        data: (w) {
          if (w == null) return const EmptyHint('No weather yet.');
          final stale =
              DateTime.now().difference(w.fetchedAt) > const Duration(hours: 2);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(w.icon, size: 46, color: AppPalette.sky),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => ref
                            .read(weatherFahrenheitProvider.notifier)
                            .toggle(),
                        child: Text(
                          '${_shown(w.tempC, fahrenheit).round()}$unit',
                          style: const TextStyle(
                              fontSize: 38, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(w.description,
                          style: const TextStyle(
                              color: AppPalette.textSecondary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _hl(Icons.arrow_upward_rounded,
                      '${_shown(w.hiC, fahrenheit).round()}$unit'),
                  const SizedBox(width: 14),
                  _hl(Icons.arrow_downward_rounded,
                      '${_shown(w.loC, fahrenheit).round()}$unit'),
                  const Spacer(),
                  Flexible(
                    child: Text(w.place,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppPalette.textSecondary,
                            fontSize: 12)),
                  ),
                ],
              ),
              if (stale)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Offline · as of ${DateFormat('MMM d, h:mm a').format(w.fetchedAt)}',
                      style: const TextStyle(
                          color: AppPalette.textFaint, fontSize: 11)),
                ),
            ],
          );
        },
      );
    }

    return GlassCard(
      title: 'Weather',
      icon: Icons.wb_sunny_outlined,
      trailing: loc == null
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz,
                  size: 18, color: AppPalette.textSecondary),
              color: const Color(0xFF241F45),
              tooltip: 'Weather options',
              onSelected: (v) {
                switch (v) {
                  case 'auto':
                    _useMyLocation(ref);
                  case 'city':
                    _searchCity(context, ref);
                  case 'provider':
                    _providerDialog(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'auto',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.my_location_rounded, size: 20),
                    title: Text('Update to my location'),
                  ),
                ),
                PopupMenuItem(
                  value: 'city',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.search_rounded, size: 20),
                    title: Text('Search a city'),
                  ),
                ),
                PopupMenuItem(
                  value: 'provider',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.key_rounded, size: 20),
                    title: Text('Weather provider'),
                  ),
                ),
              ],
            ),
      child: body,
    );
  }

  Widget _hl(IconData i, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 14, color: AppPalette.textSecondary),
          const SizedBox(width: 2),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );

  Future<void> _useMyLocation(WidgetRef ref) async {
    // detectFromIp saves on success and swallows errors; on failure nothing
    // is saved and the card falls back to the manual options.
    await ref.read(weatherLocationProvider.notifier).detectFromIp();
    ref.invalidate(weatherProvider);
  }

  Future<void> _searchCity(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var loading = false;
    String? error;
    var results = <WeatherLocation>[];

    await showGlassDialog<void>(
      context,
      title: 'Search a city',
      content: StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> run() async {
            final q = controller.text.trim();
            if (q.isEmpty) return;
            setLocal(() {
              loading = true;
              error = null;
            });
            try {
              final found = await WeatherService.search(q);
              setLocal(() {
                loading = false;
                results = found;
                if (found.isEmpty) error = 'No matches for "$q".';
              });
            } catch (_) {
              setLocal(() {
                loading = false;
                error = 'Network error. Check your connection.';
              });
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => run(),
                      decoration: const InputDecoration(
                          hintText: 'Town or city (any size)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SoftButton(
                      label: 'Search',
                      icon: Icons.search_rounded,
                      filled: true,
                      onTap: run),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child:
                          CircularProgressIndicator(strokeWidth: 2.2)),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: const TextStyle(
                        color: AppPalette.danger, fontSize: 13)),
              ],
              if (results.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in results)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined,
                              size: 18, color: AppPalette.lavender),
                          title: Text(r.name),
                          onTap: () {
                            ref
                                .read(weatherLocationProvider.notifier)
                                .set(r);
                            ref.invalidate(weatherProvider);
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _providerDialog(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: ref.read(owmKeyProvider));

    await showGlassDialog<void>(
      context,
      title: 'Weather provider',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'By default CampusBuddy uses Open-Meteo — free, no account, '
            'no key. You can optionally use OpenWeatherMap instead by '
            'pasting an API key below.',
            style: TextStyle(
                color: AppPalette.textSecondary, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const Text(
            'Get a free key:\n'
            '1. Sign up at openweathermap.org/api\n'
            '2. Open "API keys" in your account\n'
            '3. Copy the key and paste it here\n'
            '(new keys can take ~1–2 hours to activate)',
            style: TextStyle(
                color: AppPalette.textFaint, height: 1.5, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
                hintText: 'OpenWeatherMap API key (optional)'),
          ),
        ],
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () {
            ref.read(owmKeyProvider.notifier).save('');
            ref.invalidate(weatherProvider);
            Navigator.pop(dialogContext);
          },
          child: const Text('Use Open-Meteo'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(owmKeyProvider.notifier).save(controller.text);
            ref.invalidate(weatherProvider);
            Navigator.pop(dialogContext);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick add
// ---------------------------------------------------------------------------

class QuickAddCard extends ConsumerWidget {
  const QuickAddCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tile(IconData icon, String label, Color color, VoidCallback tap) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: tap,
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      title: 'Quick add',
      icon: Icons.bolt_rounded,
      child: Row(
        children: [
          tile(Icons.check_circle_outline, 'Task', AppPalette.periwinkle,
              () async {
            final t = await showTaskDialog(context,
                folders: ref.read(foldersProvider),
                courses: ref.read(coursesProvider),
                categories: ref.read(gradeCategoriesProvider));
            if (t != null) ref.read(tasksProvider.notifier).save(t);
          }),
          tile(Icons.create_new_folder_outlined, 'Folder',
              AppPalette.peach, () async {
            final f = await showFolderDialog(context,
                courses: ref.read(coursesProvider));
            if (f != null) {
              ref.read(foldersProvider.notifier).upsert(f);
            }
          }),
          tile(Icons.event_outlined, 'Event', AppPalette.mint, () async {
            final e = await showEventDialog(context);
            if (e != null) ref.read(eventsProvider.notifier).upsert(e);
          }),
          tile(Icons.school_outlined, 'Course', AppPalette.lavender,
              () async {
            final created = <Semester>[];
            final c = await showCourseDialog(context,
                institutions: ref.read(institutionsProvider),
                semesters: ref.read(semestersProvider),
                createdSemesters: created,
                onCreateSemester: (institutionId) => showSemesterDialog(
                    context, institutionId: institutionId));
            if (c != null) {
              for (final s in created) {
                ref.read(semestersProvider.notifier).upsert(s);
              }
              ref.read(coursesProvider.notifier).upsert(c);
            }
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Next up — countdown to the soonest event / assignment
// ---------------------------------------------------------------------------

class CountdownCard extends ConsumerStatefulWidget {
  const CountdownCard({super.key});

  @override
  ConsumerState<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends ConsumerState<CountdownCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.inDays >= 1) {
      final h = d.inHours % 24;
      return '${d.inDays}d ${h}h';
    }
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    ({DateTime when, String title, String kind, Color color})? next;
    void consider(DateTime when, String title, String kind, Color color) {
      if (when.isAfter(now) &&
          (next == null || when.isBefore(next!.when))) {
        next = (when: when, title: title, kind: kind, color: color);
      }
    }

    for (final e in ref.watch(eventsProvider)) {
      consider(e.start, e.title, e.type.label, AppPalette.mint);
    }
    for (final t in ref.watch(tasksProvider)) {
      if (!t.done && t.due != null) {
        consider(t.due!, t.title,
            t.isAssignment ? 'Assignment' : 'Due', AppPalette.peach);
      }
    }

    return GlassCard(
      title: 'Next up',
      icon: Icons.hourglass_top_rounded,
      child: next == null
          ? const EmptyHint('Nothing on the horizon. 🌅')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmt(next!.when.difference(now)),
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: next!.color)),
                const SizedBox(height: 6),
                Text(next!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GlassChip(label: next!.kind, color: next!.color),
                    const SizedBox(width: 8),
                    Text(relativeDay(next!.when),
                        style: const TextStyle(
                            color: AppPalette.textSecondary,
                            fontSize: 12)),
                  ],
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily focus quote
// ---------------------------------------------------------------------------

class QuoteCard extends StatefulWidget {
  const QuoteCard({super.key});

  @override
  State<QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<QuoteCard> {
  static const _quotes = [
    'Small steps every day add up to big results.',
    'You don\'t have to be perfect — just consistent.',
    'Focus on progress, not perfection.',
    'The secret of getting ahead is getting started.',
    'Done is better than perfect.',
    'Your future is created by what you do today.',
    'Slow progress is still progress.',
    'Discipline is choosing what you want most over what you want now.',
    'A little progress each day adds up to big results.',
    'Study smart, rest well, repeat.',
    'You are capable of more than you know.',
    'One page at a time is still moving forward.',
    'Breathe. You\'ve got this.',
    'Effort today, ease tomorrow.',
    'Be proud of how hard you are trying.',
  ];

  late int _i = DateTime.now().difference(DateTime(2020)).inDays %
      _quotes.length;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      onTap: () =>
          setState(() => _i = (_i + 1) % _quotes.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.format_quote_rounded,
                  size: 18, color: AppPalette.lavender),
              SizedBox(width: 8),
              Text('Today\'s focus',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _quotes[_i],
            style: const TextStyle(
                fontSize: 17, height: 1.4, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          const Text('Tap for another',
              style:
                  TextStyle(color: AppPalette.textFaint, fontSize: 11)),
        ],
      ),
    );
  }
}
