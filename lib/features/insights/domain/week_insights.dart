import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';

/// What a suggestion is about.
enum InsightKind {
  fibreLow,
  fibreGood,
  oilyFishMissing,
  oilyFishGood,
  plantOmega3,
  b12Missing,
  legumesLow,
  legumesGood,
  fruitVegLow,
  fruitVegGood,
  wholegrainLow,
  varietyLow,
  processedMeatHigh,
  sweetsHigh,
  calciumLow,
}

/// One suggestion about a week's menu, with the figures it is based on.
class Insight {
  final InsightKind kind;

  /// True for a nudge to change something, false for a well-done note.
  final bool isSuggestion;

  /// The figures the text quotes, e.g. {'avg': 3.5, 'target': 5}.
  final Map<String, num> values;

  /// For [InsightKind.varietyLow], the dish that repeats.
  final String? food;

  const Insight(
    this.kind, {
    this.isSuggestion = true,
    this.values = const {},
    this.food,
  });
}

/// Looks at a week's planned menu and suggests what could make it better:
/// enough fibre, oily fish for omega-3, a source of vitamin B12, pulses,
/// fruit and vegetables, wholegrains, variety, and not too much processed
/// meat or sweets.
///
/// These are general healthy-eating guides (such as two servings of fish a
/// week, one of them oily, and 400 g of fruit and vegetables a day), not
/// medical advice; the screens say so.
class WeekInsights {
  WeekInsights._();

  /// A day counts when it has at least this many foods planned.
  static const minFoodsPerDay = 3;

  /// Suggestions need at least this many planned days.
  static const minDays = 3;

  /// Grams that make one serving of fruit or vegetables.
  static const fruitVegServingGrams = 80.0;

  static const fruitVegGramsPerDay = 400.0;
  static const fishServingsPerWeek = 2;
  static const legumeServingsPerWeek = 3;
  static const processedMeatMaxPerWeek = 2;
  static const sweetsMaxPerWeek = 7;

  /// Days the suggestions are based on: the planned days of [week].
  static List<DayPlan> plannedDays(List<DayPlan> week) =>
      week.where((d) => d.itemCount >= minFoodsPerDay).toList();

