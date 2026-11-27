import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

export '../points/points_test_support.dart'
    show MemoryStringBox, localizedApp, bySemanticsId;

MealEntity plannerMeal(
  String name, {
  MealSourceEntity source = MealSourceEntity.custom,
  String? code,
  bool liquid = false,
}) => MealEntity(
  code: code ?? name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: liquid ? 'ml' : 'g',
  servingQuantity: null,
  servingUnit: liquid ? 'ml' : 'g',
  servingSize: null,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 10,
    fat100: 3,
    proteins100: 5,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: source,
);

PlannedItem plannedItem(
  String name,
  double amount, {
  String unit = 'g',
  MealSourceEntity source = MealSourceEntity.custom,
  String? code,
}) => PlannedItem(
  id: 'id-$name-$amount',
  meal: plannerMeal(name, source: source, code: code, liquid: unit == 'ml'),
  amount: amount,
  unit: unit,
);

DayPlan dayPlan(
  DateTime date,
  Map<IntakeTypeEntity, List<PlannedItem>> meals,
) => DayPlan(date: DateTime(date.year, date.month, date.day), meals: meals);
