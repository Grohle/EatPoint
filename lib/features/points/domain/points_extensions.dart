import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// Points of a food, worked out from its nutrition per 100 g / 100 ml.
extension MealNutrimentsPoints on MealNutrimentsEntity {
  /// Points per 100 g (or ml), or null when the energy is unknown.
  double? get pointsPer100 {
    final kcal = energyKcal100;
    if (kcal == null) return null;
    return PointsCalc.pointsPer100g(kcal);
  }

  /// The exact split of the food's points between carbohydrate, protein and
  /// fat. Null when the macros are unknown or all zero.
  PointsProfile? get pointsProfile => PointsCalc.profileFromMacros(
    carbs: carbohydrates100 ?? 0,
    protein: proteins100 ?? 0,
    fat: fat100 ?? 0,
  );

  /// The points in [grams] of the food, split by macronutrient. A food with
  /// energy but no macros counts as carbohydrate, the most common case for
  /// such entries (drinks, sweets).
  MacroPoints macroPointsFor(double grams) {
    final per100 = pointsPer100;
    if (per100 == null || grams <= 0) return MacroPoints.zero;
    final points = grams * per100 / 100;
    return PointsCalc.split(points, pointsProfile ?? PointsProfile.carbsOnly);
  }
}

extension MealEntityPoints on MealEntity {
  double? get pointsPer100 => nutriments.pointsPer100;
  PointsProfile? get pointsProfile => nutriments.pointsProfile;
}

extension IntakePoints on IntakeEntity {
  /// The points of this logged amount. Intakes store their amount already
  /// converted to grams or ml, so the total is simply its energy / 100.
  MacroPoints get macroPoints {
    final points = totalKcal / PointsCalc.kcalPerPoint;
    if (points <= 0) return MacroPoints.zero;
    final profile = meal.nutriments.pointsProfile ?? PointsProfile.carbsOnly;
    return PointsCalc.split(points, profile);
  }
}

extension IntakeListPoints on Iterable<IntakeEntity> {
  MacroPoints get macroPoints =>
      fold(MacroPoints.zero, (sum, intake) => sum + intake.macroPoints);
}
