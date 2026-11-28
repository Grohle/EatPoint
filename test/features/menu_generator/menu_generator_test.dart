import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/insights/domain/week_insights.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
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

  group('with a diet profile', () {
    GeneratedMenu withProfile(DietProfile profile, {int seed = 3}) =>
        MenuGenerator.generate(
          slots: slots,
          nameOf: nameOf,
          pool: corePool(),
          options: MenuGeneratorOptions(
            days: days,
            seed: seed,
            checker: DietChecker(profile),
            languageCode: 'es',
          ),
        );

    List<String> names(GeneratedMenu g) => [
      for (final d in g.menu.days)
        for (final m in d.meals)
          for (final f in m.foods) f.name,
    ];

    test('lactose and gluten intolerance keep dairy and bread, free-from', () {
      final g = withProfile(
        const DietProfile(
          intolerances: {Intolerance.lactose, Intolerance.gluten},
        ),
      );
      final all = names(g);
      final milky = all.where((n) => RegExp(r'^(Leche|Yogur)').hasMatch(n));
      expect(milky, isNotEmpty);
      expect(milky.every((n) => n.contains('sin lactosa')), isTrue);
      final breads = all.where((n) => n.startsWith('Pan') || n.startsWith('Pasta'));
      expect(breads, isNotEmpty);
      expect(breads.every((n) => n.contains('sin gluten')), isTrue);
      // The review can still find each food by its new name.
      for (final n in all) {
        expect(g.foods.containsKey(n), isTrue, reason: n);
      }
    });

    test('allergies leave foods out entirely', () {
      final g = withProfile(
        const DietProfile(
          allergies: {Allergen.milk, Allergen.fish, Allergen.treeNuts},
        ),
      );
      const checker = DietChecker(
        DietProfile(
          allergies: {Allergen.milk, Allergen.fish, Allergen.treeNuts},
        ),
      );
      for (final n in names(g)) {
        expect(checker.blocks(n), isFalse, reason: n);
      }
    });

    test('halal leaves out pork; the profile diet wins', () {
      final g = withProfile(
        const DietProfile(
          diet: DietStyle.pescatarian,
          religion: ReligiousDiet.halal,
        ),
      );
      for (final n in names(g)) {
        final traits = DietChecker.traitsOf(n);
        expect(traits.contains(DietTrait.pork), isFalse, reason: n);
        expect(traits.contains(DietTrait.meat), isFalse, reason: n);
      }
    });

    test('liked foods come up more often', () {
      int count(GeneratedMenu g, String word) =>
          names(g).where((n) => n.toLowerCase().contains(word)).length;
      var plain = 0;
      var liked = 0;
      for (var seed = 1; seed <= 5; seed++) {
        plain += count(withProfile(const DietProfile(), seed: seed), 'mango');
        liked += count(
          withProfile(const DietProfile(likes: ['mango']), seed: seed),
          'mango',
        );
      }
      expect(liked, greaterThan(plain));
    });
  });

  // EatPoint: variety, and the user's fixed foods.
  group('variety and fixed foods', () {
    Set<String> dayFoods(ImportedDay day, {bool skipLeftovers = true}) => {
      for (final meal in day.meals)
        if (!skipLeftovers || meal.dish == null)
          for (final f in meal.foods)
            if (!FoodKnowledge.fold(f.name).contains('aceite')) f.name,
    };

    for (final efficient in [false, true]) {
      test('no food two days running (efficient: $efficient)', () {
        for (final seed in [1, 2, 3, 4, 5]) {
          final menu = MenuGenerator.generate(
            slots: slots,
            nameOf: nameOf,
            pool: corePool(),
            options: MenuGeneratorOptions(
              days: days,
              seed: seed,
              efficient: efficient,
              leftoversLabel: 'Sobras',
            ),
          ).menu;
          for (var i = 1; i < menu.days.length; i++) {
            final today = dayFoods(menu.days[i]);
            final yesterday = dayFoods(menu.days[i - 1], skipLeftovers: false);
            expect(
              today.intersection(yesterday),
              isEmpty,
              reason: 'seed $seed, day $i',
            );
          }
        }
      });
    }

    test('an efficient week still buys fewer products than a varied one', () {
      Set<String> distinct(bool efficient) => {
        for (final day in MenuGenerator.generate(
          slots: slots,
          nameOf: nameOf,
          pool: corePool(),
          options: MenuGeneratorOptions(
            days: days,
            seed: 3,
            efficient: efficient,
          ),
        ).menu.days)
          ...dayFoods(day, skipLeftovers: false),
      };
      expect(distinct(true).length, lessThan(distinct(false).length));
    });

    test('fixed foods are in their meal every day, in place of the choice', () {
      final pool = corePool();
      final bread = pool.firstWhere((f) => f.conceptId == 'bread_slice');
      final milk = pool.firstWhere((f) => f.conceptId == 'milk');
      final breakfast = slots.firstWhere(
        (s) => s.baseType == IntakeTypeEntity.breakfast,
      );
      final menu = MenuGenerator.generate(
        slots: slots,
        nameOf: nameOf,
        pool: pool,
        options: MenuGeneratorOptions(
          days: days,
          seed: 2,
          efficient: true,
          fixed: {
            breakfast.id: [FixedFood(bread, 62), FixedFood(milk, 200)],
          },
        ),
      ).menu;
      for (final day in menu.days) {
        final meal = day.meals.firstWhere((m) => m.label == 'breakfast');
        final names = meal.foods.map((f) => f.name).toList();
        expect(names.where((n) => n == bread.name), hasLength(1));
        expect(names.where((n) => n == milk.name), hasLength(1));
        expect(meal.foods.firstWhere((f) => f.name == milk.name).amount, 200);
        // Milk took the drink's place: no yogurt besides it.
        expect(
          meal.foods.where(
            (f) => pool
                .where((p) => p.name == f.name)
                .any((p) => p.conceptId == 'yogurt'),
          ),
          isEmpty,
        );
      }
    });
  });
}
