import 'dart:math' as math;

import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

/// How a week's amount of a food is bought: [packs] packs of [size] grams
/// (or ml), with [leftover] left over; [pieces] for packs counted in
/// units (a box of 6 eggs).
class PackAdvice {
  final double size;
  final int? pieces;
  final int packs;
  final double leftover;

  const PackAdvice({
    required this.size,
    required this.packs,
    required this.leftover,
    this.pieces,
  });
}

/// Usual supermarket pack sizes in Spain, by food, for the weights the
/// planner uses (rice, pasta and lentils dry; chickpeas and beans drained).
class PackSizes {
  PackSizes._();

  static const _sizes = <String, (double, int?)>{
    'egg': (300, 6),
    'chicken_breast': (500, null),
    'chicken_thigh': (500, null),
    'turkey_breast': (400, null),
    'pork_loin': (500, null),
    'beef_steak': (400, null),
    'minced_meat': (500, null),
    'salmon': (400, null),
    'tuna_can': (240, 3),
    'sardines_can': (120, null),
    'tofu': (400, null),
    'milk': (1000, null),
    'plant_milk': (1000, null),
    'yogurt': (500, 4),
    'cheese_slice': (200, null),
    'fresh_cheese': (250, null),
    'bread_slice': (450, null),
    'oats': (500, null),
    'rice': (1000, null),
    'pasta': (500, null),
    'lentils': (1000, null),
    'chickpeas': (250, null),
    'beans': (250, null),
    'spinach': (300, null),
  };

  /// The packs to buy for [amount] g (or ml) of [name], or null when its
  /// usual pack isn't known.
  static PackAdvice? forFood(String name, double amount) {
    if (amount <= 0) return null;
    final knowledge = FoodKnowledge.instance;
    if (knowledge == null) return null;
    final concept =
        knowledge.matchFood(name)?.conceptId ?? knowledge.match(name)?.id;
    final pack = concept == null ? null : _sizes[concept];
    if (pack == null) return null;
    final (size, pieces) = pack;
    final packs = math.max(1, (amount / size - 0.05).ceil());
    return PackAdvice(
      size: size,
      pieces: pieces,
      packs: packs,
      leftover: math.max(0, packs * size - amount),
    );
  }
}
