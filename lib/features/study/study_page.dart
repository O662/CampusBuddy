import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/adaptive_draggable.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/markdown_lite.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'card_image_store.dart';

/// Which side of a card the user is answering: flip-and-self-grade vs
/// type-and-auto-grade. Threaded through [_StudySession] so the same
/// machinery serves both modes.
enum StudySessionMode { flip, typing }

/// Sentinel group key for the catch-all "Ungrouped" section. Distinct
/// from a real group id (always a uuid) so we can switch on it.
const String _kUngroupedKey = '__ungrouped__';

/// A card is "trouble" once you've reviewed it at least twice and gotten
/// it wrong at least half the time, OR missed it three+ times outright.
/// Tunable from one place so the UI text and the filter stay in sync.
bool _isTrouble(Flashcard c) =>
    c.wrongCount >= 3 || (c.reviewCount >= 2 && c.missRate >= 0.5);

/// Top-N trouble cards for a deck, most-painful first. Used by both the
/// deck-detail header and the session-complete screen.
List<Flashcard> _troubleCards(Iterable<Flashcard> cards, {int limit = 5}) {
  final filtered = cards.where(_isTrouble).toList()
    ..sort((a, b) {
      final byWrong = b.wrongCount.compareTo(a.wrongCount);
      if (byWrong != 0) return byWrong;
      return b.missRate.compareTo(a.missRate);
    });
  return filtered.take(limit).toList();
}

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key});

  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage> {
  String? _openDeckId;
  bool _studying = false;

  /// Whether the next session uses flip-and-self-grade or typing mode.
  /// Reset to flip on exit so the default entry point stays predictable.
  StudySessionMode _sessionMode = StudySessionMode.flip;

  /// When non-null, the next study session draws from this fixed list
  /// instead of the deck's due queue — used by the "Study just these"
  /// shortcut on the trouble-cards panel. Cleared on exit.
  List<Flashcard>? _focusQueue;

  /// Confirm-and-remove for a deck. Cleans up the deck's flashcards in the
  /// same pass — they're orphans without a parent deck, and silently
  /// keeping them around would leak storage and confuse the importer.
  /// Image attachments on those cards also get unlinked from disk so the
  /// support directory doesn't accumulate orphans. Returns true when the
  /// deletion went through so callers can pop back out of any open
  /// detail view.
  Future<bool> _deleteDeck(Deck deck) async {
    final deckCards =
        ref.read(cardsProvider).where((c) => c.deckId == deck.id).toList();
    final ok = await confirmDelete(
      context,
      title: 'Delete "${deck.name}"?',
      message: deckCards.isEmpty
          ? 'The deck will be removed.'
          : 'The deck and its ${deckCards.length} card'
              "${deckCards.length == 1 ? '' : 's'} will be removed. "
              'This cannot be undone.',
    );
    if (!ok) return false;
    final cardsNotifier = ref.read(cardsProvider.notifier);
    for (final c in deckCards) {
      await CardImageStore.deleteByName(c.frontImagePath);
      await CardImageStore.deleteByName(c.backImagePath);
      await cardsNotifier.remove(c.id);
    }
    await ref.read(decksProvider.notifier).remove(deck.id);
    return true;
  }

  /// Confirm-and-remove for a single card, including its image files.
  /// Pulled out of the inline `IconButton` so [_DeckDetail] doesn't need
  /// to know about [CardImageStore].
  Future<void> _deleteCard(Flashcard c) async {
    await CardImageStore.deleteByName(c.frontImagePath);
    await CardImageStore.deleteByName(c.backImagePath);
    await ref.read(cardsProvider.notifier).remove(c.id);
  }

  /// Remove a group; its decks fall back to "Ungrouped" rather than
  /// being deleted — losing a folder shouldn't lose study material.
  Future<void> _deleteDeckGroup(DeckGroup g) async {
    final decks = ref.read(decksProvider);
    final orphans = decks.where((d) => d.groupId == g.id).toList();
    final ok = await confirmDelete(
      context,
      title: 'Delete "${g.name}"?',
      message: orphans.isEmpty
          ? 'The group will be removed.'
          : 'The group will be removed and its ${orphans.length} deck'
              "${orphans.length == 1 ? '' : 's'} moved to Ungrouped.",
    );
    if (!ok) return;
    final decksNotifier = ref.read(decksProvider.notifier);
    for (final d in orphans) {
      await decksNotifier.upsert(d.copyWith(clearGroup: true));
    }
    await ref.read(deckGroupsProvider.notifier).remove(g.id);
  }

  /// Reassigns [deck] to [targetGroupId] (null → Ungrouped). Used by both
  /// the grid section drop-targets and the list-view sidebar rows, so the
  /// "drag a deck into another group" gesture has one persistence path.
  Future<void> _moveDeckToGroup(Deck deck, String? targetGroupId) async {
    if (deck.groupId == targetGroupId) return;
    final updated = deck.copyWith(
      groupId: targetGroupId,
      clearGroup: targetGroupId == null,
    );
    await ref.read(decksProvider.notifier).upsert(updated);
  }

  /// Persist a new group sequence after a sidebar drag. Pulled out so
  /// the row callback stays a one-liner.
  Future<void> _reorderGroup(DeckGroup moving, DeckGroup target,
      List<DeckGroup> ordered) async {
    if (moving.id == target.id) return;
    final list = [...ordered];
    final from = list.indexWhere((x) => x.id == moving.id);
    final targetIndex = list.indexWhere((x) => x.id == target.id);
    if (from < 0 || targetIndex < 0 || from == targetIndex) return;
    list.removeAt(from);
    final insertAt = from < targetIndex
        ? list.indexWhere((x) => x.id == target.id) + 1
        : list.indexWhere((x) => x.id == target.id);
    list.insert(insertAt, moving);
    await ref.read(deckGroupsProvider.notifier).reorder(list);
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final cards = ref.watch(cardsProvider);
    final groups = ref.watch(deckGroupsProvider);
    final viewMode = ref.watch(studyViewModeProvider);

    if (_openDeckId != null) {
      final deck = decks.where((d) => d.id == _openDeckId).firstOrNull;
      if (deck == null) {
        _openDeckId = null;
      } else {
        final deckCards =
            cards.where((c) => c.deckId == deck.id).toList();
        if (_studying) {
          // Honour an explicit focus queue (trouble cards) if one was
          // queued up before starting the session; otherwise let the
          // session pick its own queue from due cards.
          final queue = _focusQueue;
          return _StudySession(
            deck: deck,
            mode: _sessionMode,
            cards: queue ?? deckCards,
            allDeckCards: deckCards,
            fixedQueue: queue != null,
            onExit: () => setState(() {
              _studying = false;
              _focusQueue = null;
              _sessionMode = StudySessionMode.flip;
            }),
            onStudyTrouble: (picks) => setState(() {
              _focusQueue = picks;
              _sessionMode = StudySessionMode.flip;
              _studying = true;
            }),
          );
        }
        return _DeckDetail(
          deck: deck,
          cards: deckCards,
          groups: groups,
          onBack: () => setState(() => _openDeckId = null),
          onStudy: () => setState(() {
            _focusQueue = null;
            _sessionMode = StudySessionMode.flip;
            _studying = true;
          }),
          onTypingTest: () => setState(() {
            _focusQueue = null;
            _sessionMode = StudySessionMode.typing;
            _studying = true;
          }),
          onStudyTrouble: (picks) => setState(() {
            _focusQueue = picks;
            _sessionMode = StudySessionMode.flip;
            _studying = true;
          }),
          onDelete: () async {
            final removed = await _deleteDeck(deck);
            // If the deck is gone, drop back to the grid so we don't try
            // to render detail for a stale id next frame.
            if (removed && mounted) {
              setState(() {
                _openDeckId = null;
                _studying = false;
                _focusQueue = null;
              });
            }
          },
          onDeleteCard: _deleteCard,
        );
      }
    }

    // Callbacks both views need — defined once so grid and list stay in
    // sync if the wiring changes (e.g. a new arg gets added).
    void openDeck(String id) => setState(() => _openDeckId = id);
    void studyDeck(String id) => setState(() {
          _openDeckId = id;
          _sessionMode = StudySessionMode.flip;
          _studying = true;
        });
    Future<void> editDeck(Deck d) async {
      final e =
          await showDeckDialog(context, existing: d, groups: groups);
      if (e != null) ref.read(decksProvider.notifier).upsert(e);
    }

    Future<void> addToGroup(String? groupId) async {
      final d = await showDeckDialog(context,
          groups: groups, presetGroupId: groupId);
      if (d != null) ref.read(decksProvider.notifier).upsert(d);
    }

    Future<void> editGroup(DeckGroup g) async {
      final e = await showDeckGroupDialog(context, existing: g);
      if (e != null) ref.read(deckGroupsProvider.notifier).upsert(e);
    }

    return PageBody(
      title: 'Study',
      subtitle: 'Build decks and review with spaced repetition.',
      actions: [
        _StudyViewToggle(
          mode: viewMode,
          onChanged: (m) =>
              ref.read(studyViewModeProvider.notifier).set(m),
        ),
        const SizedBox(width: 10),
        SoftButton(
          label: 'New group',
          icon: Icons.create_new_folder_outlined,
          onTap: () async {
            final g = await showDeckGroupDialog(context);
            if (g != null) {
              // Drop new groups at the end so the existing layout stays put.
              final isNew = !groups.any((x) => x.id == g.id);
              DeckGroup toSave = g;
              if (isNew && groups.isNotEmpty) {
                final maxOrder = groups
                    .map((x) => x.order)
                    .reduce((a, b) => a > b ? a : b);
                toSave = g.copyWith(order: maxOrder + 1);
              }
              await ref.read(deckGroupsProvider.notifier).upsert(toSave);
            }
          },
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'New deck',
          filled: true,
          onTap: () async {
            final d = await showDeckDialog(context, groups: groups);
            if (d != null) ref.read(decksProvider.notifier).upsert(d);
          },
        ),
      ],
      child: decks.isEmpty && groups.isEmpty
          ? GlassContainer(
              child: const EmptyHint(
                  'No decks yet. Create your first deck to start studying.',
                  icon: Icons.style_outlined),
            )
          : viewMode == StudyViewMode.list
              ? _StudyListView(
                  groups: groups,
                  decks: decks,
                  cards: cards,
                  onOpenDeck: openDeck,
                  onStudyDeck: studyDeck,
                  onEditDeck: editDeck,
                  onDeleteDeck: _deleteDeck,
                  onAddDeckToGroup: addToGroup,
                  onEditGroup: editGroup,
                  onDeleteGroup: _deleteDeckGroup,
                  onMoveDeck: _moveDeckToGroup,
                  onReorderGroup: _reorderGroup,
                )
              : _GroupedDeckLayout(
                  groups: groups,
                  decks: decks,
                  cards: cards,
                  onOpenDeck: openDeck,
                  onStudyDeck: studyDeck,
                  onEditDeck: editDeck,
                  onDeleteDeck: _deleteDeck,
                  onAddDeckToGroup: addToGroup,
                  onEditGroup: editGroup,
                  onDeleteGroup: _deleteDeckGroup,
                  onMoveDeck: _moveDeckToGroup,
                ),
    );
  }
}

