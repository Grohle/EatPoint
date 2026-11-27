import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/menu_import/data/remote_menu_extractor.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_import_plan.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

MealEntity _food(String name, double kcal, double c, double p, double f) =>
    MealEntity(
      code: name,
      name: name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: 60,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: c,
        fat100: f,
        proteins100: p,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

void main() {
  final rice = _food('rice', 123, 26, 2.7, 1);
  final chicken = _food('chicken', 120, 0, 23, 2.6);
  final egg = _food('egg', 143, 0.7, 12.6, 9.5);
  final slots = [
    MealSlot.builtIn()[0],
    const MealSlot(
      id: 'm-mid',
      name: 'Media mañana',
      baseType: IntakeTypeEntity.snack,
      share: MacroPoints(carbs: 0.1, protein: 0.1, fat: 0.1),
    ),
    ...MealSlot.builtIn().skip(1),
  ];
  String nameOf(MealSlot s) => s.name ?? s.baseType.name;

  group('slotForLabel', () {
    test('exact name, concept words in both languages, built-in fallback', () {
      expect(
        MenuImportPlanner.slotForLabel('Desayuno', slots, nameOf)!.id,
        'breakfast',
      );
      expect(
        MenuImportPlanner.slotForLabel('Mid-morning', slots, nameOf)!.id,
        'm-mid',
      );
      expect(
        MenuImportPlanner.slotForLabel('MEDIA MAÑANA', slots, nameOf)!.id,
        'm-mid',
      );
      // Merienda is an afternoon snack, not the mid-morning one.
      expect(
        MenuImportPlanner.slotForLabel('Merienda', slots, nameOf)!.id,
        'snack',
      );
      expect(
        MenuImportPlanner.slotForLabel('Cena', slots, nameOf)!.id,
        'dinner',
      );
      expect(MenuImportPlanner.slotForLabel('Picnic', slots, nameOf), isNull);
    });
  });

  group('datesFor', () {
    test(
      'weekdays land in the week of the start, a repeat starts the next',
      () {
        final dates = MenuImportPlanner.datesFor(const [
          ImportedDay(weekday: 1),
          ImportedDay(weekday: 3),
          ImportedDay(weekday: 1),
        ], DateTime(2026, 11, 25)); // a Wednesday
        expect(dates, [
          DateTime(2026, 11, 23),
          DateTime(2026, 11, 25),
          DateTime(2026, 11, 30),
        ]);
      },
    );

    test('numbered and unnamed days count from the start', () {
      final dates = MenuImportPlanner.datesFor(const [
        ImportedDay(index: 1),
        ImportedDay(index: 3),
        ImportedDay(),
      ], DateTime(2026, 12, 1));
      expect(dates, [
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 3),
        DateTime(2026, 12, 4),
      ]);
    });
  });

  group('build', () {
    ({MealEntity? meal, double? usual}) match(ImportedFood f) => (
      meal: {'rice': rice, 'chicken': chicken, 'egg': egg}[f.name],
      usual: null,
    );

    test(
      'given grams stay, counts use the serving, the rest fits the budget',
      () {
        final menu = MenuTextParser.parse(
          'Lunes\nComida: rice, chicken 150 g, 2 egg',
        );
        final plan = MenuImportPlanner.build(
          menu: menu,
          slots: slots,
          nameOf: nameOf,
          start: DateTime(2026, 11, 23),
          match: match,
          budgets: const {'lunch': MacroPoints(carbs: 3, protein: 3, fat: 1.5)},
        );
        final meal = plan.single.meals.single;
        expect(meal.slot.id, 'lunch');
        final byName = {for (final f in meal.foods) f.source.name: f};
        expect(byName['chicken']!.grams, 150);
        expect(byName['chicken']!.amountSource, AmountSource.given);
        expect(byName['egg']!.grams, 120);
        expect(byName['egg']!.amountSource, AmountSource.fromCount);
        expect(byName['rice']!.amountSource, AmountSource.fitted);
        // Rice fills the carbs that are left: about 3 points.
        expect(byName['rice']!.points.carbs, closeTo(3, 0.5));
      },
    );

    test('points are converted to grams', () {
      final plan = MenuImportPlanner.build(
        menu: MenuTextParser.parse('Desayuno: rice 2 pts'),
        slots: slots,
        nameOf: nameOf,
        start: DateTime(2026, 11, 23),
        match: match,
      );
      final rice = plan.single.meals.single.foods.single;
      expect(rice.amountSource, AmountSource.fromPoints);
      expect(rice.points.total, closeTo(2, 0.1));
    });

    test('toDayPlan adds to or replaces the day, skipping unmatched foods', () {
      final plan = MenuImportPlanner.build(
        menu: MenuTextParser.parse('Cena: chicken 100 g, unicorn 50 g'),
        slots: slots,
        nameOf: nameOf,
        start: DateTime(2026, 11, 23),
        match: match,
      ).single;
      final existing = DayPlan(
        date: DateTime(2026, 11, 23),
        meals: {
          'dinner': [PlannedItem(id: 'x', meal: rice, amount: 100, unit: 'g')],
        },
      );
      final added = MenuImportPlanner.toDayPlan(plan, existing);
      expect(added.itemsFor('dinner').map((i) => i.name), ['rice', 'chicken']);
      final replaced = MenuImportPlanner.toDayPlan(
        plan,
        existing,
        replace: true,
      );
      expect(replaced.itemsFor('dinner').map((i) => i.name), ['chicken']);
    });
  });

  group('RemoteMenuExtractor.parseResponse', () {
    test('reads days, meals, foods and estimates, dropping bad values', () {
      final menu = RemoteMenuExtractor.parseResponse('''
Here you go:
```json
{"days":[{"day":"tuesday","meals":[{"meal":"Lunch","dish":"Stew",
"foods":[{"name":"lentils","grams":80,"kcal100":116,"carbs100":20,
"protein100":9,"fat100":0.4},{"name":"chorizo","grams":-5},
{"name":"","grams":10}]}]},{"day":"2026-12-03","meals":[]}]}
```''');
      expect(menu.days, hasLength(1));
      final day = menu.days.single;
      expect(day.weekday, 2);
      final foods = day.meals.single.foods;
      expect(foods.map((f) => f.name), ['lentils', 'chorizo']);
      expect(foods.first.amount, 80);
      expect(foods.first.per100!.kcal, 116);
      expect(foods[1].amount, isNull);
      expect(day.meals.single.dish, 'Stew');
    });
  });
}
