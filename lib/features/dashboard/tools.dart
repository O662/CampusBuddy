import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/note_editing.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../notes/note_window_bridge.dart';

// ---------------------------------------------------------------------------
// Notes — a compact preview of the Notes board, links to the full page
// ---------------------------------------------------------------------------

/// One-line label for a note in the dashboard preview: its title, else
/// the first non-empty body line.
String _noteHeadline(Note n) {
  if (n.title.trim().isNotEmpty) return n.title.trim();
  for (final line in n.body.split('\n')) {
    final t = line.trim();
    if (t.isNotEmpty) return t;
  }
  return 'Empty note';
}

class NotesPreviewCard extends ConsumerStatefulWidget {
  const NotesPreviewCard({super.key});

  @override
  ConsumerState<NotesPreviewCard> createState() => _NotesPreviewCardState();
}

class _NotesPreviewCardState extends ConsumerState<NotesPreviewCard> {
  final _titleC = TextEditingController();
  final _bodyC = TextEditingController();

  /// Id of the note currently being composed inline. The note is created
  /// up-front and every edit auto-saves, so progress is never lost — even
  /// if the user forgets to close the composer.
  String? _draftId;

  @override
  void dispose() {
    // A draft left completely empty is just noise — clean it up. A draft
    // with any content stays saved (that's the whole point).
    final id = _draftId;
    if (id != null) {
      final note = _find(ref.read(notesProvider), id);
      if (note != null && _isEmpty(note)) {
        ref.read(notesProvider.notifier).remove(id);
      }
    }
    _titleC.dispose();
    _bodyC.dispose();
    super.dispose();
  }