/// Lays out the deck grid as a stack of group sections — each with a
/// header (color dot, name, count, edit/delete/add controls) followed by
/// the group's decks in a [CardGrid]. Decks without a group (or with a
/// stale group id) land in the "Ungrouped" section pinned to the bottom.
class _GroupedDeckLayout extends StatelessWidget {
  const _GroupedDeckLayout({
    required this.groups,
    required this.decks,
    required this.cards,
    required this.onOpenDeck,
    required this.onStudyDeck,
    required this.onEditDeck,
    required this.onDeleteDeck,
    required this.onAddDeckToGroup,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onMoveDeck,
  });

  final List<DeckGroup> groups;
  final List<Deck> decks;
  final List<Flashcard> cards;
  final ValueChanged<String> onOpenDeck;
  final ValueChanged<String> onStudyDeck;
  final ValueChanged<Deck> onEditDeck;
  final ValueChanged<Deck> onDeleteDeck;
  final ValueChanged<String?> onAddDeckToGroup;
  final ValueChanged<DeckGroup> onEditGroup;
  final ValueChanged<DeckGroup> onDeleteGroup;

  /// `(deck, targetGroupId)` — second arg is null for Ungrouped. Called
  /// when a tile is dropped onto a different section.
  final Future<void> Function(Deck deck, String? targetGroupId) onMoveDeck;

