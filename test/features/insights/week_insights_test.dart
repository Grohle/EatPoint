import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/insights/domain/week_insights.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

MealEntity _food(String name, {double fibre = 0}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 10,
    fat100: 3,
    proteins100: 5,
    sugars100: null,
    saturatedFat100: null,
    fiber100: fibre,
  ),
  source: MealSourceEntity.custom,
);

PlannedItem _item(String name, double grams, {double fibre = 0}) => PlannedItem(
  id: name,
  meal: _food(name, fibre: fibre),
  amount: grams,
  unit: 'g',
);

void main() {
  final knowledge = FoodKnowledge.parse(
    File(FoodKnowledge.assetPath).readAsStringSync(),
  );
  final monday = DateTime(2026, 11, 23);

  List<DayPlan> week(List<List<PlannedItem>> perDay) => [
    for (var i = 0; i < perDay.length; i++)
      DayPlan(
        date: monday.add(Duration(days: i)),
        meals: {'lunch': perDay[i]},
      ),
  ];

  Set<InsightKind> kinds(List<Insight> list, {bool suggestions = true}) => {
    for (final i in list)
      if (i.isSuggestion == suggestions) i.kind,
  };

  test('needs at least three planned days', () {
    final w = week([
      [_item('Arroz blanco', 150), _item('Pollo', 150), _item('Tomate', 100)],
      [_item('Arroz blanco', 150), _item('Pollo', 150), _item('Tomate', 100)],
    ]);
    expect(WeekInsights.analyse(w, knowledge: knowledge), isEmpty);
  });

  test('a monotonous week without fish, pulses or fibre gets suggestions', () {
    final day = [
      _item('Arroz blanco', 150),
      _item('Pechuga de pollo', 150),
      _item('Galletas', 30),
      _item('Chorizo', 60),
    ];
    final w = week(List.filled(7, day));
    final insights = WeekInsights.analyse(w, knowledge: knowledge);
    expect(
      kinds(insights),
      containsAll({
        InsightKind.fibreLow,
        InsightKind.oilyFishMissing,
        InsightKind.plantOmega3,
        InsightKind.legumesLow,
        InsightKind.fruitVegLow,
        InsightKind.wholegrainLow,
        InsightKind.processedMeatHigh,
        InsightKind.calciumLow,
        InsightKind.varietyLow,
      }),
    );
    // Chicken has B12.
    expect(kinds(insights), isNot(contains(InsightKind.b12Missing)));
  });

  test('a plant-only week is told about vitamin B12', () {
    final w = week(
      List.filled(5, [
        _item('Lentejas', 80, fibre: 10),
        _item('Arroz integral', 150, fibre: 2),
        _item('Espinacas', 100, fibre: 2),
        _item('Nueces', 25),
      ]),
    );
    final insights = WeekInsights.analyse(w, knowledge: knowledge);
    expect(kinds(insights), contains(InsightKind.b12Missing));
    // Walnuts carry plant omega-3, so that nudge is not needed.
    expect(kinds(insights), isNot(contains(InsightKind.plantOmega3)));
    expect(
      kinds(insights, suggestions: false),
      contains(InsightKind.legumesGood),
    );
  });

  test('a varied week with fish, pulses and plenty of plants is praised', () {
    final days = <List<PlannedItem>>[
      [
        _item('Salmón', 140),
        _item('Patata', 200),
        _item('Ensalada', 250, fibre: 2),
        _item('Manzana', 180, fibre: 2.4),
        _item('Yogur', 125),
        _item('Pan integral', 60, fibre: 7),
      ],
      [
        _item('Lentejas', 80, fibre: 10),
        _item('Zanahoria', 200, fibre: 3),
        _item('Naranja', 130, fibre: 2.4),
        _item('Leche', 250),
        _item('Avena', 50, fibre: 10),
        _item('Tomate', 120),
      ],
      [
        _item('Sardinas', 90),
        _item('Brócoli', 250, fibre: 3),
        _item('Pera', 160, fibre: 3),
        _item('Queso', 40),
        _item('Garbanzos', 150, fibre: 6),
        _item('Pan integral', 60, fibre: 7),
      ],
      [
        _item('Merluza', 125),
        _item('Alubias', 150, fibre: 6),
        _item('Calabacín', 300, fibre: 1),
        _item('Plátano', 120, fibre: 2.6),
        _item('Yogur', 125),
        _item('Avena', 50, fibre: 10),
      ],
    ];
    final insights = WeekInsights.analyse(week(days), knowledge: knowledge);
    expect(
      kinds(insights, suggestions: false),
      containsAll({
        InsightKind.oilyFishGood,
        InsightKind.legumesGood,
        InsightKind.fruitVegGood,
      }),
    );
    expect(kinds(insights), isNot(contains(InsightKind.b12Missing)));
    expect(kinds(insights), isNot(contains(InsightKind.oilyFishMissing)));
    // Suggestions come first.
    final firstGood = insights.indexWhere((i) => !i.isSuggestion);
    expect(insights.skip(firstGood).every((i) => !i.isSuggestion), isTrue);
  });
}
