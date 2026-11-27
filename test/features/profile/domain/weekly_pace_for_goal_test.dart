import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/features/profile/domain/weekly_pace_for_goal.dart';

void main() {
  group('WeeklyPaceForGoal', () {
    test('a maintain pace no longer holds back a goal to lose weight', () {
      const goal = UserWeightGoalEntity.loseWeight;
      final pace = WeeklyPaceForGoal.adjust(goal, 0.0);
      expect(pace, -0.5);
      expect(
        CalorieGoalCalc.getKcalGoalAdjustment(goal, weeklyWeightGoalKg: pace),
        lessThan(0),
      );
    });

    test('a pace that already fits the goal is kept', () {
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.loseWeight, -0.25),
        -0.25,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.gainWeight, 0.5),
        0.5,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.maintainWeight, 0.0),
        0.0,
      );
    });

    test('a pace pointing the other way follows the goal', () {
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.gainWeight, -0.5),
        0.5,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.maintainWeight, -0.5),
        0.0,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.loseWeight, 0.25),
        -0.5,
      );
    });

    test('no pace set stays unset', () {
      for (final goal in UserWeightGoalEntity.values) {
        expect(WeeklyPaceForGoal.adjust(goal, null), isNull);
        expect(WeeklyPaceForGoal.contradicts(goal, null), isFalse);
      }
    });

    test('muscle goals set their own pace', () {
      expect(
        WeeklyPaceForGoal.adjustBodyGoal(
          BodyGoal.loseWeight,
          BodyGoal.loseWeightBuildMuscle,
          -0.5,
        ),
        -0.25,
      );
      expect(
        WeeklyPaceForGoal.adjustBodyGoal(
          BodyGoal.maintainWeight,
          BodyGoal.buildMuscle,
          null,
        ),
        0.25,
      );
      expect(
        WeeklyPaceForGoal.adjustBodyGoal(
          BodyGoal.buildMuscle,
          BodyGoal.gainWeight,
          0.25,
        ),
        0.5,
      );
      // Between plain goals a fitting pace stays.
      expect(
        WeeklyPaceForGoal.adjustBodyGoal(
          BodyGoal.maintainWeight,
          BodyGoal.loseWeight,
          null,
        ),
        isNull,
      );
    });
  });

  group('BodyGoal', () {
    test('reads back from the weight goal, muscle flag and pace', () {
      for (final goal in BodyGoal.values) {
        expect(
          BodyGoal.of(
            goal.weightGoal,
            buildMuscle: goal.buildsMuscle,
            weeklyPaceKg: goal.defaultWeeklyPaceKg,
          ),
          goal,
        );
      }
    });

    test('muscle goals ask for more protein, the others leave it', () {
      expect(BodyGoal.maintainWeight.minProteinPerKgLeanMass, isNull);
      expect(BodyGoal.buildMuscle.minProteinPerKgLeanMass, 2.2);
      expect(BodyGoal.loseWeightBuildMuscle.minProteinPerKgLeanMass, 2.4);
      expect(
        BodyGoal.loseWeightBuildMuscle.leanMassCalorieAdjustment,
        greaterThan(BodyGoal.loseWeight.leanMassCalorieAdjustment),
      );
      expect(
        BodyGoal.buildMuscle.leanMassCalorieAdjustment,
        lessThan(BodyGoal.gainWeightAndMuscle.leanMassCalorieAdjustment),
      );
    });
  });
}
