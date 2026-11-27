import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

/// An amount in household units: "1½ filetes", "½ aguacate", "2 huevos".
class PortionAmount {
  final FoodPortion portion;

  /// How many units, rounded to what a person would say: halves for most
  /// things, whole numbers for small ones (an almond, a cherry tomato).
  final double count;

  const PortionAmount(this.portion, this.count);

  double get grams => portion.grams * count;

  /// "1½ filetes", "½ aguacate", "3 almendras".
  String label(String languageCode) =>
      '${countText(count)} ${portion.name(languageCode, count)}';

  /// 0.5 → "½", 1.5 → "1½", 2 → "2".
  static String countText(double count) {
    final whole = count.floor();
    final half = (count - whole) >= 0.25 && (count - whole) < 0.75;
    final rounded = half ? whole : count.round();
    if (half) return whole == 0 ? '½' : '$rounded½';
    return '$rounded';
  }
}

/// Turns grams into household units and back.
class PortionFormatter {
  PortionFormatter._();

  /// Units lighter than this are counted in whole numbers.
  static const smallUnitGrams = 20.0;

  /// How far the rounded amount may be from the real one and still be
  /// shown (as a share of the real amount).
  static const maxError = 0.25;

  /// [grams] in [portion] units, or null when no sensible count fits (too
  /// little, too many, or too far from a round number).
  static PortionAmount? describe(double grams, FoodPortion portion) {
    if (grams <= 0 || portion.grams <= 0) return null;
    final exact = grams / portion.grams;
    final small = portion.grams < smallUnitGrams;
    final count = small
        ? exact.roundToDouble()
        : (exact * 2).roundToDouble() / 2;
    if (count <= 0) return null;
    if (small && count > 60) return null;
    if (!small && count > 12) return null;
    final error = (count * portion.grams - grams).abs() / grams;
    if (error > maxError) return null;
    return PortionAmount(portion, count);
  }

  /// [grams] of a food called [foodName], in its main household unit, using
  /// the loaded catalogue. Null when the food is unknown or no count fits.
  static PortionAmount? forFood(String foodName, double grams) {
    final concept = FoodKnowledge.instance?.match(foodName);
    final portion = concept?.mainPortion;
    return portion == null ? null : describe(grams, portion);
  }

  /// Units that are bought whole: a shopping list says "≈ 6 patatas", never
  /// "≈ 12 cucharadas".
  static const _buyableUnits = {
    'unit',
    'fillet',
    'steak',
    'thigh',
    'egg',
    'can',
    'jar',
    'yogurt',
    'tortilla',
    'bun',
    'link',
    'slice',
  };

  /// What to buy for [grams] of a food called [foodName]: whole units,
  /// rounded up. Null for foods bought by weight or volume.
  static PortionAmount? forShopping(String foodName, double grams) {
    final concept = FoodKnowledge.instance?.match(foodName);
    final portion = concept?.mainPortion;
    if (portion == null || grams <= 0) return null;
    if (!_buyableUnits.contains(portion.unit)) return null;
    final count = (grams / portion.grams - 0.15).ceilToDouble();
    if (count < 1 || count > 200) return null;
    return PortionAmount(portion, count);
  }

  /// The counts to offer as quick choices for [portion], around [current]
  /// grams when given: ½, 1, 1½, 2… for big units, 5, 10, 15… for small.
  static List<double> quickCounts(FoodPortion portion) {
    if (portion.grams < smallUnitGrams) {
      final step = portion.grams < 5 ? 5.0 : 1.0;
      return [for (var i = 1; i <= 4; i++) step * i];
    }
    if (portion.grams > 250) return const [0.5, 1, 2];
    return const [0.5, 1, 1.5, 2];
  }
}
