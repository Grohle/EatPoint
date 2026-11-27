import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';

void main() {
  PointsSettings full() => PointsSettings(
    pointsModeEnabled: false,
    budgetMethod: PointsBudgetMethod.appMacros,
    calorieAdjustment: 0.8,
    proteinGramsPerKgLeanMass: 2.0,
    carbShareOfRemainder: 0.5,
    activityMultiplier: 1.4,
    neckCm: 38,
    waistCm: 85.5,
    hipCm: 100,
    mealSplit: {
      for (final t in IntakeTypeEntity.values)
        t: const MacroPoints(carbs: 0.25, protein: 0.25, fat: 0.25),
    },
    dailyBudgetOverride: const MacroPoints(carbs: 10, protein: 7.5, fat: 5),
    budgetGuideAcknowledged: true,
  );

  group('toJson / fromJson', () {
    test('round trips every field', () {
      final s = full();
      final back = PointsSettings.fromJson(s.toJson());
      expect(back.pointsModeEnabled, false);
      expect(back.budgetMethod, PointsBudgetMethod.appMacros);
      expect(back.calorieAdjustment, 0.8);
      expect(back.proteinGramsPerKgLeanMass, 2.0);
      expect(back.carbShareOfRemainder, 0.5);
      expect(back.activityMultiplier, 1.4);
      expect(back.neckCm, 38);
      expect(back.waistCm, 85.5);
      expect(back.hipCm, 100);
      expect(back.mealSplit, s.mealSplit);
      expect(back.dailyBudgetOverride, s.dailyBudgetOverride);
      expect(back.budgetGuideAcknowledged, true);
    });

    test('defaults round trip and omit unset optionals', () {
      final json = PointsSettings.defaults.toJson();
      expect(json.containsKey('calorieAdjustment'), isFalse);
      expect(json.containsKey('mealSplit'), isFalse);
      expect(json.containsKey('dailyBudgetOverride'), isFalse);
      final back = PointsSettings.fromJson(json);
      expect(back.pointsModeEnabled, true);
      expect(back.budgetMethod, PointsBudgetMethod.leanMass);
      expect(back.calorieAdjustment, isNull);
      expect(back.mealSplit, isNull);
      expect(back.dailyBudgetOverride, isNull);
      expect(back.budgetGuideAcknowledged, false);
    });

    test('malformed json falls back to the defaults', () {
      final s = PointsSettings.fromJson({
        'budgetMethod': 'nonsense',
        'calorieAdjustment': 'lots',
        'proteinGramsPerKgLeanMass': double.nan,
        'carbShareOfRemainder': null,
        'activityMultiplier': double.infinity,
        'neckCm': '38',
        'mealSplit': 'x',
        'dailyBudgetOverride': {'carbs': 1, 'protein': 'a', 'fat': 2},
      });
      expect(s.pointsModeEnabled, true);
      expect(s.budgetMethod, PointsBudgetMethod.leanMass);
      expect(s.calorieAdjustment, isNull);
      expect(s.proteinGramsPerKgLeanMass, 1.5);
      expect(s.carbShareOfRemainder, 0.65);
      expect(s.activityMultiplier, isNull);
      expect(s.neckCm, isNull);
      expect(s.mealSplit, isNull);
      expect(s.dailyBudgetOverride, isNull);
      expect(s.budgetGuideAcknowledged, false);
    });

    test(
      'a wrongly typed bool falls back instead of throwing',
      () {
        final s = PointsSettings.fromJson({
          'pointsModeEnabled': 'yes',
          'budgetGuideAcknowledged': 1,
        });
        expect(s.pointsModeEnabled, true);
        expect(s.budgetGuideAcknowledged, false);
      },
    );

    test('an incomplete meal split is dropped, not half-applied', () {
      final json = full().toJson();
      (json['mealSplit'] as Map).remove('snack');
      final s = PointsSettings.fromJson(json);
      expect(s.mealSplit, isNull);
      expect(s.effectiveMealSplit, PointsBudgetCalc.defaultMealSplit);
    });

    test('integers are accepted for doubles', () {
      final s = PointsSettings.fromJson({'neckCm': 38, 'waistCm': 80});
      expect(s.neckCm, 38.0);
      expect(s.waistCm, 80.0);
    });
  });

  group('copyWith', () {
    test('no arguments keeps everything', () {
      final c = full().copyWith();
      expect(c.toJson(), full().toJson());
    });

    test('plain values replace', () {
      final c = PointsSettings.defaults.copyWith(
        pointsModeEnabled: false,
        budgetMethod: PointsBudgetMethod.appMacros,
        budgetGuideAcknowledged: true,
      );
      expect(c.pointsModeEnabled, false);
      expect(c.budgetMethod, PointsBudgetMethod.appMacros);
      expect(c.budgetGuideAcknowledged, true);
    });

    test('nullable setters can set a value', () {
      final c = PointsSettings.defaults.copyWith(
        calorieAdjustment: () => 0.9,
        neckCm: () => 36,
        dailyBudgetOverride: () =>
            const MacroPoints(carbs: 1, protein: 2, fat: 3),
      );
      expect(c.calorieAdjustment, 0.9);
      expect(c.neckCm, 36);
      expect(c.dailyBudgetOverride!.total, 6);
    });

    test('nullable setters can clear a value', () {
      final c = full().copyWith(
        calorieAdjustment: () => null,
        activityMultiplier: () => null,
        neckCm: () => null,
        waistCm: () => null,
        hipCm: () => null,
        mealSplit: () => null,
        dailyBudgetOverride: () => null,
      );
      expect(c.calorieAdjustment, isNull);
      expect(c.activityMultiplier, isNull);
      expect(c.neckCm, isNull);
      expect(c.waistCm, isNull);
      expect(c.hipCm, isNull);
      expect(c.mealSplit, isNull);
      expect(c.dailyBudgetOverride, isNull);
      // Untouched fields stay.
      expect(c.budgetMethod, PointsBudgetMethod.appMacros);
    });

    test('omitting a nullable setter keeps the old value', () {
      final c = full().copyWith(neckCm: () => 40);
      expect(c.neckCm, 40);
      expect(c.waistCm, 85.5);
    });
  });
}
