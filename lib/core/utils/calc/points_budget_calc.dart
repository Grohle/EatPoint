import 'dart:math' as math;

import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';

/// How the daily points budget is worked out.
enum PointsBudgetMethod {
  /// Calories from lean body mass (Cunningham), protein set first from lean
  /// mass, the rest split between carbohydrate and fat. The default.
  leanMass,

  /// The app's own calorie goal and macro percentages, converted to points.
  appMacros,
}

/// Body-composition reference used for the body-fat estimate.
enum BodyFatReference { male, female, averaged }

/// Settings for [PointsBudgetMethod.leanMass]. Every value can be changed by
/// the user; the defaults are the method's starting values.
class LeanMassBudgetSettings {
  /// Share of maintenance calories to eat, e.g. 0.75 for a 25 % deficit.
  final double calorieAdjustment;

  /// Grams of protein per kg of lean body mass.
  final double proteinGramsPerKgLeanMass;

  /// Share of the non-protein calories that go to carbohydrate; the rest
  /// goes to fat.
  final double carbShareOfRemainder;

  const LeanMassBudgetSettings({
    this.calorieAdjustment = 1.0,
    this.proteinGramsPerKgLeanMass = 1.5,
    this.carbShareOfRemainder = 0.65,
  });

  /// Starting adjustment for each weight goal: a 25 % deficit to lose
  /// weight, maintenance, or a 10 % surplus to gain.
  static const loseWeightAdjustment = 0.75;
  static const maintainWeightAdjustment = 1.0;
  static const gainWeightAdjustment = 1.10;
}

/// A daily budget and how it was reached, so the screen can explain it.
class PointsBudget {
  final PointsBudgetMethod method;
  final double kcalGoal;

  /// Budget before rounding.
  final MacroPoints exact;

  /// Budget rounded to quarter points, which is what the user plans with.
  final MacroPoints rounded;

  /// Only set for [PointsBudgetMethod.leanMass].
  final double? bodyFatPercent;
  final double? leanMassKg;
  final double? maintenanceKcal;
  final double? proteinGrams;

  const PointsBudget({
    required this.method,
    required this.kcalGoal,
    required this.exact,
    required this.rounded,
    this.bodyFatPercent,
    this.leanMassKg,
    this.maintenanceKcal,
    this.proteinGrams,
  });
}

/// Suggests a daily points budget and splits it across meals.
///
/// Every result is a guide only: a starting point to adjust as the user
/// tracks their progress, not medical or dietetic advice. Screens that show
/// it must say so.
class PointsBudgetCalc {
  /// Activity multipliers for resting energy expenditure, from sedentary to
  /// very active.
  static const sedentaryMultiplier = 1.2;
  static const lightlyActiveMultiplier = 1.375;
  static const moderatelyActiveMultiplier = 1.55;
  static const veryActiveMultiplier = 1.725;
  static const extraActiveMultiplier = 1.9;

  /// Default split of each macro's daily points across meals. Morning and
  /// afternoon snacks share the snack slot.
  static const Map<IntakeTypeEntity, MacroPoints> defaultMealSplit = {
    IntakeTypeEntity.breakfast: MacroPoints(carbs: 0.3, protein: 0.05, fat: 0.4),
    IntakeTypeEntity.lunch: MacroPoints(carbs: 0.3, protein: 0.4, fat: 0.2),
    IntakeTypeEntity.dinner: MacroPoints(carbs: 0.2, protein: 0.3, fat: 0.2),
    IntakeTypeEntity.snack: MacroPoints(carbs: 0.2, protein: 0.25, fat: 0.2),
  };

  /// Body fat percentage with the U.S. Navy circumference equations
  /// (Hodgdon & Beckett, 1984). [hipCm] is needed for the female and
  /// averaged references. Returns null when the measurements cannot give a
  /// result.
  static double? bodyFatNavy({
    required BodyFatReference reference,
    required double heightCm,
    required double neckCm,
    required double waistCm,
    double? hipCm,
  }) {
    double? male() {
      final d = waistCm - neckCm;
      if (d <= 0 || heightCm <= 0) return null;
      return 495 /
              (1.0324 -
                  0.19077 * _log10(d) +
                  0.15456 * _log10(heightCm)) -
          450;
    }

    double? female() {
      if (hipCm == null) return null;
      final d = waistCm + hipCm - neckCm;
      if (d <= 0 || heightCm <= 0) return null;
      return 495 /
              (1.29579 -
                  0.35004 * _log10(d) +
                  0.22100 * _log10(heightCm)) -
          450;
    }

    final double? result;
    switch (reference) {
      case BodyFatReference.male:
        result = male();
      case BodyFatReference.female:
        result = female();
      case BodyFatReference.averaged:
        final m = male();
        final f = female();
        result = (m == null || f == null) ? (m ?? f) : (m + f) / 2;
    }
    if (result == null || result.isNaN) return null;
    return result.clamp(3.0, 60.0);
  }

  /// Body fat percentage from BMI and age (Deurenberg et al., 1991), used
  /// when no circumference measurements are available.
  static double bodyFatFromBmi({
    required BodyFatReference reference,
    required double weightKg,
    required double heightCm,
    required int ageYears,
  }) {
    final heightM = heightCm / 100;
    final bmi = weightKg / (heightM * heightM);
    final double sexTerm;
    switch (reference) {
      case BodyFatReference.male:
        sexTerm = 1;
      case BodyFatReference.female:
        sexTerm = 0;
      case BodyFatReference.averaged:
        sexTerm = 0.5;
    }
    final result = 1.2 * bmi + 0.23 * ageYears - 10.8 * sexTerm - 5.4;
    return result.clamp(3.0, 60.0);
  }

