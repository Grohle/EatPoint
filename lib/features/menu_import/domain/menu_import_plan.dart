import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_amount_solver.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

/// How the amount of one imported food was decided.
enum AmountSource {
  /// The source gave grams or ml.
  given,

  /// The source gave points; converted to grams.
  fromPoints,

  /// The source gave a count; converted with the food's serving size.
  fromCount,

  /// Chosen to fit the meal's points budget.
  fitted,

  /// What the user usually has, or 100 g, when there was nothing to fit.
  usual,
}

/// One food ready to plan: what was read, what it matched and how much.
class PlanFood {
  final ImportedFood source;
  final MealEntity? meal;
  final double grams;
  final AmountSource amountSource;

  const PlanFood({
    required this.source,
    required this.meal,
    required this.grams,
    required this.amountSource,
  });

  MacroPoints get points =>
      meal?.nutriments.macroPointsFor(grams) ?? MacroPoints.zero;

  PlanFood withGrams(double grams) => PlanFood(
    source: source,
    meal: meal,
    grams: grams,
    amountSource: AmountSource.given,
  );
}

class PlanMeal {
  final ImportedMeal source;

  /// The user's meal it goes into.
  final MealSlot slot;
  final List<PlanFood> foods;

  const PlanMeal({
    required this.source,
    required this.slot,
    required this.foods,
  });

  MacroPoints get points =>
      foods.fold(MacroPoints.zero, (sum, f) => sum + f.points);
}

class PlanDay {
  final ImportedDay source;
  final DateTime date;
  final List<PlanMeal> meals;

  const PlanDay({
    required this.source,
    required this.date,
    required this.meals,
  });
}

/// Turns an imported menu into planner days for the user's meals.
class MenuImportPlanner {
  MenuImportPlanner._();

  /// Kinds of meal and the words that name them, in English and Spanish,
  /// with the meal type a kind is stored as.
  static const _concepts = <(IntakeTypeEntity, List<String>)>[
    (IntakeTypeEntity.breakfast, ['breakfast', 'desayuno', 'brunch']),
    (
      IntakeTypeEntity.snack,
      ['media manana', 'mid-morning', 'mid morning', 'midmorning', 'elevenses'],
    ),
    (IntakeTypeEntity.lunch, ['lunch', 'comida', 'almuerzo']),
    (
      IntakeTypeEntity.snack,
      ['merienda', 'afternoon snack', 'afternoon', 'tarde'],
    ),
    (IntakeTypeEntity.dinner, ['dinner', 'cena', 'supper']),
    (IntakeTypeEntity.snack, ['recena', 'late snack', 'resopon', 'bedtime']),
    (
      IntakeTypeEntity.snack,
      [
        'pre-workout',
        'pre workout',
        'preentreno',
        'pre-entreno',
        'antes de entrenar',
      ],
    ),
    (
      IntakeTypeEntity.snack,
      [
        'post-workout',
        'post workout',
        'postentreno',
        'post-entreno',
        'despues de entrenar',
      ],
    ),
    (IntakeTypeEntity.snack, ['snack', 'tentempie', 'picoteo', 'aperitivo']),
  ];

  /// The user's meal for [label]: one with that name; else one named like
  /// the same kind of meal (in either language); else the built-in meal of
  /// that kind's type; else the first meal of that type. Null when the
  /// label names no kind of meal.
  static MealSlot? slotForLabel(
    String label,
    List<MealSlot> slots,
    String Function(MealSlot) nameOf,
  ) {
    final folded = MenuTextParser.fold(label).trim();
    for (final slot in slots) {
      if (MenuTextParser.fold(nameOf(slot)) == folded) return slot;
    }
    for (final (type, words) in _concepts) {
      if (!words.any(folded.contains)) continue;
      for (final slot in slots) {
        final name = MenuTextParser.fold(nameOf(slot));
        if (words.any(name.contains)) return slot;
      }
      return slots.byId(type.name) ?? slots.defaultFor(type);
    }
    // A meal whose name shares the label's words ("Pre-cama" for
    // "pre-cama (23h)").
    for (final slot in slots) {
      final name = MenuTextParser.fold(nameOf(slot));
      if (name.length >= 4 &&
          (folded.contains(name) || name.contains(folded))) {
        return slot;
      }
    }
    return null;
  }

  /// The date each imported day goes to, starting at [start] (a Monday for
  /// a weekly menu): its own date when it has one, its weekday in the week
  /// of [start], "Day N" counted from [start], else one after another.
  static List<DateTime> datesFor(List<ImportedDay> days, DateTime start) {
    final first = DayPlan.dateOnly(start);
    final monday = DayPlan.weekStart(first);
    var next = first;
    var previous = -1;
    var weekOffset = 0;
    final dates = <DateTime>[];
    for (final day in days) {
      DateTime date;
      if (day.date != null) {
        date = DayPlan.dateOnly(day.date!);
      } else if (day.weekday != null) {
        // A second "Monday" in the list starts the following week.
        if (day.weekday! <= previous) weekOffset += 7;
        previous = day.weekday!;
        date = DateTime(
          monday.year,
          monday.month,
          monday.day + weekOffset + day.weekday! - 1,
        );
      } else if (day.index != null) {
        date = DateTime(first.year, first.month, first.day + day.index! - 1);
      } else {
        date = next;
      }
      dates.add(date);
      next = DateTime(date.year, date.month, date.day + 1);
    }
    return dates;
  }

