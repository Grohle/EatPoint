import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/member_menu_adapter.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

void main() {
  final knowledge = FoodKnowledge.parse(
    File(FoodKnowledge.assetPath).readAsStringSync(),
  );
  setUpAll(() => FoodKnowledge.setInstance(knowledge));

  List<GenFood> corePool() => [
    for (final f in knowledge.foods)
      GenFood.of(f.toMealEntity('es'), knowledge: knowledge),
  ];
  final slots = [...MealSlot.builtIn()];
  String nameOf(MealSlot s) => s.baseType.name;
  final days = [for (var i = 0; i < 7; i++) DateTime(2026, 11, 23 + i)];

  GeneratedMenu run({
    bool efficient = false,
    List<MenuCompanion> companions = const [],
    int seed = 3,
  }) => MenuGenerator.generate(
    slots: slots,
    nameOf: nameOf,
    pool: corePool(),
    options: MenuGeneratorOptions(
      days: days,
      seed: seed,
      efficient: efficient,
      companions: companions,
      leftoversLabel: 'Leftovers',
    ),
  );

  Set<String> distinct(GeneratedMenu g) => {
    for (final d in g.menu.days)
      for (final m in d.meals)
        for (final f in m.foods) f.name,
  };

  test('an efficient week buys fewer different products', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      final normal = distinct(run(seed: seed)).length;
      final efficient = distinct(run(seed: seed, efficient: true)).length;
      expect(
        efficient,
        lessThan(normal * 0.75),
        reason: 'seed $seed: $efficient vs $normal products',
      );
    }
  });

  test('every other lunch is the previous dinner\'s leftovers', () {
    final g = run(efficient: true);
    for (var d = 1; d < g.menu.days.length; d += 2) {
      final lunch = g.menu.days[d].meals.firstWhere((m) => m.label == 'lunch');
      final dinner = g.menu.days[d - 1].meals.firstWhere(
        (m) => m.label == 'dinner',
      );
      expect(lunch.dish, 'Leftovers');
      expect(
        lunch.foods.map((f) => f.name).toList(),
        dinner.foods.map((f) => f.name).toList(),
      );
    }
  });

  test('fish comes early in the week, pulses late', () {
    final g = run(efficient: true);
    final mains = [
      for (final d in g.menu.days)
        for (final m in d.meals)
          if ((m.label == 'lunch' || m.label == 'dinner') && m.dish == null) m,
    ];
    int? firstFish;
    int? lastLegume;
    for (var i = 0; i < mains.length; i++) {
      final proteins = mains[i].foods
          .map((f) => g.foods[f.name])
          .whereType<GenFood>();
      if (firstFish == null && proteins.any((f) => f.has('fish'))) {
        firstFish = i;
      }
      if (proteins.any(
        (f) => MenuGenerator.isProteinKind(f, ProteinKind.legume),
      )) {
        lastLegume = i;
      }
    }
    expect(firstFish, isNotNull);
    expect(lastLegume, isNotNull);
    expect(firstFish!, lessThan(lastLegume!));
    expect(firstFish, lessThan(3));
  });

  test('cooking for a vegetarian shares dishes and swaps only what '
      'they can\'t eat', () {
    final vegetarian = MenuCompanion(
      diet: DietStyle.vegetarian,
      checker: DietChecker(const DietProfile(diet: DietStyle.vegetarian)),
    );
    final pool = corePool();
    final g = MenuGenerator.generate(
      slots: slots,
      nameOf: nameOf,
      pool: pool,
      options: MenuGeneratorOptions(
        days: days,
        seed: 3,
        companions: [vegetarian],
      ),
    );
    final meals = MemberMenuAdapter.adapt(
      menu: g.menu,
      foods: g.foods,
      mySlots: slots,
      myNameOf: nameOf,
      theirSlots: slots,
      theirBudgets: {
        for (final s in slots)
          s.id: const MacroPoints(carbs: 5, protein: 3, fat: 2),
      },
      pool: pool,
      them: vegetarian,
      languageCode: 'es',
      start: days.first,
    );
    expect(meals, hasLength(28));
    var shared = 0;
    for (final meal in meals) {
      for (final item in meal.items) {
        expect(
          vegetarian.canEat(GenFood.of(item.meal, knowledge: knowledge)),
          isTrue,
          reason: '${item.name} on ${meal.date}',
        );
      }
      final day = g.menu.days[meal.date.difference(days.first).inDays];
      final mine = day.meals
          .firstWhere(
            (m) => m.label == slots.byIdOrNull(meal.slotId)!.baseType.name,
          )
          .foods
          .map((f) => f.name)
          .toSet();
      if (meal.items.every((i) => mine.contains(i.name))) shared++;
    }
    expect(
      shared,
      greaterThan(meals.length ~/ 2),
      reason: 'most meals are the same dish for both',
    );
    // Their portions are fitted to their own points.
    final lunch = meals.firstWhere(
      (m) => m.slotId == IntakeTypeEntity.lunch.name,
    );
    final points = lunch.items.fold(
      MacroPoints.zero,
      (sum, i) => sum + i.points,
    );
    expect(points.total, closeTo(10, 3));
  });
}

extension on List<MealSlot> {
  MealSlot? byIdOrNull(String id) => where((s) => s.id == id).firstOrNull;
}