  Note? _find(List<Note> all, String? id) {
    if (id == null) return null;
    for (final n in all) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool _isEmpty(Note n) =>
      n.title.trim().isEmpty && n.body.trim().isEmpty && n.tags.isEmpty;

  void _save(Note next) =>
      ref.read(notesProvider.notifier).upsert(next);

  void _startNew() {
    final all = ref.read(notesProvider);
    // New note goes to the top of the board (same as the Notes page).
    final order = all.isEmpty
        ? 0
        : all.map((n) => n.order).reduce((a, b) => a < b ? a : b) - 1;
    final note =
        Note(id: newId(), order: order, updatedAt: DateTime.now());
    _save(note);
    _titleC.clear();
    _bodyC.clear();
    setState(() => _draftId = note.id);
  }

  void _finish() {
    final id = _draftId;
    if (id != null) {
      final note = _find(ref.read(notesProvider), id);
      if (note != null && _isEmpty(note)) {
        ref.read(notesProvider.notifier).remove(id);
      }
    }
    _titleC.clear();
    _bodyC.clear();
    setState(() => _draftId = null);
  }

  void _discard() {
    final id = _draftId;
    if (id != null) ref.read(notesProvider.notifier).remove(id);
    _titleC.clear();
    _bodyC.clear();
    setState(() => _draftId = null);
  }

  Future<void> _pickColor(Note note) async {
    final picked = await showNoteColorPicker(context, note.colorSeed);
    if (picked != null) {
      _save(note.copyWith(colorSeed: picked, updatedAt: DateTime.now()));
    }
  }

  Future<void> _addTag(Note note) async {
    final onNote = note.tags.map((t) => t.toLowerCase()).toSet();
    final suggestions = <String, String>{};
    for (final n in ref.read(notesProvider)) {
      for (final t in n.tags) {
        final k = t.toLowerCase();
        if (!onNote.contains(k)) suggestions.putIfAbsent(k, () => t);
      }
    }
    final entered =
        await showAddTagDialog(context, suggestions: suggestions.values);
    final tag = entered?.trim() ?? '';
    if (tag.isEmpty) return;
    if (note.tags.any((e) => e.toLowerCase() == tag.toLowerCase())) return;
    _save(note.copyWith(
        tags: [...note.tags, tag], updatedAt: DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider).toList()
      ..sort((a, b) {
        final byTime = b.updatedAt.compareTo(a.updatedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final draft = _find(notes, _draftId);
    // The draft is shown in the composer, so keep it out of the list.
    final preview =
        notes.where((n) => n.id != _draftId).take(4).toList();

    return GlassCard(
      title: 'Notes',
      icon: Icons.sticky_note_2_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft == null) ...[
            SoftButton(
              label: 'New',
              icon: Icons.add_rounded,
              filled: true,
              onTap: _startNew,
            ),
            const SizedBox(width: 8),
          ],
          SoftButton(
            label: 'Open',
            icon: Icons.open_in_full_rounded,
            onTap: () => context.go('/notes'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft != null) ...[
            _Composer(
              note: draft,
              titleC: _titleC,
              bodyC: _bodyC,
              onTitleChanged: (v) => _save(
                  draft.copyWith(title: v, updatedAt: DateTime.now())),
              onBodyChanged: (v) => _save(
                  draft.copyWith(body: v, updatedAt: DateTime.now())),
              onPickColor: () => _pickColor(draft),
              onToggleFavorite: () => _save(draft.copyWith(
                  favorite: !draft.favorite,
                  updatedAt: DateTime.now())),
              onAddTag: () => _addTag(draft),
              onRemoveTag: (t) => _save(draft.copyWith(
                  tags: draft.tags.where((e) => e != t).toList(),
                  updatedAt: DateTime.now())),
              onPopOut: () => popOutNote(context, draft.id),
              onDiscard: _discard,
              onDone: _finish,
            ),
            const SizedBox(height: 14),
          ],
          if (preview.isEmpty && draft == null)
            const EmptyHint('No notes yet — tap New to start one.')
          else
            for (final n in preview)
              InkWell(
                onTap: () => context.go('/notes'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: n.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _noteHeadline(n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (n.favorite) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppPalette.warning),
                      ],
                    ],
                  ),
                ),
              ),
          if (notes.length > preview.length + (draft == null ? 0 : 1)) ...[
            const SizedBox(height: 6),
            Text(
                '+${notes.length - preview.length - (draft == null ? 0 : 1)} more',
                style: const TextStyle(
                    fontSize: 11, color: AppPalette.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// The inline note editor shown inside the dashboard Notes card. Bound to
/// a real note — every change auto-saves through the callbacks.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.note,
    required this.titleC,
    required this.bodyC,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPickColor,
    required this.onToggleFavorite,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onPopOut,
    required this.onDiscard,
    required this.onDone,
  });

  final Note note;
  final TextEditingController titleC;
  final TextEditingController bodyC;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final VoidCallback onPickColor;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;
  final VoidCallback onPopOut;
  final VoidCallback onDiscard;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.glassStroke),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onPickColor,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: note.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: titleC,
                  autofocus: true,
                  onChanged: onTitleChanged,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                ),
              ),
              InkWell(
                onTap: onToggleFavorite,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    note.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: AppPalette.warning,
                  ),
                ),
              ),
              InkWell(
                onTap: onPopOut,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Tooltip(
                    message: 'Pop out',
                    child: Icon(Icons.open_in_new_rounded,
                        size: 18, color: AppPalette.textSecondary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: bodyC,
            minLines: 2,
            maxLines: 6,
            onChanged: onBodyChanged,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Jot anything here…',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in note.tags)
                TagChip(label: t, onRemove: () => onRemoveTag(t)),
              AddTagButton(onTap: onAddTag),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded,
                  size: 14, color: AppPalette.textFaint),
              const SizedBox(width: 5),
              const Text('Saved automatically',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textFaint)),
              const Spacer(),
              TextButton(
                onPressed: onDiscard,
                style: TextButton.styleFrom(
                    foregroundColor: AppPalette.danger),
                child: const Text('Discard'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Word of the day — curated local list (no network needed)
// ---------------------------------------------------------------------------

class _Word {
  const _Word(this.word, this.pos, this.meaning, this.example);
  final String word;
  final String pos;
  final String meaning;
  final String example;
}

const _vocab = <_Word>[
  _Word('Ubiquitous', 'adj.', 'Present or found everywhere.',
      'Smartphones have become ubiquitous on campus.'),
  _Word('Cogent', 'adj.', 'Clear, logical, and convincing.',
      'She made a cogent argument in her thesis defense.'),
  _Word('Ephemeral', 'adj.', 'Lasting for a very short time.',
      'Motivation can be ephemeral; habits last.'),
  _Word('Pragmatic', 'adj.', 'Dealing with things sensibly and realistically.',
      'Take a pragmatic approach to your study schedule.'),
  _Word('Salient', 'adj.', 'Most noticeable or important.',
      'Highlight the salient points before the exam.'),
  _Word('Tenacious', 'adj.', 'Holding firmly; persistent.',
      'Her tenacious effort paid off at finals.'),
  _Word('Lucid', 'adj.', 'Expressed clearly; easy to understand.',
      'The professor gave a lucid explanation.'),
  _Word('Prudent', 'adj.', 'Acting with care and thought for the future.',
      'It is prudent to start the essay early.'),
  _Word('Eloquent', 'adj.', 'Fluent and persuasive in speech or writing.',
      'An eloquent closing strengthened her presentation.'),
  _Word('Diligent', 'adj.', 'Showing care and conscientious effort.',
      'Diligent note-taking makes revision easier.'),
  _Word('Astute', 'adj.', 'Having sharp judgment; perceptive.',
      'An astute observation reshaped the study group.'),
  _Word('Concise', 'adj.', 'Giving much information clearly and briefly.',
      'Keep your abstract concise.'),
  _Word('Resilient', 'adj.', 'Able to recover quickly from difficulties.',
      'Resilient students bounce back from a bad grade.'),
  _Word('Meticulous', 'adj.', 'Showing great attention to detail.',
      'Her meticulous lab notes impressed the TA.'),
  _Word('Candid', 'adj.', 'Truthful and straightforward.',
      'He gave candid feedback on the draft.'),
  _Word('Innovative', 'adj.', 'Featuring new methods; original.',
      'An innovative solution won the hackathon.'),
  _Word('Coherent', 'adj.', 'Logical and consistent.',
      'Build a coherent argument across paragraphs.'),
  _Word('Empirical', 'adj.', 'Based on observation or experiment.',
      'Support claims with empirical evidence.'),
  _Word('Nuance', 'noun', 'A subtle difference in meaning.',
      'The debate hinged on a small nuance.'),
  _Word('Paradigm', 'noun', 'A typical example or model.',
      'The discovery shifted the scientific paradigm.'),
  _Word('Catalyst', 'noun', 'Something that speeds up change.',
      'Her question was the catalyst for the project.'),
  _Word('Acumen', 'noun', 'The ability to make good judgments.',
      'Business acumen helped the team budget the trip.'),
  _Word('Rigor', 'noun', 'Thoroughness and accuracy.',
      'Academic rigor sets the course apart.'),
  _Word('Synthesis', 'noun', 'Combining ideas into a whole.',
      'The final asks for a synthesis of both theories.'),
  _Word('Brevity', 'noun', 'Concise and exact use of words.',
      'Brevity is the soul of a good summary.'),
  _Word('Tenet', 'noun', 'A principle or belief.',
      'A core tenet of the method is consistency.'),
  _Word('Aptitude', 'noun', 'Natural ability to do something.',
      'She showed an aptitude for statistics.'),
  _Word('Discern', 'verb', 'To recognize or distinguish.',
      'Discern the thesis from supporting points.'),
  _Word('Elucidate', 'verb', 'To make something clear; explain.',
      'Please elucidate the second step.'),
  _Word('Bolster', 'verb', 'To support or strengthen.',
      'Citations bolster your argument.'),
];

class WordOfDayCard extends StatefulWidget {
  const WordOfDayCard({super.key});

  @override
  State<WordOfDayCard> createState() => _WordOfDayCardState();
}

class _WordOfDayCardState extends State<WordOfDayCard> {
  late int _i =
      DateTime.now().difference(DateTime(2020)).inDays % _vocab.length;

  @override
  Widget build(BuildContext context) {
    final w = _vocab[_i];
    return GlassContainer(
      onTap: () => setState(() => _i = (_i + 1) % _vocab.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.spellcheck_rounded,
                  size: 18, color: AppPalette.lavender),
              SizedBox(width: 8),
              Text('Word of the day',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(w.word,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Text(w.pos,
                  style: const TextStyle(
                      color: AppPalette.textSecondary,
                      fontStyle: FontStyle.italic)),
            ],
          ),
          const SizedBox(height: 8),
          Text(w.meaning, style: const TextStyle(height: 1.35)),
          const SizedBox(height: 8),
          Text('“${w.example}”',
              style: const TextStyle(
                  color: AppPalette.textSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.35)),
          const SizedBox(height: 12),
          const Text('Tap for another',
              style: TextStyle(color: AppPalette.textFaint, fontSize: 11)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Two-week overview — calendar grid + agenda for the next 14 days
// ---------------------------------------------------------------------------

class TwoWeekOverviewCard extends ConsumerWidget {
  const TwoWeekOverviewCard({super.key});

  static const _dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Start from the Sunday of the current week so the grid reads like a
    // calendar; covers this week + next week (14 days).
    final start = today.subtract(Duration(days: today.weekday % 7));
    final days = List.generate(14, (i) => start.add(Duration(days: i)));
    final windowEnd = start.add(const Duration(days: 14));

    final events = ref.watch(eventsProvider);
    final dueTasks = ref
        .watch(tasksProvider)
        .where((t) => !t.done && t.due != null)
        .toList();

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    int countOn(DateTime d) =>
        events.where((e) => sameDay(e.start, d)).length +
        dueTasks.where((t) => sameDay(t.due!, d)).length;

    // Agenda: upcoming items inside the window, soonest first.
    final agenda = <({DateTime when, String title, String tag, Color color})>[
      for (final e in events)
        if (!e.start.isBefore(today) && e.start.isBefore(windowEnd))
          (
            when: e.start,
            title: e.title,
            tag: e.type.label,
            color: AppPalette.mint
          ),
      for (final t in dueTasks)
        if (!t.due!.isBefore(today) && t.due!.isBefore(windowEnd))
          (
            when: t.due!,
            title: t.title,
            tag: t.isAssignment ? 'Assignment' : 'Due',
            color: AppPalette.peach
          ),
    ]..sort((x, y) => x.when.compareTo(y.when));

    Widget cell(DateTime d) {
      final isToday = sameDay(d, today);
      final inPast = d.isBefore(today);
      final n = countOn(d);
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isToday
                ? AppPalette.accent.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: isToday
                  ? AppPalette.accent.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Text('${d.day}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isToday ? FontWeight.w800 : FontWeight.w600,
                      color: inPast
                          ? AppPalette.textFaint
                          : AppPalette.textPrimary)),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: n == 0
                    ? const SizedBox()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var k = 0; k < (n > 3 ? 3 : n); k++)
                            Container(
                              width: 5,
                              height: 5,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 1),
                              decoration: const BoxDecoration(
                                  color: AppPalette.lavender,
                                  shape: BoxShape.circle),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return GlassCard(
      title: '2-week overview',
      icon: Icons.date_range_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final l in _dow)
                Expanded(
                  child: Center(
                    child: Text(l,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppPalette.textSecondary)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(children: [for (final d in days.take(7)) cell(d)]),
          Row(children: [for (final d in days.skip(7)) cell(d)]),
          const Divider(height: 24),
          if (agenda.isEmpty)
            const EmptyHint('Clear skies for the next two weeks. ☁️')
          else
            for (final item in agenda.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: item.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    Text(relativeDay(item.when),
                        style: const TextStyle(
                            color: AppPalette.textSecondary,
                            fontSize: 12)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
