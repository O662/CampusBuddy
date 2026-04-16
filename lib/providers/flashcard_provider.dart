import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';

class FlashcardProvider extends ChangeNotifier {
  static const _key = 'flashcard_decks';

  List<FlashcardDeck> _decks = [];
  List<FlashcardDeck> get decks => List.unmodifiable(_decks);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _decks = list
          .map((e) => FlashcardDeck.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_decks.map((d) => d.toJson()).toList()));
  }

  Future<void> addDeck(FlashcardDeck deck) async {
    _decks.add(deck);
    notifyListeners();
    await _save();
  }

  Future<void> updateDeck(FlashcardDeck deck) async {
    final i = _decks.indexWhere((d) => d.id == deck.id);
    if (i >= 0) {
      _decks[i] = deck;
      notifyListeners();
      await _save();
    }
  }

  Future<void> deleteDeck(String id) async {
    _decks.removeWhere((d) => d.id == id);
    notifyListeners();
    await _save();
  }

  FlashcardDeck? deckById(String id) {
    try {
      return _decks.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addCard(String deckId, Flashcard card) async {
    final deck = deckById(deckId);
    if (deck == null) return;
    final updated = deck.copyWith(cards: [...deck.cards, card]);
    await updateDeck(updated);
  }

  Future<void> updateCard(String deckId, Flashcard card) async {
    final deck = deckById(deckId);
    if (deck == null) return;
    final cards = deck.cards.map((c) => c.id == card.id ? card : c).toList();
    await updateDeck(deck.copyWith(cards: cards));
  }

  Future<void> deleteCard(String deckId, String cardId) async {
    final deck = deckById(deckId);
    if (deck == null) return;
    final cards = deck.cards.where((c) => c.id != cardId).toList();
    await updateDeck(deck.copyWith(cards: cards));
  }
}
