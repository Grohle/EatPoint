import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/food_db/presentation/my_foods_screen.dart';
import 'package:opennutritracker/features/food_knowledge/data/portion_override_store.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

class _Custom extends Fake implements CustomMealDataSource {
  final meals = <MealDBO>[];
  final _changes = StreamController<void>.broadcast();

  @override
  List<MealDBO> getAllCustomMeals() => meals;

  @override
  Stream<void> watch() => _changes.stream;

  @override
  Future<void> deleteCustomMeal(String mealKey) async {
    meals.removeWhere((m) => (m.code ?? m.name) == mealKey);
    _changes.add(null);
  }
}

MealDBO _meal(String name) => MealDBO.fromMealEntity(
  MealEntity(
    code: null,
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 300,
      carbohydrates100: 50,
      fat100: 8,
      proteins100: 9,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  ),
);

void main() {
  late _Custom custom;
  late PortionOverrideStore portions;

  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    custom = _Custom()..meals.add(_meal('Tortillas de la abuela'));
    portions = PortionOverrideStore(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    locator.registerSingleton<PortionOverrideStore>(portions);
    FoodPortions.configure(user: portions.portionFor);
  });

  tearDown(() async {
    FoodPortions.configure();
    await locator.reset();
  });

  testWidgets('lists my foods, searches the catalogue and sets a weight', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        MyFoodsScreen(customMeals: custom),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(MyFoodsScreen)));
    expect(find.text('Tortillas de la abuela'), findsOneWidget);
    expect(find.text(s.myFoodsMine('1')), findsOneWidget);

    // Searching shows foods to edit from the catalogue too.
    await tester.enterText(bySemanticsId('my-foods-search'), 'huevo');
    await tester.pumpAndSettle();
    expect(find.text(s.myFoodsDatabase), findsOneWidget);
    expect(find.textContaining('Huevo'), findsWidgets);

    // My own weight for my tortillas.
    await tester.enterText(bySemanticsId('my-foods-search'), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.unitWeightChange).last);
    await tester.pumpAndSettle();
    await tester.enterText(bySemanticsId('unit-weight-grams'), '42');
    await tester.pump();
    await tester.tap(bySemanticsId('unit-weight-save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('= 42 g'), findsOneWidget);
    expect(PortionFormatter.forFood('Tortillas de la abuela', 84)!.count, 2);
  });
}
