import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';

import 'planner_test_support.dart';

void main() {
  final monday = DateTime(2026, 11, 23);

  String aisleName(ShoppingAisle a) => a.name;

  group('build', () {
    test('sums the same food across days and meals', () {
      final plans = [
        (
          owner: 'me',
          plan: dayPlan(monday, {
            IntakeTypeEntity.lunch: [plannedItem('Arroz', 100)],
            IntakeTypeEntity.dinner: [plannedItem('arroz', 50)],
          }),
        ),
        (
          owner: 'me',
          plan: dayPlan(monday.add(const Duration(days: 1)), {
            IntakeTypeEntity.lunch: [plannedItem('Arroz', 25)],
          }),
        ),
      ];
      final items = ShoppingListBuilder.build(plans);
      expect(items, hasLength(1));
      expect(items.single.amount, 175);
      expect(items.single.unit, 'g');
      expect(items.single.aisle, ShoppingAisle.pantry);
    });

    test('keeps g and ml of the same name apart', () {
      final items = ShoppingListBuilder.build([
        (
          owner: 'me',
          plan: dayPlan(monday, {
            IntakeTypeEntity.lunch: [
              plannedItem('Leche', 100),
              plannedItem('Leche', 200, unit: 'ml'),
            ],
          }),
        ),
      ]);
      expect(items, hasLength(2));
    });

    test('splits the amount per owner', () {
      final items = ShoppingListBuilder.build([
        (
          owner: 'a',
          plan: dayPlan(monday, {
            IntakeTypeEntity.lunch: [plannedItem('Pollo', 100)],
          }),
        ),
        (
          owner: 'b',
          plan: dayPlan(monday, {
            IntakeTypeEntity.lunch: [plannedItem('Pollo', 150)],
          }),
        ),
      ]);
      expect(items.single.amount, 250);
      expect(items.single.perOwner, {'a': 100, 'b': 150});
    });

    test('expands recipes into scaled ingredients', () {
      final plans = [
        (
          owner: 'me',
          plan: dayPlan(monday, {
            IntakeTypeEntity.dinner: [
              plannedItem(
                'Paella',
                300,
                source: MealSourceEntity.recipe,
                code: 'r1',
              ),
            ],
          }),
        ),
      ];
      final items = ShoppingListBuilder.build(
        plans,
        recipeIngredients: (meal, grams) {
          expect(meal.code, 'r1');
          // The recipe weighs 600 g: 300 g of dish is half of it.
          final factor = grams / 600;
          return [
            (meal: plannerMeal('Arroz'), grams: 200 * factor),
            (meal: plannerMeal('Pollo'), grams: 400 * factor),
          ];
        },
      );
      expect(items.map((i) => i.name), ['Pollo', 'Arroz']);
      expect(items.firstWhere((i) => i.name == 'Arroz').amount, 100);
      expect(items.firstWhere((i) => i.name == 'Pollo').amount, 200);
    });

    test('keeps the recipe itself when it cannot be expanded', () {
      final items = ShoppingListBuilder.build([
        (
          owner: 'me',
          plan: dayPlan(monday, {
            IntakeTypeEntity.dinner: [
              plannedItem('Paella', 300, source: MealSourceEntity.recipe),
            ],
          }),
        ),
      ], recipeIngredients: (_, _) => null);
      expect(items.single.name, 'Paella');
    });

    test('ignores empty names and non-positive amounts, sorts by aisle', () {
      final items = ShoppingListBuilder.build([
        (
          owner: 'me',
          plan: dayPlan(monday, {
            IntakeTypeEntity.lunch: [
              plannedItem('Zanahoria', 80),
              plannedItem('Pollo', 120),
              plannedItem('  ', 50),
              plannedItem('Arroz', 0),
            ],
          }),
        ),
      ]);
      expect(items.map((i) => i.name), ['Zanahoria', 'Pollo']);
    });
  });

  group('aisleFor', () {
    test('"tomate frito" is pantry, "tomate" is produce', () {
      expect(
        ShoppingListBuilder.aisleFor('Tomate frito'),
        ShoppingAisle.pantry,
      );
      expect(ShoppingListBuilder.aisleFor('Tomate'), ShoppingAisle.produce);
    });

    test('Spanish and English names', () {
      expect(
        ShoppingListBuilder.aisleFor('Pechuga de pollo'),
        ShoppingAisle.meatFish,
      );
      expect(
        ShoppingListBuilder.aisleFor('Chicken breast'),
        ShoppingAisle.meatFish,
      );
      expect(
        ShoppingListBuilder.aisleFor('Leche entera'),
        ShoppingAisle.dairyEggs,
      );
      expect(
        ShoppingListBuilder.aisleFor('Greek yogurt'),
        ShoppingAisle.dairyEggs,
      );
      expect(
        ShoppingListBuilder.aisleFor('Pan integral'),
        ShoppingAisle.bakery,
      );
      expect(ShoppingListBuilder.aisleFor('Plátano'), ShoppingAisle.produce);
      expect(
        ShoppingListBuilder.aisleFor('Zumo de naranja'),
        ShoppingAisle.produce,
      );
      expect(ShoppingListBuilder.aisleFor('Rice'), ShoppingAisle.pantry);
      expect(ShoppingListBuilder.aisleFor('Café'), ShoppingAisle.drinks);
      expect(ShoppingListBuilder.aisleFor('Xyzzy'), ShoppingAisle.other);
    });

    test('keywords match at the start of a word only', () {
      // "pan" must not match inside "campana"/"japan".
      expect(ShoppingListBuilder.aisleFor('Campana'), ShoppingAisle.other);
    });
  });

  group('export', () {
    final items = [
      const ShoppingItem(
        key: 'a|g',
        name: 'Arroz, integral',
        amount: 250.4,
        unit: 'g',
        aisle: ShoppingAisle.pantry,
      ),
      const ShoppingItem(
        key: 'b|g',
        name: 'Salsa "casera"',
        amount: 1200,
        unit: 'g',
        aisle: ShoppingAisle.pantry,
      ),
      const ShoppingItem(
        key: 'c|ml',
        name: 'Agua',
        amount: 500,
        unit: 'ml',
        aisle: ShoppingAisle.drinks,
      ),
    ];

    test('toText groups by aisle and shows ticks', () {
      final text = ShoppingListBuilder.toText(
        items,
        {'a|g'},
        aisleName: aisleName,
        amountText: (i) => '${i.amount.round()} ${i.unit}',
      );
      expect(
        text,
        'PANTRY\n'
        '☑ Arroz, integral — 250 g\n'
        '☐ Salsa "casera" — 1200 g\n'
        '\n'
        'DRINKS\n'
        '☐ Agua — 500 ml',
      );
    });

    test('toCsv escapes commas and quotes', () {
      final csv = ShoppingListBuilder.toCsv(
        items,
        {'b|g'},
        aisleName: aisleName,
        header: ['Aisle', 'Item', 'Amount', 'Unit', 'Done'],
      );
      expect(csv.split('\n'), [
        'Aisle,Item,Amount,Unit,Done',
        'pantry,"Arroz, integral",250,g,0',
        'pantry,"Salsa ""casera""",1200,g,1',
        'drinks,Agua,500,ml,0',
      ]);
    });
  });
}