  @override
  Widget build(BuildContext context) {
    final orderedGroups = [...groups]
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final knownIds = {for (final g in orderedGroups) g.id};

    final byGroup = <String, List<Deck>>{
      for (final g in orderedGroups) g.id: [],
      _kUngroupedKey: [],
    };
    for (final d in decks) {
      final key = (d.groupId != null && knownIds.contains(d.groupId))
          ? d.groupId!
          : _kUngroupedKey;
      byGroup[key]!.add(d);
    }

    Widget tile(Deck d) => _DraggableDeckTile(
          deck: d,
          total: cards.where((c) => c.deckId == d.id).length,
          due: cards.where((c) => c.deckId == d.id && c.isDue).length,
          onOpen: () => onOpenDeck(d.id),
          onStudy: () => onStudyDeck(d.id),
          onEdit: () => onEditDeck(d),
          onDelete: () => onDeleteDeck(d),
        );

    Widget dropSection({
      required String? targetGroupId,
      required Widget section,
    }) {
      return DragTarget<Deck>(
        // Reject same-group drops so the hover state doesn't light up on a
        // no-op (and so `onMoveDeck` isn't called pointlessly).
        onWillAcceptWithDetails: (d) => d.data.groupId != targetGroupId,
        onAcceptWithDetails: (d) => onMoveDeck(d.data, targetGroupId),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: hovering
                  ? AppPalette.accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              border: Border.all(
                color: hovering
                    ? AppPalette.accent.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: section,
          );
        },
      );
    }

    final sections = <Widget>[];
    for (final g in orderedGroups) {
      final list = byGroup[g.id]!;
      sections.add(dropSection(
        targetGroupId: g.id,
        section: _DeckSection(
          title: g.name,
          accentColor: g.color,
          count: list.length,
          onAdd: () => onAddDeckToGroup(g.id),
          onEdit: () => onEditGroup(g),
          onDelete: () => onDeleteGroup(g),
          child: list.isEmpty
              ? const EmptyHint(
                  'No decks here yet — drag one in or use “+”.',
                  icon: Icons.style_outlined)
              : CardGrid(children: [for (final d in list) tile(d)]),
        ),
      ));
    }

    final ungrouped = byGroup[_kUngroupedKey]!;
    // Always render the Ungrouped section when at least one real group
    // exists — even when empty — so the user has somewhere to drop decks
    // back to "no group" without opening the edit dialog.
    if (ungrouped.isNotEmpty || orderedGroups.isNotEmpty) {
      sections.add(dropSection(
        targetGroupId: null,
        section: _DeckSection(
          title: 'Ungrouped',
          accentColor: AppPalette.textFaint,
          count: ungrouped.length,
          onAdd: () => onAddDeckToGroup(null),
          child: ungrouped.isEmpty
              ? const EmptyHint('Drop decks here to un-group them.',
                  icon: Icons.inbox_outlined)
              : CardGrid(children: [for (final d in ungrouped) tile(d)]),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          sections[i],
          if (i != sections.length - 1) const SizedBox(height: 24),
        ],
      ],
    );
  }
}

/// One labeled section in [_GroupedDeckLayout] — the horizontal header
/// (color dot + name + count chip + add / edit / delete menu) on top of
/// the section's deck grid (or an empty hint when the group is empty).
class _DeckSection extends StatelessWidget {
  const _DeckSection({
    required this.title,
    required this.accentColor,
    required this.count,
    required this.onAdd,
    required this.child,
    this.onEdit,
    this.onDelete,
  });

  final String title;
  final Color accentColor;
  final int count;
  final VoidCallback onAdd;
  final Widget child;

