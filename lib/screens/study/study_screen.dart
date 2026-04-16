import 'dart:math';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import '../../models/flashcard.dart';
import '../../providers/flashcard_provider.dart';
import '../../providers/study_provider.dart';

// ── Root screen ───────────────────────────────────────────────────────────────

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Secondary tab bar
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: false,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.55),
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.timer_outlined), text: 'Timer'),
              Tab(icon: Icon(Icons.style_outlined), text: 'Flashcards'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _TimerTab(),
              _FlashcardsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TIMER TAB
// ══════════════════════════════════════════════════════════════════════════════

class _TimerTab extends StatelessWidget {
  const _TimerTab();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _TimerPanel()),
          SizedBox(width: 24),
          Expanded(flex: 2, child: _StatsAndSettingsPanel()),
        ],
      ),
    );
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final theme = Theme.of(context);

    final modeColors = {
      StudyMode.work: theme.colorScheme.primary,
      StudyMode.shortBreak: Colors.green,
      StudyMode.longBreak: Colors.teal,
    };
    final modeLabels = {
      StudyMode.work: 'Focus',
      StudyMode.shortBreak: 'Short Break',
      StudyMode.longBreak: 'Long Break',
    };
    final color = modeColors[provider.mode]!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SegmentedButton<StudyMode>(
              segments: const [
                ButtonSegment(
                    value: StudyMode.work,
                    label: Text('Focus'),
                    icon: Icon(Icons.psychology)),
                ButtonSegment(
                    value: StudyMode.shortBreak,
                    label: Text('Short Break'),
                    icon: Icon(Icons.coffee)),
                ButtonSegment(
                    value: StudyMode.longBreak,
                    label: Text('Long Break'),
                    icon: Icon(Icons.weekend)),
              ],
              selected: {provider.mode},
              onSelectionChanged: (s) => provider.setMode(s.first),
            ),
            const SizedBox(height: 48),
            CircularPercentIndicator(
              radius: 130,
              lineWidth: 14,
              percent: provider.progress.clamp(0.0, 1.0),
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    provider.timeDisplay,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: [const FontFeature.tabularFigures()],
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    modeLabels[provider.mode]!,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              progressColor: color,
              backgroundColor: color.withValues(alpha: 0.15),
              circularStrokeCap: CircularStrokeCap.round,
              animation: false,
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(provider.sessionsBeforeLongBreak, (i) {
                final completed = i <
                    (provider.completedSessions %
                        provider.sessionsBeforeLongBreak);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: completed ? 24 : 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: completed ? color : color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.refresh),
                  onPressed: provider.reset,
                  tooltip: 'Reset',
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: provider.startPause,
                  icon:
                      Icon(provider.isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(provider.isRunning ? 'Pause' : 'Start'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size(160, 48),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsAndSettingsPanel extends StatelessWidget {
  const _StatsAndSettingsPanel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _StatsCard(),
        SizedBox(height: 16),
        _SettingsCard(),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Study Stats',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Divider(height: 24),
            _StatRow(
              icon: Icons.check_circle_outline,
              label: 'Sessions Today',
              value: '${provider.completedSessions}',
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: Icons.emoji_events_outlined,
              label: 'Total Sessions',
              value: '${provider.totalSessions}',
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: Icons.timer_outlined,
              label: 'Total Focus Time',
              value: _formatMinutes(provider.totalMinutesStudied),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard();

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text('Timer Settings',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(_expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 24),
              _MinutePicker(
                label: 'Focus',
                value: provider.workMinutes,
                onChanged: (v) => provider.updateSettings(workMinutes: v),
              ),
              const SizedBox(height: 12),
              _MinutePicker(
                label: 'Short Break',
                value: provider.shortBreakMinutes,
                onChanged: (v) => provider.updateSettings(shortBreakMinutes: v),
              ),
              const SizedBox(height: 12),
              _MinutePicker(
                label: 'Long Break',
                value: provider.longBreakMinutes,
                onChanged: (v) => provider.updateSettings(longBreakMinutes: v),
              ),
              const SizedBox(height: 12),
              _MinutePicker(
                label: 'Sessions before long break',
                value: provider.sessionsBeforeLongBreak,
                min: 2,
                max: 8,
                onChanged: (v) =>
                    provider.updateSettings(sessionsBeforeLongBreak: v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MinutePicker extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  const _MinutePicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 60,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        SizedBox(
          width: 32,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FLASHCARDS TAB
// ══════════════════════════════════════════════════════════════════════════════

enum _FlashcardView { list, study, quiz }

class _FlashcardsTab extends StatefulWidget {
  const _FlashcardsTab();

  @override
  State<_FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<_FlashcardsTab> {
  String? _selectedDeckId;
  _FlashcardView _view = _FlashcardView.list;

  void _selectDeck(String id) => setState(() {
        _selectedDeckId = id;
        _view = _FlashcardView.list;
      });

  void _startStudy() => setState(() => _view = _FlashcardView.study);
  void _startQuiz() => setState(() => _view = _FlashcardView.quiz);
  void _exitMode() => setState(() => _view = _FlashcardView.list);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FlashcardProvider>();

    // Keep selectedDeckId in sync if a deck was deleted
    if (_selectedDeckId != null &&
        provider.deckById(_selectedDeckId!) == null) {
      _selectedDeckId = null;
      _view = _FlashcardView.list;
    }

    final selectedDeck = _selectedDeckId != null
        ? provider.deckById(_selectedDeckId!)
        : null;

    // Study / quiz mode: full-width
    if (selectedDeck != null && _view == _FlashcardView.study) {
      return _StudyMode(deck: selectedDeck, onExit: _exitMode);
    }
    if (selectedDeck != null && _view == _FlashcardView.quiz) {
      return _QuizMode(deck: selectedDeck, onExit: _exitMode);
    }

    // Default: side-by-side layout
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: deck list
        SizedBox(
          width: 240,
          child: _DeckListPanel(
            decks: provider.decks,
            selectedDeckId: _selectedDeckId,
            onSelect: _selectDeck,
            onAdd: () => _showCreateDeckDialog(context, provider),
            onDelete: (id) => provider.deleteDeck(id),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        // Right: card list or empty state
        Expanded(
          child: selectedDeck == null
              ? _EmptyDeckState(onCreateDeck: () =>
                  _showCreateDeckDialog(context, provider))
              : _CardListPanel(
                  deck: selectedDeck,
                  onStudy: selectedDeck.cards.isNotEmpty ? _startStudy : null,
                  onQuiz: selectedDeck.cards.length >= 2 ? _startQuiz : null,
                  onAddCard: () =>
                      _showAddCardDialog(context, provider, selectedDeck.id),
                  onEditCard: (card) => _showEditCardDialog(
                      context, provider, selectedDeck.id, card),
                  onDeleteCard: (cardId) =>
                      provider.deleteCard(selectedDeck.id, cardId),
                  onEditDeck: () =>
                      _showEditDeckDialog(context, provider, selectedDeck),
                ),
        ),
      ],
    );
  }

  Future<void> _showCreateDeckDialog(
      BuildContext context, FlashcardProvider provider) async {
    final deck = await showDialog<FlashcardDeck>(
      context: context,
      builder: (_) => const _DeckDialog(),
    );
    if (deck == null || !context.mounted) return;
    await provider.addDeck(deck);
    setState(() => _selectedDeckId = deck.id);
  }

  Future<void> _showEditDeckDialog(
      BuildContext context, FlashcardProvider provider, FlashcardDeck deck) async {
    final updated = await showDialog<FlashcardDeck>(
      context: context,
      builder: (_) => _DeckDialog(existing: deck),
    );
    if (updated == null || !context.mounted) return;
    await provider.updateDeck(updated);
  }

  Future<void> _showAddCardDialog(
      BuildContext context, FlashcardProvider provider, String deckId) async {
    final card = await showDialog<Flashcard>(
      context: context,
      builder: (_) => const _CardDialog(),
    );
    if (card == null || !context.mounted) return;
    await provider.addCard(deckId, card);
  }

  Future<void> _showEditCardDialog(BuildContext context,
      FlashcardProvider provider, String deckId, Flashcard card) async {
    final updated = await showDialog<Flashcard>(
      context: context,
      builder: (_) => _CardDialog(existing: card),
    );
    if (updated == null || !context.mounted) return;
    await provider.updateCard(deckId, updated);
  }
}

// ── Deck list panel (left sidebar) ────────────────────────────────────────────

class _DeckListPanel extends StatelessWidget {
  final List<FlashcardDeck> decks;
  final String? selectedDeckId;
  final void Function(String) onSelect;
  final VoidCallback onAdd;
  final void Function(String) onDelete;

  const _DeckListPanel({
    required this.decks,
    required this.selectedDeckId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Text('Decks',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: 20,
                  tooltip: 'New deck',
                  onPressed: onAdd,
                  style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: decks.isEmpty
                ? Center(
                    child: Text('No decks yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4))),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: decks
                        .map((d) => _DeckTile(
                              deck: d,
                              selected: d.id == selectedDeckId,
                              onTap: () => onSelect(d.id),
                              onDelete: () => onDelete(d.id),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  final FlashcardDeck deck;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DeckTile({
    required this.deck,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = deck.color;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deck.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : null),
                      overflow: TextOverflow.ellipsis),
                  Text('${deck.cards.length} cards',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5))),
                ],
              ),
            ),
            if (selected)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 16, color: theme.colorScheme.error),
                onPressed: onDelete,
                style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                tooltip: 'Delete deck',
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyDeckState extends StatelessWidget {
  final VoidCallback onCreateDeck;
  const _EmptyDeckState({required this.onCreateDeck});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Select a deck to get started',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          Text('or create one using the + button',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35))),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: onCreateDeck,
            child: const Text('Create Deck'),
          ),
        ],
      ),
    );
  }
}

// ── Card list panel (right side) ──────────────────────────────────────────────

class _CardListPanel extends StatelessWidget {
  final FlashcardDeck deck;
  final VoidCallback? onStudy;
  final VoidCallback? onQuiz;
  final VoidCallback onAddCard;
  final void Function(Flashcard) onEditCard;
  final void Function(String) onDeleteCard;
  final VoidCallback onEditDeck;

  const _CardListPanel({
    required this.deck,
    required this.onStudy,
    required this.onQuiz,
    required this.onAddCard,
    required this.onEditCard,
    required this.onDeleteCard,
    required this.onEditDeck,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = deck.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
          decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(deck.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Rename deck',
                onPressed: onEditDeck,
                style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
              const SizedBox(width: 8),
              // Study button
              FilledButton.icon(
                onPressed: onStudy,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Study'),
                style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 0)),
              ),
              const SizedBox(width: 8),
              // Quiz button
              OutlinedButton.icon(
                onPressed: onQuiz,
                icon: const Icon(Icons.quiz_outlined, size: 18),
                label: const Text('Quiz'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 0)),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onAddCard,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Card'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 0)),
              ),
            ],
          ),
        ),
        // Subtitle info
        if (onQuiz == null && deck.cards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text('Add at least 2 cards to enable Quiz mode',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    fontStyle: FontStyle.italic)),
          ),
        // Card list
        Expanded(
          child: deck.cards.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_card_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.25)),
                      const SizedBox(height: 12),
                      Text('No cards yet',
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4))),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: onAddCard,
                        icon: const Icon(Icons.add),
                        label: const Text('Add your first card'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: deck.cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final card = deck.cards[i];
                    return _CardRow(
                      card: card,
                      index: i + 1,
                      color: color,
                      onEdit: () => onEditCard(card),
                      onDelete: () => onDeleteCard(card.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  final Flashcard card;
  final int index;
  final Color color;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CardRow({
    required this.card,
    required this.index,
    required this.color,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
            // Card number
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text('$index',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                      fontWeight: FontWeight.bold)),
            ),
            // Front
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Front',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45))),
                    const SizedBox(height: 2),
                    Text(card.front, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            // Divider
            VerticalDivider(
                width: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
            // Back
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Back',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45))),
                    const SizedBox(height: 2),
                    Text(card.back, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            // Actions
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: theme.colorScheme.error),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STUDY MODE (flip cards)
// ══════════════════════════════════════════════════════════════════════════════

class _StudyMode extends StatefulWidget {
  final FlashcardDeck deck;
  final VoidCallback onExit;

  const _StudyMode({required this.deck, required this.onExit});

  @override
  State<_StudyMode> createState() => _StudyModeState();
}

class _StudyModeState extends State<_StudyMode>
    with SingleTickerProviderStateMixin {
  late List<Flashcard> _cards;
  int _index = 0;
  bool _showingBack = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.deck.cards)..shuffle();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _anim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    if (_showingBack) {
      _ctrl.reverse().then((_) => setState(() => _showingBack = false));
    } else {
      _ctrl.forward().then((_) => setState(() => _showingBack = true));
    }
  }

  void _next() {
    if (_index < _cards.length - 1) {
      _ctrl.reset();
      setState(() {
        _showingBack = false;
        _index++;
      });
    }
  }

  void _prev() {
    if (_index > 0) {
      _ctrl.reset();
      setState(() {
        _showingBack = false;
        _index--;
      });
    }
  }

  void _shuffle() {
    _ctrl.reset();
    setState(() {
      _cards.shuffle();
      _index = 0;
      _showingBack = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = _cards[_index];
    final color = widget.deck.color;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onExit,
                tooltip: 'Back to deck',
              ),
              const SizedBox(width: 16),
              Text(widget.deck.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_index + 1} / ${_cards.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(width: 16),
              IconButton.outlined(
                icon: const Icon(Icons.shuffle),
                onPressed: _shuffle,
                tooltip: 'Shuffle',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + 1) / _cards.length,
              minHeight: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 32),
          // Flip card
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 600, maxHeight: 380),
                child: GestureDetector(
                  onTap: _flip,
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (_, _) {
                      final angle = _anim.value * pi;
                      final isBack = angle > pi / 2;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        child: isBack
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(pi),
                                child: _FlipCardFace(
                                  label: 'Back',
                                  text: card.back,
                                  color: color,
                                  isBack: true,
                                  theme: theme,
                                ),
                              )
                            : _FlipCardFace(
                                label: 'Front',
                                text: card.front,
                                color: color,
                                isBack: false,
                                theme: theme,
                              ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                onPressed: _index > 0 ? _prev : null,
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Previous',
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: _flip,
                style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 44)),
                child: Text(_showingBack ? 'Show Front' : 'Flip'),
              ),
              const SizedBox(width: 16),
              IconButton.outlined(
                onPressed: _index < _cards.length - 1 ? _next : null,
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
                tooltip: 'Next',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Tap the card or the button to flip',
              style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

class _FlipCardFace extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final bool isBack;
  final ThemeData theme;

  const _FlipCardFace({
    required this.label,
    required this.text,
    required this.color,
    required this.isBack,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isBack
            ? color.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isBack ? color.withValues(alpha: 0.4) : theme.dividerColor,
            width: isBack ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isBack
                  ? color.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: isBack
                        ? color
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isBack
                    ? color
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUIZ MODE
// ══════════════════════════════════════════════════════════════════════════════

class _QuizQuestion {
  final Flashcard card;
  final List<String> options;
  final int correctIndex;

  _QuizQuestion({
    required this.card,
    required this.options,
    required this.correctIndex,
  });
}

class _QuizMode extends StatefulWidget {
  final FlashcardDeck deck;
  final VoidCallback onExit;

  const _QuizMode({required this.deck, required this.onExit});

  @override
  State<_QuizMode> createState() => _QuizModeState();
}

class _QuizModeState extends State<_QuizMode> {
  late List<_QuizQuestion> _questions;
  int _questionIndex = 0;
  int _score = 0;
  int? _selectedOption;
  bool _answered = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _buildQuestions();
  }

  void _buildQuestions() {
    final rng = Random();
    final cards = List<Flashcard>.from(widget.deck.cards)..shuffle(rng);

    _questions = cards.map((card) {
      final wrongAnswers = widget.deck.cards
          .where((c) => c.id != card.id)
          .map((c) => c.back)
          .toList()
        ..shuffle(rng);

      // Pick up to 3 wrong answers
      final pool = wrongAnswers.take(3).toList();
      pool.add(card.back);
      pool.shuffle(rng);

      final correctIndex = pool.indexOf(card.back);
      return _QuizQuestion(
        card: card,
        options: pool,
        correctIndex: correctIndex,
      );
    }).toList();
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    setState(() {
      _selectedOption = index;
      _answered = true;
      if (index == _questions[_questionIndex].correctIndex) _score++;
    });
  }

  void _next() {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _answered = false;
        _selectedOption = null;
      });
    } else {
      setState(() => _finished = true);
    }
  }

  void _restart() {
    setState(() {
      _buildQuestions();
      _questionIndex = 0;
      _score = 0;
      _answered = false;
      _selectedOption = null;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.deck.color;

    if (_finished) {
      return _QuizResults(
        score: _score,
        total: _questions.length,
        color: color,
        deckName: widget.deck.name,
        onRestart: _restart,
        onExit: widget.onExit,
        theme: theme,
      );
    }

    final q = _questions[_questionIndex];

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onExit,
                tooltip: 'Exit quiz',
              ),
              const SizedBox(width: 16),
              Text('${widget.deck.name} — Quiz',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_questionIndex + 1} / ${_questions.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(width: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_score correct',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_questionIndex + 1) / _questions.length,
              minHeight: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 32),
          // Question card
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Question
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text('Question',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.45))),
                          const SizedBox(height: 12),
                          Text(q.card.front,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Answer options
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 3.5,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(q.options.length, (i) {
                        final isCorrect = i == q.correctIndex;
                        final isSelected = i == _selectedOption;

                        Color bg = theme.colorScheme.surface;
                        Color border = theme.dividerColor;
                        Color textColor = theme.colorScheme.onSurface;
                        IconData? trailingIcon;

                        if (_answered) {
                          if (isCorrect) {
                            bg = Colors.green.withValues(alpha: 0.12);
                            border = Colors.green;
                            textColor = Colors.green.shade700;
                            trailingIcon = Icons.check_circle_outline;
                          } else if (isSelected) {
                            bg = theme.colorScheme.error.withValues(alpha: 0.1);
                            border = theme.colorScheme.error;
                            textColor = theme.colorScheme.error;
                            trailingIcon = Icons.cancel_outlined;
                          }
                        }

                        return InkWell(
                          onTap: _answered ? null : () => _selectAnswer(i),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border, width: _answered && (isCorrect || isSelected) ? 2 : 1),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _answered && (isCorrect || isSelected)
                                        ? Colors.transparent
                                        : theme.colorScheme.surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    String.fromCharCode(65 + i),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: textColor),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(q.options[i],
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: textColor),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (trailingIcon != null)
                                  Icon(trailingIcon, size: 18, color: textColor),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_answered) ...[
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(160, 44)),
                        child: Text(_questionIndex < _questions.length - 1
                            ? 'Next Question'
                            : 'See Results'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizResults extends StatelessWidget {
  final int score;
  final int total;
  final Color color;
  final String deckName;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final ThemeData theme;

  const _QuizResults({
    required this.score,
    required this.total,
    required this.color,
    required this.deckName,
    required this.onRestart,
    required this.onExit,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? score / total : 0.0;
    final resultColor = percent >= 0.8
        ? Colors.green
        : percent >= 0.6
            ? Colors.orange
            : Colors.red;
    final message = percent >= 0.8
        ? 'Great job!'
        : percent >= 0.6
            ? 'Good effort!'
            : 'Keep studying!';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Quiz Complete', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(deckName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 32),
                CircularPercentIndicator(
                  radius: 80,
                  lineWidth: 10,
                  percent: percent.clamp(0.0, 1.0),
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$score/$total',
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold, color: resultColor)),
                      Text('correct',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
                    ],
                  ),
                  progressColor: resultColor,
                  backgroundColor: resultColor.withValues(alpha: 0.15),
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                const SizedBox(height: 20),
                Text(message,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: resultColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onExit,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Deck'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: onRestart,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake'),
                      style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DIALOGS
// ══════════════════════════════════════════════════════════════════════════════

class _DeckDialog extends StatefulWidget {
  final FlashcardDeck? existing;
  const _DeckDialog({this.existing});

  @override
  State<_DeckDialog> createState() => _DeckDialogState();
}

class _DeckDialogState extends State<_DeckDialog> {
  late final TextEditingController _name;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _colorValue =
        widget.existing?.colorValue ?? FlashcardDeck.palette[4]; // default indigo
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Deck' : 'New Deck'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Deck name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Color',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: FlashcardDeck.palette.map((c) {
                final selected = c == _colorValue;
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final deck = widget.existing != null
                ? widget.existing!.copyWith(name: name, colorValue: _colorValue)
                : FlashcardDeck(name: name, colorValue: _colorValue);
            Navigator.pop(context, deck);
          },
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _CardDialog extends StatefulWidget {
  final Flashcard? existing;
  const _CardDialog({this.existing});

  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  late final TextEditingController _front;
  late final TextEditingController _back;

  @override
  void initState() {
    super.initState();
    _front = TextEditingController(text: widget.existing?.front ?? '');
    _back = TextEditingController(text: widget.existing?.back ?? '');
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Card' : 'New Card'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _front,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Front (question)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _back,
              decoration: const InputDecoration(
                labelText: 'Back (answer)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final front = _front.text.trim();
            final back = _back.text.trim();
            if (front.isEmpty || back.isEmpty) return;
            final card = widget.existing != null
                ? widget.existing!.copyWith(front: front, back: back)
                : Flashcard(front: front, back: back);
            Navigator.pop(context, card);
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
