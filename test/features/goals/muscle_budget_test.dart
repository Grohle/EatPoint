import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';

void main() {
  group('musclePercents', () {
    test('raises protein to 1.8 g/kg and keeps the carb:fat ratio', () {
      final p = GetPointsBudgetUsecase.musclePercents(
        goal: BodyGoal.buildMuscle,
        weightKg: 80,
        kcalGoal: 2800,
        carbs: 0.6,
        protein: 0.15,
        fat: 0.25,
      );
      // 1.8 × 80 g × 4 kcal / 2800 kcal.
      expect(p.protein, closeTo(144 * 4 / 2800, 1e-9));
      expect(p.carbs + p.protein + p.fat, closeTo(1, 1e-9));
      expect(p.carbs / p.fat, closeTo(0.6 / 0.25, 1e-9));
    });

    test('leaves the other goals and enough protein alone', () {
      final plain = GetPointsBudgetUsecase.musclePercents(
        goal: BodyGoal.gainWeight,
        weightKg: 80,
        kcalGoal: 2800,
        carbs: 0.6,
        protein: 0.15,
        fat: 0.25,
      );
      expect(plain.protein, 0.15);
      final high = GetPointsBudgetUsecase.musclePercents(
        goal: BodyGoal.buildMuscle,
        weightKg: 60,
        kcalGoal: 2000,
        carbs: 0.4,
        protein: 0.35,
        fat: 0.25,
      );
      expect(high.protein, 0.35);
    });

    test('a deficit asks for more protein, capped at 40 %', () {
      final p = GetPointsBudgetUsecase.musclePercents(
        goal: BodyGoal.loseWeightBuildMuscle,
        weightKg: 120,
        kcalGoal: 1800,
        carbs: 0.6,
        protein: 0.15,
        fat: 0.25,
      );
      expect(p.protein, 0.4);
    });
  });
}