  /// Builds the plan. [match] gives each food's nutrition (and the amount
  /// the user usually has); [budgets] is each meal's points budget, used
  /// to fit amounts when [fitToBudget] is on.
  static List<PlanDay> build({
    required ImportedMenu menu,
    required List<MealSlot> slots,
    required String Function(MealSlot) nameOf,
    required DateTime start,
    required ({MealEntity? meal, double? usual}) Function(ImportedFood) match,
    Map<String, MacroPoints> budgets = const {},
    bool fitToBudget = true,
  }) {
    final dates = datesFor(menu.days, start);
    final result = <PlanDay>[];
    for (var d = 0; d < menu.days.length; d++) {
      final day = menu.days[d];
      final meals = <PlanMeal>[];
      final unlabeled = day.meals.where((m) => m.label == null).length;
      var position = 0;
      for (final meal in day.meals) {
        MealSlot? slot = meal.label == null
            ? null
            : slotForLabel(meal.label!, slots, nameOf);
        if (slot == null) {
          // Unnamed meals fill the user's meals in order; a single unnamed
          // list of foods is the whole day's first meal.
          final i = unlabeled == slots.length
              ? position
              : position.clamp(0, slots.length - 1);
          slot = slots[i];
          position++;
        }
        final matched = [for (final f in meal.foods) (f, match(f))];
        final fixed = <int, PlanFood>{};
        final free = <int>[];
        for (var i = 0; i < matched.length; i++) {
          final (food, m) = matched[i];
          final per100 = m.meal?.nutriments.macroPointsFor(100);
          if (food.amount != null) {
            fixed[i] = PlanFood(
              source: food,
              meal: m.meal,
              grams: food.amount!,
              amountSource: AmountSource.given,
            );
          } else if (food.points != null &&
              per100 != null &&
              per100.total > 0) {
            fixed[i] = PlanFood(
              source: food,
              meal: m.meal,
              grams: PointsCalc.pointsToGrams(
                food.points!,
                per100.total,
              ).roundedGrams,
              amountSource: AmountSource.fromPoints,
            );
          } else if (food.count != null &&
              m.meal != null &&
              _pieceGrams(food.name, m.meal!) != null) {
            fixed[i] = PlanFood(
              source: food,
              meal: m.meal,
              grams: PointsCalc.roundPracticalGrams(
                food.count! * _pieceGrams(food.name, m.meal!)!,
              ),
              amountSource: AmountSource.fromCount,
            );
          } else {
            free.add(i);
          }
        }
        final budget = budgets[slot.id];
        final fitted = <int, double>{};
        final canFit = free
            .where(
              (i) =>
                  (matched[i].$2.meal?.nutriments.macroPointsFor(100).total ??
                      0) >
                  0,
            )
            .toList();
        if (fitToBudget && budget != null && canFit.isNotEmpty) {
          final used = fixed.values.fold(
            MacroPoints.zero,
            (sum, f) => sum + f.points,
          );
          final grams = MenuAmountSolver.solve(
            per100: [
              for (final i in canFit)
                matched[i].$2.meal!.nutriments.macroPointsFor(100),
            ],
            budget: budget - used,
          );
          for (var k = 0; k < canFit.length; k++) {
            fitted[canFit[k]] = grams[k];
          }
        }
        final foods = <PlanFood>[
          for (var i = 0; i < matched.length; i++)
            fixed[i] ??
                (fitted[i] != null
                    ? PlanFood(
                        source: matched[i].$1,
                        meal: matched[i].$2.meal,
                        grams: fitted[i]!,
                        amountSource: AmountSource.fitted,
                      )
                    : PlanFood(
                        source: matched[i].$1,
                        meal: matched[i].$2.meal,
                        grams: PointsCalc.roundPracticalGrams(
                          matched[i].$2.usual ??
                              (matched[i].$1.count != null
                                  ? matched[i].$1.count! * 100
                                  : 100),
                        ),
                        amountSource: AmountSource.usual,
                      )),
        ];
        // Two imported meals for the same user meal are merged.
        final existing = meals.indexWhere((m) => m.slot.id == slot!.id);
        if (existing >= 0) {
          meals[existing] = PlanMeal(
            source: meals[existing].source,
            slot: slot,
            foods: [...meals[existing].foods, ...foods],
          );
        } else {
          meals.add(PlanMeal(source: meal, slot: slot, foods: foods));
        }
      }
      result.add(PlanDay(source: day, date: dates[d], meals: meals));
    }
    return result;
  }

  /// What one piece of a food weighs: its household unit when EatPoint
  /// knows it ("2 huevos" → 2 × 50 g), else its serving size.
  static double? _pieceGrams(String name, MealEntity meal) {
    final portion =
        (FoodKnowledge.instance?.match(name) ??
                FoodKnowledge.instance?.match(meal.name ?? ''))
            ?.mainPortion;
    if (portion != null) return portion.grams;
    final serving = meal.servingQuantity;
    return serving != null && serving > 0 ? serving : null;
  }

  /// The planner day for [day], added to [existing] or replacing it.
  /// Foods without nutrition are left out.
  static DayPlan toDayPlan(
    PlanDay day,
    DayPlan existing, {
    bool replace = false,
  }) {
    var plan = replace ? DayPlan.empty(day.date) : existing;
    for (final meal in day.meals) {
      final items = [
        for (final f in meal.foods)
          if (f.meal != null && f.grams > 0)
            PlannedItem(
              id: IdGenerator.getUniqueID(),
              meal: f.meal!,
              amount: f.grams,
              unit: f.meal!.isLiquid ? 'ml' : 'g',
            ),
      ];
      if (items.isEmpty) continue;
      plan = plan.withMeal(meal.slot.id, [
        if (!replace) ...plan.itemsFor(meal.slot.id),
        ...items,
      ]);
    }
    return plan;
  }
}
