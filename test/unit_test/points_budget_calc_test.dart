import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';

void main() {
  group('bodyFatNavy', () {
    test('male reference', () {
      final bf = PointsBudgetCalc.bodyFatNavy(
        reference: BodyFatReference.male,
        heightCm: 185,
        neckCm: 44,
        waistCm: 112,
      );
      expect(bf, closeTo(29.08, 0.01));
    });

    test('female reference without hip is null', () {
      expect(
        PointsBudgetCalc.bodyFatNavy(
          reference: BodyFatReference.female,
          heightCm: 165,
          neckCm: 34,
          waistCm: 80,
        ),
        isNull,
      );
    });

    test('female reference with hip', () {
      final bf = PointsBudgetCalc.bodyFatNavy(
        reference: BodyFatReference.female,
        heightCm: 165,
        neckCm: 34,
        waistCm: 80,
        hipCm: 100,
      );
      expect(bf, isNotNull);
      expect(bf!, greaterThan(25));
      expect(bf, lessThan(40));
    });

    test('waist not larger than neck is null', () {
      expect(
        PointsBudgetCalc.bodyFatNavy(
          reference: BodyFatReference.male,
          heightCm: 180,
          neckCm: 44,
          waistCm: 44,
        ),
        isNull,
      );
      expect(
        PointsBudgetCalc.bodyFatNavy(
          reference: BodyFatReference.male,
          heightCm: 180,
          neckCm: 44,
          waistCm: 40,
        ),
        isNull,
      );
    });

    test('averaged is the mean of male and female', () {
      double? calc(BodyFatReference r) => PointsBudgetCalc.bodyFatNavy(
            reference: r,
            heightCm: 175,
            neckCm: 38,
            waistCm: 90,
            hipCm: 100,
          );
      final male = calc(BodyFatReference.male)!;
      final female = calc(BodyFatReference.female)!;
      expect(
        calc(BodyFatReference.averaged),
        closeTo((male + female) / 2, 1e-9),
      );
    });
  });

  test('bodyFatFromBmi for a male', () {
    // BMI = 123 / 1.85^2 = 35.939; 1.2 * 35.939 + 0.23 * 30 - 10.8 - 5.4
    final bf = PointsBudgetCalc.bodyFatFromBmi(
      reference: BodyFatReference.male,
      weightKg: 123,
      heightCm: 185,
      ageYears: 30,
    );
    expect(bf, closeTo(33.83, 0.01));
  });

  test('cunninghamRestingKcal', () {
    // 370 + 21.6 * 87.33 = 2256.33
    expect(PointsBudgetCalc.cunninghamRestingKcal(87.33),
        closeTo(2256.33, 0.01));
  });

  group('leanMassBudget', () {
    const settings = LeanMassBudgetSettings(calorieAdjustment: 0.75);

    test('reference case with measured body fat', () {
      final b = PointsBudgetCalc.leanMassBudget(
        weightKg: 123,
        bodyFatPercent: 29.081864488766996,
        activityMultiplier: 1.2,
        settings: settings,
      );
      expect(b.method, PointsBudgetMethod.leanMass);
      expect(b.leanMassKg, closeTo(87.229, 0.01));
      expect(b.maintenanceKcal, closeTo(2704.98, 0.01));
      expect(b.kcalGoal, closeTo(2028.74, 0.01));
      expect(b.proteinGrams, closeTo(130.84, 0.01));
      expect(b.exact.carbs, closeTo(9.785, 0.01));
      expect(b.exact.protein, closeTo(5.234, 0.01));
      expect(b.exact.fat, closeTo(5.269, 0.01));
      expect(
        b.rounded,
        const MacroPoints(carbs: 9.75, protein: 5.25, fat: 5.25),
      );
    });

    test('body fat rounded to a whole percent gives the reference kcal goal', () {
      // lean = 87.33, maintenance = 2256.33 * 1.2 = 2707.596,
      // goal = 2707.596 * 0.75 = 2030.697
      final b = PointsBudgetCalc.leanMassBudget(
        weightKg: 123,
        bodyFatPercent: 29,
        activityMultiplier: 1.2,
        settings: settings,
      );
      expect(b.kcalGoal, closeTo(2030.70, 0.01));
    });

    test('remainder is never negative', () {
      // Goal is about 270 kcal, below the 523 kcal of protein.
      final b = PointsBudgetCalc.leanMassBudget(
        weightKg: 123,
        bodyFatPercent: 29.081864488766996,
        activityMultiplier: 1.2,
        settings: const LeanMassBudgetSettings(calorieAdjustment: 0.1),
      );
      expect(b.exact.carbs, 0);
      expect(b.exact.fat, 0);
      expect(b.exact.protein, closeTo(5.234, 0.01));
    });
  });

  test('appMacrosBudget converts percentages to points', () {
    final b = PointsBudgetCalc.appMacrosBudget(
      kcalGoal: 2000,
      carbsPercent: 0.6,
      proteinPercent: 0.15,
      fatPercent: 0.25,
    );
    expect(b.method, PointsBudgetMethod.appMacros);
    expect(b.exact, const MacroPoints(carbs: 12, protein: 3, fat: 5));
    expect(b.rounded, const MacroPoints(carbs: 12, protein: 3, fat: 5));
  });

  group('mealBudgets', () {
    const daily = MacroPoints(carbs: 9.75, protein: 5.25, fat: 5.25);
    const meals = [
      IntakeTypeEntity.breakfast,
      IntakeTypeEntity.lunch,
      IntakeTypeEntity.dinner,
      IntakeTypeEntity.snack,
    ];

    test('meals add up exactly to the daily budget in quarter points', () {
      final result = PointsBudgetCalc.mealBudgets(daily);
      final sum = meals.fold<MacroPoints>(
        MacroPoints.zero,
        (acc, m) => acc + result[m]!,
      );
      expect(sum.carbs, closeTo(9.75, 1e-9));
      expect(sum.protein, closeTo(5.25, 1e-9));
      expect(sum.fat, closeTo(5.25, 1e-9));

      for (final m in meals) {
        final r = result[m]!;
        for (final v in [r.carbs, r.protein, r.fat]) {
          expect(v / 0.25, closeTo((v / 0.25).roundToDouble(), 1e-9));
        }
      }
    });

    test('largest remainder gives the expected distribution', () {
      final result = PointsBudgetCalc.mealBudgets(daily);

      // Carbs: 9.75 = 39 quarters, weights .3/.3/.2/.2.
      //   ideal 11.7, 11.7, 7.8, 7.8; floors 11, 11, 7, 7 = 36; 3 left.
      //   Fractions .7, .7, .8, .8: dinner, snack, then breakfast
      //   (tie with lunch, breakfast first) -> 12, 11, 8, 8 quarters.
      expect(result[IntakeTypeEntity.breakfast]!.carbs, closeTo(3.0, 1e-9));
      expect(result[IntakeTypeEntity.lunch]!.carbs, closeTo(2.75, 1e-9));
      expect(result[IntakeTypeEntity.dinner]!.carbs, closeTo(2.0, 1e-9));
      expect(result[IntakeTypeEntity.snack]!.carbs, closeTo(2.0, 1e-9));

      // Protein: 5.25 = 21 quarters, weights .05/.4/.3/.25.
      //   ideal 1.05, 8.4, 6.3, 5.25; floors 1, 8, 6, 5 = 20; 1 left.
      //   Largest fraction is .4 (lunch) -> 1, 9, 6, 5 quarters.
      expect(result[IntakeTypeEntity.breakfast]!.protein, closeTo(0.25, 1e-9));
      expect(result[IntakeTypeEntity.lunch]!.protein, closeTo(2.25, 1e-9));
      expect(result[IntakeTypeEntity.dinner]!.protein, closeTo(1.5, 1e-9));
      expect(result[IntakeTypeEntity.snack]!.protein, closeTo(1.25, 1e-9));

      // Fat: 5.25 = 21 quarters, weights .4/.2/.2/.2.
      //   ideal 8.4, 4.2, 4.2, 4.2; floors 8, 4, 4, 4 = 20; 1 left.
      //   Largest fraction is .4 (breakfast) -> 9, 4, 4, 4 quarters.
      expect(result[IntakeTypeEntity.breakfast]!.fat, closeTo(2.25, 1e-9));
      expect(result[IntakeTypeEntity.lunch]!.fat, closeTo(1.0, 1e-9));
      expect(result[IntakeTypeEntity.dinner]!.fat, closeTo(1.0, 1e-9));
      expect(result[IntakeTypeEntity.snack]!.fat, closeTo(1.0, 1e-9));
    });

    test('a zero budget gives zeros', () {
      final result = PointsBudgetCalc.mealBudgets(MacroPoints.zero);
      expect(result.length, 4);
      for (final m in meals) {
        expect(result[m], MacroPoints.zero);
      }
    });
  });

  test('defaultMealSplit shares sum to 1 for every macro', () {
    final split = PointsBudgetCalc.defaultMealSplit.values;
    expect(split.fold<double>(0, (a, m) => a + m.carbs), closeTo(1, 1e-9));
    expect(split.fold<double>(0, (a, m) => a + m.protein), closeTo(1, 1e-9));
    expect(split.fold<double>(0, (a, m) => a + m.fat), closeTo(1, 1e-9));
  });
}
