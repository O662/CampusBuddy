import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class Flashcard {
  final String id;
  final String front;
  final String back;

  Flashcard({String? id, required this.front, required this.back})
      : id = id ?? const Uuid().v4();

  Flashcard copyWith({String? front, String? back}) =>
      Flashcard(id: id, front: front ?? this.front, back: back ?? this.back);

  Map<String, dynamic> toJson() => {'id': id, 'front': front, 'back': back};

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] as String,
        front: j['front'] as String,
        back: j['back'] as String,
      );
}

class FlashcardDeck {
  final String id;
  final String name;
  final int colorValue;
  final List<Flashcard> cards;
  final DateTime createdAt;

  FlashcardDeck({
    String? id,
    required this.name,
    required this.colorValue,
    List<Flashcard>? cards,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        cards = cards ?? [],
        createdAt = createdAt ?? DateTime.now();

  Color get color => Color(colorValue);

  FlashcardDeck copyWith({
    String? name,
    int? colorValue,
    List<Flashcard>? cards,
  }) =>
      FlashcardDeck(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        cards: cards ?? List<Flashcard>.from(this.cards),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'cards': cards.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory FlashcardDeck.fromJson(Map<String, dynamic> j) => FlashcardDeck(
        id: j['id'] as String,
        name: j['name'] as String,
        colorValue: j['colorValue'] as int,
        cards: (j['cards'] as List)
            .map((c) => Flashcard.fromJson(c as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static const List<int> palette = [
    0xFFEF5350,
    0xFFEC407A,
    0xFFAB47BC,
    0xFF7E57C2,
    0xFF5C6BC0,
    0xFF42A5F5,
    0xFF26C6DA,
    0xFF26A69A,
    0xFF66BB6A,
    0xFFFFCA28,
    0xFFFFA726,
    0xFF8D6E63,
  ];
}