  /// Suggestions first, then the notes on what is going well. Empty when
  /// fewer than [minDays] days are planned.
  static List<Insight> analyse(
    List<DayPlan> week, {
    required FoodKnowledge knowledge,
    double fibreTargetPoints = 5,
  }) {
    final days = plannedDays(week);
    if (days.length < minDays) return const [];
    final n = days.length;

    FoodConcept? concept(PlannedItem i) => knowledge.match(i.name);
    final items = [
      for (final d in days)
        for (final list in d.meals.values) ...list,
    ];
    bool tagged(PlannedItem i, String tag) => concept(i)?.hasTag(tag) ?? false;
    bool wholegrainByName(PlannedItem i) {
      final name = FoodKnowledge.fold(i.name);
      return RegExp(
        r'\b(integral|integrales|wholemeal|wholegrain|whole wheat|whole-wheat|centeno|rye|avena|oat)',
      ).hasMatch(name);
    }

    // Servings: one per planned food of that kind, as a person would count.
    int servings(String tag) => items.where((i) => tagged(i, tag)).length;

    final suggestions = <Insight>[];
    final good = <Insight>[];

    // Fibre.
    final fibreAvg = days.fold(0.0, (sum, d) => sum + d.totalFibre) / n;
    if (fibreTargetPoints > 0) {
      final values = {'avg': _round(fibreAvg), 'target': fibreTargetPoints};
      if (fibreAvg < fibreTargetPoints * 0.8) {
        suggestions.add(Insight(InsightKind.fibreLow, values: values));
      } else if (fibreAvg >= fibreTargetPoints) {
        good.add(
          Insight(InsightKind.fibreGood, isSuggestion: false, values: values),
        );
      }
    }

    // Fish and omega-3, scaled to a whole week.
    final perWeek = 7 / n;
    final oily = servings('oily_fish') * perWeek;
    final fish = servings('fish') * perWeek;
    if (oily < 1) {
      suggestions.add(
        Insight(
          InsightKind.oilyFishMissing,
          values: {'fish': fish.round(), 'target': fishServingsPerWeek},
        ),
      );
      if (fish < 1 && servings('omega3_ala') == 0) {
        suggestions.add(const Insight(InsightKind.plantOmega3));
      }
    } else if (fish >= fishServingsPerWeek) {
      good.add(
        Insight(
          InsightKind.oilyFishGood,
          isSuggestion: false,
          values: {'fish': fish.round()},
        ),
      );
    }

    // Vitamin B12: only animal foods (and fortified ones) carry it.
    if (servings('b12') == 0) {
      suggestions.add(const Insight(InsightKind.b12Missing));
    }

    // Pulses.
    final legumes = servings('legume') * perWeek;
    if (legumes < legumeServingsPerWeek) {
      suggestions.add(
        Insight(
          InsightKind.legumesLow,
          values: {'count': legumes.round(), 'target': legumeServingsPerWeek},
        ),
      );
    } else {
      good.add(
        Insight(
          InsightKind.legumesGood,
          isSuggestion: false,
          values: {'count': legumes.round()},
        ),
      );
    }

    // Fruit and vegetables, by weight.
    final fruitVegGrams =
        items
            .where((i) => tagged(i, 'veg') || tagged(i, 'fruit'))
            .fold(0.0, (sum, i) => sum + i.amount) /
        n;
    final fvValues = {
      'grams': fruitVegGrams.round(),
      'servings': (fruitVegGrams / fruitVegServingGrams).round(),
      'target': fruitVegGramsPerDay.round(),
    };
    if (fruitVegGrams < fruitVegGramsPerDay * 0.75) {
      suggestions.add(Insight(InsightKind.fruitVegLow, values: fvValues));
    } else if (fruitVegGrams >= fruitVegGramsPerDay) {
      good.add(
        Insight(
          InsightKind.fruitVegGood,
          isSuggestion: false,
          values: fvValues,
        ),
      );
    }

    // Wholegrains among the bread, pasta, rice and cereals.
    final grains = items.where((i) {
      final c = concept(i);
      return c != null &&
          c.hasTag('carb') &&
          !c.hasTag('legume') &&
          !c.hasTag('sweet') &&
          c.id != 'potato' &&
          c.id != 'sweet_potato' &&
          c.id != 'corn';
    }).toList();
    if (grains.length >= 3) {
      final whole = grains
          .where((i) => tagged(i, 'wholegrain') || wholegrainByName(i))
          .length;
      if (whole / grains.length < 0.5) {
        suggestions.add(
          Insight(
            InsightKind.wholegrainLow,
            values: {'whole': whole, 'total': grains.length},
          ),
        );
      }
    }

    // Processed meat and sweets.
    final processed = servings('processed_meat') * perWeek;
    if (processed > processedMeatMaxPerWeek) {
      suggestions.add(
        Insight(
          InsightKind.processedMeatHigh,
          values: {'count': processed.round(), 'max': processedMeatMaxPerWeek},
        ),
      );
    }
    final sweets = servings('sweet') * perWeek;
    if (sweets > sweetsMaxPerWeek) {
      suggestions.add(
        Insight(
          InsightKind.sweetsHigh,
          values: {'count': sweets.round(), 'max': sweetsMaxPerWeek},
        ),
      );
    }

    // Calcium: dairy and other calcium-rich foods, about two a day.
    final calcium = servings('calcium') / n;
    if (calcium < 1.5) {
      suggestions.add(
        Insight(InsightKind.calciumLow, values: {'perDay': _round(calcium)}),
      );
    }

    // Variety: a dish planned on most days of the week. Staples that are
    // eaten daily on purpose (milk, oil, bread, fruit) are not counted.
    final perDayDishes = <String, int>{};
    final displayName = <String, String>{};
    for (final d in days) {
      final seen = <String>{};
      for (final i in d.meals.values.expand((l) => l)) {
        final c = concept(i);
        if (c != null &&
            (c.hasTag('fat') ||
                c.hasTag('fruit') ||
                c.hasTag('dairy') ||
                c.id == 'bread_slice' ||
                c.id == 'olive_oil')) {
          continue;
        }
        final key = ShoppingListBuilder.normalise(i.name);
        if (key.isEmpty || !seen.add(key)) continue;
        perDayDishes[key] = (perDayDishes[key] ?? 0) + 1;
        displayName[key] = i.name;
      }
    }
    final repeated =
        perDayDishes.entries
            .where((e) => e.value >= 5 && e.value >= n - 1)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (repeated.isNotEmpty) {
      suggestions.add(
        Insight(
          InsightKind.varietyLow,
          values: {'days': repeated.first.value},
          food: displayName[repeated.first.key],
        ),
      );
    }

    return [...suggestions, ...good];
  }

  static double _round(double v) => (v * 10).round() / 10;
}
