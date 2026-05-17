import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key});

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {
  String? _openDeckId;
  bool _studying = false;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final cards = ref.watch(cardsProvider);

    if (_openDeckId != null) {
      final deck = decks.where((d) => d.id == _openDeckId).firstOrNull;
      if (deck == null) {
        _openDeckId = null;
      } else {
        final deckCards =
            cards.where((c) => c.deckId == deck.id).toList();
        if (_studying) {
          return _StudySession(
            deck: deck,
            cards: deckCards,
            onExit: () => setState(() => _studying = false),
          );
        }
        return _DeckDetail(
          deck: deck,
          cards: deckCards,
          onBack: () => setState(() => _openDeckId = null),
          onStudy: () => setState(() => _studying = true),
        );
      }
    }

    return PageBody(
      title: 'Study',
      subtitle: 'Build decks and review with spaced repetition.',
      actions: [
        SoftButton(
          label: 'New deck',
          filled: true,
          onTap: () async {
            final d = await showDeckDialog(context);
            if (d != null) ref.read(decksProvider.notifier).upsert(d);
          },
        ),
      ],
      child: decks.isEmpty
          ? GlassContainer(
              child: const EmptyHint(
                  'No decks yet. Create your first deck to start studying.',
                  icon: Icons.style_outlined),
            )
          : CardGrid(
              children: [
                for (final d in decks)
                  _DeckTile(
                    deck: d,
                    total: cards.where((c) => c.deckId == d.id).length,
                    due: cards
                        .where((c) => c.deckId == d.id && c.isDue)
                        .length,
                    onOpen: () => setState(() => _openDeckId = d.id),
                    onStudy: () => setState(() {
                      _openDeckId = d.id;
                      _studying = true;
                    }),
                  ),
              ],
            ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.total,
    required this.due,
    required this.onOpen,
    required this.onStudy,
  });

  final Deck deck;
  final int total;
  final int due;
  final VoidCallback onOpen;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: deck.color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.style_rounded, color: deck.color),
              ),
              const Spacer(),
              if (due > 0)
                GlassChip(label: '$due due', color: AppPalette.peach),
            ],
          ),
          const SizedBox(height: 14),
          Text(deck.name,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          if (deck.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(deck.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: AppPalette.textSecondary)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text('$total cards',
                  style: const TextStyle(
                      color: AppPalette.textSecondary, fontSize: 13)),
              const Spacer(),
              SoftButton(
                label: 'Study',
                icon: Icons.play_arrow_rounded,
                filled: true,
                onTap: total == 0 ? () {} : onStudy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeckDetail extends ConsumerWidget {
  const _DeckDetail({
    required this.deck,
    required this.cards,
    required this.onBack,
    required this.onStudy,
  });

  final Deck deck;
  final List<Flashcard> cards;
  final VoidCallback onBack;
  final VoidCallback onStudy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      title: deck.name,
      subtitle: '${cards.length} cards · ${cards.where((c) => c.isDue).length} due',
      actions: [
        SoftButton(
            label: 'Back', icon: Icons.arrow_back_rounded, onTap: onBack),
        const SizedBox(width: 8),
        SoftButton(
          label: 'Add card',
          onTap: () async {
            final c = await showCardDialog(context, deckId: deck.id);
            if (c != null) ref.read(cardsProvider.notifier).upsert(c);
          },
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'Study',
          filled: true,
          icon: Icons.play_arrow_rounded,
          onTap: cards.isEmpty ? () {} : onStudy,
        ),
      ],
      child: cards.isEmpty
          ? GlassContainer(
              child: const EmptyHint('This deck has no cards yet.'))
          : Column(
              children: [
                for (final c in cards)
                  GlassContainer(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.front,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(c.back,
                                  style: const TextStyle(
                                      color: AppPalette.textSecondary)),
                            ],
                          ),
                        ),
                        GlassChip(label: 'Box ${c.box}'),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppPalette.textSecondary,
                          onPressed: () async {
                            final e = await showCardDialog(context,
                                deckId: deck.id, existing: c);
                            if (e != null) {
                              ref
                                  .read(cardsProvider.notifier)
                                  .upsert(e);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: AppPalette.textSecondary,
                          onPressed: () => ref
                              .read(cardsProvider.notifier)
                              .remove(c.id),
                        ),
                      ],
                    ),
                  ),
              ]
                  .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 12), child: w))
                  .toList(),
            ),
    );
  }
}

class _StudySession extends ConsumerStatefulWidget {
  const _StudySession({
    required this.deck,
    required this.cards,
    required this.onExit,
  });

  final Deck deck;
  final List<Flashcard> cards;
  final VoidCallback onExit;

  @override
  ConsumerState<_StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends ConsumerState<_StudySession> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _flipped = false;
  int _correct = 0;

  @override
  void initState() {
    super.initState();
    final due = widget.cards.where((c) => c.isDue).toList();
    _queue = (due.isEmpty ? widget.cards : due).toList()..shuffle();
  }

  void _grade(bool correct) {
    final card = _queue[_index];
    ref
        .read(cardsProvider.notifier)
        .upsert(card.reviewed(correct: correct));
    setState(() {
      if (correct) _correct++;
      _flipped = false;
      _index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty || _index >= _queue.length) {
      return PageBody(
        title: 'Session complete 🎉',
        subtitle: widget.deck.name,
        scrollable: false,
        child: Expanded(
          child: Center(
            child: GlassContainer(
              width: 380,
              padding: const EdgeInsets.all(36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.celebration_rounded,
                      size: 48, color: AppPalette.mint),
                  const SizedBox(height: 16),
                  Text(
                    _queue.isEmpty
                        ? 'Nothing due right now — come back later!'
                        : 'You got $_correct of ${_queue.length} right.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  SoftButton(
                    label: 'Done',
                    filled: true,
                    icon: Icons.check_rounded,
                    onTap: widget.onExit,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final card = _queue[_index];
    return PageBody(
      title: 'Studying',
      subtitle: '${_index + 1} / ${_queue.length} · ${widget.deck.name}',
      scrollable: false,
      actions: [
        SoftButton(
            label: 'Exit', icon: Icons.close_rounded, onTap: widget.onExit),
      ],
      child: Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => _flipped = !_flipped),
                child: GlassContainer(
                  width: 520,
                  height: 280,
                  highlight: _flipped,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_flipped ? 'ANSWER' : 'QUESTION',
                            style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 2,
                                color: AppPalette.textSecondary)),
                        const SizedBox(height: 18),
                        Text(
                          _flipped ? card.back : card.front,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 18),
                        if (!_flipped)
                          const Text('Tap to reveal',
                              style: TextStyle(
                                  color: AppPalette.textFaint,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (_flipped)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SoftButton(
                      label: 'Again',
                      icon: Icons.replay_rounded,
                      onTap: () => _grade(false),
                    ),
                    const SizedBox(width: 14),
                    SoftButton(
                      label: 'Got it',
                      icon: Icons.check_rounded,
                      filled: true,
                      onTap: () => _grade(true),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