  /// Only real groups can be edited / deleted; the synthetic "Ungrouped"
  /// section omits both (its callbacks are null).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onEdit != null || onDelete != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              GlassChip(label: '$count'),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                color: AppPalette.lavender,
                tooltip: 'Add deck here',
                onPressed: onAdd,
              ),
              if (hasMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: AppPalette.textSecondary),
                  color: const Color(0xFF241F45),
                  tooltip: 'Group options',
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 20),
                        title: Text('Edit group'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            size: 20, color: AppPalette.danger),
                        title: Text('Delete group'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        child,
      ],
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
    required this.onEdit,
    required this.onDelete,
  });

  final Deck deck;
  final int total;
  final int due;
  final VoidCallback onOpen;
  final VoidCallback onStudy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
              if (due > 0) ...[
                GlassChip(label: '$due due', color: AppPalette.peach),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 18, color: AppPalette.textSecondary),
                color: const Color(0xFF241F45),
                tooltip: 'Deck options',
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined, size: 20),
                      title: Text('Edit deck'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          size: 20, color: AppPalette.danger),
                      title: Text('Delete deck'),
                    ),
                  ),
                ],
              ),
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
    required this.groups,
    required this.onBack,
    required this.onStudy,
    required this.onTypingTest,
    required this.onStudyTrouble,
    required this.onDelete,
    required this.onDeleteCard,
  });

  final Deck deck;
  final List<Flashcard> cards;
  final List<DeckGroup> groups;
  final VoidCallback onBack;
  final VoidCallback onStudy;
  final VoidCallback onTypingTest;
  final ValueChanged<List<Flashcard>> onStudyTrouble;
  final VoidCallback onDelete;
  final Future<void> Function(Flashcard) onDeleteCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trouble = _troubleCards(cards);
    // Typing only works for cards whose answer side has text — pure
    // image cards are impossible to type. Disable the button when none
    // qualify so we don't dump the user into an empty session.
    final typableCount =
        cards.where((c) => c.back.trim().isNotEmpty).length;
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
          label: 'Delete',
          icon: Icons.delete_outline,
          onTap: onDelete,
        ),
        const SizedBox(width: 8),
        SoftButton(
          label: 'Typing test',
          icon: Icons.keyboard_outlined,
          onTap: typableCount == 0 ? () {} : onTypingTest,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (trouble.isNotEmpty) ...[
                  _TroubleCardsPanel(
                    cards: trouble,
                    onStudyThese: () => onStudyTrouble(trouble),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final c in cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CardRow(
                      card: c,
                      onEdit: () async {
                        final e = await showCardDialog(context,
                            deckId: deck.id, existing: c);
                        if (e != null) {
                          ref.read(cardsProvider.notifier).upsert(e);
                        }
                      },
                      onDelete: () => onDeleteCard(c),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One row in the deck-detail list. Shows a thumbnail (if attached),
/// markdown-rendered front/back text, the Leitner box, edit + delete
/// affordances, and a "missed N×" chip when the card has been getting
/// graded wrong.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.onEdit,
    required this.onDelete,
  });

  final Flashcard card;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.frontImagePath != null) ...[
            _CardThumbnail(name: card.frontImagePath!, size: 56),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownText(card.front,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary)),
                const SizedBox(height: 4),
                MarkdownText(card.back,
                    style:
                        const TextStyle(color: AppPalette.textSecondary)),
                if (card.backImagePath != null) ...[
                  const SizedBox(height: 8),
                  _CardThumbnail(name: card.backImagePath!, size: 80),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (card.wrongCount > 0) ...[
                    GlassChip(
                        label: 'Missed ${card.wrongCount}×',
                        color: AppPalette.peach),
                    const SizedBox(width: 6),
                  ],
                  GlassChip(label: 'Box ${card.box}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppPalette.textSecondary,
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppPalette.textSecondary,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Header panel that flags the deck's most-missed cards and offers a
/// one-tap focused review on just those. Shown both above the deck-detail
/// list and on the session-complete screen so the user catches it whether
/// they're browsing or just finished a round.
class _TroubleCardsPanel extends StatelessWidget {
  const _TroubleCardsPanel({
    required this.cards,
    required this.onStudyThese,
  });

  final List<Flashcard> cards;
  final VoidCallback onStudyThese;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded,
                  size: 18, color: AppPalette.peach),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Trouble cards',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              SoftButton(
                label: 'Study just these',
                filled: true,
                icon: Icons.play_arrow_rounded,
                onTap: onStudyThese,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'These are the ones you’ve been getting wrong most often — '
            'a focused pass will help.',
            style: TextStyle(
                fontSize: 12, color: AppPalette.textSecondary),
          ),
          const Divider(height: 22),
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  if (c.frontImagePath != null) ...[
                    _CardThumbnail(name: c.frontImagePath!, size: 40),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: MarkdownText(
                      c.front.isEmpty ? '(image card)' : c.front,
                      style: const TextStyle(
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  GlassChip(
                      label:
                          '${c.wrongCount}/${c.reviewCount} missed',
                      color: AppPalette.peach),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Square-ish image preview used in deck-detail rows and the trouble
/// panel. Resolves filename → absolute path via [CardImageStore]; uses
/// the same broken-image fallback as the dialog so missing files never
/// crash the build.
class _CardThumbnail extends StatelessWidget {
  const _CardThumbnail({required this.name, this.size = 64});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: CardImageStore.fileFor(name),
      builder: (context, snap) {
        final file = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: size,
            height: size * 0.75,
            child: file == null
                ? const ColoredBox(color: Colors.black26)
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black26,
                      child: Icon(Icons.broken_image_outlined,
                          size: 18, color: AppPalette.textFaint),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _StudySession extends ConsumerStatefulWidget {
  const _StudySession({
    required this.deck,
    required this.mode,
    required this.cards,
    required this.allDeckCards,
    required this.fixedQueue,
    required this.onExit,
    required this.onStudyTrouble,
  });

  final Deck deck;

  /// Flip-and-self-grade vs type-and-auto-grade. In typing mode the
  /// queue is filtered to cards whose answer side has text (image-only
  /// cards can't be typed); see [_StudySessionState.initState].
  final StudySessionMode mode;

  /// The cards to study this session. For the default flow this is the
  /// deck's full card list (the session itself filters to "due"); for a
  /// focused trouble-cards run this is the exact list to queue, with no
  /// further filtering.
  final List<Flashcard> cards;

  /// Every card in the deck — used when computing trouble cards on the
  /// completion screen so the panel reflects the deck, not just this
  /// session's queue.
  final List<Flashcard> allDeckCards;

  /// True when [cards] is already the intended queue (focused trouble
  /// session). Disables the "due only" filter and reshuffle so the user
  /// sees exactly the cards they asked for, in roughly that order.
  final bool fixedQueue;

  final VoidCallback onExit;
  final ValueChanged<List<Flashcard>> onStudyTrouble;

  @override
  ConsumerState<_StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends ConsumerState<_StudySession> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _flipped = false;
  int _correct = 0;

  /// Typing-mode state — the controller backs the answer field, focus
  /// drives auto-focus across cards, `_submitted` flips the UI from
  /// "enter answer" to "see result", and `_autoCorrect` records whether
  /// our normalizer matched.
  final _typingController = TextEditingController();
  final _typingFocus = FocusNode();
  bool _typingSubmitted = false;
  bool _typingAutoCorrect = false;

  /// Ids of cards the user missed in *this* session. We use the latest
  /// version of each from the cards provider on the completion screen so
  /// the trouble panel's miss counts include the just-finished session.
  final Set<String> _missedThisSession = {};

  @override
  void initState() {
    super.initState();
    if (widget.fixedQueue) {
      _queue = [...widget.cards];
    } else {
      final due = widget.cards.where((c) => c.isDue).toList();
      _queue = (due.isEmpty ? widget.cards : due).toList()..shuffle();
    }
    if (widget.mode == StudySessionMode.typing) {
      // Drop cards we can't auto-grade (empty answer side, e.g. image-
      // only) so the user isn't asked to "type" an image.
      _queue =
          _queue.where((c) => c.back.trim().isNotEmpty).toList();
    }
  }

  @override
  void dispose() {
    _typingController.dispose();
    _typingFocus.dispose();
    super.dispose();
  }

  void _grade(bool correct) {
    final card = _queue[_index];
    ref
        .read(cardsProvider.notifier)
        .upsert(card.reviewed(correct: correct));
    setState(() {
      if (correct) {
        _correct++;
      } else {
        _missedThisSession.add(card.id);
      }
      _flipped = false;
      _typingController.clear();
      _typingSubmitted = false;
      _typingAutoCorrect = false;
      _index++;
    });
    if (widget.mode == StudySessionMode.typing && _index < _queue.length) {
      // Put the cursor back in the field so the user can just keep typing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _typingFocus.requestFocus();
      });
    }
  }

  /// Normalises a string for the typing-mode comparison: drop the small
  /// markdown markers we render (so the user doesn't have to type `**`),
  /// lowercase, trim, collapse internal whitespace, and strip leading /
  /// trailing punctuation. Deliberately forgiving — synonyms still need
  /// the "I was right" override.
  String _normalizeForTyping(String s) {
    var t = s.replaceAll(RegExp(r'[`*_]+'), '');
    t = t.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll(
        RegExp(r'^[\p{P}\p{S}]+|[\p{P}\p{S}]+$', unicode: true), '');
    return t;
  }

  void _submitTyping() {
    if (_typingSubmitted) return;
    final card = _queue[_index];
    final typed = _typingController.text;
    if (typed.trim().isEmpty) return;
    final ok = _normalizeForTyping(typed) ==
        _normalizeForTyping(card.back);
    setState(() {
      _typingSubmitted = true;
      _typingAutoCorrect = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty || _index >= _queue.length) {
      return _buildComplete(context);
    }
    return widget.mode == StudySessionMode.typing
        ? _buildTyping(context)
        : _buildFlip(context);
  }

  /// Shared header — same subtitle layout for both modes, with a "Typing
  /// test" annotation so the user knows which they're in.
  String _subtitleFor(String suffix) {
    final mode = widget.mode == StudySessionMode.typing
        ? ' · Typing test'
        : '';
    final trouble = widget.fixedQueue ? ' · Trouble cards' : '';
    return '${_index + 1} / ${_queue.length} · ${widget.deck.name}'
        '$mode$trouble$suffix';
  }

  Widget _buildFlip(BuildContext context) {
    final card = _queue[_index];
    return PageBody(
      title: 'Studying',
      subtitle: _subtitleFor(''),
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: 520, maxWidth: 520, minHeight: 280),
                  child: GlassContainer(
                    highlight: _flipped,
                    child: _CardFace(
                      label: _flipped ? 'ANSWER' : 'QUESTION',
                      text: _flipped ? card.back : card.front,
                      imageName: _flipped
                          ? card.backImagePath
                          : card.frontImagePath,
                      hint: _flipped ? null : 'Tap to reveal',
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

  Widget _buildTyping(BuildContext context) {
    final card = _queue[_index];
    return PageBody(
      title: 'Typing test',
      subtitle: _subtitleFor(''),
      scrollable: false,
      actions: [
        SoftButton(
            label: 'Exit', icon: Icons.close_rounded, onTap: widget.onExit),
      ],
      child: Expanded(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minWidth: 560, maxWidth: 560),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassContainer(
                    child: _CardFace(
                      label: 'QUESTION',
                      text: card.front,
                      imageName: card.frontImagePath,
                      hint: null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GlassContainer(
                    child: _TypingFace(
                      controller: _typingController,
                      focusNode: _typingFocus,
                      submitted: _typingSubmitted,
                      autoCorrect: _typingAutoCorrect,
                      correctAnswer: card.back,
                      correctImageName: card.backImagePath,
                      onSubmit: _submitTyping,
                      onContinueRight: () => _grade(true),
                      onContinueWrong: () => _grade(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The session-complete screen. Pulls the live card list from the
  /// provider so the trouble panel reflects the just-saved review counts,
  /// then biases the panel toward cards the user actually missed this
  /// session (they're the freshest evidence of trouble).
  Widget _buildComplete(BuildContext context) {
    final live = ref.watch(cardsProvider);
    final liveById = {for (final c in live) c.id: c};
    // Refresh allDeckCards through the live provider so the trouble panel
    // sees this session's miss counts instead of the pre-session snapshot.
    final freshDeckCards = widget.allDeckCards
        .map((c) => liveById[c.id] ?? c)
        .toList();
    final trouble = _troubleCards(freshDeckCards);
    final justMissed = _missedThisSession
        .map((id) => liveById[id])
        .whereType<Flashcard>()
        .toList();

    return PageBody(
      title: 'Session complete 🎉',
      subtitle: widget.deck.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
            child: Row(
              children: [
                const Icon(Icons.celebration_rounded,
                    size: 36, color: AppPalette.mint),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _queue.isEmpty
                        ? 'Nothing due right now — come back later!'
                        : 'You got $_correct of ${_queue.length} right.',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                SoftButton(
                  label: 'Done',
                  filled: true,
                  icon: Icons.check_rounded,
                  onTap: widget.onExit,
                ),
              ],
            ),
          ),
          if (trouble.isNotEmpty) ...[
            const SizedBox(height: 16),
            _TroubleCardsPanel(
              cards: trouble,
              onStudyThese: () => widget.onStudyTrouble(trouble),
            ),
          ] else if (justMissed.isNotEmpty) ...[
            // No qualifying "trouble" cards yet (e.g. first time missing
            // them), but the user did slip — surface them anyway so a
            // focused retry is one tap away.
            const SizedBox(height: 16),
            _TroubleCardsPanel(
              cards: justMissed,
              onStudyThese: () => widget.onStudyTrouble(justMissed),
            ),
          ],
        ],
      ),
    );
  }
}

/// Center column of a study card — eyebrow label, the markdown body, an
/// optional image, and the "Tap to reveal" hint on the question side.
/// Lives outside the session class so the layout is identical for both
/// faces and easy to scan.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.label,
    required this.text,
    required this.imageName,
    required this.hint,
  });

  final String label;
  final String text;
  final String? imageName;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: AppPalette.textSecondary)),
          const SizedBox(height: 18),
          if (imageName != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _CardThumbnail(name: imageName!, size: 360),
            ),
            const SizedBox(height: 18),
          ],
          if (text.isNotEmpty)
            MarkdownText(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600),
            ),
          if (hint != null) ...[
            const SizedBox(height: 18),
            Text(hint!,
                style: const TextStyle(
                    color: AppPalette.textFaint, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Typing-mode answer panel. Pre-submit it shows a text field + "Check"
/// button (Enter submits). Post-submit it reveals the correct answer
/// with a green/red banner; the user can either accept the auto-grade
/// or override via "I was right" (e.g. for a synonym we didn't match).
class _TypingFace extends StatelessWidget {
  const _TypingFace({
    required this.controller,
    required this.focusNode,
    required this.submitted,
    required this.autoCorrect,
    required this.correctAnswer,
    required this.correctImageName,
    required this.onSubmit,
    required this.onContinueRight,
    required this.onContinueWrong,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool submitted;
  final bool autoCorrect;
  final String correctAnswer;
  final String? correctImageName;
  final VoidCallback onSubmit;
  final VoidCallback onContinueRight;
  final VoidCallback onContinueWrong;

  @override
  Widget build(BuildContext context) {
    if (!submitted) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('YOUR ANSWER',
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: AppPalette.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                  hintText: 'Type the answer and press Enter'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: SoftButton(
                label: 'Check',
                icon: Icons.check_rounded,
                filled: true,
                onTap: onSubmit,
              ),
            ),
          ],
        ),
      );
    }

    final accent =
        autoCorrect ? AppPalette.success : AppPalette.danger;
    final banner = autoCorrect ? 'Correct!' : 'Not quite';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accent.withValues(alpha: 0.15),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                    autoCorrect
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: accent,
                    size: 20),
                const SizedBox(width: 10),
                Text(banner,
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('YOUR ANSWER',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  color: AppPalette.textSecondary)),
          const SizedBox(height: 4),
          Text(
            controller.text.trim().isEmpty
                ? '(blank)'
                : controller.text,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          const Text('CORRECT ANSWER',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  color: AppPalette.textSecondary)),
          const SizedBox(height: 6),
          if (correctImageName != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: _CardThumbnail(name: correctImageName!, size: 240),
            ),
            const SizedBox(height: 8),
          ],
          MarkdownText(
            correctAnswer,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!autoCorrect) ...[
                SoftButton(
                  label: 'I was right',
                  icon: Icons.thumb_up_alt_outlined,
                  onTap: onContinueRight,
                ),
                const SizedBox(width: 10),
                SoftButton(
                  label: 'Next',
                  filled: true,
                  icon: Icons.arrow_forward_rounded,
                  onTap: onContinueWrong,
                ),
              ] else
                SoftButton(
                  label: 'Next',
                  filled: true,
                  icon: Icons.arrow_forward_rounded,
                  onTap: onContinueRight,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps a [_DeckTile] in an [AdaptiveDraggable] so the user can pick it
/// up with the mouse (or long-press on touch) and drop it into another
/// group's drop zone. Tap-throughs to the tile's buttons still work —
/// the gesture only engages on actual movement (see [AdaptiveDraggable]).
class _DraggableDeckTile extends StatelessWidget {
  const _DraggableDeckTile({
    required this.deck,
    required this.total,
    required this.due,
    required this.onOpen,
    required this.onStudy,
    required this.onEdit,
    required this.onDelete,
  });

  final Deck deck;
  final int total;
  final int due;
  final VoidCallback onOpen;
  final VoidCallback onStudy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tile = _DeckTile(
      deck: deck,
      total: total,
      due: due,
      onOpen: onOpen,
      onStudy: onStudy,
      onEdit: onEdit,
      onDelete: onDelete,
    );
    return AdaptiveDraggable<Deck>(
      data: deck,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.95,
          child: SizedBox(
            width: 280,
            child: _DeckDragPreview(deck: deck),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

/// Compact stand-in shown while a deck tile is being dragged. Mirrors
/// the folder drag preview in the To-do page so the gesture feels the
/// same across the app.
class _DeckDragPreview extends StatelessWidget {
  const _DeckDragPreview({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: deck.color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.style_rounded,
                color: deck.color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              deck.name.trim().isEmpty ? 'Deck' : deck.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: AppPalette.textFaint),
        ],
      ),
    );
  }
}

/// Segmented [Grid | List] selector that mirrors the To-do page's mode
/// toggle so the two pages feel consistent.
class _StudyViewToggle extends StatelessWidget {
  const _StudyViewToggle({required this.mode, required this.onChanged});

  final StudyViewMode mode;
  final ValueChanged<StudyViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, StudyViewMode m, IconData icon) {
      final selected = mode == m;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? const Color(0xFF15132B)
                      : AppPalette.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFF15132B)
                          : AppPalette.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Grid', StudyViewMode.grid, Icons.view_module_outlined),
          seg('List', StudyViewMode.list, Icons.view_list_outlined),
        ],
      ),
    );
  }
}

/// Two-pane list view for the Study page: a group sidebar on the left
/// and the selected group's decks on the right. Mirrors the To-do
/// list view so the page feels consistent. Falls back to a stacked
/// layout on narrow widths so neither pane gets squeezed too thin.
class _StudyListView extends StatefulWidget {
  const _StudyListView({
    required this.groups,
    required this.decks,
    required this.cards,
    required this.onOpenDeck,
    required this.onStudyDeck,
    required this.onEditDeck,
    required this.onDeleteDeck,
    required this.onAddDeckToGroup,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onMoveDeck,
    required this.onReorderGroup,
  });

  final List<DeckGroup> groups;
  final List<Deck> decks;
  final List<Flashcard> cards;
  final ValueChanged<String> onOpenDeck;
  final ValueChanged<String> onStudyDeck;
  final ValueChanged<Deck> onEditDeck;
  final ValueChanged<Deck> onDeleteDeck;
  final ValueChanged<String?> onAddDeckToGroup;
  final ValueChanged<DeckGroup> onEditGroup;
  final ValueChanged<DeckGroup> onDeleteGroup;
  final Future<void> Function(Deck deck, String? targetGroupId) onMoveDeck;
  final Future<void> Function(
      DeckGroup moving, DeckGroup target, List<DeckGroup> ordered) onReorderGroup;

  @override
  State<_StudyListView> createState() => _StudyListViewState();
}

class _StudyListViewState extends State<_StudyListView> {
  /// Currently-selected sidebar row. Null on first build → resolved to a
  /// sensible default (first group, or Ungrouped) in `build`.
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final orderedGroups = [...widget.groups]
      ..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        if (byOrder != 0) return byOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final knownIds = {for (final g in orderedGroups) g.id};

    final byGroup = <String, List<Deck>>{
      for (final g in orderedGroups) g.id: [],
      _kUngroupedKey: [],
    };
    for (final d in widget.decks) {
      final key = (d.groupId != null && knownIds.contains(d.groupId))
          ? d.groupId!
          : _kUngroupedKey;
      byGroup[key]!.add(d);
    }
    final ungroupedCount = byGroup[_kUngroupedKey]!.length;

    String? resolveSelection() {
      String? fallback() {
        if (orderedGroups.isNotEmpty) return orderedGroups.first.id;
        if (ungroupedCount > 0) return _kUngroupedKey;
        return null;
      }

      final key = _selectedKey;
      if (key == null) return fallback();
      if (key == _kUngroupedKey) {
        return ungroupedCount > 0 ? _kUngroupedKey : fallback();
      }
      if (orderedGroups.any((g) => g.id == key)) return key;
      return fallback();
    }

    final selection = resolveSelection();

    Widget deckTile(Deck d) => _DraggableDeckTile(
          deck: d,
          total: widget.cards.where((c) => c.deckId == d.id).length,
          due: widget.cards
              .where((c) => c.deckId == d.id && c.isDue)
              .length,
          onOpen: () => widget.onOpenDeck(d.id),
          onStudy: () => widget.onStudyDeck(d.id),
          onEdit: () => widget.onEditDeck(d),
          onDelete: () => widget.onDeleteDeck(d),
        );

    Widget detail() {
      if (selection == null) {
        return GlassContainer(
          child: const EmptyHint(
              'Pick a group on the left, or create one to get started.',
              icon: Icons.folder_open_rounded),
        );
      }
      final isUngrouped = selection == _kUngroupedKey;
      final group = isUngrouped
          ? null
          : orderedGroups.firstWhere((g) => g.id == selection);
      final decksHere = byGroup[selection]!;
      final accent = isUngrouped ? AppPalette.textFaint : group!.color;
      final title = isUngrouped ? 'Ungrouped' : group!.name;

      return GlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                GlassChip(label: '${decksHere.length}'),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  color: AppPalette.lavender,
                  tooltip: 'Add deck here',
                  onPressed: () => widget
                      .onAddDeckToGroup(isUngrouped ? null : group!.id),
                ),
                if (!isUngrouped)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: AppPalette.textSecondary),
                    color: const Color(0xFF241F45),
                    tooltip: 'Group options',
                    onSelected: (v) {
                      if (v == 'edit') widget.onEditGroup(group!);
                      if (v == 'delete') widget.onDeleteGroup(group!);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, size: 20),
                          title: Text('Edit group'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline,
                              size: 20, color: AppPalette.danger),
                          title: Text('Delete group'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 22),
            if (decksHere.isEmpty)
              const EmptyHint('Nothing here yet. Drag a deck in or use “+”.',
                  icon: Icons.style_outlined)
            else
              CardGrid(children: [for (final d in decksHere) deckTile(d)]),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final pane = _GroupListPane(
          groups: orderedGroups,
          counts: {for (final g in orderedGroups) g.id: byGroup[g.id]!.length},
          ungroupedCount: ungroupedCount,
          selectedKey: selection,
          onSelect: (key) => setState(() => _selectedKey = key),
          onReorderGroup: (moving, target) =>
              widget.onReorderGroup(moving, target, orderedGroups),
          onAcceptDeck: widget.onMoveDeck,
        );

        // Below ~700px the side-by-side layout starts squeezing the right
        // pane; stack instead so each surface keeps a usable width.
        if (c.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pane,
              const SizedBox(height: 16),
              detail(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 260, child: pane),
            const SizedBox(width: 16),
            Expanded(child: detail()),
          ],
        );
      },
    );
  }
}

