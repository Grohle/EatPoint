import 'dart:math' as math;

import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

/// What a meal still lacks: the points of each macro left in its budget
/// and the fibre still short of its minimum, never below zero.
class MealGap {
  final MacroPoints macros;
  final double fibre;

  const MealGap({required this.macros, this.fibre = 0});

  /// The budget left once [used] (and [adding], about to be logged) count.
  factory MealGap.of({
    required MacroPoints budget,
    required MacroPoints used,
    MacroPoints adding = MacroPoints.zero,
    double fibreTarget = 0,
    double fibreUsed = 0,
    double fibreAdding = 0,
  }) {
    final left = budget - used - adding;
    return MealGap(
      macros: MacroPoints(
        carbs: math.max(0, left.carbs),
        protein: math.max(0, left.protein),
        fat: math.max(0, left.fat),
      ),
      fibre: math.max(0, fibreTarget - fibreUsed - fibreAdding),
    );
  }

  /// Less than this is not worth a suggestion (a quarter point, the step
  /// amounts move in).
  static const threshold = 0.25;

  bool get hasCarbs => macros.carbs >= threshold;
  bool get hasProtein => macros.protein >= threshold;
  bool get hasFat => macros.fat >= threshold;
  bool get hasFibre => fibre >= threshold;

  /// Nothing worth closing.
  bool get isClosed => !hasCarbs && !hasProtein && !hasFat && !hasFibre;
}

/// A food that would help close a meal, and how much of it.
class CloserSuggestion {
  final CoreFood food;
  final double grams;
  final MacroPoints points;
  final double fibre;

  /// Share of the gap it closes, 0..1.
  final double covers;

  const CloserSuggestion({
    required this.food,
    required this.grams,
    required this.points,
    required this.fibre,
    required this.covers,
  });
}

/// Suggests foods from EatPoint's food list that fill what a meal lacks
/// without going over its budget: protein first when it is missing, then
/// carbs, fat and fibre. Amounts snap to half household portions where
/// the food has them ("½ avocado"), otherwise to 5 g.
class MealCloser {
  MealCloser._();

  /// A suggestion may go over a macro's budget by this much.
  static const tolerance = 0.25;

  /// Foods never suggested to close a meal.
  static const _avoidTags = {'sweet', 'processed_meat'};

  static List<CloserSuggestion> suggest(
    MealGap gap,
    FoodKnowledge knowledge, {
    int limit = 4,
    Set<String> excludeConcepts = const {},
  }) {
    if (gap.isClosed) return const [];
    final want = gap.macros;
    final wantTotal =
        (gap.hasCarbs ? want.carbs : 0) +
        (gap.hasProtein ? want.protein : 0) +
        (gap.hasFat ? want.fat : 0);
    final candidates = <(CloserSuggestion, double)>[];
    for (final food in knowledge.foods) {
      final concept = knowledge.conceptById(food.conceptId);
      if (food.tags.any(_avoidTags.contains) ||
          (concept?.tags.any(_avoidTags.contains) ?? false)) {
        continue;
      }
      if (excludeConcepts.contains(food.conceptId)) continue;
      final nutriments = food.toMealEntity('en').nutriments;
      final per = nutriments.macroPointsFor(1);
      final fibrePer = nutriments.fibrePointsFor(1);
      if (per.total <= 0) continue;
      // The most of it that keeps every macro within its budget.
      var maxGrams = double.infinity;
      for (final (k, left) in [
        (per.carbs, want.carbs),
        (per.protein, want.protein),
        (per.fat, want.fat),
      ]) {
        if (k > 0) maxGrams = math.min(maxGrams, (left + tolerance) / k);
      }
      if (!maxGrams.isFinite || maxGrams < 5) continue;
      final portion = concept?.mainPortion;
      final grams = _snap(
        math.min(maxGrams, _usualMax(food, concept, portion?.grams)),
        portion?.grams,
      );
      if (grams < 5) continue;
      final points = per * grams;
      final fibre = fibrePer * grams;
      double filled(double got, double left, bool counts) =>
          counts ? math.min(got, left) : 0;
      var covered =
          filled(points.carbs, want.carbs, gap.hasCarbs) +
          filled(points.protein, want.protein, gap.hasProtein) +
          filled(points.fat, want.fat, gap.hasFat);
      // Points a macro that is not missing would take, beyond tolerance.
      var wasted = 0.0;
      if (!gap.hasCarbs) wasted += points.carbs;
      if (!gap.hasProtein) wasted += points.protein;
      if (!gap.hasFat) wasted += points.fat;
      var score = wantTotal > 0 ? (covered - 0.5 * wasted) / wantTotal : 0.0;
      // Protein is the hardest to make up later in the day.
      if (gap.hasProtein && want.protein > 0) {
        score += 0.3 * math.min(points.protein, want.protein) / want.protein;
      }
      if (gap.hasFibre) {
        score += 0.4 * math.min(fibre, gap.fibre) / gap.fibre;
        covered += math.min(fibre, gap.fibre);
      }
      if (score < 0.2) continue;
      final total = wantTotal + (gap.hasFibre ? gap.fibre : 0);
      candidates.add((
        CloserSuggestion(
          food: food,
          grams: grams,
          points: points,
          fibre: fibre,
          covers: total > 0 ? math.min(1, covered / total) : 0,
        ),
        score,
      ));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    // One food per concept and at most two of the same main macro, so the
    // list offers real choices.
    final picked = <CloserSuggestion>[];
    final concepts = <String>{};
    final perKind = <String, int>{};
    for (final (c, _) in candidates) {
      if (concepts.contains(c.food.conceptId)) continue;
      final kind = _kind(c.points);
      if ((perKind[kind] ?? 0) >= 2) continue;
      concepts.add(c.food.conceptId);
      perKind[kind] = (perKind[kind] ?? 0) + 1;
      picked.add(c);
      if (picked.length >= limit) break;
    }
    return picked;
  }

  /// The most of a food a person would add to a meal: one piece of fruit,
  /// a side of vegetables, two portions of anything else, and never more
  /// than 250 g.
  static double _usualMax(
    CoreFood food,
    FoodConcept? concept,
    double? portionGrams,
  ) {
    bool tagged(String tag) =>
        food.tags.contains(tag) || (concept?.hasTag(tag) ?? false);
    if (tagged('fruit') && portionGrams != null) return portionGrams;
    if (tagged('veg')) return 200;
    final byPortion = portionGrams == null ? 200.0 : portionGrams * 2;
    return math.min(250, byPortion);
  }

  static String _kind(MacroPoints p) {
    if (p.protein >= p.carbs && p.protein >= p.fat) return 'protein';
    if (p.carbs >= p.fat) return 'carbs';
    return 'fat';
  }

  /// Down to half portions when the food has a household unit, else to
  /// 5 g; never more than [maxGrams].
  static double _snap(double maxGrams, double? portionGrams) {
    if (portionGrams != null && portionGrams > 0) {
      final halves = (maxGrams / (portionGrams / 2)).floorToDouble();
      if (halves >= 1) return (halves * portionGrams / 2).roundToDouble();
    }
    return (maxGrams / 5).floorToDouble() * 5;
  }
}