  /// Resting energy expenditure from lean body mass (Cunningham, 1991).
  static double cunninghamRestingKcal(double leanMassKg) =>
      370 + 21.6 * leanMassKg;

  /// The default method: calories from lean mass, protein first.
  static PointsBudget leanMassBudget({
    required double weightKg,
    required double bodyFatPercent,
    required double activityMultiplier,
    LeanMassBudgetSettings settings = const LeanMassBudgetSettings(),
  }) {
    final leanMass = weightKg * (100 - bodyFatPercent) / 100;
    final maintenance = cunninghamRestingKcal(leanMass) * activityMultiplier;
    final kcalGoal = maintenance * settings.calorieAdjustment;
    final proteinGrams = leanMass * settings.proteinGramsPerKgLeanMass;
    final proteinKcal = proteinGrams * PointsCalc.proteinKcalPerGram;
    final remainder = math.max(0.0, kcalGoal - proteinKcal);
    final exact = MacroPoints(
      carbs: remainder * settings.carbShareOfRemainder / PointsCalc.kcalPerPoint,
      protein: proteinKcal / PointsCalc.kcalPerPoint,
      fat: remainder *
          (1 - settings.carbShareOfRemainder) /
          PointsCalc.kcalPerPoint,
    );
    return PointsBudget(
      method: PointsBudgetMethod.leanMass,
      kcalGoal: kcalGoal,
      exact: exact,
      rounded: roundBudget(exact),
      bodyFatPercent: bodyFatPercent,
      leanMassKg: leanMass,
      maintenanceKcal: maintenance,
      proteinGrams: proteinGrams,
    );
  }

  /// The app's calorie goal and macro percentages as points.
  static PointsBudget appMacrosBudget({
    required double kcalGoal,
    required double carbsPercent,
    required double proteinPercent,
    required double fatPercent,
  }) {
    final exact = MacroPoints(
      carbs: kcalGoal * carbsPercent / PointsCalc.kcalPerPoint,
      protein: kcalGoal * proteinPercent / PointsCalc.kcalPerPoint,
      fat: kcalGoal * fatPercent / PointsCalc.kcalPerPoint,
    );
    return PointsBudget(
      method: PointsBudgetMethod.appMacros,
      kcalGoal: kcalGoal,
      exact: exact,
      rounded: roundBudget(exact),
    );
  }

  /// Rounds each macro to the nearest quarter point.
  static MacroPoints roundBudget(MacroPoints exact) => MacroPoints(
        carbs: PointsCalc.snapToStep(exact.carbs),
        protein: PointsCalc.snapToStep(exact.protein),
        fat: PointsCalc.snapToStep(exact.fat),
      );

  /// Splits a daily budget across meals with [split] (the share of each
  /// macro per meal). Each macro is distributed in quarter points so the
  /// meals add up exactly to the daily figure, giving leftover quarters to
  /// the meals that lost most to rounding.
  static Map<IntakeTypeEntity, MacroPoints> mealBudgets(
    MacroPoints daily, {
    Map<IntakeTypeEntity, MacroPoints> split = defaultMealSplit,
  }) => distribute(daily, split);

  /// Splits [daily] across any set of meals keyed by [K], weighted by
  /// [split], the same way as [mealBudgets].
  static Map<K, MacroPoints> distribute<K>(
    MacroPoints daily,
    Map<K, MacroPoints> split,
  ) {
    final meals = split.keys.toList();
    final carbs = _distribute(
      daily.carbs,
      [for (final m in meals) split[m]!.carbs],
    );
    final protein = _distribute(
      daily.protein,
      [for (final m in meals) split[m]!.protein],
    );
    final fat = _distribute(
      daily.fat,
      [for (final m in meals) split[m]!.fat],
    );
    return {
      for (var i = 0; i < meals.length; i++)
        meals[i]: MacroPoints(carbs: carbs[i], protein: protein[i], fat: fat[i]),
    };
  }

  /// Largest-remainder distribution of [total] in [PointsCalc.pointStep]
  /// units, weighted by [weights].
  static List<double> _distribute(double total, List<double> weights) {
    const step = PointsCalc.pointStep;
    final units = (total / step).round();
    final weightSum = weights.fold<double>(0, (a, b) => a + b);
    if (units <= 0 || weightSum <= 0) {
      return List.filled(weights.length, 0);
    }
    final ideal = [for (final w in weights) units * w / weightSum];
    final floors = [for (final x in ideal) x.floor()];
    var left = units - floors.fold<int>(0, (a, b) => a + b);
    // Largest remainder first; ties go to the earlier meal so the result
    // never depends on how the sort orders equal keys.
    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = (ideal[b] - floors[b]).compareTo(
          ideal[a] - floors[a],
        );
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (final i in order) {
      if (left <= 0) break;
      floors[i] += 1;
      left -= 1;
    }
    return [for (final f in floors) f * step];
  }

  static double _log10(double x) => math.log(x) / math.ln10;
}