/// Sidebar listing every group + an "Ungrouped" row at the bottom.
/// Each row doubles as a drag-source (for reordering groups) and a
/// drop-target (for moving a deck into that group). Ungrouped is
/// drop-only — it isn't a real group so it can't be reordered.
class _GroupListPane extends StatelessWidget {
  const _GroupListPane({
    required this.groups,
    required this.counts,
    required this.ungroupedCount,
    required this.selectedKey,
    required this.onSelect,
    required this.onReorderGroup,
    required this.onAcceptDeck,
  });

  final List<DeckGroup> groups;
  final Map<String, int> counts;
  final int ungroupedCount;
  final String? selectedKey;
  final ValueChanged<String> onSelect;
  final void Function(DeckGroup moving, DeckGroup target) onReorderGroup;
  final Future<void> Function(Deck deck, String? targetGroupId) onAcceptDeck;

  @override
  Widget build(BuildContext context) {
    final hasAnyRow = groups.isNotEmpty || ungroupedCount > 0;
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6, left: 2),
            child: Text(
              'Groups',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          if (!hasAnyRow)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: EmptyHint(
                'No groups yet.\nTap “New group” to make one.',
                icon: Icons.create_new_folder_outlined,
              ),
            )
          else ...[
            for (final g in groups)
              _GroupListRow(
                key: ValueKey(g.id),
                group: g,
                count: counts[g.id] ?? 0,
                selected: selectedKey == g.id,
                onTap: () => onSelect(g.id),
                onReorderTarget: (moving) => onReorderGroup(moving, g),
                onAcceptDeck: (deck) => onAcceptDeck(deck, g.id),
              ),
            // Ungrouped is always shown when there are real groups, so the
            // user has somewhere to drop decks back to "no group".
            if (groups.isNotEmpty || ungroupedCount > 0) ...[
              if (groups.isNotEmpty) const Divider(height: 14),
              _UngroupedListRow(
                count: ungroupedCount,
                selected: selectedKey == _kUngroupedKey,
                onTap: () => onSelect(_kUngroupedKey),
                onAcceptDeck: (deck) => onAcceptDeck(deck, null),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One group row in the sidebar — draggable to reorder, droppable to
/// accept a deck from elsewhere. Mirrors `_FolderListRow` in todo_page.
class _GroupListRow extends StatelessWidget {
  const _GroupListRow({
    super.key,
    required this.group,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onReorderTarget,
    required this.onAcceptDeck,
  });

  final DeckGroup group;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<DeckGroup> onReorderTarget;
  final Future<void> Function(Deck deck) onAcceptDeck;

  @override
  Widget build(BuildContext context) {
    // Outer DragTarget accepts decks (drop → move into this group).
    return DragTarget<Deck>(
      onWillAcceptWithDetails: (d) => d.data.groupId != group.id,
      onAcceptWithDetails: (d) => onAcceptDeck(d.data),
      builder: (context, deckCandidate, _) {
        final deckHovering = deckCandidate.isNotEmpty;
        // Inner DragTarget + Draggable for group reordering.
        return DragTarget<DeckGroup>(
          onWillAcceptWithDetails: (d) => d.data.id != group.id,
          onAcceptWithDetails: (d) => onReorderTarget(d.data),
          builder: (context, groupCandidate, _) {
            final groupHovering = groupCandidate.isNotEmpty;
            return AdaptiveDraggable<DeckGroup>(
              data: group,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.95,
                  child: SizedBox(
                    width: 260,
                    child: _DeckGroupDragPreview(group: group),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _rowChild(
                    hovering: false, deckHovering: false),
              ),
              child: _rowChild(
                hovering: groupHovering,
                deckHovering: deckHovering,
              ),
            );
          },
        );
      },
    );
  }

  Widget _rowChild({
    required bool hovering,
    required bool deckHovering,
  }) {
    final base = selected
        ? AppPalette.accent.withValues(alpha: 0.18)
        : (hovering
            ? AppPalette.accent.withValues(alpha: 0.10)
            : Colors.transparent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: base,
            // A separate, stronger highlight for a hovering deck makes
            // the "drop here to move" affordance unmistakeable.
            border: deckHovering
                ? Border.all(
                    color: AppPalette.accent.withValues(alpha: 0.55),
                    width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: group.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                ),
              ),
              GlassChip(label: '$count'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catch-all "Ungrouped" sidebar row. Drop-only (it isn't a real group
/// so it can't be reordered or edited).
class _UngroupedListRow extends StatelessWidget {
  const _UngroupedListRow({
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onAcceptDeck,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function(Deck deck) onAcceptDeck;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Deck>(
      onWillAcceptWithDetails: (d) => d.data.groupId != null,
      onAcceptWithDetails: (d) => onAcceptDeck(d.data),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        final base = selected
            ? AppPalette.accent.withValues(alpha: 0.18)
            : Colors.transparent;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: base,
                border: hovering
                    ? Border.all(
                        color:
                            AppPalette.accent.withValues(alpha: 0.55),
                        width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: AppPalette.textFaint,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ungrouped',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? AppPalette.textPrimary
                            : AppPalette.textSecondary,
                      ),
                    ),
                  ),
                  GlassChip(label: '$count'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact preview rendered while a sidebar group row is being dragged
/// to reorder. Mirrors `_FolderDragPreview` in the To-do page.
class _DeckGroupDragPreview extends StatelessWidget {
  const _DeckGroupDragPreview({required this.group});

  final DeckGroup group;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                color: group.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group.name.trim().isEmpty ? 'Group' : group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: AppPalette.textFaint),
        ],
      ),
    );
  }
}
