import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/insights/domain/week_insights.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_import_plan.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
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

  GeneratedMenu run(
    DietStyle diet, {
    List<String> excluded = const [],
    int seed = 3,
  }) => MenuGenerator.generate(
    slots: slots,
    nameOf: nameOf,
    pool: corePool(),
    options: MenuGeneratorOptions(
      days: days,
      diet: diet,
      excluded: excluded,
      seed: seed,
    ),
  );

  test('fills every meal of every day', () {
    final generated = run(DietStyle.omnivore);
    expect(generated.menu.days, hasLength(7));
    for (final day in generated.menu.days) {
      expect(day.meals.map((m) => m.label), [
        'breakfast',
        'lunch',
        'snack',
        'dinner',
      ]);
      for (final meal in day.meals) {
        expect(meal.foods, isNotEmpty);
      }
    }
  });

  test('omnivore week has oily fish, pulses and no protein twice in a row', () {
    final generated = run(DietStyle.omnivore);
    final mains = [
      for (final d in generated.menu.days)
        for (final m in d.meals)
          if (m.label == 'lunch' || m.label == 'dinner') m,
    ];
    final proteins = [
      for (final m in mains) generated.foods[m.foods.first.name]!,
    ];
    expect(proteins.where((f) => f.has('oily_fish')).length, 2);
    expect(proteins.where((f) => f.has('legume')).length, 3);
    for (var i = 1; i < proteins.length; i++) {
      expect(
        proteins[i].name == proteins[i - 1].name,
        isFalse,
        reason: 'meal $i repeats ${proteins[i].name}',
      );
    }
  });

  test('vegetarian and vegan weeks leave out what they should', () {
    for (final diet in [DietStyle.vegetarian, DietStyle.vegan]) {
      final generated = run(diet);
      for (final f in generated.foods.values) {
        expect(f.has('fish'), isFalse, reason: '$diet ${f.name}');
        expect(
          f.conceptId,
          isNot(anyOf('chicken_breast', 'beef_steak', 'pork_loin')),
        );
        if (diet == DietStyle.vegan) {
          expect(
            f.conceptId,
            isNot(anyOf('egg', 'milk', 'yogurt', 'cheese_slice')),
          );
        }
      }
    }
  });

  test('excluded words are respected', () {
    final generated = run(DietStyle.omnivore, excluded: ['salmón', 'cerdo']);
    expect(
      generated.foods.keys.any(
        (n) =>
            FoodKnowledge.fold(n).contains('salmon') ||
            FoodKnowledge.fold(n).contains('cerdo'),
      ),
      isFalse,
    );
  });

  test('the generated week, fitted to a budget, earns good suggestions', () {
    final generated = run(DietStyle.omnivore);
    final budget = slots.budgets(
      const MacroPoints(carbs: 10, protein: 7.5, fat: 5.25),
    );
    final plan = MenuImportPlanner.build(
      menu: generated.menu,
      slots: slots,
      nameOf: nameOf,
      start: days.first,
      budgets: budget,
      match: (f) => (meal: generated.foods[f.name]?.meal, usual: null),
    );
    final week = [
      for (final d in plan)
        MenuImportPlanner.toDayPlan(d, DayPlan.empty(d.date)),
    ];
    // Every day lands close to its budget.
    for (final d in week) {
      expect(d.totalPoints.total, closeTo(22.75, 4.5));
    }
    final insights = WeekInsights.analyse(week, knowledge: knowledge);
    final suggestions = {
      for (final i in insights)
        if (i.isSuggestion) i.kind,
    };
    expect(suggestions, isNot(contains(InsightKind.oilyFishMissing)));
    expect(suggestions, isNot(contains(InsightKind.legumesLow)));
    expect(suggestions, isNot(contains(InsightKind.b12Missing)));
    expect(suggestions, isNot(contains(InsightKind.varietyLow)));
  });

  test('the same seed gives the same week, another seed a different one', () {
    List<String> names(GeneratedMenu g) => [
      for (final d in g.menu.days)
        for (final m in d.meals)
          for (final f in m.foods) f.name,
    ];
    expect(
      names(run(DietStyle.omnivore, seed: 5)),
      names(run(DietStyle.omnivore, seed: 5)),
    );
    expect(
      names(run(DietStyle.omnivore, seed: 5)),
      isNot(names(run(DietStyle.omnivore, seed: 6))),
    );
  });

  test('meal kinds come from the slot types', () {
    expect(
      slots.where((s) => s.baseType == IntakeTypeEntity.lunch),
      hasLength(1),
    );
  });
}
