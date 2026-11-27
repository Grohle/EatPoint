import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

void main() {
  test('1 fibre point is 5 g', () {
    expect(PointsCalc.fibrePoints(25), 5);
    expect(PointsCalc.fibrePoints(0), 0);
    expect(PointsCalc.fibrePoints(-3), 0);
  });

  test('fibre points of an amount of food', () {
    const oats = MealNutrimentsEntity(
      energyKcal100: 372,
      carbohydrates100: 59,
      fat100: 7,
      proteins100: 13,
      sugars100: null,
      saturatedFat100: null,
      fiber100: 10,
    );
    expect(oats.fibrePointsFor(50), 1); // 5 g
    const unknown = MealNutrimentsEntity(
      energyKcal100: 100,
      carbohydrates100: 10,
      fat100: 1,
      proteins100: 1,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    );
    expect(unknown.fibrePointsFor(100), 0);
  });

  test('the daily minimum is split by the meals carb shares', () {
    final slots = MealSlot.builtIn();
    final targets = slots.fibreTargets(5);
    expect(targets.values.fold(0.0, (a, b) => a + b), 5);
    for (final v in targets.values) {
      expect((v / PointsCalc.pointStep) % 1, 0);
    }
    // Breakfast and lunch carry the biggest carb shares.
    expect(targets['breakfast']! >= targets['dinner']!, isTrue);
  });

  test('fibre target setting round-trips and rejects nonsense', () {
    final s = PointsSettings.defaults.copyWith(fibreTargetGrams: 30);
    expect(PointsSettings.fromJson(s.toJson()).fibreTargetGrams, 30);
    expect(
      PointsSettings.fromJson({'fibreTargetGrams': -4}).fibreTargetGrams,
      PointsSettings.defaultFibreTargetGrams,
    );
    expect(
      PointsSettings.fromJson({}).fibreTargetGrams,
      PointsSettings.defaultFibreTargetGrams,
    );
  });
}
